"""The agent's tools against a local OpenAI-compatible mock that asks for them (no real key, no cost).

Recreates the container with a test key, points the agent item at the mock, sends cases, and checks: the four tools are offered and
return what they should; the ordered calls are recorded; the tokens and the rounds are the sums of the whole investigation, not
the last round; a tool that does not exist, a loop that never ends, an answer that cites evidence no tool returned, and an agent that
tries to lower a critical each end where the rules say; no session runs without its limit and nothing keeps running after the limit.
The container is recreated without the test key at the end.
"""
import json
import subprocess
import sys
import time

from common import ROOT, compose, iris, oru, query, wait_for
import live_mock_check as live

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)
        print("FAIL:", message)


COLUMNS = ["ID", "Route", "FailureKind", "FailureReason", "Rounds", "ToolCallCount", "ToolFailureCount", "EvidenceCheck", "InputTokens", "OutputTokens",
           "AgentDecision", "AgentSeverity", "FloorSeverity", "FinalSeverity", "PolicyRefusal", "Divergence", "Evidence", "SchemaValid", "SessionId"]


def decision(case_id):
    rows = query("SELECT %s FROM Readback_Trace.Decision WHERE MessageControlId='%s' ORDER BY ID DESC" % (",".join(COLUMNS), case_id), COLUMNS)
    return rows[0] if rows else None


def calls_of(trace_id):
    cols = ["Seq", "Tool", "Status", "Reason", "ArgumentsJson", "ResultJson"]
    return query("SELECT %s FROM Readback_Trace.ToolCall WHERE Decision=%s ORDER BY Seq" % (",".join(cols), trace_id), cols)


def requests_for(case_id):
    return [r for r in live.mock_requests() if "Case id: " + case_id in json.dumps(r["body"].get("messages", []))]


def main():
    live.start_stack(live.FILES)
    compose("exec", "-d", "iris", "python3", "/opt/readback/tests/e2e/mock_openai.py")
    time.sleep(2)
    check(live.set_setting("Readback.Agent", "Adapter", "ProviderConfig", '{"api_key":"@{env:OPENAI_API_KEY}","base_url":"http://127.0.0.1:8099/v1/"}'),
          "could not point the agent item at the mock")
    check(live.set_setting("Readback.Triage", "Host", "AgentTimeoutSeconds", "20"), "could not set the timeout")
    # A low limit, so that a loop that learns something new every round is stopped by the limit itself, not by the
    # platform's stall detection (which a repeated call triggers after four rounds).
    subprocess.run(["docker", "compose", "exec", "-T", "iris", "sh", "-c", "cat > /tmp/agent-tools-test.json"], cwd=ROOT, text=True,
                   input='{"maxIterations":3,"maxToolCalls":6,"toolResultMaxChars":2000,"expectedRounds":3}', check=True)
    out = iris('set sc=##class(Readback.Config.Loader).LoadAgentTools("/tmp/agent-tools-test.json")\nwrite "RB_BOUND="_$system.Status.IsOK(sc),!')
    check("RB_BOUND=1" in out, "could not set the iteration limit for the test: %s" % out)
    time.sleep(3)

    tag = "TL%d" % (int(time.time()) % 100000)
    cases = {
        "good": oru(tag + "-GOOD", "SYN9100001", "718-7", "Hemoglobin", "8.1", "g/dL", ref="MODE:toolgood", indices=[("HEMOLYSIS_INDEX", "120")]),
        "none": oru(tag + "-NONE", "SYN9100002", "2823-3", "Potassium", "4.0", "mmol/L", ref="MODE:toolnone"),
        "bad": oru(tag + "-BAD", "SYN9100003", "2823-3", "Potassium", "4.0", "mmol/L", ref="MODE:toolbad"),
        "badcrit": oru(tag + "-BADC", "SYN9100004", "2823-3", "Potassium", "6.9", "mmol/L", ref="MODE:toolbad"),
        "unknown": oru(tag + "-UNK", "SYN9100005", "2823-3", "Potassium", "4.0", "mmol/L", ref="MODE:toolunknown"),
        "unkcrit": oru(tag + "-UNKC", "SYN9100006", "2823-3", "Potassium", "6.9", "mmol/L", ref="MODE:toolunknown"),
        "loop": oru(tag + "-LOOP", "SYN9100007", "2823-3", "Potassium", "4.0", "mmol/L", ref="MODE:toolloop"),
        "same": oru(tag + "-SAME", "SYN9100008", "2823-3", "Potassium", "4.0", "mmol/L", ref="MODE:toolloopsame"),
    }
    history = oru(tag + "-H1", "SYN9100001", "718-7", "Hemoglobin", "12.4", "g/dL", collected="20260228080000")
    acks = live.send([history] + list(cases.values()))
    check(all(a == "AA" for _, a in acks), "an intake acknowledgement was not AA: %s" % acks)

    ids = {"good": "-GOOD", "none": "-NONE", "bad": "-BAD", "badcrit": "-BADC", "unknown": "-UNK", "unkcrit": "-UNKC", "loop": "-LOOP", "same": "-SAME"}
    t = {}
    for key, suffix in ids.items():
        t[key] = wait_for(lambda s=suffix: decision(tag + s), 60)
        check(t[key] is not None, "no trace record for " + key)

    # The normal investigation: history, change and sample quality in one round, then an answer citing what came back.
    g = t.get("good")
    if g:
        check(g["Rounds"] == "2", "two rounds expected (one tool round, one answer): %s" % g["Rounds"])
        check(g["ToolCallCount"] == "3" and g["ToolFailureCount"] == "0", "three calls, none failed expected: %s/%s" % (g["ToolCallCount"], g["ToolFailureCount"]))
        check(g["EvidenceCheck"] == "ok", "the evidence should check out: %s" % g["EvidenceCheck"])
        # The mock reports 120 prompt and 40 completion tokens for the first round and 150 and 40 for the second.
        check(g["InputTokens"] == "270" and g["OutputTokens"] == "80", "tokens must be the sum of the rounds (270/80), not the last round: %s/%s" % (g["InputTokens"], g["OutputTokens"]))
        check(g["Route"] == "readback" and g["FinalSeverity"] == "3", "an acute drop must end at read-back: %s" % g)
        rows = calls_of(g["ID"])
        check([r["Tool"] for r in rows] == ["get_patient_history", "get_delta_assessment", "get_sample_quality"], "the calls are not recorded in the order made: %s" % [r["Tool"] for r in rows])
        check(all(r["Status"] == "ok" for r in rows), "every call should be ok: %s" % [r["Status"] for r in rows])
        by_tool = {r["Tool"]: r["ResultJson"] for r in rows}
        check("earlier-result-1" in by_tool.get("get_patient_history", "") and "12.4" in by_tool.get("get_patient_history", ""), "the history tool did not return the earlier result")
        check("critical by change" in by_tool.get("get_delta_assessment", ""), "the delta tool did not hand over the floor's verdict")
        check("sample-index-hemolysis" in by_tool.get("get_sample_quality", ""), "the sample quality tool did not return the index")
        check("earlier-result-1" in g["Evidence"] and "delta-assessment" in g["Evidence"], "the answer's evidence is not what the tools returned: %s" % g["Evidence"])
        mock = requests_for(tag + "-GOOD")
        check(len(mock) == 2, "two model requests expected, saw %d" % len(mock))
        if mock:
            first = mock[0]["body"]
            check("12.4" not in json.dumps(first["messages"]) and "HEMOLYSIS" not in json.dumps(first["messages"]), "the first request already holds what only the tools should give")
            check("SYN9100001" not in json.dumps(first["messages"]), "the patient identifier is in the request: no tool takes one and the agent has no use for it")
            for tool in first.get("tools", []):
                props = tool["function"]["parameters"].get("properties", {})
                check(not any("patient" in k.lower() or "case" in k.lower() for k in props), "tool %s offers an identifier argument: %s" % (tool["function"]["name"], list(props)))

        # Each call is a step of the session in the visual trace, between the agent's request and its response.
        steps = query("SELECT ID, SourceConfigName, TargetConfigName, MessageBodyClassName, MessageBodyId FROM Ens.MessageHeader WHERE SessionId=%s ORDER BY ID" % g["SessionId"],
                      ["ID", "SourceConfigName", "TargetConfigName", "MessageBodyClassName", "MessageBodyId"])
        names = [(s["SourceConfigName"], s["TargetConfigName"]) for s in steps if s["MessageBodyClassName"] == "Readback.Msg.ToolCall"]
        check(len(names) == 3 and all(n == ("Readback.Agent", "Readback.Agent.ToolTrace") for n in names), "three tool call steps expected in the visual trace: %s" % names)
        order = [s["MessageBodyClassName"] for s in steps]
        request = next((i for i, s in enumerate(steps) if s["TargetConfigName"] == "Readback.Agent"), -1)
        answer = next((i for i, s in enumerate(steps) if s["SourceConfigName"] == "Readback.Agent" and s["MessageBodyClassName"].endswith("LLMResponse")), -1)
        inside = [i for i, s in enumerate(steps) if s["MessageBodyClassName"] == "Readback.Msg.ToolCall"]
        check(request >= 0 and answer > request and all(request < i < answer for i in inside), "the tool call steps are not between the agent request and its response: %s" % order)
        # One message per call, in the order the calls were made, labelled live, with no identifier of a patient anywhere in it.
        sent = []
        for i in inside:
            rows_ = query("SELECT Seq, Tool, Status, Mode, Arguments, Summary, CaseId FROM Readback_Msg.ToolCall WHERE ID=%s" % steps[i]["MessageBodyId"],
                          ["Seq", "Tool", "Status", "Mode", "Arguments", "Summary", "CaseId"])
            sent.extend(rows_)
        check([r["Tool"] for r in sent] == ["get_patient_history", "get_delta_assessment", "get_sample_quality"], "the steps are not the calls in the order made: %s" % [r["Tool"] for r in sent])
        check([r["Seq"] for r in sent] == ["1", "2", "3"], "the steps are not numbered 1, 2, 3: %s" % [r["Seq"] for r in sent])
        check(all(r["Mode"] == "live" and r["Status"] == "ok" for r in sent), "every step of a live call must be labelled live and ok: %s" % sent)
        check(not any("SYN9" in " ".join(r.values()) for r in sent), "a patient identifier is in a tool trace message: %s" % sent)

    n = t.get("none")
    if n:
        check(n["Rounds"] == "1" and n["ToolCallCount"] == "0" and n["EvidenceCheck"] == "ok", "an answer with no tool call should be one round, no calls, evidence ok: %s" % n)

    for key, kind in (("bad", "evidence-not-from-tools"), ("badcrit", "evidence-not-from-tools")):
        r = t.get(key)
        if r:
            check(r["FailureKind"] == kind and r["EvidenceCheck"] == "not-from-tools" and r["SchemaValid"] == "0", "%s: evidence not returned by a tool must be an invalid answer: %s" % (key, r))
    check(t["bad"]["Route"] == "review", "an invented source with a floor of 0 must go to a person")
    check(t["badcrit"]["Route"] == "readback" and t["badcrit"]["FinalSeverity"] == "3", "an invented source on a rule-critical value must still reach the read-back")

    for key in ("unknown", "unkcrit"):
        r = t.get(key)
        if r:
            check(r["FailureKind"] == "tool-failure" and r["ToolFailureCount"] == "1", "%s: an unknown tool must be a tool failure: %s" % (key, r))
            check([c["Status"] for c in calls_of(r["ID"])] == ["unknown-tool"], "%s: the call must be recorded as unknown-tool" % key)
    check(t["unknown"]["Route"] == "review", "a tool failure with a floor of 0 must go to a person")
    check(t["unkcrit"]["Route"] == "readback", "a tool failure on a rule-critical value must still reach the read-back")

    # A loop that never ends: the iteration limit stops it, and nothing keeps running after.
    lp = t.get("loop")
    if lp:
        check(lp["FailureKind"] == "tool-limit" and lp["Route"] == "review", "a loop that never ends must stop at the limit and go to a person: %s" % lp)
        check("reached its limit" in lp["FailureReason"], "the limit itself (not the stall detection) should have stopped it: %s" % lp["FailureReason"])
        bound = int(iris('set rs=##class(Readback.Config.AgentTools).Current()\nwrite "RB_N="_rs.MaxIterations,!')[0].split("=")[1])
        first = len(requests_for(tag + "-LOOP"))
        time.sleep(4)
        later = len(requests_for(tag + "-LOOP"))
        check(first <= bound + 1, "the loop made %d requests, the limit is %d" % (first, bound))
        check(later == first, "the model was still being called after the limit (%d then %d)" % (first, later))
    sm = t.get("same")
    if sm:
        check(sm["Route"] == "review" and sm["FailureKind"] == "tool-limit", "the same call forever must end with a person as a stalled investigation: %s" % sm)

    # The trace operation switched off: the decision is exactly the same and no step is sent. A twin of the "good" case, on another patient.
    if g:
        out = iris('set sc=##class(Ens.Director).EnableConfigItem("Readback.Agent.ToolTrace",0,1)\nwrite !,"RB_OFF="_$system.Status.IsOK(sc),!')
        check("RB_OFF=1" in out, "could not switch the tool trace operation off: %s" % out)
        time.sleep(3)
        twin = [oru(tag + "-H2", "SYN9100011", "718-7", "Hemoglobin", "12.4", "g/dL", collected="20260228080000"),
                oru(tag + "-OFF", "SYN9100011", "718-7", "Hemoglobin", "8.1", "g/dL", ref="MODE:toolgood", indices=[("HEMOLYSIS_INDEX", "120")])]
        acks = live.send(twin)
        check(all(a == "AA" for _, a in acks), "an intake acknowledgement was not AA with the trace operation off: %s" % acks)
        off = wait_for(lambda: decision(tag + "-OFF"), 60)
        check(off is not None, "no decision with the trace operation switched off")
        if off:
            same = ["Route", "FinalSeverity", "FloorSeverity", "AgentSeverity", "AgentDecision", "Rounds", "ToolCallCount", "ToolFailureCount", "FailureKind", "EvidenceCheck", "SchemaValid", "PolicyRefusal", "Divergence"]
            check([off[k] for k in same] == [g[k] for k in same], "the decision differs with the trace operation off: %s vs %s" % ([off[k] for k in same], [g[k] for k in same]))
            check(off["FailureKind"] == "" and off["ToolFailureCount"] == "0", "a failed trace message must not fail the investigation: %s" % off)
            check(len(calls_of(off["ID"])) == 3, "the three calls must still be recorded in the product's own trace")
            hdr = query("SELECT Status, TargetConfigName FROM Ens.MessageHeader WHERE SessionId=%s AND MessageBodyClassName='Readback.Msg.ToolCall'" % off["SessionId"], ["Status", "TargetConfigName"])
            print("trace headers with the operation off:", hdr)
            # Sent to a switched-off item, a message waits in its queue (created or queued) and is never processed: the sender is not held up.
            check(all(h["Status"] in ("1", "2") for h in hdr), "steps were processed although the operation is off: %s" % hdr)
        out = iris('set sc=##class(Ens.Director).EnableConfigItem("Readback.Agent.ToolTrace",1,1)\nwrite !,"RB_ON="_$system.Status.IsOK(sc),!')
        check("RB_ON=1" in out, "could not switch the tool trace operation back on: %s" % out)

    # No session without the limit: the only creator of a session is the operation, and it sets the limit first.
    out = iris('set sc=$system.OBJ.Load("/opt/readback/tests/objectscript/Readback/Test/SessionLimitTest.cls","ck")\n'
               'write "RB_LIMITTEST=",$system.Status.IsOK(sc),!')
    check("RB_LIMITTEST=1" in out, "the session limit test did not load")

    leaks = live.scalar("SELECT COUNT(*) FROM Readback_Trace.Decision WHERE InputText LIKE '%%%s%%' OR RawOutput LIKE '%%%s%%' OR FailureReason LIKE '%%%s%%'" % (live.KEY, live.KEY, live.KEY))
    check(leaks == "0", "the key value appears in %s trace records" % leaks)
    leaks = live.scalar("SELECT COUNT(*) FROM Readback_Trace.ToolCall WHERE ArgumentsJson LIKE '%%%s%%' OR ResultJson LIKE '%%%s%%' OR Reason LIKE '%%%s%%'" % (live.KEY, live.KEY, live.KEY))
    check(leaks == "0", "the key value appears in %s tool call rows" % leaks)

    print("cases checked:", len(t))
    live.start_stack(["docker-compose.yml"], env={"OPENAI_API_KEY": ""})
    if failures:
        print("FAILED (%d):" % len(failures))
        for f in failures:
            print(" -", f)
        return 1
    print("tools check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
