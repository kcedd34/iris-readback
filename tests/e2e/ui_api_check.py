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

from common import iris, oru, query, scalar, wait_for
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
    # The feed of decisions: closed field list, newest first, paged, bounded, and no patient identifier.
    status, text, took = call(API, "observer", "GET", "/decisions?limit=5")
    feed = js(text) or {}
    check(status == 200 and set(feed) == {"items", "more"}, "/decisions did not answer {items, more}: %s %s" % (status, text[:120]))
    items = feed.get("items", [])
    stored = scalar("SELECT COUNT(*) FROM Readback_Trace.Decision")
    check(len(items) <= 5 and (len(items) > 0 or int(stored or 0) == 0), "/decisions?limit=5 returned %d items with %s decisions stored" % (len(items), stored))
    check([i["decisionId"] for i in items] == sorted((i["decisionId"] for i in items), reverse=True), "the feed is not newest first")
    for item in items:
        check(set(item) <= {"decisionId", "controlId", "analyte", "value", "decidedAt", "mode", "route", "floor", "agent", "final", "held", "conversion", "cost", "rounds", "toolCallCount", "toolFailureCount"},
              "a feed item carries a field outside the contract: %s" % sorted(item))
        check(isinstance(item["held"], bool) and set(item["floor"]) == {"severity", "ruleId", "note"}, "a feed item has a malformed held or floor part")
    if feed.get("more") and items:
        older = (js(call(API, "observer", "GET", "/decisions?limit=5&before=%s" % items[-1]["decisionId"])[1]) or {}).get("items", [])
        check(all(i["decisionId"] < items[-1]["decisionId"] for i in older), "the next page of the feed is not older")
    check(len((js(call(API, "observer", "GET", "/decisions?limit=100000")[1]) or {}).get("items", [])) <= 200, "the feed is not capped at 200")
    blob_feed = call(API, "observer", "GET", "/decisions?limit=200")[1]
    ids_feed = [r["PatientId"] for r in query("SELECT DISTINCT TOP 50 PatientId FROM Readback_Msg.LabResult", ["PatientId"])]
    check(not any(i and i in blob_feed for i in ids_feed), "the feed carries a patient identifier")
    check(not any(k in blob_feed for k in ("InputText", "RawOutput", "rawOutput")), "the feed carries a prompt or a raw output")
    check(call(API, None, "GET", "/decisions")[0] == 401, "/decisions without credentials is not refused")
    check(call(API, "observer", "POST", "/decisions", {})[0] in (404, 405), "a POST to /decisions is not refused")
    # What the agent read must reach the public observer: the read-only role needs SELECT on the tool call rows, or both lists come back empty.
    with_calls = [i for i in items if i.get("toolCallCount", 0) > 0]
    if with_calls:
        view = js(call(API, "observer", "GET", "/decisions/" + with_calls[0]["controlId"])[1]) or {}
        check(len(view.get("toolCalls", [])) == with_calls[0]["toolCallCount"], "the decision view shows %d tool calls, the feed says %s: the observer cannot read them" % (len(view.get("toolCalls", [])), with_calls[0]["toolCallCount"]))
        flow_entries = [d for d in full.get("decided", []) if d["controlId"] == with_calls[0]["controlId"]]
        check(not flow_entries or len(flow_entries[0]["toolCalls"]) > 0, "the flow entry of a case with tool calls lists none")
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
    first = call(API, "observer", "POST", "/flow/submit", {"scenarioId": "hemoglobin-in-range"})
    check(first[0] == 200 and js(first[1]).get("accepted") is True, "a valid submit did not answer accepted: %s %s" % first[:2])
    second = call(API, "observer", "POST", "/flow/submit", {"scenarioId": "hemoglobin-in-range"})
    check(second[0] == 429, "a second submit within a second is not refused with 429 (got %s)" % second[0])
    check("error" in (js(second[1]) or {}), "the 429 body is not the product's error body")
    # Without credentials the platform refuses, whatever the path.
    check(call(API, None, "GET", "/flow")[0] == 401, "/flow without credentials is not refused")


def alerts_part():
    """The same sample submitted twice is two cases with two decisions and two alerts, each with its own level of escalation."""
    ids = []
    for _ in range(2):
        status, text, _ = call(API, "observer", "POST", "/flow/submit", {"scenarioId": "potassium-critical-value"})
        check(status == 200, "submit did not answer 200: %s %s" % (status, text[:100]))
        ids += (js(text) or {}).get("controlIds", [])
        time.sleep(1.3)
    check(len(ids) == 2 and ids[0] != ids[1], "two submissions of the same sample must give two case ids: %s" % ids)
    check(all(i.startswith("RB2026-00001-S") for i in ids), "the case id must carry the sample's id and a suffix of its own: %s" % ids)

    def both_waiting():
        snap = js(call(API, "observer", "GET", "/flow")[1]) or {}
        found = {w["controlId"]: w for w in snap.get("waiting", []) if w.get("controlId") in ids}
        return found if len(found) == 2 else None

    found = wait_for(both_waiting, 60)
    check(found is not None, "both submissions did not reach the waiting list")
    if not found:
        return
    check(found[ids[0]]["decisionId"] != found[ids[1]]["decisionId"], "the two cases share one decision")

    def alert_of(case):
        return scalar("SELECT ID FROM Ens_Alerting.ManagedAlert WHERE SessionId = (SELECT SessionId FROM Readback_Trace.Decision WHERE MessageControlId = '%s')" % case)

    # The read-back task says the concrete rule, with the value and the limit, and resolves the evidence it cites.
    view = js(call(API, "communicator1", "GET", "/taskview/%s" % found[ids[0]]["decisionId"])[1]) or {}
    lines = view.get("ruleLines") or []
    check(any("8.7 mmol/L \u2265 6.5 mmol/L" in l and "potassium" in l for l in lines), "the task does not state the rule with value and limit: %s" % lines)
    items = ((view.get("agent") or {}).get("evidenceItems")) or []
    check(all(set(i) == {"id", "text"} for i in items), "the evidence items do not carry an id and a text: %s" % items)
    check(all(i["text"] for i in items if i["id"] == "current-result"), "the current result is not resolved to its value")

    first, second = alert_of(ids[0]), alert_of(ids[1])
    check(first and second and first != second, "the two cases must have two alerts: %s %s" % (first, second))
    iris('set a=##class(Ens.Alerting.ManagedAlert).%%OpenId(%s) set a.EscalationLevel=1 write a.%%Save(),!' % first)

    def levels():
        snap = js(call(API, "observer", "GET", "/flow")[1]) or {}
        now = {w["controlId"]: w for w in snap.get("waiting", []) if w.get("controlId") in ids}
        return now if len(now) == 2 and now[ids[0]].get("alertLevel") == 1 else None

    now = wait_for(levels, 20)
    check(now is not None, "the escalated alert did not show on its own case")
    if now:
        check(not now[ids[1]].get("alertLevel"), "the second case took the first one's level of escalation: %s" % now[ids[1]].get("alertLevel"))
    alerts = js(call(API, "observer", "GET", "/alerts")[1]) or []
    mine = {a["controlId"]: a for a in alerts if a.get("controlId") in ids}
    check(len(mine) == 2 and mine[ids[0]]["decisionId"] != mine[ids[1]]["decisionId"], "the open alerts do not show two decisions: %s" % list(mine))


def decisions_part():
    """What the Decisions screen is fed: the held seal, the rounded conversion and the concrete rule in the detail of the floor."""
    def feed_item(case):
        feed = js(call(API, "observer", "GET", "/decisions?limit=50")[1]) or {}
        return next((i for i in feed.get("items", []) if i["controlId"] == case), None)

    cases = {}
    for scenario in ("potassium-agent-tries-to-lower", "glucose-sharp-rise"):
        status, text, _ = call(API, "observer", "POST", "/flow/submit", {"scenarioId": scenario})
        check(status == 200, "submit of %s did not answer 200: %s" % (scenario, text[:100]))
        cases[scenario] = (js(text) or {}).get("controlIds", ["?"])[-1]
        time.sleep(1.3)
    held = wait_for(lambda: feed_item(cases["potassium-agent-tries-to-lower"]), 60)
    check(held is not None, "the held case did not reach the feed")
    if held:
        check(held["held"] is True and held["floor"]["severity"] == 3 and held["final"]["severity"] == 3, "the floor did not hold: %s" % held)
        check(held["agent"].get("severity", 3) < 3, "the agent was meant to answer below critical: %s" % held["agent"])
        check(held["route"] == "readback", "the held case must stay at read-back: %s" % held["route"])
        check(held["value"] == {"text": "6.7", "unit": "mmol/L"}, "the feed does not carry the value of the result: %s" % held.get("value"))
        detail = js(call(API, "observer", "GET", "/decisions/%s" % held["controlId"])[1]) or {}
        lines = detail.get("ruleLines") or []
        check(any("6.7 mmol/L \u2265 6.5 mmol/L" in l for l in lines), "the detail of the floor does not state the rule with value and limit: %s" % lines)
    glucose = wait_for(lambda: feed_item(cases["glucose-sharp-rise"]), 60)
    check(glucose is not None, "the glucose case did not reach the feed")
    if glucose:
        conv = glucose.get("conversion") or {}
        check(conv.get("unit") == "mmol/L" and len(str(conv.get("converted", "")).split(".")[-1]) == 1 and "." in str(conv.get("converted", "")), "the conversion is not rounded to one decimal: %s" % conv)
        check(held is None or "conversion" not in held, "a case with no conversion carries a conversion")
        detail = js(call(API, "observer", "GET", "/decisions/%s" % glucose["controlId"])[1]) or {}
        check(len(detail.get("ruleLines") or []) >= 1, "the floor of the glucose case has no rule sentence although its floor is above zero: %s" % detail.get("floorNote"))


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
    parts = os.environ.get("PARTS", "flow,task,alerts,decisions").split(",")
    if "flow" in parts:
        flow_part()
    if "task" in parts:
        task_part()
    if "alerts" in parts:
        alerts_part()
    if "decisions" in parts:
        decisions_part()
    if failures:
        print("FAILED (%d)" % len(failures))
        return 1
    print("ui api check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
