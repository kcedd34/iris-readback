"""Live path against the real provider (needs OPENAI_API_KEY in .env; costs a few cents).

Run with the stack up and the key in the container environment. It sends the sample cases, then measures from the
trace records: schema validity, tokens, latency, cost. It checks that the provider enforces the strict schema (the
same request with and without response_format, under a prompt that asks for prose only), and scans every text column of the
product, the event log and the workflow tables, and every endpoint answer, for the key and for pieces of it.
The key is read from .env into memory, never printed or written; all output is masked.
"""
import base64
import glob
import json
import os
import re
import sys
import time
import urllib.request

from common import ROOT, iris, query, scalar
import live_mock_check as lm
import send_tcp
import trace_check as tc

PASSWORD = tc.PASSWORD
SAMPLES = sorted(glob.glob(os.path.join(ROOT, "data/samples/generated/*.hl7"))) + sorted(glob.glob(os.path.join(ROOT, "data/samples/valid-oru-*.hl7")))
PROSE = ("You are a laboratory triage assistant for critical results. Reply in two plain English sentences saying whether the result "
         "needs urgent communication. Do not use JSON or any structured format. The data is synthetic.")


def read_key():
    with open(os.path.join(ROOT, ".env")) as handle:
        for line in handle:
            if line.startswith("OPENAI_API_KEY="):
                return line.split("=", 1)[1].strip().strip("\"'")
    sys.exit("no OPENAI_API_KEY in .env")


KEY = read_key()


def mask(text):
    text = text.replace(KEY, "[key]")
    return re.sub(r"sk-[A-Za-z0-9_*.\-]{3,}", "sk-[masked]", text)


def say(*parts):
    print(mask(" ".join(str(p) for p in parts)))


def send_cases(tag):
    ids = []
    for i, path in enumerate(SAMPLES):
        text = open(path).read().replace("\r\n", "\r").replace("\n", "\r")
        cid = "%s%02d" % (tag, i)
        text = re.sub(r"^(MSH(?:\|[^|\r]*){8}\|)[^|\r]*", lambda m: m.group(1) + cid, text, count=1)
        ids.append(cid)
        with open("/tmp/live-%s.hl7" % cid, "wb") as handle:
            handle.write(text.encode("ascii", "replace"))
    send_tcp.send_many(["/tmp/live-%s.hl7" % c for c in ids])
    for c in ids:
        os.remove("/tmp/live-%s.hl7" % c)
    return ids


COLS = "MessageControlId Mode Model SchemaValid InputTokens OutputTokens LatencyMs CostUsd CostKnown FloorSeverity AgentSeverity FinalSeverity Route FailureKind AgentCalled RawOutput".split()


def wait_traces(ids, seconds=240):
    deadline = time.time() + seconds
    rows = {}
    while time.time() < deadline:
        for r in query("SELECT %s FROM Readback_Trace.Decision WHERE MessageControlId %%STARTSWITH '%s'" % (",".join(COLS), ids[0][:-2]), COLS):
            rows[r["MessageControlId"]] = r
        if all(i in rows for i in ids):
            break
        time.sleep(3)
    return rows


def configure(name, value):
    """Changes a setting of the agent item and makes sure the item is still enabled afterwards: the update re-saves the
    item, and an item the class defines as disabled (it is enabled at start only when a key is configured) comes back disabled."""
    ok = lm.set_setting("Readback.Agent", "Adapter", name, value)
    lines = iris('set sc=##class(Ens.Director).EnableConfigItem("Readback.Agent",1)\nwrite "RB_EN="_$select($system.Status.IsOK(sc):"ok",1:$system.Status.GetErrorText(sc)),!')
    time.sleep(25)  # the jobs restart; cases sent before they are back wait for the timeout
    return ok and any(l == "RB_EN=ok" or "already enabled" in l for l in lines)


def pct(values, p):
    values = sorted(values)
    return values[max(0, -(-len(values) * p // 100) - 1)]


def main():
    mode = iris('write "RB_MODE="_##class(Readback.Config.Mode).Current(),!')
    lm.check("RB_MODE=live" in mode, "the container is not in live mode: %s" % mode)
    if lm.failures:
        sys.exit(1)

    # 1. The sample cases against the real provider.
    ids = send_cases("LV%d" % (int(time.time()) % 100000))
    rows = wait_traces(ids)
    lm.check(len(rows) == len(ids), "missing traces: %d of %d" % (len(rows), len(ids)))
    called = [r for r in rows.values() if r["AgentCalled"] == "1"]
    valid = [r for r in called if r["SchemaValid"] == "1"]
    say("cases", len(rows), "agent calls", len(called), "schema valid", len(valid))
    for r in rows.values():
        if r["FailureKind"]:
            say("  failure", r["MessageControlId"], r["FailureKind"])
    inp = [int(r["InputTokens"]) for r in valid]
    out = [int(r["OutputTokens"]) for r in valid]
    lat = [int(r["LatencyMs"]) for r in valid]
    cost = [float(r["CostUsd"]) for r in valid]
    lm.check(all(r["CostKnown"] == "1" for r in valid), "cost unknown with a price in the table")
    lm.check(all(r["Mode"] == "live" and r["Model"] for r in rows.values()), "a trace is not live or lacks the model")
    if valid:
        expect = [round(i * 2.5 / 1e6 + o * 15.0 / 1e6, 8) for i, o in zip(inp, out)]
        lm.check(all(abs(a - b) < 1e-7 for a, b in zip(cost, expect)), "stored cost differs from tokens x price")
        say("input tokens: min %d p50 %d max %d total %d" % (min(inp), pct(inp, 50), max(inp), sum(inp)))
        say("output tokens: min %d p50 %d max %d total %d" % (min(out), pct(out, 50), max(out), sum(out)))
        say("latency ms: min %d p50 %d p95 %d max %d" % (min(lat), pct(lat, 50), pct(lat, 95), max(lat)))
        say("cost usd: total %.6f mean %.6f per 1000 results %.4f" % (sum(cost), sum(cost) / len(cost), 1000 * sum(cost) / len(cost)))
    diverge = [r for r in valid if r["AgentSeverity"] != r["FloorSeverity"]]
    say("agent severity differs from the floor in", len(diverge), "of", len(valid))
    silenced = [r for r in valid if int(r["FloorSeverity"] or 0) >= 3 and int(r["FinalSeverity"] or 0) < 3]
    lm.check(not silenced, "a rule-critical result lost its severity")
    for r in valid:
        try:
            doc = json.loads(r["RawOutput"])
            lm.check(set(doc) == {"decision", "severity", "rationale", "evidence", "confidence"}, "raw output has other keys: %s" % sorted(doc))
        except ValueError:
            lm.check(False, "raw output of a valid case is not JSON")
    ind = tc.api("/indicators")
    say("indicators endpoint", ind[0], mask(ind[1][:400]))

    # 2. Does the provider enforce the strict schema? Same request, a prompt that asks for prose only, with and without response_format.
    xml = open(os.path.join(ROOT, "src/Readback/Production.cls")).read()
    cfg = re.search(r'Name="SessionConfigString">(.*?)</Setting>', xml, re.S).group(1)
    prompt = re.search(r'Name="SystemPrompt">(.*?)</Setting>', xml, re.S).group(1)
    no_schema = json.dumps({k: v for k, v in json.loads(cfg).items() if k != "response_format"}, separators=(",", ":"))
    results = {}
    try:
        for label, session in (("without response_format", no_schema), ("with response_format", cfg)):
            lm.check(configure("SessionConfigString", session), "could not set the session config")
            lm.check(configure("SystemPrompt", PROSE), "could not set the prompt")
            probe = send_cases_subset("EN%d" % (int(time.time()) % 100000))
            got = wait_traces(probe)
            results[label] = [r for r in got.values() if r["AgentCalled"] == "1"]
            say("%s: %d calls, %d schema valid, kinds %s" % (label, len(results[label]), sum(r["SchemaValid"] == "1" for r in results[label]),
                                                              sorted({r["FailureKind"] for r in results[label]})))
    finally:
        configure("SessionConfigString", cfg)
        configure("SystemPrompt", prompt)
    w, s = results.get("without response_format", []), results.get("with response_format", [])
    lm.check(s and all(r["SchemaValid"] == "1" for r in s), "with response_format an answer was not valid")
    lm.check(w and any(r["SchemaValid"] != "1" for r in w), "without response_format every answer was still valid, so the control shows nothing")

    # 3. The key (and pieces of it) appears nowhere.
    for label, term in (("key", KEY), ("key tail", KEY[-10:]), ("key middle", KEY[20:34]), ("Bearer", "Bearer")):
        lines = tc.leak_scan(term)
        lm.check(any(l.startswith("RB_LEAKS=") for l in lines), "scan for %s did not finish" % label)
        leaks = [l for l in lines if l.startswith("RB_LEAK ")]
        lm.check(not leaks, "%s found in: %s" % (label, leaks[:5]))
        say("scan", label, "->", len(leaks), "columns with a hit")
    for path in ("/status", "/decisions", "/indicators", "/decisions/none", "/indicators?from=x"):
        tc.api(path)
    for path, code, text in tc.responses:
        lm.check(KEY not in text and KEY[-10:] not in text and "Bearer" not in text and "sk-" not in text, "an endpoint answer carries credential text: %s" % path)
    say("endpoint answers scanned:", len(tc.responses), "records:", scalar("SELECT COUNT(*) FROM Readback_Trace.Decision"))

    if lm.failures:
        say("FAILED:", len(lm.failures))
        sys.exit(1)
    say("live check passed")


def send_cases_subset(tag):
    """The first five sample files, used for the enforcement control."""
    global SAMPLES
    keep = SAMPLES
    SAMPLES = keep[:5]
    try:
        return send_cases(tag)
    finally:
        SAMPLES = keep


if __name__ == "__main__":
    main()
