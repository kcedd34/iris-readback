"""Retrieval end to end, through the agent's policy search tool against a local mock (no real key, no cost): the passages the
tool returns are traced, a human-confirmed case becomes an example and an unconfirmed one never does, a completed review feeds
the pool, and no identifier is in either vector table.
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


import live_mock_check as live
from tools_check import calls_of


def start_stack():
    live.start_stack(live.FILES, env={"READBACK_DEMO_PASSWORD": PASSWORD})
    compose("exec", "-d", "iris", "python3", "/opt/readback/tests/e2e/mock_openai.py")
    time.sleep(2)
    check(live.set_setting("Readback.Agent", "Adapter", "ProviderConfig", '{"api_key":"@{env:OPENAI_API_KEY}","base_url":"http://127.0.0.1:8099/v1/"}'), "could not point the agent item at the mock")
    time.sleep(3)


def search_result(trace_id):
    """The parsed result of the policy search tool of a decision, or None."""
    for row in calls_of(trace_id):
        if row["Tool"] == "search_policy" and row["Status"] == "ok":
            return json.loads(row["ResultJson"])
    return None


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
    return oru(control_id, "SYN94%05d" % n, "2823-3", "Potassium", "6.8", "mmol/L", ref="MODE:toolhemo", indices=[("HEMOLYSIS_INDEX", "250")])


def main():
    start_stack()
    ready = wait_for(lambda: scalar("SELECT COUNT(*) FROM Ens_Util.Log WHERE Text LIKE 'Retrieval engine ready%'") not in ("", "0"), 240, 3)
    check(bool(ready), "the retrieval operation never reported ready")
    tag = "RTR%d" % (int(time.time()) % 100000)
    hemo = ["%s-H%02d" % (tag, i) for i in range(20)]
    similar = tag + "-S1"
    review_src = tag + "-REV"
    review_sim = tag + "-S2"
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
    check(all("recollect-hemolysis" in json.dumps(search_result(t[m]["ID"]) or {}) for m in with_passage), "a passage in the trace is not in the result the agent was handed")
    check(all(t[m]["IndexVersion"] != "" and t[m]["RetrievalNote"] == "" for m in hemo), "index version or retrieval note wrong in the trace")
    first = t[sorted(hemo, key=lambda m: int(t[m]["ID"]))[0]]
    check((search_result(first["ID"]) or {}).get("similarCases") == [], "a fresh pool must hand the agent no similar confirmed case")
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
            sim = (search_result(s1["ID"]) or {}).get("similarCases") or [{}]
            check(sim[0].get("id") == "similar-case-1" and sim[0].get("decision") == "critical" and sim[0].get("route") == "readback", "the case example is not handed to the agent in its shape: %s" % sim[0])
            check(json.loads(s1["CaseLabels"] or "[]")[:1] == ["similar-case-1"], "case labels not traced")

    # 3. A completed review feeds the pool.
    # A case whose agent asks for a tool that does not exist goes to a person: that is the review the test completes.
    send([oru(review_src, "SYN9400200", "2823-3", "Potassium", "4.2", "mmol/L", ref="MODE:toolunknown")])
    rev = wait_for(lambda: tasks_of("reviewer1", PASSWORD) and next((i for i in tasks_of("reviewer1", PASSWORD) if review_src in i.get("subject", "")), None), 60)
    check(bool(rev), "no review task appeared for the case without a recording")
    if rev:
        # The trace records the task only after the assignment: completing it before that leaves nothing to record against.
        check(bool(wait_for(lambda: (trace(review_src) or {}).get("TaskId", "") not in ("", "UNASSIGNED"), 30)), "the review task was not recorded in the trace in time")
        status, text = call("reviewer1", PASSWORD, "POST", "/task/" + rev["id"], {"action": "Reviewed", "formFields": {"Note": "Looked at it"}})
        done = wait_for(lambda: scalar("SELECT ReviewedBy FROM Readback_Trace.Decision WHERE MessageControlId = '%s'" % review_src) == "reviewer1", 20)
        check(bool(done), "the review was not recorded in the trace: %s %s" % (status, text[:100]))
        reviewed_trace = trace(review_src)["ID"]
        # The agent searches for the description of the reviewed case; the pool must hand that case back as an example.
        description = iris('set l=##class(Readback.Msg.LabResult).%New() set l.AnalyteCode="2823-3", l.ValueText="4.2", l.ValueNumeric=4.2, l.Unit="mmol/L", l.PatientId="SYN9400200", l.MessageControlId="x"\n'
                           'write "RB_DESC="_##class(Readback.Retrieval.Describe).Text(l),!')
        text = description[0].split("=", 1)[1] if description else "potassium 4.2 mmol/L"
        subprocess.run(["docker", "compose", "exec", "-T", "iris", "sh", "-c", "cat > /tmp/mock-query"], cwd=ROOT, text=True, input=text, check=True)
        send([oru(review_sim, "SYN9400201", "2823-3", "Potassium", "4.2", "mmol/L", ref="MODE:toolquery")])
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
    live.start_stack(["docker-compose.yml"], env={"OPENAI_API_KEY": "", "READBACK_DEMO_PASSWORD": PASSWORD})
    print("retrieval check passed: %d of 20 hemolysis cases retrieved the recollect passage" % len(with_passage))
    return 0


if __name__ == "__main__":
    sys.exit(main())
