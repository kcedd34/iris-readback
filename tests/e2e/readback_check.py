"""Read-back end to end through the community workflow REST module.

Needs the stack running with no provider key, so every case ends with a floor-driven route (a
rule-critical case still goes to read-back when the agent step fails). Checks rotation, the block on a
divergent value, completion on a match, refusal for a person outside the role, no second completion,
and the review task.
"""
import base64
import json
import os
import re
import sys
import tempfile
import time
import urllib.error
import urllib.request

from common import compose, oru, query, scalar, wait_for
import send_tcp

BASE = "http://127.0.0.1:%s/workflow/rest" % os.environ.get("READBACK_PORTAL_PORT", "52790")
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)
        print("FAIL:", message)


def demo_password():
    value = os.environ.get("READBACK_DEMO_PASSWORD", "").strip()
    if value:
        return value
    logs = compose("logs", "iris").stdout
    found = re.findall(r"generated demo password \(shown once\): (\S+)", logs)
    return found[-1] if found else ""


def call(user, password, method, path, body=None):
    token = base64.b64encode(("%s:%s" % (user, password)).encode()).decode()
    request = urllib.request.Request(BASE + path, method=method, data=None if body is None else json.dumps(body).encode(),
                                     headers={"Authorization": "Basic " + token, "Content-Type": "application/json", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, response.read().decode()
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode()


def tasks_of(user, password):
    status, text = call(user, password, "GET", "/tasks")
    if status != 200:
        return None
    try:
        return json.loads(text) if text.strip() else []
    except ValueError:
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


def task_for(tag_id, password, users):
    """Returns (user, task) for the open task whose subject names the case, searching the users' worklists."""
    for user in users:
        for task in tasks_of(user, password) or []:
            if tag_id in task.get("subject", ""):
                return user, task
    return None, None


def main():
    password = demo_password()
    check(password != "", "no demo password found (set READBACK_DEMO_PASSWORD or read the container log)")
    ready = wait_for(lambda: call("communicator1", password, "GET", "/user-info")[0] == 200, 240, 3)
    check(bool(ready), "workflow-rest is not answering (needs network once at first start)")
    if failures:
        return 1

    tag = "RBK%d" % (int(time.time()) % 100000)
    comm = ["communicator1", "communicator2"]
    ids = [tag + "-1", tag + "-2", tag + "-3"]
    texts = [oru(i, "SYN95000%02d" % n, "2823-3", "Potassium", "6.9", "mmol/L", ref="3.5-5.1") for n, i in enumerate(ids, 1)]
    texts.append(oru(tag + "-R", "SYN9500009", "2823-3", "Potassium", "4.0", "mmol/L", ref="3.5-5.1"))
    acks = send(texts)
    check(all(a == "AA" for _, a in acks), "intake acknowledgement not AA: %s" % acks)

    found = {}
    for i in ids:
        found[i] = wait_for(lambda i=i: task_for(i, password, comm)[1] is not None and task_for(i, password, comm), 30)
        check(bool(found[i]), "no read-back task appeared for " + i)
    if failures:
        return 1
    owners = [found[i][0] for i in ids]
    # Two processes assign at the same time, so the order by case id can differ from the order of the turns;
    # the rotation shows as a 2 and 1 split over the two people.
    split = sorted(owners.count(u) for u in comm)
    check(split == [1, 2], "tasks were not shared in rotation over two people: %s" % owners)

    user, task = found[ids[0]]
    task_id = task["id"]
    check(task["subject"].startswith("[replay] Read-back "), "the task subject does not say replay: %s" % task["subject"])
    status, text = call(user, password, "GET", "/task/" + task_id)
    detail = json.loads(text)
    check("Value: 6.9 mmol/L" in detail.get("message", ""), "the task message lacks the value")
    check("replay" in detail.get("message", ""), "the task message does not say replay")
    check("ToldWho" in detail.get("formFields", {}) and "ReadbackValue" in detail.get("formFields", {}), "form fields missing: %s" % detail.get("formFields"))

    # A divergent value is blocked, kept as an attempt, and the task stays open.
    for value in ("9.6", "", "six", "6,9"):
        status, text = call(user, password, "POST", "/task/" + task_id, {"action": "Communicated", "formFields": {"ToldWho": "Dr Example", "ReadbackValue": value}})
        check(status != 200, "a divergent value %r was accepted" % value)
    check(any(t["id"] == task_id for t in tasks_of(user, password) or []), "the task closed after divergent attempts")
    attempts = scalar("SELECT COUNT(*) FROM Readback_Trace.ReadbackAttempt WHERE Matched = 0 AND TaskId = '%s'" % task_id.split("||")[0])
    check(attempts == "4", "expected 4 kept divergent attempts, found %s" % attempts)
    check(scalar("SELECT COUNT(*) FROM Readback_Trace.Decision WHERE ConfirmedBy <> '' AND TaskId = '%s'" % task_id.split("||")[0]) == "0", "a communication was recorded without a match")

    # A person outside the role cannot complete it, even with the right value.
    status, text = call("observer", password, "POST", "/task/" + task_id, {"action": "Communicated", "formFields": {"ToldWho": "Dr Example", "ReadbackValue": "6.9"}})
    check(status != 200, "a person outside the role completed the task")
    check(any(t["id"] == task_id for t in tasks_of(user, password) or []), "the task closed after an outsider's attempt")
    status, text = call(comm[1] if user == comm[0] else comm[0], password, "POST", "/task/" + task_id, {"action": "Communicated", "formFields": {"ToldWho": "Dr Example", "ReadbackValue": "6.9"}})
    check(status != 200, "a role member who does not own the task completed it")

    # The matching value completes it, formatting aside.
    status, text = call(user, password, "POST", "/task/" + task_id, {"action": "Communicated", "formFields": {"ToldWho": "Dr Example", "ReadbackValue": "6.90"}})
    check(status == 200, "the matching value was refused: %s %s" % (status, text[:200]))
    gone = wait_for(lambda: not any(t["id"] == task_id for t in tasks_of(user, password) or []), 15)
    check(bool(gone), "the task did not close after a matching read-back")
    row = query("SELECT ConfirmedBy,ReadbackMatch FROM Readback_Trace.Decision WHERE TaskId = '%s'" % task_id.split("||")[0], ["ConfirmedBy", "ReadbackMatch"])
    check(row and row[0]["ConfirmedBy"] == user and row[0]["ReadbackMatch"] == "1", "the confirmation is not in the trace: %s" % row)

    # No second completion. The REST layer answers 200 to a completed task without doing anything, so the
    # state is what counts: no new attempt, the same confirmation.
    before = scalar("SELECT COUNT(*) FROM Readback_Trace.ReadbackAttempt WHERE TaskId = '%s'" % task_id.split("||")[0])
    call(user, password, "POST", "/task/" + task_id, {"action": "Communicated", "formFields": {"ToldWho": "Someone else", "ReadbackValue": "6.9"}})
    after = scalar("SELECT COUNT(*) FROM Readback_Trace.ReadbackAttempt WHERE TaskId = '%s'" % task_id.split("||")[0])
    check(before == after, "a completed task accepted another submission (%s then %s attempts)" % (before, after))
    row = query("SELECT ConfirmedBy FROM Readback_Trace.Decision WHERE TaskId = '%s'" % task_id.split("||")[0], ["ConfirmedBy"])
    check(row and row[0]["ConfirmedBy"] == user, "the confirmation changed after a second submission")

    # The review task, for a case that is not critical by rule and has no usable agent answer.
    review = wait_for(lambda: task_for(tag + "-R", password, ["reviewer1"])[1], 30)
    check(bool(review), "no review task appeared")
    if review:
        check(review["subject"].startswith("[replay] Review "), "the review subject does not say replay: %s" % review["subject"])
        status, text = call("reviewer1", password, "POST", "/task/" + review["id"], {"action": "Reviewed", "formFields": {"Note": "Looked at it"}})
        check(status == 200, "the reviewer could not complete the review: %s %s" % (status, text[:200]))
        status, text = call("communicator1", password, "POST", "/task/" + review["id"], {"action": "Reviewed", "formFields": {"Note": "x"}})
        check(status != 200, "a communicator completed a review task")

    if failures:
        print("FAILED (%d):" % len(failures))
        for item in failures:
            print(" -", item)
        return 1
    print("read-back check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
