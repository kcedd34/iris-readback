"""What the public address forwards and what it refuses (specs/005-flow-ui/contracts/proxy-paths.md).

Runs against the interface service of the running stack (UI_URL, default http://127.0.0.1:8080). Needs READBACK_DEMO_PASSWORD
for the paths that take the person's own credentials. At least 30 requests: the allowed ones succeed, the rest are refused
with the proxy's own English JSON body and no platform content, headers or cookies.
"""
import base64
import http.client
import json
import os
import sys
import time
import urllib.parse

URL = urllib.parse.urlparse(os.environ.get("UI_URL", "http://127.0.0.1:8080"))
PASSWORD = os.environ.get("READBACK_DEMO_PASSWORD", "")
failures = []
count = 0
PLATFORM_MARKERS = ("InterSystems", "IRIS", "Caché", "Cache for", "CSP", "Apache", "%ObjectErrors", "stack", "objlasterror", "SQLCODE", "ERROR #")


def check(condition, message):
    if not condition:
        failures.append(message)
        print("FAIL:", message)


def basic(user):
    return "Basic " + base64.b64encode(("%s:%s" % (user, PASSWORD)).encode()).decode()


def request(method, path, headers=None, body=None):
    global count
    count += 1
    conn = http.client.HTTPConnection(URL.hostname, URL.port, timeout=30)
    try:
        conn.request(method, path, body=body, headers=headers or {})
        response = conn.getresponse()
        data = response.read().decode("utf-8", "replace")
        return response.status, dict((k.lower(), v) for k, v in response.getheaders()), data
    finally:
        conn.close()


def refused(method, path, label, headers=None, body=None, allow=(400, 401, 403, 404, 405, 413, 414)):
    status, h, data = request(method, path, headers, body)
    check(status in allow, "%s: %s %s answered %s, expected a refusal" % (label, method, path[:60], status))
    check(not any(m in data for m in PLATFORM_MARKERS), "%s: the refusal of %s carries platform content: %s" % (label, path[:60], data[:80]))
    check("set-cookie" not in h and h.get("server", "").lower() in ("nginx", ""), "%s: the refusal of %s has a platform header: %s" % (label, path[:60], h.get("server")))
    return status, data


def main():
    if not PASSWORD:
        print("FAIL: READBACK_DEMO_PASSWORD is not set")
        return 1
    # --- allowed, with no credentials from the visitor (the proxy supplies the read-only account)
    for path in ("/", "/ui-config.json", "/readback/api/status", "/readback/api/flow", "/readback/api/flow?after=0", "/readback/api/flow/samples",
                 "/readback/api/alerts", "/readback/api/indicators?from=2020-01-01%2000:00:00&to=2030-01-01%2000:00:00"):
        status, h, data = request("GET", path)
        check(status == 200, "allowed path %s answered %s" % (path, status))
        check("content-security-policy" in h, "allowed path %s has no content security policy" % path)
        check("set-cookie" not in h and h.get("server", "").lower() in ("nginx", ""), "allowed path %s leaks a platform header" % path)
        check(PASSWORD not in data, "allowed path %s carries the demo password" % path)
    status, h, data = request("GET", "/")
    page = data
    check("<script" in page and "https://" not in page.replace("http://www.w3.org", ""), "the page loads something from outside or has no script")
    css = [l for l in page.split('"') if l.startswith("/assets/") and l.endswith(".css")]
    check(bool(css) and request("GET", css[0])[0] == 200, "the stylesheet is not served")
    check(request("GET", "/assets/not-there.js")[0] == 404, "a missing asset is not a 404")
    first = json.loads(request("GET", "/readback/api/flow?after=0")[2])
    ids = [d["controlId"] for d in first.get("decided", [])[:1]]
    if ids:
        check(request("GET", "/readback/api/decisions/" + ids[0])[0] == 200, "an allowed decision path is not 200")
    check(PASSWORD not in json.dumps(first), "the flow carries the demo password")

    # --- the visitor's own Authorization is ignored on the read-only paths (the proxy's own is used)
    check(request("GET", "/readback/api/status", {"Authorization": "Basic bm9ib2R5Om5vcGU="})[0] == 200, "a wrong visitor credential changed the read-only answer")

    # --- the person's own paths need their own credentials, and nothing is injected for them
    for path in ("/readback/api/taskview/1", "/workflow/rest/tasks", "/workflow/rest/user-info", "/workflow/rest/task/1%7C%7Ccommunicator1"):
        status, _, data = request("GET", path)
        check(status in (401, 404), "%s without credentials answered %s (the proxy must not inject the read-only account there)" % (path, status))
        check(not any(m in data for m in PLATFORM_MARKERS), "%s without credentials carries platform content" % path)
    status, _, data = request("GET", "/workflow/rest/user-info", {"Authorization": basic("communicator1")})
    check(status == 200 and "communicator1" in data, "the person's own credentials are not forwarded to the workflow layer: %s" % status)
    check(request("GET", "/workflow/rest/tasks", {"Authorization": basic("communicator1")})[0] == 200, "the person's task list is not reachable with their credentials")
    check(request("GET", "/workflow/rest/tasks/10", {"Authorization": basic("communicator1")})[0] == 200, "the task list with a count is not reachable")
    status, _, data = request("GET", "/workflow/rest/task/999999%7C%7Ccommunicator1", {"Authorization": basic("communicator1")})
    check(status != 200 or "stack" not in data, "an error of the workflow layer reached the visitor")
    # An error of the platform is replaced by the proxy's fixed body (Probe 13: the platform's own error body names internals).
    status, _, data = request("POST", "/workflow/rest/task/999999%7C%7Ccommunicator1", {"Authorization": basic("communicator1"), "Content-Type": "application/json"},
                              json.dumps({"action": "Communicated", "formFields": {"ToldWho": "x", "ReadbackValue": "1"}}))
    check(status >= 400 and not any(m in data for m in PLATFORM_MARKERS), "a failed task action shows platform content: %s %s" % (status, data[:80]))
    check(json.loads(data).get("error") if data.startswith("{") else False, "a failed task action is not the proxy's JSON error")

    # --- refused: the platform's own paths and anything that is not on the list
    for path in ("/csp/sys/UtilHome.csp", "/csp/sys/", "/csp/user/", "/api/atelier/", "/api/mgmnt/", "/ensemble/", "/csp/ensdemo/",
                 "/workflow/rest/test", "/workflow/rest/logout", "/workflow/rest/", "/readback/api/", "/readback/api", "/readback/api/unknown",
                 "/readback/api/decisions/", "/readback/api/decisions/..%2fstatus", "/readback/api/decisions/%2e%2e/%2e%2e/csp/sys/UtilHome.csp", "/readback/api/decisions/..%252fstatus",
                 "//csp/sys/", "/readback/api/status/..;/x", "/readback/api/status.", "/readback/api/flow/", "/readback/api/flow/samples/x",
                 "/workflow/rest/tasks/abc", "/workflow/rest/task/abc", "/workflow/rest/task/1", "/assets/../index.html", "/.git/config", "/.env",
                 "/etc/passwd", "/index.html", "/ui-config.json/x", "/%00", "/readback/api/taskview/", "/readback/api/taskview/a/b"):
        refused("GET", path, "not on the list", {"Authorization": basic("communicator1")})
    refused("GET", "/" + "a" * 6000, "a very long path")
    # --- a wrong method on an allowed path
    for method, path in (("POST", "/readback/api/status"), ("DELETE", "/readback/api/flow"), ("PUT", "/readback/api/flow/samples"), ("POST", "/readback/api/alerts"),
                         ("GET", "/readback/api/flow/submit"), ("PATCH", "/readback/api/flow/submit"), ("POST", "/readback/api/decisions/1"),
                         ("POST", "/readback/api/taskview/1"), ("DELETE", "/workflow/rest/task/1%7C%7Ccommunicator1"), ("POST", "/workflow/rest/tasks"), ("POST", "/ui-config.json")):
        refused(method, path, "wrong method", {"Authorization": basic("communicator1")}, body=b"{}" if method in ("POST", "PUT", "PATCH") else None)

    # --- submit: the body limit and the rate limit
    time.sleep(1.2)
    status, data = refused("POST", "/readback/api/flow/submit", "an oversized submit", {"Content-Type": "application/json"}, body=json.dumps({"scenarioId": "x" * 400}).encode(), allow=(413,))
    time.sleep(1.2)
    seen = []
    for _ in range(8):
        seen.append(request("POST", "/readback/api/flow/submit", {"Content-Type": "application/json"}, json.dumps({"scenarioId": "no-such-scenario"}).encode())[0])
    check(429 in seen, "a burst of submissions was never rate limited: %s" % seen)
    check(all(s in (400, 429) for s in seen), "a burst of invalid submissions got an unexpected status: %s" % seen)

    check(count >= 30, "only %d requests were made" % count)
    if failures:
        print("FAILED (%d)" % len(failures))
        return 1
    print("ui proxy check passed (%d requests)" % count)
    return 0


if __name__ == "__main__":
    sys.exit(main())
