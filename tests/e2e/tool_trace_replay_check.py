"""Every recorded tool call as a Visual Trace step in replay mode, and the decision unchanged when the trace operation is off.

Starts the stack with no key, sends the committed samples, and checks, for every subject case whose recording holds tool calls: the
session of its decision has one Readback.Msg.ToolCall step per recorded call, in the recorded order, numbered from 1, labelled
replay, between the request to the replay operation and its response, and carrying no identifier of a patient. Then it switches
the trace operation off, sends the samples again and checks that every decision is the same (route, severities, failure) and
that no step was sent: nothing in the decision's path depends on the trace message.
"""
import json
import sys

from common import iris, query, scalar, wait_for
from readback_check import call
import replay_check as rc

failures = []
COLUMNS = ["ID", "Route", "FinalSeverity", "FloorSeverity", "AgentSeverity", "AgentDecision", "FailureKind", "ToolCallCount", "SessionId"]


def check(condition, message):
    if not condition:
        failures.append(message)
        print("FAIL:", message)


def decisions(control_id):
    return query("SELECT %s FROM Readback_Trace.Decision WHERE MessageControlId='%s' ORDER BY ID" % (",".join(COLUMNS), control_id), COLUMNS)


def steps(session):
    headers = query("SELECT ID, SourceConfigName, TargetConfigName, MessageBodyClassName, MessageBodyId FROM Ens.MessageHeader WHERE SessionId=%s ORDER BY ID" % session,
                    ["ID", "SourceConfigName", "TargetConfigName", "MessageBodyClassName", "MessageBodyId"])
    sent = []
    for index, h in enumerate(headers):
        if h["MessageBodyClassName"] != "Readback.Msg.ToolCall":
            continue
        rows = query("SELECT Seq, Tool, Status, Mode, Arguments, CaseId FROM Readback_Msg.ToolCall WHERE ID=%s" % h["MessageBodyId"], ["Seq", "Tool", "Status", "Mode", "Arguments", "CaseId"])
        for r in rows:
            r["index"], r["source"], r["target"] = index, h["SourceConfigName"], h["TargetConfigName"]
            sent.append(r)
    request = next((i for i, h in enumerate(headers) if h["TargetConfigName"] == "Readback.Agent.Replay"), -1)
    answer = next((i for i, h in enumerate(headers) if h["SourceConfigName"] == "Readback.Agent.Replay" and h["MessageBodyClassName"].endswith("LLMResponse")), -1)
    return sent, request, answer


def main():
    rc.start_stack()
    check(bool(wait_for(lambda: call("communicator1", rc.PASSWORD, "GET", "/user-info")[0] == 200, 240, 3)), "workflow-rest is not answering")
    items = rc.messages()
    recordings = rc.shipped_recordings()
    acks = rc.send([m[1] for m in items])
    check(all(a == "AA" for _, a in acks), "an acknowledgement was not AA")
    check(bool(wait_for(lambda: all(len(decisions(i[0])) >= 1 for i in items), 120, 2)), "not every case reached a decision")
    if failures:
        return 1

    with_calls = [(mid, recordings[mid]) for mid, _, _, role in items if mid in recordings and recordings[mid].get("toolCalls")]
    check(len(with_calls) >= 20, "expected at least 20 recordings with tool calls, found %d" % len(with_calls))
    longest = max((len(r["toolCalls"]) for _, r in with_calls), default=0)
    check(longest >= 4, "expected a recording with four tool calls (the held scenario): the longest has %d" % longest)
    checked = 0
    for mid, rec in with_calls:
        d = decisions(mid)[0]
        sent, request, answer = steps(d["SessionId"])
        want = [c["tool"] for c in rec["toolCalls"]]
        check([s["Tool"] for s in sent] == want, "%s: the steps are not the recorded calls in order: %s vs %s" % (mid, [s["Tool"] for s in sent], want))
        check([s["Seq"] for s in sent] == [str(i + 1) for i in range(len(want))], "%s: the steps are not numbered from 1: %s" % (mid, [s["Seq"] for s in sent]))
        check(all(s["Mode"] == "replay" for s in sent), "%s: a step is not labelled replay" % mid)
        check(all(s["source"] == "Readback.Agent.Replay" and s["target"] == "Readback.Agent.ToolTrace" for s in sent), "%s: a step has the wrong source or target" % mid)
        check(request >= 0 and answer > request and all(request < s["index"] < answer for s in sent), "%s: the steps are not between the request and the response" % mid)
        check(not any("SYN" in " ".join(str(v) for v in s.values()) for s in sent), "%s: a patient identifier is in a step" % mid)
        check(d["ToolCallCount"] == str(len(want)), "%s: the decision counts %s calls, the recording %d" % (mid, d["ToolCallCount"], len(want)))
        checked += 1
    print("recorded investigations checked:", checked)
    first = {m[0]: decisions(m[0])[0] for m in items}

    # The trace operation off: the same samples again, the same decisions, no step.
    out = iris('set sc=##class(Ens.Director).EnableConfigItem("Readback.Agent.ToolTrace",0,1)\nwrite !,"RB_OFF="_$system.Status.IsOK(sc),!')
    check("RB_OFF=1" in out, "could not switch the trace operation off: %s" % out)
    acks = rc.send([m[1] for m in items])
    check(all(a == "AA" for _, a in acks), "an acknowledgement was not AA with the trace operation off")
    check(bool(wait_for(lambda: all(len(decisions(i[0])) >= 2 for i in items), 120, 2)), "with the trace operation off, not every case reached a decision")
    same = ["Route", "FinalSeverity", "FloorSeverity", "AgentSeverity", "AgentDecision", "FailureKind", "ToolCallCount"]
    differ = 0
    sent_off = 0
    for mid, _, _, _ in items:
        rows = decisions(mid)
        if len(rows) < 2:
            continue
        second = rows[-1]
        if [second[k] for k in same] != [first[mid][k] for k in same]:
            differ += 1
            print("differs:", mid, [second[k] for k in same], [first[mid][k] for k in same])
        if scalar("SELECT COUNT(*) FROM Ens.MessageHeader WHERE SessionId=%s AND MessageBodyClassName='Readback.Msg.ToolCall' AND Status NOT IN (1, 2)" % second["SessionId"]) != "0":
            sent_off += 1
    check(differ == 0, "%d decisions differ with the trace operation off" % differ)
    check(sent_off == 0, "%d decisions have a processed step although the trace operation is off" % sent_off)
    out = iris('set sc=##class(Ens.Director).EnableConfigItem("Readback.Agent.ToolTrace",1,1)\nwrite !,"RB_ON="_$system.Status.IsOK(sc),!')
    check("RB_ON=1" in out, "could not switch the trace operation back on: %s" % out)
    errors = scalar("SELECT COUNT(*) FROM Ens_Util.Log WHERE Type=2")
    print("event log errors after the run:", errors)

    if failures:
        print("FAILED (%d):" % len(failures))
        for f in failures[:20]:
            print(" -", f)
        return 1
    print("tool trace replay check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
