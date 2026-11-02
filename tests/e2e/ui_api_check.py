"""Contracts of the flow API additions (specs/005-flow-ui/contracts/flow-api.md) against the running replay stack.

Calls the platform's own port as the read-only account (what the proxy does for the public), so it checks the product,
not the proxy. Needs READBACK_DEMO_PASSWORD. The read-back task part runs when PARTS includes task (default all).
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

from common import oru, query, scalar, wait_for
import send_tcp
import tempfile

PORT = os.environ.get("READBACK_PORTAL_PORT", "52790")
API = "http://127.0.0.1:%s/readback/api" % PORT
WF = "http://127.0.0.1:%s/workflow/rest" % PORT
PASSWORD = os.environ.get("READBACK_DEMO_PASSWORD", "")
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)
        print("FAIL:", message)


def call(base, user, method, path, body=None, raw=None):
    headers = {"Accept": "application/json", "Content-Type": "application/json"}
    if user:
        headers["Authorization"] = "Basic " + base64.b64encode(("%s:%s" % (user, PASSWORD)).encode()).decode()
    data = raw if raw is not None else (None if body is None else json.dumps(body).encode())
    request = urllib.request.Request(base + path, method=method, data=data, headers=headers)
    started = time.time()
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, response.read().decode(), time.time() - started
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode(), time.time() - started


def js(text):
    try:
        return json.loads(text)
    except ValueError:
        return None


def flow_part():
    status, text, took = call(API, "observer", "GET", "/flow")
    snap = js(text)
    check(status == 200 and isinstance(snap, dict), "/flow did not answer 200 with an object: %s %s" % (status, text[:120]))
    for key in ("mode", "cursor", "decided", "inFlight", "waiting", "waitingTotal", "confirmed"):
        check(key in (snap or {}), "/flow lacks %s" % key)
    check((snap or {}).get("decided") == [], "/flow without after must start from now (decided empty)")
    check(took < 0.5, "/flow took %.0f ms" % (took * 1000))
    status, text, took = call(API, "observer", "GET", "/flow?after=0")
    full = js(text) or {}
    check(status == 200 and len(full.get("decided", [])) <= 200, "/flow?after=0 is not a bounded page")
    check(took < 1.0, "/flow?after=0 took %.0f ms" % (took * 1000))
    for entry in full.get("decided", [])[:5]:
        for key in ("decisionId", "controlId", "analyte", "route", "finalSeverity", "reason", "failureKind", "agentCalled", "mode", "decidedAt", "toolCalls", "rounds", "policyRefusal"):
            check(key in entry, "a decided entry lacks %s" % key)
        check(isinstance(entry.get("toolCalls"), list), "toolCalls of a decided entry is not a list")
        for call_entry in entry.get("toolCalls", []):
            check(set(call_entry) == {"seq", "tool", "status", "summary"}, "a tool call entry of the flow carries more than seq, tool, status and summary: %s" % sorted(call_entry))
    check(call(API, "observer", "GET", "/flow?after=abc")[0] == 400, "after=abc is not refused with 400")
    check(call(API, "observer", "GET", "/flow?after=-1")[0] == 400, "after=-1 is not refused with 400")
    blob = call(API, "observer", "GET", "/flow?after=0")[1]
    patients = scalar("SELECT COUNT(*) FROM Readback_Msg.LabResult")
    ids = [r["PatientId"] for r in query("SELECT DISTINCT TOP 20 PatientId FROM Readback_Msg.LabResult", ["PatientId"])]
    check(not any(i and i in blob for i in ids), "the flow snapshot carries a patient identifier (%s results stored)" % patients)
    key = os.environ.get("OPENAI_API_KEY", "")
    check(not key or key not in blob, "the flow snapshot carries the provider key")

    # The scenarios.
    status, text, _ = call(API, "observer", "GET", "/flow/samples")
    samples = js(text)
    check(status == 200 and isinstance(samples, list) and len(samples) >= 8, "/flow/samples did not list the scenarios")
    for s in samples or []:
        for field in ("id", "label", "analyte", "expected", "messageCount"):
            check(field in s, "a scenario lacks %s" % field)

    # The submit guards.
    check(call(API, "observer", "POST", "/flow/submit", {"scenarioId": "no-such-scenario"})[0] == 400, "an unknown scenario is not refused with 400")
    time.sleep(1.2)
    check(call(API, "observer", "POST", "/flow/submit", {"scenarioId": "potassium-critical-value", "text": "MSH|x"})[0] == 400, "a body with more than the scenario id is not refused")
    time.sleep(1.2)
    check(call(API, "observer", "POST", "/flow/submit", raw=b"MSH|^~\\&|not json")[0] == 400, "a body that is not JSON is not refused")
    time.sleep(1.2)
    check(call(API, "observer", "POST", "/flow/submit", {"scenarioId": 7})[0] == 400, "a scenario id that is not a string is not refused")
    time.sleep(1.2)
    first = call(API, "observer", "POST", "/flow/submit", {"scenarioId": "hemoglobin-low-not-critical"})
    check(first[0] == 200 and js(first[1]).get("accepted") is True, "a valid submit did not answer accepted: %s %s" % first[:2])
    second = call(API, "observer", "POST", "/flow/submit", {"scenarioId": "hemoglobin-low-not-critical"})
    check(second[0] == 429, "a second submit within a second is not refused with 429 (got %s)" % second[0])
    check("error" in (js(second[1]) or {}), "the 429 body is not the product's error body")
    # Without credentials the platform refuses, whatever the path.
    check(call(API, None, "GET", "/flow")[0] == 401, "/flow without credentials is not refused")


def send(texts):
    with tempfile.TemporaryDirectory() as work:
        paths = []
        for i, text in enumerate(texts):
            path = os.path.join(work, "m%d.hl7" % i)
            with open(path, "wb") as handle:
                handle.write(text.encode("ascii"))
            paths.append(path)
        return send_tcp.send_many(paths)


def post_task(user, task_id, told, value):
    path = "/task/" + task_id.replace("|", "%7C")
    return call(WF, user, "POST", path, {"action": "Communicated", "formFields": {"ToldWho": told, "ReadbackValue": value}})


def task_part():
    tag = "UIA%d" % (int(time.time()) % 100000)
    cid = tag + "-1"
    acks = send([oru(cid, "SYN9700001", "2823-3", "Potassium", "6.9", "mmol/L", ref="3.5-5.1")])
    check(all(a == "AA" for _, a in acks), "the intake did not acknowledge AA")
    assigned = wait_for(lambda: query("SELECT TaskId FROM Readback_Trace.Decision WHERE MessageControlId='%s' AND TaskId<>'' AND TaskId<>'UNASSIGNED'" % cid, ["TaskId"]), 40)
    check(bool(assigned), "no assigned task for the case")
    if not assigned:
        return
    did = scalar("SELECT MAX(ID) FROM Readback_Trace.Decision WHERE MessageControlId='%s'" % cid)
    view = lambda user: js(call(API, user, "GET", "/taskview/" + did)[1]) or {}
    owner = (view("observer") or {}).get("assignedTo")
    check(owner in ("communicator1", "communicator2"), "the task has no assignee: %s" % owner)
    other = "communicator2" if owner == "communicator1" else "communicator1"
    task_id = "%s||%s" % (view("observer")["taskId"], owner)

    mine = view(owner)
    for key in ("controlId", "patientId", "analyteName", "valueText", "unit", "reason", "state", "attemptCount", "assignedTo", "canConfirm", "taskId", "mode"):
        check(key in mine, "the task view lacks %s" % key)
    check(mine.get("valueText") == "6.9" and mine.get("unit") == "mmol/L", "the task view does not carry the value as received")
    check(mine.get("state") == "open" and mine.get("canConfirm") is True, "the assignee cannot confirm an open task")
    check(view(other).get("canConfirm") is False and view("observer").get("canConfirm") is False, "someone who is not the assignee can confirm")
    check(call(API, None, "GET", "/taskview/" + did)[0] == 401, "the task view answers without credentials")
    check(call(API, owner, "GET", "/taskview/999999999")[0] == 404, "an unknown decision is not a 404")
    check("patientId" in call(API, owner, "GET", "/taskview/" + did)[1], "the synthetic patient identifier is missing from the person's own task view")
    decisions = call(API, "observer", "GET", "/decisions/" + cid)[1]
    check("SYN9700001" not in decisions, "the public decision view carries the patient identifier")

    # The observer and the other communicator are refused and nothing changes.
    for user in ("observer", other):
        status, text, _ = post_task(user, task_id, "Dr X", "6.9")
        after = view(owner)
        check(after.get("state") == "open" and after.get("attemptCount") == 0, "%s changed the task (state %s, attempts %s)" % (user, after.get("state"), after.get("attemptCount")))
    # A wrong value leaves the task open and records the attempt.
    post_task(owner, task_id, "Dr X", "6.8")
    after = view(owner)
    check(after.get("state") == "open" and after.get("attemptCount") == 1, "a wrong value did not leave the task open with one attempt")
    check((after.get("lastAttempt") or {}).get("matched") is False, "the last attempt is not recorded as a mismatch")
    # An empty told-whom is refused as an attempt that does not count as confirmed.
    post_task(owner, task_id, "", "6.9")
    check(view(owner).get("state") == "open", "an empty told-whom completed the task")
    # The right value completes it and closes the case at read-back.
    post_task(owner, task_id, "Dr X", "6.9")
    done = view(owner)
    check(done.get("state") == "completed" and done.get("confirmedBy") == owner, "the right value did not complete the task as the assignee")
    flow = js(call(API, "observer", "GET", "/flow")[1]) or {}
    check(all(w.get("controlId") != cid for w in flow.get("waiting", [])), "a confirmed case is still listed as waiting")
    check(any(c.get("controlId") == cid and c.get("confirmedBy") == owner for c in flow.get("confirmed", [])), "a confirmed case is not among the recently confirmed")


def main():
    if not PASSWORD:
        print("FAIL: READBACK_DEMO_PASSWORD is not set")
        return 1
    parts = os.environ.get("PARTS", "flow,task").split(",")
    if "flow" in parts:
        flow_part()
    if "task" in parts:
        task_part()
    if failures:
        print("FAILED (%d)" % len(failures))
        return 1
    print("ui api check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
