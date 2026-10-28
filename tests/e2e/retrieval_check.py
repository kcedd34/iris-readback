"""Retrieval end to end, replay mode, fresh stack: policy passages reach the agent text and are traced, a
human-confirmed case becomes an example and an unconfirmed one never does, a completed review feeds the pool,
and no identifier is in either vector table.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import time

from common import ROOT, compose, iris, oru, query, scalar, wait_for
from readback_check import call, tasks_of
import make_hostile
import send_tcp

PASSWORD = "demo-pass-for-tests"
CALM = json.dumps({"decision": "NON_CRITICAL", "severity": 0, "rationale": "Looks normal.", "evidence": ["current-result"], "confidence": "high"}, sort_keys=True)
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)
        print("FAIL:", message)


def start_stack():
    compose("up", "-d", "--build", "--force-recreate", extra_env={"OPENAI_API_KEY": "", "READBACK_DEMO_PASSWORD": PASSWORD})
    subprocess.run([os.path.join(ROOT, "src/ops/verify.sh"), "240"], cwd=ROOT, check=True, capture_output=True)


def load_recordings(ids):
    with tempfile.TemporaryDirectory() as work:
        path = os.path.join(work, "retrieval.jsonl")
        with open(path, "wb") as handle:
            for mid in ids:
                row = {"messageControlId": mid, "promptVersion": make_hostile.prompt_version(), "replaySet": "retrieval", "answer": CALM,
                       "model": "fixture", "inputTokens": 100, "outputTokens": 50, "source": "fixture"}
                handle.write((json.dumps(row, sort_keys=True) + "\n").encode("ascii"))
        compose("cp", path, "iris:/tmp/retrieval.jsonl")
    lines = iris('set sc=##class(Readback.Replay.Recording).LoadFile("/tmp/retrieval.jsonl",.n)\n'
                 'write "RB_LOAD="_$select($system.Status.IsOK(sc):n,1:$system.Status.GetErrorText(sc)),!\n'
                 'do ##class(Readback.Replay.Recording).Activate("retrieval")')
    return any(l == "RB_LOAD=%d" % len(ids) for l in lines)


def send(texts):
    with tempfile.TemporaryDirectory() as work:
        paths = []
        for i, text in enumerate(texts):
            path = os.path.join(work, "m%d.hl7" % i)
            with open(path, "wb") as handle:
                handle.write(text.encode("ascii"))
            paths.append(path)
        return send_tcp.send_many(paths)


COLUMNS = ["ID", "Route", "TaskId", "PassageIds", "CaseLabels", "CaseTraceIds", "IndexVersion", "RetrievalNote", "InputText", "AgentCalled"]


def trace(control_id):
    rows = query("SELECT %s FROM Readback_Trace.Decision WHERE MessageControlId='%s' ORDER BY ID DESC" % (",".join(COLUMNS), control_id), COLUMNS)
    return rows[0] if rows else None


def hemolysis(control_id, n):
    return oru(control_id, "SYN94%05d" % n, "2823-3", "Potassium", "6.8", "mmol/L", indices=[("HEMOLYSIS_INDEX", "250")])


def main():
    start_stack()
    ready = wait_for(lambda: scalar("SELECT COUNT(*) FROM Ens_Util.Log WHERE Text LIKE 'Retrieval engine ready%'") not in ("", "0"), 240, 3)
    check(bool(ready), "the retrieval operation never reported ready")
    tag = "RTR%d" % (int(time.time()) % 100000)
    hemo = ["%s-H%02d" % (tag, i) for i in range(20)]
    similar = tag + "-S1"
    review_src = tag + "-REV"
    review_sim = tag + "-S2"
    check(load_recordings(hemo + [similar, review_sim]), "the recording set did not load")
    if failures:
        return 1

    # 1. Twenty hemolysis cases: the recollect passage is retrieved, shown with its id, and traced.
    check(all(a == "AA" for _, a in send([hemolysis(mid, i) for i, mid in enumerate(hemo)])), "an intake acknowledgement was not AA")
    t = {mid: wait_for(lambda m=mid: trace(m), 120) for mid in hemo}
    check(all(t.values()), "not every hemolysis case has a trace")
    if failures:
        return 1
    with_passage = [m for m in hemo if "recollect-hemolysis" in t[m]["PassageIds"]]
    check(len(with_passage) >= 18, "recollect-hemolysis retrieved for only %d of 20 hemolysis cases" % len(with_passage))
    check(all("[recollect-hemolysis]" in t[m]["InputText"] for m in with_passage), "a retrieved passage is not in the agent text with its id")
    check(all(t[m]["IndexVersion"] != "" and t[m]["RetrievalNote"] == "" for m in hemo), "index version or retrieval note wrong in the trace")
    first = t[sorted(hemo, key=lambda m: int(t[m]["ID"]))[0]]
    check("No similar confirmed case." in first["InputText"], "a fresh pool must say there is no similar confirmed case")
    check(all(json.loads(t[m]["CaseTraceIds"] or "[]") == [] for m in sorted(hemo, key=lambda m: int(t[m]["ID"]))[:1]), "the first case had a case example on a fresh pool")

    # 2. A matched read-back makes its case an example; unconfirmed ones never are.
    check(bool(wait_for(lambda: call("communicator1", PASSWORD, "GET", "/user-info")[0] == 200, 240, 3)), "workflow-rest is not answering")
    # The trace records the task only after assignment; wait for that so lists are reliable.
    check(bool(wait_for(lambda: all(t[m]["TaskId"] not in ("", "UNASSIGNED") for m in hemo) or all((trace(m) or {}).get("TaskId", "") not in ("", "UNASSIGNED") for m in hemo), 60)), "tasks were not assigned")

    def find_task():
        for candidate in ("communicator1", "communicator2"):
            for item in tasks_of(candidate, PASSWORD) or []:
                for mid in hemo:
                    if mid in item.get("subject", ""):
                        return candidate, item, mid
        return None

    found = wait_for(find_task, 60)
    user, task, confirmed_id = found if found else (None, None, None)
    check(task is not None, "no read-back task found among the hemolysis cases")
    if task:
        status, text = call(user, PASSWORD, "POST", "/task/" + task["id"], {"action": "Communicated", "formFields": {"ToldWho": "Dr Example", "ReadbackValue": "6.8"}})
        done = wait_for(lambda: scalar("SELECT ConfirmedBy FROM Readback_Trace.Decision WHERE MessageControlId = '%s'" % confirmed_id) == user, 20)
        check(bool(done), "the read-back confirmation was not recorded: %s %s" % (status, text[:100]))
        confirmed_trace = t[confirmed_id]["ID"]
        send([hemolysis(similar, 90)])
        s1 = wait_for(lambda: trace(similar), 60)
        check(bool(s1), "no trace for the similar result")
        if s1:
            ids = json.loads(s1["CaseTraceIds"] or "[]")
            check(str(confirmed_trace) in [str(i) for i in ids], "the confirmed case is not an example for a similar result: %s" % ids)
            others = {str(t[m]["ID"]) for m in hemo if m != confirmed_id}
            check(not (others & {str(i) for i in ids}), "an unconfirmed case was used as an example")
            check("similar-case-1:" in s1["InputText"] and "Decision: critical. Route: readback." in s1["InputText"], "the case example is not in the agent text in its shape")
            check(json.loads(s1["CaseLabels"] or "[]")[:1] == ["similar-case-1"], "case labels not traced")

    # 3. A completed review feeds the pool.
    send([oru(review_src, "SYN9400200", "2823-3", "Potassium", "4.2", "mmol/L")])
    rev = wait_for(lambda: tasks_of("reviewer1", PASSWORD) and next((i for i in tasks_of("reviewer1", PASSWORD) if review_src in i.get("subject", "")), None), 60)
    check(bool(rev), "no review task appeared for the case without a recording")
    if rev:
        status, text = call("reviewer1", PASSWORD, "POST", "/task/" + rev["id"], {"action": "Reviewed", "formFields": {"Note": "Looked at it"}})
        done = wait_for(lambda: scalar("SELECT ReviewedBy FROM Readback_Trace.Decision WHERE MessageControlId = '%s'" % review_src) == "reviewer1", 20)
        check(bool(done), "the review was not recorded in the trace: %s %s" % (status, text[:100]))
        reviewed_trace = trace(review_src)["ID"]
        send([oru(review_sim, "SYN9400201", "2823-3", "Potassium", "4.2", "mmol/L")])
        s2 = wait_for(lambda: trace(review_sim), 60)
        check(bool(s2), "no trace for the result similar to the reviewed one")
        if s2:
            check(str(reviewed_trace) in [str(i) for i in json.loads(s2["CaseTraceIds"] or "[]")], "a reviewed case did not become an example: %s" % s2["CaseTraceIds"])

    # 4. No identifier in either vector table.
    for table in ("Readback_Retrieval.PolicyVec", "Readback_Retrieval.CaseVec"):
        texts = query("SELECT text FROM %s" % table, ["text"])
        check(len(texts) > 0, table + " is empty")
        bad = [x["text"][:60] for x in texts if re.search(r"SYN\d|%s|RB[A-Z0-9]*-\d" % tag, x["text"])]
        check(not bad, "%s holds an identifier: %s" % (table, bad[:2]))

    if failures:
        print("FAILED (%d):" % len(failures))
        for item in failures[:25]:
            print(" -", item)
        return 1
    print("retrieval check passed: %d of 20 hemolysis cases retrieved the recollect passage" % len(with_passage))
    return 0


if __name__ == "__main__":
    sys.exit(main())
