"""The evaluation harness end to end, in replay, with no key.

Builds a small dataset (2 cases per category) and test-only recordings in a replay set of their own, runs
`src/ops/evaluate.sh replay eval-test` against the running product and checks the report: every case in a cell or in the
`none` column, the agent matrix equal to the recorded answers, no silenced critical, the missed critical and the downgrade
attempts listed, a case with no recording counted and not dropped, recorded latency (not measured) in the export, and a second
run on a cleaned state giving a byte-identical report. Nothing is written to data/eval or to the shipped recordings.
"""
import glob
import json
import os
import subprocess
import sys
import tempfile

import make_hostile
from common import ROOT, compose, iris, query, scalar

sys.path.insert(0, os.path.join(ROOT, "src", "python"))
from readback.evaluation import dataset as eval_dataset  # noqa: E402

PYTHON = os.environ.get("PYTHON", sys.executable)
SET = "eval-test"
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)
        print("FAIL:", message)


def start_stack():
    compose("up", "-d", "--build", "--force-recreate", extra_env={"OPENAI_API_KEY": "", "READBACK_DEMO_PASSWORD": "demo-pass-for-tests"})
    subprocess.run([os.path.join(ROOT, "src/ops/verify.sh"), "240"], cwd=ROOT, check=True, capture_output=True)


def answer(decision, severity):
    return json.dumps({"decision": decision, "severity": severity, "rationale": "test-only answer", "evidence": ["current-result"], "confidence": "high"})


def stand_in(rows):
    """message id -> (answer text or None for no recording, label). The rule is fixed so the matrices can be counted by hand."""
    seen = {}
    plan = {}
    for r in rows:
        if r["role"] == "history":
            plan[r["messageId"]] = (answer("NON_CRITICAL", 0), "history")
            continue
        n = seen[r["category"]] = seen.get(r["category"], 0) + 1
        c = r["category"]
        if c == "clear-critical":
            plan[r["messageId"]] = (answer("CRITICAL", 3), "agrees")
        elif c == "contextual-critical":
            plan[r["messageId"]] = (answer("CRITICAL", 3), "agrees") if n == 1 else (answer("NON_CRITICAL", 0), "missed")
        elif c == "explainable-false-critical":
            plan[r["messageId"]] = (answer("NON_CRITICAL", 0), "downgrade")
        elif c == "acute-drop-in-range":
            plan[r["messageId"]] = (answer("CRITICAL", 3), "agrees")
        elif c == "sample-problem":
            plan[r["messageId"]] = (answer("RECOLLECT", 1), "downgrade")
        elif c == "recollect":
            plan[r["messageId"]] = (answer("RECOLLECT", 1), "agrees")
        elif c == "ambiguous":
            plan[r["messageId"]] = (answer("NEEDS_REVIEW", 2), "agrees") if n == 1 else ("this is not json", "invalid")
        else:
            plan[r["messageId"]] = (answer("NON_CRITICAL", 0), "agrees") if n == 1 else (None, "norecording")
    return plan


def load_recordings(plan, version, path):
    rows = []
    for i, (mid, (text, _)) in enumerate(sorted(plan.items())):
        if text is None:
            continue
        rows.append({"messageControlId": mid, "promptVersion": version, "replaySet": SET, "answer": text, "model": "gpt-5.4",
                     "inputTokens": 700, "outputTokens": 100, "latencyMs": 1000 + 100 * (i % 10), "source": "fixture"})
    with open(path, "w") as handle:
        for row in rows:
            handle.write(json.dumps(row) + "\n")
    compose("cp", path, "iris:/tmp/eval-test.jsonl")
    lines = iris('set sc=##class(Readback.Replay.Recording).LoadFile("/tmp/eval-test.jsonl",.n)\nwrite "RB_LOADED="_n_"|"_$select($system.Status.IsOK(sc):"ok",1:$system.Status.GetErrorText(sc)),!')
    return rows, next((l for l in lines if l.startswith("RB_LOADED=")), "")


def wipe_state():
    """Empties the trace and the confirmed-case pool, as a fresh stack would be."""
    iris('set rs=##class(%SQL.Statement).%ExecDirect(,"DELETE FROM Readback_Trace.Decision")\n'
         'set rs=##class(%SQL.Statement).%ExecDirect(,"DELETE FROM Readback_Retrieval.CaseVec")\nwrite "RB_WIPED",!')


def run_replay(env):
    proc = subprocess.run([os.path.join(ROOT, "src/ops/evaluate.sh"), "replay", SET], cwd=ROOT, capture_output=True, text=True, env=env, timeout=900)
    return proc.returncode, proc.stdout + proc.stderr


def main():
    start_stack()
    with tempfile.TemporaryDirectory() as work:
        rows = eval_dataset.build(seed=7, per_category=2)
        subjects = [r for r in rows if r["role"] == "subject"]
        check(len(subjects) == 16, "the test dataset should have 16 subject cases, has %d" % len(subjects))
        data_path = os.path.join(work, "dataset.jsonl")
        with open(data_path, "w") as handle:
            for r in rows:
                handle.write(json.dumps(r, sort_keys=True) + "\n")
        plan = stand_in(rows)
        recs, loaded = load_recordings(plan, make_hostile.prompt_version(), os.path.join(work, "recs.jsonl"))
        check(loaded == "RB_LOADED=%d|ok" % len(recs), "the test recordings did not load: %s" % loaded)
        env = dict(os.environ, EVAL_DATASET=data_path, EVAL_OUT=os.path.join(work, "out"), EVAL_WORK=os.path.join(work, "run"), EVAL_SAMPLES="0",
                   PYTHON=PYTHON, OPENAI_API_KEY="")

        # The live command refuses without a key and sends nothing.
        wipe_state()
        proc = subprocess.run([os.path.join(ROOT, "src/ops/evaluate.sh"), "live", "gpt-5.4", "--yes"], cwd=ROOT, capture_output=True, text=True, env=env, timeout=300)
        check(proc.returncode == 2 and "no provider key" in proc.stdout, "live mode without a key did not refuse: %s %s" % (proc.returncode, proc.stdout[:200]))
        check(scalar("SELECT COUNT(*) FROM Readback_Trace.Decision") == "0", "the refused live run sent something")

        code, out = run_replay(env)
        check(code == 0, "the replay evaluation failed (%s): %s" % (code, out[-500:]))
        report_path = os.path.join(work, "out", "report.json")
        check(os.path.exists(report_path), "no report was written")
        if not os.path.exists(report_path):
            return finish()
        first_bytes = open(report_path, "rb").read()
        model = json.loads(first_bytes)["models"].get("gpt-5.4")
        check(model is not None, "the report has no model gpt-5.4: %s" % list(json.loads(first_bytes)["models"]))
        if model:
            check_report(model, plan, subjects)
        rows_file = os.path.join(work, "run", "rows-gpt-5.4.jsonl")
        check_rows(rows_file, recs)

        # A second run on a cleaned state gives a byte-identical report.
        wipe_state()
        code, out = run_replay(env)
        check(code == 0, "the second replay failed (%s): %s" % (code, out[-300:]))
        check(open(report_path, "rb").read() == first_bytes, "the second report differs from the first (FR-015)")
        check(open(os.path.join(work, "out", "report.md")).read() != "", "the Markdown report is empty")

        # No credential-like text in any output.
        for path in (report_path, os.path.join(work, "out", "report.md"), rows_file):
            text = open(path).read()
            check("sk-" not in text and "Bearer" not in text, "credential-like text in " + path)
    wipe_state()
    iris('set rs=##class(%SQL.Statement).%ExecDirect(,"DELETE FROM Readback_Replay.Recording WHERE ReplaySet = \'eval-test\'")\n'
         'do ##class(Readback.Replay.Recording).Activate("default")\nwrite "RB_CLEAN",!')
    check_shipped_replay()
    return finish()


def check_shipped_replay():
    """The shipped recordings come from real runs and reproduce the published report (FR-015, SC-003, SC-005)."""
    shipped = os.path.join(ROOT, "data", "replay", "recordings.jsonl")
    rows = [json.loads(l) for l in open(shipped) if l.strip()]
    check(rows and not any(r.get("source") != "recorded" for r in rows), "the shipped recordings hold a row that is not a recorded answer")
    published = json.load(open(os.path.join(ROOT, "data", "eval", "report.json")))
    # Every shipped sample result has a recording of the real run in the default set.
    ids = {r["messageControlId"] for r in rows if r.get("replaySet") == "default"}
    for path in sorted(glob.glob(os.path.join(ROOT, "data", "samples", "**", "*.hl7"), recursive=True)):
        text = open(path, errors="ignore").read().replace("\r", "\n")
        if "ORU" not in text.split("\n")[0] or os.path.basename(path).startswith("invalid-"):
            continue  # a message that carries no result never reaches the agent
        mid = text.split("\n")[0].split("|")[9]
        check(mid in ids, "the shipped sample %s has no recording" % os.path.basename(path))
    for replay_set, model in (("default", "gpt-5.4"), ("gpt-5.4-mini", "gpt-5.4-mini")):
        wipe_state()
        with tempfile.TemporaryDirectory() as work:
            env = dict(os.environ, EVAL_OUT=os.path.join(work, "out"), EVAL_WORK=os.path.join(work, "run"), PYTHON=PYTHON, OPENAI_API_KEY="")
            code, out = run_replay_set(env, replay_set)
            check(code == 0, "the replay of %s failed (%s): %s" % (replay_set, code, out[-300:]))
            path = os.path.join(work, "out", "report.json")
            if os.path.exists(path):
                again = json.load(open(path))["models"].get(model)
                check(again == published["models"].get(model), "the replay of %s differs from the published report" % replay_set)
    wipe_state()
    iris('do ##class(Readback.Replay.Recording).Activate("default")\nwrite "RB_CLEAN",!')


def run_replay_set(env, replay_set):
    proc = subprocess.run([os.path.join(ROOT, "src/ops/evaluate.sh"), "replay", replay_set], cwd=ROOT, capture_output=True, text=True, env=env, timeout=1800)
    return proc.returncode, proc.stdout + proc.stderr


def check_report(model, plan, subjects):
    agent, final = model["matrixAgent"], model["matrixFinal"]
    total_agent = sum(sum(row.values()) for row in agent.values())
    total_final = sum(sum(row.values()) for row in final.values())
    check(total_agent == 16 and total_final == 16, "every subject case must be in a cell or in none: %d and %d" % (total_agent, total_final))
    # The agent matrix equals the recorded answers (counted by hand from the stand-in rule).
    check(agent["CRITICAL"] == {"CRITICAL": 5, "RECOLLECT": 2, "NEEDS_REVIEW": 0, "NON_CRITICAL": 3, "none": 0},
          "agent matrix, expected CRITICAL: %s" % agent["CRITICAL"])
    check(agent["RECOLLECT"]["RECOLLECT"] == 2, "agent matrix, expected RECOLLECT: %s" % agent["RECOLLECT"])
    check(agent["NEEDS_REVIEW"] == {"CRITICAL": 0, "RECOLLECT": 0, "NEEDS_REVIEW": 1, "NON_CRITICAL": 0, "none": 1}, "agent matrix, expected NEEDS_REVIEW: %s" % agent["NEEDS_REVIEW"])
    check(agent["NON_CRITICAL"] == {"CRITICAL": 0, "RECOLLECT": 0, "NEEDS_REVIEW": 0, "NON_CRITICAL": 1, "none": 1}, "agent matrix, expected NON_CRITICAL: %s" % agent["NON_CRITICAL"])
    check(model["silencedCriticals"] == 0, "silenced criticals: %s" % model["silencedCriticalIds"])
    check(len(model["missedCriticals"]) == 1, "exactly one missed critical (a contextual case answered NON_CRITICAL): %s" % model["missedCriticals"])
    check(model["downgradeAttempts"] == 4, "downgrade attempts (2 explainable, 2 sample-problem): %s" % model["downgradeAttempts"])
    check(model["failureCounts"].get("no-recorded-answer", 0) >= 1, "the case with no recording is not counted: %s" % model["failureCounts"])
    check(model["failureCounts"].get("schema-invalid", 0) == 1, "the invalid answer is not counted as schema-invalid: %s" % model["failureCounts"])
    check(model["costPerThousandUsd"] is not None and model["unknownCostRows"] <= 2, "cost should be known for the recorded model: %s / %s" % (model["costPerThousandUsd"], model["unknownCostRows"]))
    check(model["missingSubjects"] == [], "a subject case never reached the trace: %s" % model["missingSubjects"])


def check_rows(path, recs):
    exported = {}
    with open(path) as handle:
        for line in handle:
            row = json.loads(line)
            exported.setdefault(row["messageControlId"], row)
    for rec in recs:
        row = exported.get(rec["messageControlId"])
        if row is None:
            check(False, "no exported row for " + rec["messageControlId"])
            continue
        check(row["latencyMs"] == rec["latencyMs"], "%s: exported latency %s, recorded %s" % (rec["messageControlId"], row["latencyMs"], rec["latencyMs"]))
        check(row["model"] == "gpt-5.4", "%s: model %s" % (rec["messageControlId"], row["model"]))
        check("inputText" not in row and "InputText" not in row, "the export holds the input text")


def finish():
    if failures:
        print("FAILED (%d):" % len(failures))
        for f in failures[:25]:
            print(" -", f)
        return 1
    print("evaluation check passed (16 cases, replay, byte-identical second run)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
