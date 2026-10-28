"""Trace, indicators and redaction through the live path against the mock (a test key, no cost).

Processes 50 cases that reach every route and failure kind, then:
  - rebuilds every decision from its trace record alone and compares it with what was stored and what the
    decisions endpoint returns;
  - computes the indicators by hand from SQL and compares them with the endpoint, asks for an empty window and a bad one;
  - provokes a 500 and checks the error bodies;
  - searches every trace field, event-log line, task text, both vector tables and every endpoint response
    for the test key value, and for the credential text the mock echoed, and finds none.
The container is recreated without the key at the end.
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

from common import compose, iris, oru, query, scalar, wait_for
import live_mock_check as lm

os.environ.setdefault("READBACK_DEMO_PASSWORD", "demo-pass-for-tests")
PASSWORD = os.environ["READBACK_DEMO_PASSWORD"]
PORT = os.environ.get("READBACK_PORTAL_PORT", "52790")
check = lm.check
responses = []


def api(path, user="communicator1"):
    token = base64.b64encode(("%s:%s" % (user, PASSWORD)).encode()).decode()
    request = urllib.request.Request("http://127.0.0.1:%s/readback/api%s" % (PORT, path), headers={"Authorization": "Basic " + token})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            status, text = response.status, response.read().decode()
    except urllib.error.HTTPError as error:
        status, text = error.code, error.read().decode()
    responses.append((path, status, text))
    return status, text


def case_list(tag):
    """(suffix, patient, analyte args, value, unit, marker, expected route, expected failure kind or '')."""
    k = ("2823-3", "Potassium", "mmol/L")
    rows = []
    for i in range(10):
        rows.append(("CRIT%d" % i, k, "6.9", "mmol/L", None, "readback", ""))
    for i in range(8):
        rows.append(("REL%d" % i, k, "4.0", "mmol/L", "MODE:noncrit", "release", ""))
    for i in range(6):
        rows.append(("RECO%d" % i, k, "4.0", "mmol/L", "MODE:recollect", "recollect", ""))
    for i in range(4):
        rows.append(("E500%d" % i, k, "4.0", "mmol/L", "MODE:500", "review", "provider-error"))
    for i in range(2):
        rows.append(("E500C%d" % i, k, "6.9", "mmol/L", "MODE:500", "readback", "provider-error"))
    for i in range(3):
        rows.append(("REF%d" % i, k, "4.0", "mmol/L", "MODE:refusal", "review", "empty-or-refused"))
    for i in range(3):
        rows.append(("BAD%d" % i, k, "4.0", "mmol/L", "MODE:badjson", "review", "schema-invalid"))
    for i in range(4):
        rows.append(("AGT%d" % i, k, "4.0", "mmol/L", None, "readback", ""))
    for i in range(4):
        rows.append(("UNIT%d" % i, k, "4.0", "furlong", "MODE:noncrit", "review", ""))
    for i in range(2):
        rows.append(("ECHO5%d" % i, k, "4.0", "mmol/L", "MODE:echo500", "review", "provider-error"))
    for i in range(2):
        rows.append(("ECHO4%d" % i, k, "4.0", "mmol/L", "MODE:echo401", "review", "provider-error"))
    # Last: a slow answer holds an agent job for the whole timeout, and the cases queued behind it would time out too.
    for i in range(2):
        rows.append(("SLOW%d" % i, k, "4.0", "mmol/L", "MODE:slow", "review", "timeout"))
    assert len(rows) == 50
    return rows


def record(control_id):
    rows = query("SELECT ID,Route,FinalSeverity,Divergence,FailureKind,FailureReason,SchemaValid,AgentCalled,LatencyMs,CostKnown FROM Readback_Trace.Decision "
                 "WHERE MessageControlId='%s' ORDER BY ID DESC" % control_id,
                 ["ID", "Route", "FinalSeverity", "Divergence", "FailureKind", "FailureReason", "SchemaValid", "AgentCalled", "LatencyMs", "CostKnown"])
    return rows[0] if rows else None


def rebuild(trace_id):
    lines = iris('set r=##class(Readback.Trace.Rebuild).Explain(%s)\n'
                 'write "RB_R="_r.ok_"|"_r.finalSeverity_"|"_r.route_"|"_r.divergence_"|"_r.error,!' % trace_id)
    for line in lines:
        if line.startswith("RB_R="):
            return line[5:].split("|")
    return None


def nearest_rank(values, percent):
    values = sorted(values)
    rank = -(-percent * len(values) // 100)
    return values[max(1, min(rank, len(values))) - 1]


def main():
    lm.start_stack(lm.FILES)
    compose("exec", "-d", "iris", "python3", "/opt/readback/tests/e2e/mock_openai.py")
    time.sleep(2)
    check(lm.set_setting("Readback.Agent", "Adapter", "ProviderConfig", '{"api_key":"@{env:OPENAI_API_KEY}","base_url":"http://127.0.0.1:8099/v1/"}'), "could not point the agent item at the mock")
    check(lm.set_setting("Readback.Triage", "Host", "AgentTimeoutSeconds", "3"), "could not set the timeout")
    time.sleep(3)

    tag = "TR%d" % (int(time.time()) % 100000)
    cases = case_list(tag)
    texts = []
    for n, (suffix, k, value, unit, marker, route, kind) in enumerate(cases):
        indices = [("HEMOLYSIS_INDEX", marker)] if marker else None
        texts.append(oru("%s-%s" % (tag, suffix), "SYN97%05d" % n, k[0], k[1], value, unit, indices=indices))
    acks = lm.send(texts)
    check(all(a == "AA" for _, a in acks), "an intake acknowledgement was not AA")

    stored = {}
    for suffix, *_ in cases:
        stored[suffix] = wait_for(lambda s=suffix: record("%s-%s" % (tag, s)), 90)
        check(stored[suffix] is not None, "no trace record for " + suffix)
    if lm.failures:
        return 1

    routes = set()
    for suffix, k, value, unit, marker, route, kind in cases:
        row = stored[suffix]
        routes.add(row["Route"])
        check(row["Route"] == route, "%s: expected route %s, got %s (%s: %s)" % (suffix, route, row["Route"], row["FailureKind"], row["FailureReason"]))
        if kind:
            check(row["FailureKind"] == kind, "%s: expected failure kind %s, got %s" % (suffix, kind, row["FailureKind"]))
    check({"readback", "review", "release", "recollect"} <= routes, "not every route was reached: %s" % routes)

    # 1. Every decision rebuilt from its record equals what was stored and what the endpoint returns.
    for suffix, *_ in cases:
        row = stored[suffix]
        got = rebuild(row["ID"])
        check(got is not None and got[0] == "1", "%s: the record could not be rebuilt: %s" % (suffix, got))
        if got and got[0] == "1":
            check(got[1] == row["FinalSeverity"] and got[2] == row["Route"] and got[3] == row["Divergence"],
                  "%s: rebuilt %s differs from stored %s/%s/%s" % (suffix, got[1:4], row["FinalSeverity"], row["Route"], row["Divergence"]))
        status, text = api("/decisions/%s-%s" % (tag, suffix))
        check(status == 200, "%s: decisions endpoint answered %s" % (suffix, status))
        if status == 200:
            body = json.loads(text)
            check(body["route"] == row["Route"] and str(body["finalSeverity"]) == row["FinalSeverity"], "%s: endpoint differs from the record" % suffix)
            for field in ("conversionOutcome", "passageIds", "caseLabels", "indexVersion", "budgetState", "budgetBasis", "agentCalled", "originalUnit"):
                check(field in body, "%s: the decision lacks %s" % (suffix, field))
            if suffix.startswith("CRIT0"):
                check(body["originalUnit"] == "mmol/L" and body["conversionOutcome"] == "not-needed", "unit record: %s" % body)
                check(len(body["passageIds"]) >= 1, "no passage ids in the trace of a case that called the agent")
            if suffix.startswith("UNIT0"):
                check(body["conversionOutcome"] == "not-convertible" and body["originalUnit"] == "furlong", "unit not convertible record: %s" % body)

    # 2. Indicators by hand from SQL against the endpoint.
    rows = query("SELECT Route,Divergence,SchemaValid,FailureKind,CostKnown,AgentCalled,LatencyMs FROM Readback_Trace.Decision",
                 ["Route", "Divergence", "SchemaValid", "FailureKind", "CostKnown", "AgentCalled", "LatencyMs"])
    status, text = api("/indicators")
    check(status == 200, "indicators answered %s" % status)
    if status == 200:
        got = json.loads(text)
        n = len(rows)
        check(got["recordCount"] == n, "record count %s vs %s" % (got["recordCount"], n))
        check(abs(got["reviewRate"] - sum(r["Route"] == "review" for r in rows) / n) < 1e-5, "review rate")
        check(abs(got["divergenceRate"] - sum(r["Divergence"] != "" for r in rows) / n) < 1e-5, "divergence rate")
        invalid = sum(r["SchemaValid"] in ("0", "") and r["FailureKind"] in ("schema-invalid", "empty-or-refused") for r in rows)
        check(abs(got["invalidRate"] - invalid / n) < 1e-5, "invalid rate")
        known = sum(r["CostKnown"] == "1" for r in rows)
        check(got["unknownCostRecords"] == n - known, "unknown cost records %s vs %s" % (got["unknownCostRecords"], n - known))
        if known == 0:
            check(got["costPerThousandResults"] is None, "an unknown cost must be null, never 0: %s" % got["costPerThousandResults"])
        lat = [int(r["LatencyMs"]) for r in rows if r["AgentCalled"] == "1" and r["LatencyMs"] != ""]
        check(lat and got["latencyP50Ms"] == nearest_rank(lat, 50) and got["latencyP95Ms"] == nearest_rank(lat, 95),
              "latency percentiles %s/%s vs %s/%s" % (got["latencyP50Ms"], got["latencyP95Ms"], nearest_rank(lat, 50), nearest_rank(lat, 95)))
    status, text = api("/indicators?from=1999-01-01%2000:00:00&to=1999-01-02%2000:00:00")
    check(status == 200, "an empty window must still answer 200, got %s" % status)
    if status == 200:
        got = json.loads(text)
        check(got["recordCount"] == 0 and all(got[k] is None for k in ("costPerThousandResults", "latencyP50Ms", "latencyP95Ms", "reviewRate", "divergenceRate", "invalidRate")),
              "an empty window gives null figures: %s" % got)
    status, text = api("/indicators?from=yesterday")
    check(status == 400 and list(json.loads(text)) == ["error"], "a bad timestamp must give 400 with only an error field: %s %s" % (status, text))

    # 3. Status blocks and error bodies, including a provoked 500.
    status, text = api("/status")
    check(status == 200, "status answered %s" % status)
    if status == 200:
        body = json.loads(text)
        check(body["retrieval"]["passages"] > 0 and body["retrieval"]["indexVersion"] and body["retrieval"]["available"] is True, "status retrieval block: %s" % body.get("retrieval"))
        check(body["unitComponent"]["registered"] is True, "status unit component block: %s" % body.get("unitComponent"))
    status, text = api("/decisions/NO-SUCH-CASE")
    check(status == 404 and list(json.loads(text)) == ["error"], "404 body: %s %s" % (status, text))
    status, text = api("/nowhere")
    check(status in (404, 405) and list(json.loads(text)) == ["error"], "unknown route body: %s %s" % (status, text))
    # A real uncaught exception: the class behind /indicators is removed for a moment, then loaded again from the source.
    iris('do $system.OBJ.Delete("Readback.Trace.Indicators","/nodisplay")')
    try:
        status, text = api("/indicators", user="reviewer1")
        check(status == 500 and json.loads(text) == {"error": "internal error"}, "provoked 500 body: %s %s" % (status, text[:200]))
    finally:
        reloaded = iris('set sc=$system.OBJ.Load("/opt/readback/src/Readback/Trace/Indicators.cls","ck")\nwrite "RB_RELOAD="_$select($system.Status.IsOK(sc):"ok",1:"failed"),!')
        check("RB_RELOAD=ok" in reloaded, "the indicators class did not load again")
    status, _ = api("/indicators")
    check(status == 200, "the endpoint did not recover after the class was loaded again: %s" % status)

    # 4. The key value and the credential text the mock echoed appear nowhere.
    echoed = [r for s, *_ in cases if s.startswith("ECHO") for r in [stored[s]["FailureReason"]]]
    check(all("[key redacted]" in r or r == "" for r in echoed) and any("[key redacted]" in r for r in echoed), "the echoed credential was not redacted in the failure reasons: %s" % echoed[:2])


def leak_scan(term):
    """Counts the rows containing term in every text column of the product, event log and workflow tables.
    The terminal reads one line at a time, so each block is on one line."""
    script = ('set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT TABLE_SCHEMA,TABLE_NAME,COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE (TABLE_SCHEMA %STARTSWITH \'Readback\' OR TABLE_SCHEMA %STARTSWITH \'Ens\') AND DATA_TYPE IN (\'VARCHAR\',\'LONGVARCHAR\')")\n'
              'set found=0\n'
              'while rs.%Next() { set t=rs.%Get("TABLE_SCHEMA")_"."_rs.%Get("TABLE_NAME"), c=rs.%Get("COLUMN_NAME")  set r2=##class(%SQL.Statement).%ExecDirect(,"SELECT COUNT(*) FROM "_t_" WHERE "_c_" LIKE ?","%"_"' + term + '"_"%")  if r2.%SQLCODE>=0 { do r2.%Next()  if r2.%GetData(1)>0 { set found=found+1  write "RB_LEAK "_t_"."_c_" "_r2.%GetData(1),! } } }\n'
              'write "RB_LEAKS="_found,!')
    return iris(script)


def finish():
    for term in (lm.KEY, "Bearer"):
        lines = leak_scan(term)
        done = [l for l in lines if l.startswith("RB_LEAKS=")]
        check(done, "the table scan for %r did not finish: %s" % (term, lines[:3]))
        leaks = [l for l in lines if l.startswith("RB_LEAK ")]
        check(not leaks, "%r found in: %s" % (term, leaks[:5]))
        if leaks and any("MessageHeader" in l for l in leaks):
            for row in query("SELECT ID,MessageBodyClassName,SourceConfigName,TargetConfigName,Status FROM Ens.MessageHeader WHERE ErrorStatus LIKE '%%%s%%'" % term, ["ID", "MessageBodyClassName", "SourceConfigName", "TargetConfigName", "Status"])[:4]:
                print("   header:", row)
        if leaks:
            for row in query("SELECT ConfigName,Type,SourceClass,Text FROM Ens_Util.Log WHERE Text LIKE '%%%s%%'" % term, ["ConfigName", "Type", "SourceClass", "Text"])[:6]:
                print("   log:", row["ConfigName"], row["Type"], row["SourceClass"], row["Text"][:240])
    mock_log = lm.mock_requests()
    check(any(r.get("auth") == "Bearer " + lm.KEY for r in mock_log), "the mock never saw the test key, so the scan proves nothing")
    for path, code, text in responses:
        check(lm.KEY not in text and "Bearer" not in text and "sk-" not in text, "an endpoint response carries credential text: %s %s" % (path, code))
    print("records:", scalar("SELECT COUNT(*) FROM Readback_Trace.Decision"), "responses scanned:", len(responses))
    lm.start_stack(["docker-compose.yml"], env={"OPENAI_API_KEY": ""})
    if lm.failures:
        print("FAILED (%d):" % len(lm.failures))
        for f in lm.failures:
            print(" -", f)
        return 1
    print("trace check passed")
    return 0


if __name__ == "__main__":
    rc = main()
    sys.exit(finish() or rc)
