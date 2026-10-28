"""Replay mode end to end: no provider key, recorded answers, honest labeling, same human step.

Starts the stack with no key, processes the committed sample messages twice and checks invariants that hold whatever
the recorded answers say: every case reaches a decision, the two runs agree, a rule-critical case stays critical, a
divergence is recorded whenever the agent is below the floor, the trace names the recording's model and keeps its latency,
a case with no recording goes to a human, and a read-back completes as in live mode.

The three behaviours that need a particular answer (the agent lowering a critical, advising a new sample on a hemolyzed
critical, raising an acute drop) are driven by test-only recordings in a replay set of their own, loaded for the test and
removed afterwards. They are never written to the recordings that ship with the product.
"""
import json
import os
import subprocess
import sys
import tempfile
import time

from common import ROOT, compose, iris, query, scalar, wait_for
from readback_check import call, tasks_of
import send_tcp

PASSWORD = "demo-pass-for-tests"
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)
        print("FAIL:", message)


def start_stack():
    compose("up", "-d", "--build", "--force-recreate", extra_env={"OPENAI_API_KEY": "", "READBACK_DEMO_PASSWORD": PASSWORD})
    subprocess.run([os.path.join(ROOT, "src/ops/verify.sh"), "240"], cwd=ROOT, check=True, capture_output=True)


def messages():
    """(id, text, category, role) for the committed sample set, history before subject as in the labels file."""
    base = os.path.join(ROOT, "data", "samples", "generated")
    with open(os.path.join(base, "labels.jsonl")) as handle:
        labels = [json.loads(line) for line in handle if line.strip()]
    out = []
    for label in labels:
        with open(os.path.join(base, label["file"]), "rb") as f:
            out.append((label["messageId"], f.read(), label["category"], label["role"]))
    for name, mid in (("valid-oru-1.hl7", "RBSAMPLE0001"), ("valid-oru-2.hl7", "RBSAMPLE0002")):
        with open(os.path.join(ROOT, "data", "samples", name), "rb") as f:
            out.append((mid, f.read(), "hand-sample", "subject"))
    return out


def send(payloads):
    with tempfile.TemporaryDirectory() as work:
        paths = []
        for i, data in enumerate(payloads):
            path = os.path.join(work, "m%d.hl7" % i)
            with open(path, "wb") as handle:
                handle.write(data)
            paths.append(path)
        return send_tcp.send_many(paths)


def traces(control_id):
    return query("SELECT Mode,Provider,Model,RecordedLatencyMs,RawOutput,Route,FinalSeverity,FloorSeverity,AgentDecision,AgentSeverity,Divergence,FailureKind,FailureReason,TaskId "
                 "FROM Readback_Trace.Decision WHERE MessageControlId='%s' ORDER BY ID" % control_id,
                 ["Mode", "Provider", "Model", "RecordedLatencyMs", "RawOutput", "Route", "FinalSeverity", "FloorSeverity", "AgentDecision", "AgentSeverity", "Divergence", "FailureKind", "FailureReason", "TaskId"])


def shipped_recordings():
    """The rows of the default replay set in the file that ships with the product, by message id."""
    with open(os.path.join(ROOT, "data", "replay", "recordings.jsonl")) as handle:
        rows = [json.loads(line) for line in handle if line.strip()]
    return {r["messageControlId"]: r for r in rows if r.get("replaySet", "default") == "default"}


DELETE_STANDINS = 'set rs=##class(%SQL.Statement).%ExecDirect(,"DELETE FROM Readback_Replay.Recording WHERE ReplaySet = \'standin\'")'
ANSWER = '{"decision":"%s","severity":%d,"rationale":"test-only answer","evidence":["current-result"],"confidence":"high"}'


def load_standins(answers):
    """answers: message id -> (decision, severity). Test-only recordings in the replay set 'standin', labelled fixture."""
    lines = [DELETE_STANDINS]
    for mid, (decision, severity) in answers.items():
        text = (ANSWER % (decision, severity)).replace('"', '""')
        lines.append('set r=##class(Readback.Replay.Recording).%New()  set r.ReplaySet="standin", r.MessageControlId="' + mid + '", r.PromptVersion=##class(Readback.Triage.Prompt).#Version, r.AnswerText="' + text
                     + '", r.Model="fixture", r.InputTokens=1, r.OutputTokens=1, r.Source="fixture"  do r.%Save()')
    lines.append('write "RB_STANDIN_OK",!')
    return "RB_STANDIN_OK" in iris("\n".join(lines))


def activate(replay_set):
    return any(l == "RB_ACTIVE=ok" for l in iris('set sc=##class(Readback.Replay.Recording).Activate("%s")\nwrite "RB_ACTIVE="_$select($system.Status.IsOK(sc):"ok",1:"failed"),!' % replay_set))


def main():
    start_stack()
    ready = wait_for(lambda: call("communicator1", PASSWORD, "GET", "/user-info")[0] == 200, 240, 3)
    check(bool(ready), "workflow-rest is not answering")
    status, text = (0, "")
    import urllib.request, base64, urllib.error
    def api(path):
        token = base64.b64encode(("communicator1:%s" % PASSWORD).encode()).decode()
        req = urllib.request.Request("http://127.0.0.1:%s/readback/api%s" % (os.environ.get("READBACK_PORTAL_PORT", "52790"), path), headers={"Authorization": "Basic " + token})
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                return r.status, r.read().decode()
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode()
    status, text = api("/status")
    check(status == 200, "the status endpoint did not answer: %s %s" % (status, text[:100]))
    if status == 200:
        body = json.loads(text)
        check(body["mode"] == "replay", "status does not say replay: %s" % body["mode"])
        check(body["recordingsLoaded"] == len(shipped_recordings()), "expected %d recordings loaded, got %s" % (len(shipped_recordings()), body["recordingsLoaded"]))
        check(body["productionRunning"] is True, "the production is not running")
        check("sk-" not in text and "api_key" not in text.lower(), "the status response carries key-like text")

    items = messages()
    ids = [m[0] for m in items]
    for run in (1, 2):
        acks = send([m[1] for m in items])
        check(all(a == "AA" for _, a in acks), "run %d: an acknowledgement was not AA" % run)
        done = wait_for(lambda: all(len(traces(i)) >= run for i in ids), 90, 2)
        check(bool(done), "run %d: not every case reached a decision" % run)
    if failures:
        return 1

    recordings = shipped_recordings()
    by_category = {}
    for mid, _, category, role in items:
        t = traces(mid)
        check(len(t) >= 2, "%s: expected two trace records, found %d" % (mid, len(t)))
        if len(t) < 2:
            continue
        first, second = t[-2], t[-1]
        check(first["RawOutput"] == second["RawOutput"] and first["RawOutput"] != "", "%s: the two runs gave different agent answers" % mid)
        check(first["Mode"] == "replay" and first["Provider"] == "replay", "%s: not labeled replay: %s/%s" % (mid, first["Mode"], first["Provider"]))
        check(first["Route"] in ("readback", "review", "recollect", "release"), "%s: no final route" % mid)
        check(first["FailureKind"] in ("", "low-confidence", "schema-invalid"), "%s: unexpected failure %s %s" % (mid, first["FailureKind"], first["FailureReason"]))
        if first["FloorSeverity"] == "3":
            check(first["FinalSeverity"] == "3" and first["Route"] == "readback", "%s: a rule-critical result did not stay critical: %s" % (mid, first))
        if first["AgentSeverity"] != "" and int(first["AgentSeverity"]) < int(first["FloorSeverity"] or 0):
            check(first["Divergence"] != "", "%s: the agent was below the floor and no divergence was recorded: %s" % (mid, first))
        rec = recordings.get(mid)
        if rec:
            check(first["Model"] == rec.get("model"), "%s: the trace names %r, the recording %r" % (mid, first["Model"], rec.get("model")))
            if rec.get("latencyMs") not in (None, ""):
                check(first["RecordedLatencyMs"] == str(rec["latencyMs"]), "%s: recorded latency %r, expected %r" % (mid, first["RecordedLatencyMs"], rec["latencyMs"]))
        by_category.setdefault((category, role), []).append((mid, first))

    # The behaviours that need a particular answer are driven by test-only recordings in their own set.
    pick = {c: by_category[(c, "subject")][0][0] for c in ("explainable-false-critical", "sample-problem", "acute-drop-in-range") if by_category.get((c, "subject"))}
    check(len(pick) == 3, "the sample set lacks a subject case of each of the three special categories: %s" % sorted(pick))
    if len(pick) == 3:
        answers = {pick["explainable-false-critical"]: ("NON_CRITICAL", 0), pick["sample-problem"]: ("RECOLLECT", 1), pick["acute-drop-in-range"]: ("CRITICAL", 3)}
        check(load_standins(answers) and activate("standin"), "the test-only recordings could not be loaded")
        special = [m for m in items if m[0] in pick.values()]
        send([m[1] for m in special])
        done = wait_for(lambda: all(len(traces(m[0])) >= 3 for m in special), 60, 2)
        check(bool(done), "the three special cases did not reach a third decision")
        t = traces(pick["explainable-false-critical"])[-1]
        check(t["FloorSeverity"] == "3" and t["AgentDecision"] == "NON_CRITICAL" and t["FinalSeverity"] == "3" and t["Divergence"] != "",
              "the NON_CRITICAL answer did not diverge from a critical floor: %s" % t)
        t = traces(pick["sample-problem"])[-1]
        check(t["AgentDecision"] == "RECOLLECT" and t["Route"] == "readback" and t["FinalSeverity"] == "3", "a rule-critical hemolyzed potassium must stay critical with the recollect advice: %s" % t)
        t = traces(pick["acute-drop-in-range"])[-1]
        check(t["FloorSeverity"] == "0" and t["Route"] == "readback" and t["AgentDecision"] == "CRITICAL", "the acute drop was not raised by the agent: %s" % t)
        iris(DELETE_STANDINS + '\nwrite "RB_GONE",!')
        check(activate("default"), "the default replay set could not be selected again")

    # A case with no recording goes to a human; a rule-critical one stays critical.
    from common import oru
    tag = "RPL%d" % (int(time.time()) % 100000)
    send([oru(tag + "-CRIT", "SYN9600001", "2823-3", "Potassium", "6.9", "mmol/L").encode("ascii"),
          oru(tag + "-CALM", "SYN9600002", "2823-3", "Potassium", "4.0", "mmol/L").encode("ascii")])
    crit = wait_for(lambda: traces(tag + "-CRIT"), 30)
    calm = wait_for(lambda: traces(tag + "-CALM"), 30)
    if crit:
        check(crit[-1]["FailureKind"] == "no-recorded-answer" and crit[-1]["Route"] == "readback" and crit[-1]["FinalSeverity"] == "3", "no recording, rule-critical: %s" % crit[-1])
    if calm:
        check(calm[-1]["FailureKind"] == "no-recorded-answer" and calm[-1]["Route"] == "review" and calm[-1]["FailureReason"] == "no recorded answer", "no recording, not critical: %s" % calm[-1])

    # The decision endpoint serves the trace and says replay.
    status, text = api("/decisions/RBSAMPLE0001")
    check(status == 200 and json.loads(text)["mode"] == "replay" and json.loads(text)["provider"] == "replay", "the decision endpoint did not state replay: %s" % text[:150])

    # The human step is the same as in live mode.
    def find_task():
        for user in ("communicator1", "communicator2"):
            for task in tasks_of(user, PASSWORD) or []:
                if "RBSAMPLE0001" in task.get("subject", ""):
                    return user, task
        return None
    found = wait_for(find_task, 30)
    check(bool(found), "no read-back task for RBSAMPLE0001")
    if found:
        user, task = found
        check(task["subject"].startswith("[replay] Read-back "), "the task subject does not say replay")
        status, text = call(user, PASSWORD, "POST", "/task/" + task["id"], {"action": "Communicated", "formFields": {"ToldWho": "Dr Example", "ReadbackValue": "9.6"}})
        check(status != 200, "a divergent read-back was accepted in replay mode")
        status, text = call(user, PASSWORD, "POST", "/task/" + task["id"], {"action": "Communicated", "formFields": {"ToldWho": "Dr Example", "ReadbackValue": "6.9"}})
        check(status == 200, "the matching read-back was refused in replay mode: %s" % text[:150])
        closed = wait_for(lambda: not any(t["id"] == task["id"] for t in tasks_of(user, PASSWORD) or []), 15)
        check(bool(closed), "the task did not close after a matching read-back in replay mode")

    if failures:
        print("FAILED (%d):" % len(failures))
        for f in failures:
            print(" -", f)
        return 1
    print("replay check passed (%d messages, two runs)" % len(items))
    return 0


if __name__ == "__main__":
    sys.exit(main())
