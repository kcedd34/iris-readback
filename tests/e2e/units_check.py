"""Unit normalization end to end: Java component, UCUM, trace fields and the fixed reasons.

Replay mode with a small recorded set (a calm agent answer for every case), so the reason a case goes to
review is the one the unit rule gives and not a missing recording. Also stops the conversion item to prove
the "unit conversion unavailable" path, including the exception for values critical under a known unit.
"""
import json
import os
import subprocess
import sys
import tempfile
import time

from common import ROOT, compose, iris, oru, query, scalar, wait_for
import make_hostile
import send_tcp

PASSWORD = "demo-pass-for-tests"
failures = []
CALM = json.dumps({"decision": "NON_CRITICAL", "severity": 0, "rationale": "Looks normal.", "evidence": ["current-result"], "confidence": "high"}, sort_keys=True)


def check(condition, message):
    if not condition:
        failures.append(message)
        print("FAIL:", message)


def start_stack():
    compose("up", "-d", "--build", "--force-recreate", extra_env={"OPENAI_API_KEY": "", "READBACK_DEMO_PASSWORD": PASSWORD})
    subprocess.run([os.path.join(ROOT, "src/ops/verify.sh"), "240"], cwd=ROOT, check=True, capture_output=True)


def load_recordings(ids):
    with tempfile.TemporaryDirectory() as work:
        path = os.path.join(work, "units.jsonl")
        with open(path, "wb") as handle:
            for mid in ids:
                row = {"messageControlId": mid, "promptVersion": make_hostile.prompt_version(), "replaySet": "units", "answer": CALM,
                       "model": "fixture", "inputTokens": 1, "outputTokens": 1, "source": "fixture"}
                handle.write((json.dumps(row, sort_keys=True) + "\n").encode("ascii"))
        compose("cp", path, "iris:/tmp/units.jsonl")
    lines = iris('set sc=##class(Readback.Replay.Recording).LoadFile("/tmp/units.jsonl",.n)\n'
                 'write "RB_LOAD="_$select($system.Status.IsOK(sc):n,1:$system.Status.GetErrorText(sc)),!\n'
                 'do ##class(Readback.Replay.Recording).Activate("units")')
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


def trace(control_id):
    rows = query("SELECT OriginalValue,OriginalUnit,ConvertedValue,ConvertedUnit,ConversionOutcome,FloorSeverity,FloorNote,FinalSeverity,Route,FailureKind,FailureReason "
                 "FROM Readback_Trace.Decision WHERE MessageControlId='%s' ORDER BY ID DESC" % control_id,
                 ["OriginalValue", "OriginalUnit", "ConvertedValue", "ConvertedUnit", "ConversionOutcome", "FloorSeverity", "FloorNote", "FinalSeverity", "Route", "FailureKind", "FailureReason"])
    return rows[0] if rows else None


def main():
    start_stack()
    tag = "UNT%d" % (int(time.time()) % 100000)
    cases = {
        "g_mg": oru(tag + "-GMG", "SYN9700001", "2345-7", "Glucose", "540", "mg/dL"),
        "g_mmol": oru(tag + "-GMM", "SYN9700002", "2345-7", "Glucose", "29.97", "mmol/L"),
        "g_calm": oru(tag + "-GCALM", "SYN9700003", "2345-7", "Glucose", "100", "mg/dL"),
        "k_foo": oru(tag + "-KFOO", "SYN9700004", "2823-3", "Potassium", "4.0", "foo"),
        "k_meq": oru(tag + "-KMEQ", "SYN9700005", "2823-3", "Potassium", "6.9", "mEq/L"),
        "k_same": oru(tag + "-KSAME", "SYN9700006", "2823-3", "Potassium", "4.0", "mmol/L"),
        "k_text": oru(tag + "-KTXT", "SYN9700007", "2823-3", "Potassium", "HEMOLYZED", "mmol/L"),
    }
    ids = {k: "%s-%s" % (tag, s) for k, s in zip(cases, ["GMG", "GMM", "GCALM", "KFOO", "KMEQ", "KSAME", "KTXT"])}
    extra = [tag + "-UG", tag + "-UK"]
    check(load_recordings(list(ids.values()) + extra), "the recording set did not load")
    acks = send(list(cases.values()))
    check(all(a == "AA" for _, a in acks), "an intake acknowledgement was not AA")
    t = {}
    for key, mid in ids.items():
        t[key] = wait_for(lambda m=mid: trace(m), 90)
        check(t[key] is not None, "no trace for " + key)
    if failures:
        return 1

    g = t["g_mg"]
    check(g["ConversionOutcome"] == "converted" and g["OriginalValue"] == "540" and g["OriginalUnit"] == "mg/dL" and g["ConvertedUnit"] == "mmol/L", "glucose mg/dL not converted in the trace: %s" % g)
    check(abs(float(g["ConvertedValue"] or 0) - 29.9740) < 0.01, "glucose 540 mg/dL converted to %s mmol/L, expected about 29.97" % g["ConvertedValue"])
    check(g["FloorSeverity"] == "3" and g["Route"] == "readback", "540 mg/dL must be critical after conversion: %s" % g)
    m = t["g_mmol"]
    check(m["ConversionOutcome"] == "not-needed" and m["ConvertedUnit"] == "mmol/L", "a value in the reference unit was converted: %s" % m)
    check(m["FloorSeverity"] == g["FloorSeverity"] and m["Route"] == g["Route"], "the same quantity in the two units gave different floors or routes")
    c = t["g_calm"]
    check(c["ConversionOutcome"] == "converted" and c["FloorSeverity"] == "0" and c["Route"] == "release", "100 mg/dL (about 5.5 mmol/L) must be released after conversion, not flagged critical: %s" % c)
    f = t["k_foo"]
    check(f["ConversionOutcome"] == "not-convertible" and f["Route"] == "review" and f["FailureReason"] == "unit not convertible", "an unconvertible unit must go to review with the fixed reason: %s" % f)
    e = t["k_meq"]
    check(e["ConversionOutcome"] == "not-convertible" and e["FloorSeverity"] == "3" and e["Route"] == "readback", "6.9 mEq/L (rejected spelling, critical under a known unit) must go to read-back: %s" % e)
    s = t["k_same"]
    check(s["ConversionOutcome"] == "not-needed" and s["Route"] == "release", "a calm result in the reference unit must be released: %s" % s)
    x = t["k_text"]
    check(x["ConversionOutcome"] == "skipped" and x["ConvertedValue"] == "", "a non-numeric value must skip conversion: %s" % x)

    # The conversion component is not available: the case is still judged, conservatively, and a person sees it.
    iris('set sc=##class(Ens.Director).EnableConfigItem("Readback.Units",0)')
    time.sleep(4)
    more = {"ug": oru(extra[0], "SYN9700008", "2345-7", "Glucose", "100", "mg/dL"),
            "uk": oru(extra[1], "SYN9700009", "2823-3", "Potassium", "4.0", "umol/L")}
    send(list(more.values()))
    u1 = wait_for(lambda: trace(extra[0]), 60)
    u2 = wait_for(lambda: trace(extra[1]), 60)
    if u1:
        check(u1["ConversionOutcome"] == "unavailable" and u1["FloorSeverity"] == "3" and u1["Route"] == "readback", "with the component down a value critical under a known unit must still go to read-back: %s" % u1)
    if u2:
        check(u2["ConversionOutcome"] == "unavailable" and u2["Route"] == "review" and u2["FailureReason"] == "unit conversion unavailable", "with the component down a calm value must go to review with the fixed reason: %s" % u2)
    logged = scalar("SELECT COUNT(*) FROM Ens_Util.Log WHERE Text LIKE '%unit conversion unavailable%'")
    check(int(logged or 0) > 0, "the failure is not in the event log")
    iris('set sc=##class(Ens.Director).EnableConfigItem("Readback.Units",1)')
    iris('do ##class(Readback.Replay.Recording).Activate("default")\n'
         'set rs=##class(%SQL.Statement).%ExecDirect(,"DELETE FROM Readback_Replay.Recording WHERE ReplaySet = \'units\'")')

    if failures:
        print("FAILED (%d):" % len(failures))
        for item in failures:
            print(" -", item)
        return 1
    print("units check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
