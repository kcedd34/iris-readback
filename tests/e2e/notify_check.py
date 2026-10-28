"""Notification of critical results end to end, in replay, with no key.

Short windows (8 seconds) through the escalation file. Checks that a critical result opens one alert for the first person with
a delivery and its receipt, that after the window the platform's own escalation moves it to the second person with a second
delivery, that after the list the alert stays open as exhausted, that a delivery which gets no receipt or fails still escalates
and never closes the alert, that a divergent read-back leaves the alert open and a matching one closes it, that a result for
review raises no alert, that the escalation file can be edited, and that ten alerts opened together all follow the same steps.
Then it restarts the container with an open alert and checks it is still there and still escalates.
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

from common import ROOT, compose, iris, oru, wait_for
import live_mock_check as lm
from readback_check import call, tasks_of
import send_tcp

PASSWORD = os.environ.get("READBACK_DEMO_PASSWORD", "demo-pass-for-tests")
PORT = os.environ.get("READBACK_PORTAL_PORT", "52790")
WINDOW = 8
failures = []
responses = []
TAG = str(int(time.time()) % 100000)


def check(condition, message):
    if not condition:
        failures.append(message)
        print("FAIL:", message)


def start_stack():
    compose("up", "-d", "--build", "--force-recreate", extra_env={"OPENAI_API_KEY": "", "READBACK_DEMO_PASSWORD": PASSWORD})
    subprocess.run([os.path.join(ROOT, "src/ops/verify.sh"), "240"], cwd=ROOT, check=True, capture_output=True)


def api(path):
    token = base64.b64encode(("communicator1:%s" % PASSWORD).encode()).decode()
    request = urllib.request.Request("http://127.0.0.1:%s/readback/api%s" % (PORT, path), headers={"Authorization": "Basic " + token})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            status, text = response.status, response.read().decode()
    except urllib.error.HTTPError as error:
        status, text = error.code, error.read().decode()
    responses.append((path, status, text))
    return status, text


def send(payloads):
    with tempfile.TemporaryDirectory() as work:
        paths = []
        for i, data in enumerate(payloads):
            path = os.path.join(work, "m%d.hl7" % i)
            with open(path, "wb") as handle:
                handle.write(data.encode("ascii"))
            paths.append(path)
        return send_tcp.send_many(paths)


def set_escalation(first, window, people):
    levels = ",".join('{"recipient":"%s"}' % p for p in people)
    text = '{"firstWindowSeconds":%d,"windowSeconds":%d,"levels":[%s]}' % (first, window, levels)
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
        handle.write(text)
        path = handle.name
    os.chmod(path, 0o644)  # the instance reads it as another user
    compose("cp", path, "iris:/tmp/escalation-test.json")
    os.unlink(path)
    lines = iris('set sc=##class(Readback.Notify.Escalation).Load("/tmp/escalation-test.json")\nwrite "RB_ESC="_$select($system.Status.IsOK(sc):"ok",1:$system.Status.GetErrorText(sc)),!')
    return "RB_ESC=ok" in lines


def set_pager(mode):
    ok = lm.set_setting("Readback.Notify.Pager", "Adapter", "DeliveryMode", mode)
    time.sleep(20)  # the item's jobs restart
    return ok


def critical(cid, patient):
    return oru(cid, patient, "2823-3", "Potassium", "6.9", "mmol/L")


def events(cid):
    status, text = api("/decisions/" + cid)
    if status != 200:
        return None
    return [(n["event"], n["recipient"], n["level"], n.get("detail", "")) for n in json.loads(text).get("notifications", [])]


def names(cid):
    ev = events(cid)
    return None if ev is None else [e[0] for e in ev]


def wait_events(cid, wanted, seconds=60):
    """Waits until the case's events contain every (event, recipient) pair of wanted."""
    def done():
        ev = events(cid)
        return ev is not None and all(any(e[0] == w[0] and (w[1] is None or e[1] == w[1]) for e in ev) for w in wanted)
    return wait_for(done, seconds, 1)


def alert_of(cid):
    status, text = api("/alerts")
    if status != 200:
        return None
    return next((a for a in json.loads(text) if a["controlId"] == cid), None)


def find_task(cid):
    for user in ("communicator1", "communicator2"):
        for task in tasks_of(user, PASSWORD) or []:
            if cid in task.get("subject", ""):
                return user, task
    return None


def read_back(cid, value):
    found = wait_for(lambda: find_task(cid), 30)
    if not found:
        return None
    user, task = found
    return call(user, PASSWORD, "POST", "/task/" + task["id"], {"action": "Communicated", "formFields": {"ToldWho": "Dr Example", "ReadbackValue": value}})


def main():
    start_stack()
    check(bool(wait_for(lambda: call("communicator1", PASSWORD, "GET", "/user-info")[0] == 200, 240, 3)), "workflow-rest is not answering")
    check(set_escalation(WINDOW, WINDOW, ["communicator1", "communicator2"]), "the short escalation file did not load")

    # 1. The full path with a pager that acknowledges: open, deliver, receipt, escalate, deliver, receipt, exhausted.
    a = "NTFA-" + TAG
    send([critical(a, "SYN9610001")])
    check(bool(wait_events(a, [("opened", "communicator1"), ("delivery-receipt", "communicator1")], 60)), "no opened alert with a receipt for the first person: %s" % events(a))
    alert = alert_of(a)
    check(alert is not None and alert["level"] == 0 and alert["alerted"] == "communicator1" and alert["owner"] == "communicator1" and alert["state"] == "open",
          "the open alert is not at level 0 for the first person: %s" % alert)
    first = names(a) or []
    check(first[:3] == ["opened", "delivery-attempt", "delivery-receipt"], "the first events are not opened, attempt, receipt: %s" % first)
    check(bool(wait_events(a, [("escalated", "communicator2"), ("delivery-receipt", "communicator2")], 60)), "the alert did not escalate to the second person with a receipt: %s" % events(a))
    alert = alert_of(a)
    check(alert is not None and alert["level"] == 1 and alert["alerted"] == "communicator2" and alert["owner"] == "communicator1", "after the window the alert is not at level 1: %s" % alert)
    ev = events(a) or []
    check([e[0] for e in ev].count("delivery-attempt") == 2 and [e[0] for e in ev].count("escalated") == 1, "expected two attempts and one escalation: %s" % [e[0] for e in ev])
    check(bool(wait_events(a, [("exhausted", "communicator2")], 60)), "the alert did not reach exhausted: %s" % names(a))
    status, text = api("/status")
    body = json.loads(text) if status == 200 else {}
    check(body.get("alerts", {}).get("exhausted", 0) >= 1 and body.get("alerts", {}).get("open", 0) >= 1, "the status does not show the exhausted alert: %s" % body.get("alerts"))
    check(alert_of(a) is not None and alert_of(a)["state"] == "exhausted", "the alert is not listed as exhausted: %s" % alert_of(a))
    time.sleep(WINDOW + 4)
    check((names(a) or []).count("exhausted") == 1, "the exhausted row must be written once: %s" % names(a))
    check(alert_of(a) is not None, "the exhausted alert was closed or dropped")

    # 2. A wrong read-back leaves the alert open; the right one closes it.
    status, text = read_back(a, "9.6") or (0, "")
    check(status != 200, "a divergent read-back was accepted: %s %s" % (status, text[:100]))
    check(alert_of(a) is not None, "a divergent read-back closed the alert")
    check("confirmed" not in (names(a) or []), "a divergent read-back was recorded as a confirmation")
    status, text = read_back(a, "6.9") or (0, "")
    check(status == 200, "the matching read-back was refused: %s %s" % (status, text[:150]))
    check(bool(wait_for(lambda: alert_of(a) is None, 30, 1)), "the matching read-back did not close the alert")
    ev = events(a) or []
    confirmed = [e for e in ev if e[0] == "confirmed"]
    check(len(confirmed) == 1 and confirmed[0][1] in ("communicator1", "communicator2"), "the confirmed row has no person: %s" % confirmed)

    # 3. A result that goes to review raises no alert.
    r = "NTFR-" + TAG
    send([oru(r, "SYN9610002", "2823-3", "Potassium", "4.0", "mmol/L")])
    check(bool(wait_for(lambda: api("/decisions/" + r)[0] == 200, 60, 1)), "no decision for the calm case")
    time.sleep(3)
    check(alert_of(r) is None and events(r) == [], "a result for review raised an alert: %s %s" % (alert_of(r), events(r)))

    # 4. A pager that gives no receipt, and one that fails: the alert still escalates and is never closed by delivery.
    for mode, detail in (("silent", "not acknowledged"), ("fail", "channel error")):
        check(set_pager(mode), "the pager mode %s was not set" % mode)
        cid = "NTF%s-%s" % (mode[:1].upper(), TAG)
        send([critical(cid, "SYN96100%02d" % (3 if mode == "silent" else 4))])
        check(bool(wait_events(cid, [("delivery-failed", "communicator1"), ("escalated", "communicator2")], 60)), "%s: no failed delivery and escalation: %s" % (mode, events(cid)))
        ev = events(cid) or []
        check(not any(e[0] == "delivery-receipt" for e in ev), "%s: a receipt was recorded" % mode)
        check(any(e[0] == "delivery-failed" and detail in e[3] for e in ev), "%s: the failure does not say why (%s): %s" % (mode, detail, ev))
        check(alert_of(cid) is not None, "%s: the alert was closed without a read-back" % mode)
        status, text = read_back(cid, "6.9") or (0, "")
        check(status == 200, "%s: the matching read-back was refused" % mode)
        check(bool(wait_for(lambda: alert_of(cid) is None, 30, 1)), "%s: the alert did not close on the read-back" % mode)
    check(set_pager("deliver"), "the pager mode deliver was not set again")

    # 5. Editing the escalation file changes the next alert: a third person.
    check(set_escalation(WINDOW, WINDOW, ["communicator1", "communicator2", "reviewer1"]), "the three-person file did not load")
    e = "NTFE-" + TAG
    send([critical(e, "SYN9610005")])
    check(bool(wait_events(e, [("escalated", "reviewer1")], 90)), "the alert did not reach the third person: %s" % events(e))
    alert = alert_of(e)
    check(alert is not None and alert["level"] == 2 and alert["alerted"] == "reviewer1", "the third level is not shown: %s" % alert)
    read_back(e, "6.9")
    check(set_escalation(WINDOW, WINDOW, ["communicator1", "communicator2"]), "the two-person file did not load again")

    # 6. Ten alerts opened together all follow the same steps (SC-006).
    ids = ["NTFT%02d-%s" % (i, TAG) for i in range(10)]
    send([critical(c, "SYN96101%02d" % i) for i, c in enumerate(ids)])
    steps = ["opened", "delivery-attempt", "delivery-receipt", "escalated", "delivery-attempt", "delivery-receipt", "exhausted"]
    wait_for(lambda: all("exhausted" in (names(c) or []) for c in ids), 150, 2)
    good = 0
    for c in ids:
        seq = [n for n in (names(c) or []) if n in ("opened", "escalated", "exhausted", "delivery-attempt", "delivery-receipt")]
        if seq[:7] == steps and alert_of(c) is not None:
            good += 1
        else:
            print("   ", c, seq)
    check(good == 10, "only %d of 10 alerts followed the steps" % good)
    for c in ids[:5]:
        read_back(c, "6.9")
    check(bool(wait_for(lambda: all(alert_of(c) is None for c in ids[:5]), 40, 1)), "the five confirmed alerts did not close")
    check(all(alert_of(c) is not None for c in ids[5:]), "an alert that nobody confirmed was closed")

    # 7. Nothing in any answer looks like a credential.
    for path, code, text in responses:
        check("sk-" not in text and "Bearer" not in text and "api_key" not in text.lower(), "credential-like text in the answer of %s" % path)

    # 8. A restart keeps an open alert and it still escalates.
    check(set_escalation(20, 8, ["communicator1", "communicator2"]), "the long first window did not load")
    z = "NTFZ-" + TAG
    send([critical(z, "SYN9610200")])
    check(bool(wait_events(z, [("opened", "communicator1")], 60)), "no alert before the restart")
    compose("restart", "iris")
    subprocess.run([os.path.join(ROOT, "src/ops/verify.sh"), "240"], cwd=ROOT, check=True, capture_output=True)
    check(bool(wait_for(lambda: call("communicator1", PASSWORD, "GET", "/user-info")[0] == 200, 240, 3)), "workflow-rest is not answering after the restart")
    check(alert_of(z) is not None, "the open alert is not there after the restart")
    check(bool(wait_events(z, [("escalated", "communicator2")], 120)), "the alert did not escalate after the restart: %s" % events(z))
    return finish()


def finish():
    # Leave the escalation file as the product ships it.
    iris('set sc=##class(Readback.Notify.Escalation).Load()\nwrite "RB_DONE",!')
    if failures:
        print("FAILED (%d):" % len(failures))
        for f in failures[:30]:
            print(" -", f)
        return 1
    print("notification check passed (full path, silent and failing pager, review, edited file, 10 of 10, restart)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
