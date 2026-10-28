"""Live path against a local OpenAI-compatible mock (no real key, no cost).

Recreates the container with a test key, points the agent item at the mock, sends cases, and checks:
the request carries the strict schema, the trace record is complete, the earlier result reaches the agent,
every failure kind lands in review (or read-back when the rule is critical), and the key value appears
nowhere it must not. The container is recreated without the test key at the end.
"""
import json
import os
import subprocess
import sys
import tempfile
import time

import make_hostile
from common import ROOT, compose, iris, oru, query, scalar, wait_for
import send_tcp

KEY = "test-key-for-mock"
FILES = ["docker-compose.yml", "tests/e2e/docker-compose.live-mock.yml"]
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)
        print("FAIL:", message)


def start_stack(files, env=None):
    compose("up", "-d", "--build", "--force-recreate", files=files, extra_env=env)
    subprocess.run([os.path.join(ROOT, "src/ops/verify.sh"), "240"], cwd=ROOT, check=True, capture_output=True)


def set_setting(item, target, name, value):
    value = value.replace('"', '""')
    lines = iris('set sc=$system.OBJ.Load("/opt/readback/tests/objectscript/Readback/Test/Support.cls","ck")\n'
                 'set sc=##class(Readback.Test.Support).SetSetting("%s","%s","%s","%s")\n'
                 'write "RB_SET="_$select($system.Status.IsOK(sc):"ok",1:$system.Status.GetErrorText(sc)),!' % (item, target, name, value))
    return any(l == "RB_SET=ok" for l in lines)


def mock_requests():
    out = compose("exec", "-T", "iris", "bash", "-c", "cat /tmp/mock-requests.jsonl 2>/dev/null || true").stdout
    return [json.loads(l) for l in out.splitlines() if l.strip()]


def request_for(case_id):
    for req in reversed(mock_requests()):
        if "Case id: " + case_id in json.dumps(req["body"].get("messages", [])):
            return req
    return None


def trace(case_id):
    rows = query("SELECT Mode,PromptVersion,Model,InputTokens,OutputTokens,LatencyMs,CostKnown,CostUsd,FloorSeverity,AgentSeverity,AgentDecision,"
                 "FinalSeverity,Route,FailureKind,Divergence,SchemaValid FROM Readback_Trace.Decision WHERE MessageControlId='%s' ORDER BY ID DESC" % case_id,
                 ["Mode", "PromptVersion", "Model", "InputTokens", "OutputTokens", "LatencyMs", "CostKnown", "CostUsd", "FloorSeverity", "AgentSeverity",
                  "AgentDecision", "FinalSeverity", "Route", "FailureKind", "Divergence", "SchemaValid"])
    return rows[0] if rows else None


def send(texts):
    with tempfile.TemporaryDirectory() as work:
        paths = []
        for i, text in enumerate(texts):
            path = os.path.join(work, "m%d.hl7" % i)
            with open(path, "wb") as handle:
                handle.write(text.encode("ascii"))
            paths.append(path)
        return send_tcp.send_many(paths)


def main():
    start_stack(FILES)
    compose("exec", "-d", "iris", "python3", "/opt/readback/tests/e2e/mock_openai.py")
    time.sleep(2)
    check(set_setting("Readback.Agent", "Adapter", "ProviderConfig", '{"api_key":"@{env:OPENAI_API_KEY}","base_url":"http://127.0.0.1:8099/v1/"}'), "could not point the agent item at the mock")
    check(set_setting("Readback.Triage", "Host", "AgentTimeoutSeconds", "3"), "could not set the timeout")
    time.sleep(3)

    tag = "LM%d" % (int(time.time()) % 100000)
    cases = {
        "ok": oru(tag + "-OK", "SYN9000001", "2823-3", "Potassium", "6.9", "mmol/L", ref="3.5-5.1"),
        "hist": oru(tag + "-H1", "SYN9000002", "718-7", "Hemoglobin", "12.4", "g/dL", collected="20260228080000"),
        "drop": oru(tag + "-DROP", "SYN9000002", "718-7", "Hemoglobin", "8.1", "g/dL", ref="12.0-17.0"),
        "e500": oru(tag + "-E500", "SYN9000003", "2823-3", "Potassium", "4.0", "mmol/L", indices=[("HEMOLYSIS_INDEX", "MODE:500")]),
        "refusal": oru(tag + "-REF", "SYN9000004", "2823-3", "Potassium", "4.0", "mmol/L", indices=[("HEMOLYSIS_INDEX", "MODE:refusal")]),
        "badjson": oru(tag + "-BAD", "SYN9000005", "2823-3", "Potassium", "4.0", "mmol/L", indices=[("HEMOLYSIS_INDEX", "MODE:badjson")]),
        "e500crit": oru(tag + "-E500C", "SYN9000007", "2823-3", "Potassium", "6.9", "mmol/L", indices=[("HEMOLYSIS_INDEX", "MODE:500")]),
        "slow": oru(tag + "-SLOW", "SYN9000006", "2823-3", "Potassium", "4.0", "mmol/L", indices=[("HEMOLYSIS_INDEX", "MODE:slow")]),
    }
    # One connection, history first: the acknowledgement is sent after the result is stored, so the earlier
    # result is stored before the later one is triaged.
    acks = send([cases["hist"]] + [cases[k] for k in cases if k != "hist"])
    check(all(a == "AA" for _, a in acks), "an intake acknowledgement was not AA: %s" % acks)

    ids = {"ok": "-OK", "drop": "-DROP", "e500": "-E500", "refusal": "-REF", "badjson": "-BAD", "slow": "-SLOW", "e500crit": "-E500C"}
    traces = {}
    for key, suffix in ids.items():
        traces[key] = wait_for(lambda s=suffix: trace(tag + s), 40)
        check(traces[key] is not None, "no trace record for case " + key)

    t = traces.get("ok")
    if t:
        check(t["Mode"] == "live", "mode is not live: %s" % t["Mode"])
        check(t["PromptVersion"] == make_hostile.prompt_version(), "prompt version missing")
        check(t["Model"] == "gpt-5.4", "model not recorded from the item setting: %r" % t["Model"])
        check(t["InputTokens"] == "120" and t["OutputTokens"] == "40", "tokens not recorded: %s/%s" % (t["InputTokens"], t["OutputTokens"]))
        check(int(t["LatencyMs"] or 0) > 0, "latency not recorded")
        check(t["CostKnown"] == "1" and abs(float(t["CostUsd"]) - (120 * 2.5 + 40 * 15.0) / 1e6) < 1e-9, "cost is not tokens x the price table: %s %s" % (t["CostKnown"], t["CostUsd"]))
        check(t["FinalSeverity"] == "3" and t["Route"] == "readback", "critical case did not route to read-back: %s" % t)
    req = request_for(tag + "-OK")
    check(req is not None, "the mock saw no request for the first case")
    if req:
        body = req["body"]
        rf = body.get("response_format", {})
        check(rf.get("type") == "json_schema" and rf.get("json_schema", {}).get("strict") is True, "request lacks the strict schema")
        check("decision" in json.dumps(rf), "schema content missing from the request")
        check(body.get("max_completion_tokens") == 400 and "max_tokens" not in body, "the output cap is not max_completion_tokens 400")
        check(body.get("temperature") == 0, "temperature is not 0")
        check(req["auth"] == "Bearer " + KEY, "the test key did not reach the provider")
    t = traces.get("drop")
    if t:
        check(t["FloorSeverity"] == "0" and t["AgentSeverity"] == "3" and t["FinalSeverity"] == "3" and t["Route"] == "readback",
              "the agent raise did not become the final severity: %s" % t)
    req = request_for(tag + "-DROP")
    check(req is not None and "12.4 g/dL" in json.dumps(req["body"]["messages"]), "the earlier result did not reach the agent")

    expected = {"e500": "provider-error", "refusal": "empty-or-refused", "badjson": "schema-invalid", "slow": "timeout"}
    for key, kind in expected.items():
        t = traces.get(key)
        if t:
            check(t["FailureKind"] == kind and t["Route"] == "review", "%s: expected %s/review, got %s/%s" % (key, kind, t["FailureKind"], t["Route"]))
    t = traces.get("e500crit")
    if t:
        check(t["FailureKind"] == "provider-error" and t["Route"] == "readback" and t["FinalSeverity"] == "3", "a rule-critical case with a provider error must still be read-back: %s" % t)

    leaks = scalar("SELECT COUNT(*) FROM Readback_Trace.Decision WHERE InputText LIKE '%%%s%%' OR RawOutput LIKE '%%%s%%' OR FailureReason LIKE '%%%s%%'" % (KEY, KEY, KEY))
    check(leaks == "0", "the key value appears in %s trace records" % leaks)
    leaks = scalar("SELECT COUNT(*) FROM Ens_Util.Log WHERE Text LIKE '%%%s%%'" % KEY)
    check(leaks == "0", "the key value appears in %s log lines" % leaks)

    print("traces checked:", len(traces))
    # Back to a clean container without the test key.
    start_stack(["docker-compose.yml"], env={"OPENAI_API_KEY": ""})
    if failures:
        print("FAILED (%d):" % len(failures))
        for f in failures:
            print(" -", f)
        return 1
    print("live mock check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
