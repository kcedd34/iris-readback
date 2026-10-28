"""P-7 end to end, replay mode: the budget stops the agent and a critical result never waits for it.

A small hourly token ceiling is loaded through the real reload path, 100 cases are sent, and the trace shows
that the agent stops being called, rule-critical cases still go to read-back, the others go to review with the
literal reason, the status endpoint reports the state, a higher ceiling resumes calls without a restart, and a
per-result ceiling below one request gives the result-ceiling reason.
"""
import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

from common import ROOT, compose, iris, oru, query, scalar, wait_for
import make_hostile
import send_tcp

PASSWORD = "demo-pass-for-tests"
CALLS_ALLOWED = 10
TOKENS_PER_CALL = 150
failures = []
CALM = json.dumps({"decision": "NON_CRITICAL", "severity": 0, "rationale": "Looks normal.", "evidence": ["current-result"], "confidence": "high"}, sort_keys=True)


def check(condition, message):
    if not condition:
        failures.append(message)
        print("FAIL:", message)


def start_stack():
    compose("up", "-d", "--build", "--force-recreate", extra_env={"OPENAI_API_KEY": "", "READBACK_DEMO_PASSWORD": PASSWORD})
    subprocess.run([os.path.join(ROOT, "src/ops/verify.sh"), "240"], cwd=ROOT, check=True, capture_output=True)


def api(path):
    token = base64.b64encode(("communicator1:%s" % PASSWORD).encode()).decode()
    request = urllib.request.Request("http://127.0.0.1:%s/readback/api%s" % (os.environ.get("READBACK_PORTAL_PORT", "52790"), path), headers={"Authorization": "Basic " + token})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, response.read().decode()
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode()


def load_recordings(ids):
    with tempfile.TemporaryDirectory() as work:
        path = os.path.join(work, "budget.jsonl")
        with open(path, "wb") as handle:
            for mid in ids:
                row = {"messageControlId": mid, "promptVersion": make_hostile.prompt_version(), "replaySet": "budget", "answer": CALM,
                       "model": "fixture", "inputTokens": 100, "outputTokens": 50, "source": "fixture"}
                handle.write((json.dumps(row, sort_keys=True) + "\n").encode("ascii"))
        compose("cp", path, "iris:/tmp/budget.jsonl")
    lines = iris('set sc=##class(Readback.Replay.Recording).LoadFile("/tmp/budget.jsonl",.n)\n'
                 'write "RB_LOAD="_$select($system.Status.IsOK(sc):n,1:$system.Status.GetErrorText(sc)),!\n'
                 'do ##class(Readback.Replay.Recording).Activate("budget")')
    return any(l == "RB_LOAD=%d" % len(ids) for l in lines)


def set_budget(per_result, cost, tokens):
    text = json.dumps({"perResultTokens": per_result, "hourlyCostUsd": cost, "hourlyTokens": tokens})
    lines = iris('do ##class(%%File).CreateDirectoryChain("/tmp/budgetcheck")\n'
                 'set f=##class(%%Stream.FileCharacter).%%New() do f.LinkToFile("/tmp/budgetcheck/budget.json") do f.Write("%s") do f.%%Save()\n'
                 'set sc=##class(Readback.Config.Loader).LoadBudget("/tmp/budgetcheck/budget.json")\n'
                 'write "RB_SET="_$select($system.Status.IsOK(sc):"ok",1:$system.Status.GetErrorText(sc)),!' % text.replace('"', '""'))
    return "RB_SET=ok" in lines


def window_used():
    lines = iris('write "RB_USED="_##class(Readback.Budget.Guard).Now("fixture").used,!')
    return int(float([l for l in lines if l.startswith("RB_USED=")][0].split("=")[1]))


def send(texts):
    with tempfile.TemporaryDirectory() as work:
        paths = []
        for i, text in enumerate(texts):
            path = os.path.join(work, "m%d.hl7" % i)
            with open(path, "wb") as handle:
                handle.write(text.encode("ascii"))
            paths.append(path)
        return send_tcp.send_many(paths)


def trace(control_id):
    rows = query("SELECT ID,AgentCalled,BudgetState,BudgetBasis,Route,FloorSeverity,FinalSeverity,FailureKind,FailureReason FROM Readback_Trace.Decision WHERE MessageControlId='%s' ORDER BY ID DESC" % control_id,
                 ["ID", "AgentCalled", "BudgetState", "BudgetBasis", "Route", "FloorSeverity", "FinalSeverity", "FailureKind", "FailureReason"])
    return rows[0] if rows else None


def main():
    start_stack()
    tag = "BDG%d" % (int(time.time()) % 100000)
    ids = ["%s-%03d" % (tag, i) for i in range(100)]
    later = ["%s-L%d" % (tag, i) for i in range(5)]
    single = tag + "-R"
    check(load_recordings(ids + later + [single]), "the recording set did not load")
    base = window_used()
    check(set_budget(6000, 5.0, base + CALLS_ALLOWED * TOKENS_PER_CALL), "the budget file did not load")

    critical = {mid for i, mid in enumerate(ids) if i % 4 == 0}
    texts = [oru(mid, "SYN96%05d" % i, "2823-3", "Potassium", "6.9" if mid in critical else "4.0", "mmol/L") for i, mid in enumerate(ids)]
    check(all(a == "AA" for _, a in send(texts)), "an intake acknowledgement was not AA")
    t = {}
    for mid in ids:
        t[mid] = wait_for(lambda m=mid: trace(m), 120)
    check(all(t.values()), "not every case has a trace")
    if failures:
        return 1

    ordered = sorted(ids, key=lambda m: int(t[m]["ID"]))
    called = [m for m in ordered if t[m]["AgentCalled"] == "1"]
    skipped = [m for m in ordered if t[m]["AgentCalled"] != "1"]
    check(CALLS_ALLOWED <= len(called) <= CALLS_ALLOWED + 2, "expected about %d agent calls (pool of 2 may overshoot by 2), saw %d" % (CALLS_ALLOWED, len(called)))
    check(len(skipped) >= 100 - CALLS_ALLOWED - 2, "too few cases skipped the agent: %d" % len(skipped))
    check(all(t[m]["AgentCalled"] != "1" for m in ordered[-60:]), "the agent was called again after the ceiling was reached")
    for m in skipped:
        row = t[m]
        check(row["BudgetState"] == "hourly-ceiling" and row["BudgetBasis"] == "tokens", "%s: budget state %s/%s" % (m, row["BudgetState"], row["BudgetBasis"]))
        check(row["FailureKind"] == "budget-reached", "%s: failure kind %s" % (m, row["FailureKind"]))
        if m in critical:
            check(row["Route"] == "readback" and row["FinalSeverity"] == "3", "%s: a rule-critical case must stay on read-back, got %s" % (m, row["Route"]))
        else:
            check(row["Route"] == "review" and row["FailureReason"] == "budget reached: hourly ceiling", "%s: expected review with the literal reason, got %s / %s" % (m, row["Route"], row["FailureReason"]))
    check(any(m in critical for m in skipped), "no rule-critical case was skipped, so the critical path was not exercised")

    status, text = api("/status")
    check(status == 200, "status did not answer: %s" % status)
    if status == 200:
        body = json.loads(text)
        b = body.get("budget", {})
        check(b.get("state") == "reached" and b.get("basis") == "tokens", "status budget block: %s" % b)
        check(b.get("hourlyTokens") == base + CALLS_ALLOWED * TOKENS_PER_CALL and b.get("perResultTokens") == 6000, "status shows the ceilings: %s" % b)
        check("sk-" not in text and "api_key" not in text.lower(), "the status response carries key-like text")

    # A higher ceiling applies without a restart and calls resume.
    check(set_budget(6000, 5.0, base + 1000000), "the higher budget did not load")
    send([oru(mid, "SYN9690%02d" % i, "2823-3", "Potassium", "4.0", "mmol/L") for i, mid in enumerate(later)])
    resumed = [wait_for(lambda m=mid: trace(m), 60) for mid in later]
    check(all(resumed), "no trace for the cases after the ceiling was raised")
    if all(resumed):
        check(all(r["AgentCalled"] == "1" and r["BudgetState"] == "ok" for r in resumed), "calls did not resume after the ceiling was raised: %s" % [(r["AgentCalled"], r["BudgetState"]) for r in resumed])
    status, text = api("/status")
    check(status == 200 and json.loads(text)["budget"]["state"] == "ok", "status did not return to ok")

    # A per-result ceiling below one request.
    check(set_budget(100, 5.0, base + 1000000), "the small per-result budget did not load")
    send([oru(single, "SYN9699001", "2823-3", "Potassium", "4.0", "mmol/L")])
    one = wait_for(lambda: trace(single), 60)
    check(bool(one) and one["BudgetState"] == "result-ceiling" and one["AgentCalled"] != "1" and one["FailureReason"] == "budget reached: result ceiling", "result ceiling case: %s" % one)

    iris('set sc=##class(Readback.Config.Loader).LoadAll()\ndo ##class(Readback.Replay.Recording).Activate("default")')

    if failures:
        print("FAILED (%d):" % len(failures))
        for item in failures[:30]:
            print(" -", item)
        return 1
    print("budget check passed: %d agent calls, %d skipped (%d rule-critical on read-back)" % (len(called), len(skipped), len([m for m in skipped if m in critical])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
