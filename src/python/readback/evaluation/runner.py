"""Runs the evaluation through the running product and builds the report.

    python -m readback.evaluation.runner live gpt-5.4 [--yes] [--resume] [--output-cap N]
    python -m readback.evaluation.runner replay [replaySet]
    python -m readback.evaluation.runner report

live    needs the provider key in the container (the mode must be live), a clean state, and `--yes` after the estimate is shown.
replay  needs no key and refuses to run when a key is configured (a replay must never call the provider).
report  builds data/eval/report.json and report.md from the rows of every run in the work folder.

The key is never read, printed or written here: the container holds it, and every printed line is masked anyway.
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys
import time

from readback.evaluation import mllp, record, report

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
WORK = os.environ.get("EVAL_WORK", os.path.join(ROOT, ".local", "eval"))
# The dataset, the output folder and the sample messages can be overridden for the tests of the harness itself (EVAL_DATASET,
# EVAL_OUT, EVAL_SAMPLES=0); a real run uses the defaults.
DATASET = os.environ.get("EVAL_DATASET", os.path.join(ROOT, "data", "eval", "dataset.jsonl"))
SAMPLES = os.path.join(ROOT, "data", "samples")
PRICES = os.path.join(ROOT, "data", "config", "price-table.json")
RECORDINGS = os.path.join(ROOT, "data", "replay", "recordings.jsonl")
OUT = os.environ.get("EVAL_OUT", os.path.join(ROOT, "data", "eval"))
SHIPPED_EVAL = os.path.join(ROOT, "data", "eval")
LARGE_MODEL = "gpt-5.4"

# What one result used, as the basis of the estimate: the whole investigation (every round), input and output tokens. The first live run,
# before the agent had tools, used 708 and 100. The default is the estimate made before any run with tools; a pilot measures the real
# figure and EVAL_TOKENS_PER_CALL="input,output" replaces it.
TOKENS_PER_CALL = tuple(int(x) for x in os.environ.get("EVAL_TOKENS_PER_CALL", "3200,200").split(","))
# The ceilings a run sets so that nothing is skipped by the budget; they are written in the report. The hourly cost ceiling is the
# author's authorization for the round (EVAL_HOURLY_COST): once the cost of the last hour reaches it the budget guard stops the calls.
RUN_CEILINGS = (10000, float(os.environ.get("EVAL_HOURLY_COST", "6")), 10000000)

_MASKS = (re.compile(r"sk-[A-Za-z0-9_*.\-]{3,}"), re.compile(r"Bearer\s+\S+"))


def mask(text):
    for pattern in _MASKS:
        text = pattern.sub("[masked]", text)
    return text


def say(*parts):
    print(mask(" ".join(str(p) for p in parts)), flush=True)


def compose(*args, input_text=None, timeout=900):
    return subprocess.run(["docker", "compose", *args], cwd=ROOT, input=input_text, capture_output=True, text=True, timeout=timeout)


def iris(script, timeout=900):
    """Runs ObjectScript in USER, one block per line, and returns the lines that start with RB_."""
    proc = compose("exec", "-T", "iris", "iris", "session", "IRIS", "-U", "USER", input_text=script + "\nhalt\n", timeout=timeout)
    return [line.strip() for line in proc.stdout.splitlines() if line.strip().startswith("RB_")]


STATUS_LINE = 'write "RB_SC="_$select($system.Status.IsOK(sc):"ok",1:$system.Status.GetErrorText(sc)),!'


def container_mode():
    lines = iris('write "RB_MODE="_##class(Readback.Config.Mode).Current(),!')
    return next((l.split("=", 1)[1] for l in lines if l.startswith("RB_MODE=")), "")


def run_status(script):
    lines = iris(script)
    result = next((l for l in lines if l.startswith("RB_SC=")), "RB_SC=no answer")
    return result == "RB_SC=ok", result[6:]


def message_id(text):
    return text.split("\r")[0].split("|")[9]


def shipped_messages():
    """The sample messages of the product, history before subject as in their labels, then the two hand-written ones."""
    paths = []
    labels = os.path.join(SAMPLES, "generated", "labels.jsonl")
    with open(labels) as handle:
        for line in handle:
            if line.strip():
                paths.append(os.path.join(SAMPLES, "generated", json.loads(line)["file"]))
    paths += sorted(glob.glob(os.path.join(SAMPLES, "valid-oru-*.hl7")))
    out = []
    for path in paths:
        with open(path, newline="") as handle:
            text = handle.read().replace("\r\n", "\r").replace("\n", "\r")
        out.append((message_id(text), text))
    return out


def pilot_messages(count):
    """A small run for measuring: about count subject cases, balanced across the categories, each with the earlier results that
    explain it (the history rows of its patient), so the change tool has something to compare."""
    with open(DATASET) as handle:
        rows = [json.loads(l) for l in handle if l.strip()]
    categories = sorted({r["category"] for r in rows if r["role"] == "subject"})
    per = max(1, count // len(categories))
    picked = []
    for category in categories:
        picked += [r for r in rows if r["role"] == "subject" and r["category"] == category][:per]
    patients = {r["patientId"] for r in picked}
    chosen = [r for r in rows if r["patientId"] in patients and (r["role"] == "history" or r in picked)]
    return [(r["messageId"], r["text"]) for r in chosen]


def dataset_messages():
    with open(DATASET) as handle:
        return [(r["messageId"], r["text"]) for r in (json.loads(l) for l in handle if l.strip())]


def all_messages():
    return dataset_messages() + (shipped_messages() if os.environ.get("EVAL_SAMPLES", "1") != "0" else [])


def traced_ids():
    lines = iris('set rs=##class(%SQL.Statement).%ExecDirect(,"SELECT DISTINCT MessageControlId FROM Readback_Trace.Decision")\n'
                 'while rs.%Next() { write "RB_ID ",rs.%Get("MessageControlId"),! }')
    return {l[6:] for l in lines if l.startswith("RB_ID ")}


def price_of(model):
    with open(PRICES) as handle:
        for row in json.load(handle)["prices"]:
            if row["model"] == model:
                return row
    return None


def estimate(model, count):
    price = price_of(model)
    if not price or price.get("inputPerMillion") is None or price.get("outputPerMillion") is None:
        return None, price
    per_call = TOKENS_PER_CALL[0] * price["inputPerMillion"] / 1e6 + TOKENS_PER_CALL[1] * price["outputPerMillion"] / 1e6
    return per_call * count, price


def wait_for_traces(ids, stall_seconds=240, limit_seconds=5400):
    start = last_change = time.time()
    seen = set()
    while True:
        now_seen = traced_ids() & ids
        if now_seen != seen:
            seen, last_change = now_seen, time.time()
            say("traced {} of {}".format(len(seen), len(ids)))
        if len(seen) == len(ids):
            return True
        if time.time() - last_change > stall_seconds or time.time() - start > limit_seconds:
            return False
        time.sleep(10)


def export_rows(model_hint):
    ok, text = run_status('set sc=##class(Readback.Eval.Export).Rows("/tmp/eval-rows.jsonl","",.n)\n' + STATUS_LINE)
    if not ok:
        raise RuntimeError("export failed: " + text)
    os.makedirs(WORK, exist_ok=True)
    tmp = os.path.join(WORK, "rows-export.jsonl")
    proc = compose("cp", "iris:/tmp/eval-rows.jsonl", tmp)
    if proc.returncode:
        raise RuntimeError("could not copy the export out: " + mask(proc.stderr))
    with open(tmp) as handle:
        rows = [json.loads(l) for l in handle if l.strip()]
    models = sorted({r["model"] for r in rows if r.get("model")})
    name = models[0] if len(models) == 1 else (model_hint or "mixed")
    final = os.path.join(WORK, "rows-{}.jsonl".format(name))
    os.replace(tmp, final)
    return final, name, len(rows)


def build_reports():
    runs, metas = [], []
    for path in sorted(glob.glob(os.path.join(WORK, "rows-*.jsonl"))):
        name = os.path.basename(path)[len("rows-"):-len(".jsonl")]
        runs += ["--run", "{}={}".format(name, path)]
        # The settings of a live run are kept beside its report, so a replay states the same header.
        meta = next((m for m in (os.path.join(WORK, "meta-{}.json".format(name)), os.path.join(SHIPPED_EVAL, "meta-{}.json".format(name))) if os.path.exists(m)), None)
        if meta:
            metas += ["--meta", "{}={}".format(name, meta)]
    if not runs:
        say("no run to report: the work folder {} has no rows".format(WORK))
        return 2
    # The report of the previous round, when there is one, so that the new report states how each figure moved.
    previous = os.environ.get("EVAL_PREVIOUS") or next((p for p in (os.path.join(SHIPPED_EVAL, "report-before-tools.json"),) if os.path.exists(p)), None)
    extra = ["--previous", previous] if previous else []
    return report.main(runs + metas + extra + ["--dataset", DATASET, "--prices", PRICES, "--out", OUT])


def run_live(model, resume=False, yes=False, output_cap=None, replay_set=None, pilot=None, record_answers=True):
    mode = container_mode()
    if mode != "live":
        say("refusing: the product is in {} mode, so no provider key is configured in the container. Nothing was sent.".format(mode or "unknown"))
        return 2
    messages = pilot_messages(pilot) if pilot else all_messages()
    ids = {m[0] for m in messages}
    clean, why = clean_state()
    if not clean and not resume:
        say("refusing: the state is not clean ({}). Start from a fresh stack, or use --resume to finish a run that stopped.".format(why))
        return 2
    done = traced_ids() if resume else set()
    todo = [m for m in messages if m[0] not in done]
    cost, price = estimate(model, len(todo))
    say("model {}: {} messages to send ({} already traced)".format(model, len(todo), len(done & ids)))
    if cost is None:
        say("estimated cost: unknown (no price for {} in the price table)".format(model))
    else:
        say("estimated cost: about {:.2f} USD (at {} input and {} output tokens per call, price dated {})".format(cost, TOKENS_PER_CALL[0], TOKENS_PER_CALL[1], price["priceDate"]))
    if not yes:
        say("nothing was sent. Run again with --yes to start; this run is paid.")
        return 0
    ok, text = run_status('set sc=##class(Readback.Eval.Control).UseModel("{}")\n'.format(model) + STATUS_LINE)
    if not ok:
        say("could not set the model:", text)
        return 1
    cap = output_cap
    if cap:
        ok, text = run_status('set sc=##class(Readback.Eval.Control).UseOutputCap({})\n'.format(int(cap)) + STATUS_LINE)
        if not ok:
            say("could not set the output cap:", text)
            return 1
    previous = next((l[8:] for l in iris('write "RB_PREV "_##class(Readback.Eval.Control).CeilingsJson(),!') if l.startswith("RB_PREV ")), "{}")
    ok, text = run_status('set sc=##class(Readback.Eval.Control).UseCeilings({},{},{},.prev)\n'.format(*RUN_CEILINGS) + STATUS_LINE)
    if not ok:
        say("could not set the run ceilings:", text)
        return 1
    ceilings = next((l[8:] for l in iris('write "RB_CEIL "_##class(Readback.Eval.Control).CeilingsText(),!') if l.startswith("RB_CEIL ")), "")
    try:
        acks = mllp.send_many(todo, progress=lambda n, total: say("sent {} of {}".format(n, total)) if n % 50 == 0 or n == total else None)
        bad = [i for i, a in acks if a != "AA"]
        if bad:
            say("{} messages were not acknowledged AA: {}".format(len(bad), ", ".join(bad[:5])))
        complete = wait_for_traces(ids)
        if not complete:
            say("not every message reached a decision; the run can be resumed with --resume")
        path, name, count = export_rows(model)
    finally:
        restore_ceilings(previous)
    for folder in (WORK, OUT):
        os.makedirs(folder, exist_ok=True)
        with open(os.path.join(folder, "meta-{}.json".format(name)), "w") as handle:
            json.dump({"settings": "temperature 0; strict JSON schema; output cap {} tokens; model {}".format(cap or 400, model), "ceilings": ceilings}, handle, indent=2)
    if not record_answers:
        say("exported {} rows to {}; nothing was recorded (a pilot never touches the recordings that ship)".format(count, path))
        return 0 if complete else 1
    target = replay_set or ("default" if name == LARGE_MODEL else name)
    try:
        recorded, skipped = record.from_export(path, target, RECORDINGS)
    except ValueError as error:
        say("not recorded:", error)
        return 1
    say("exported {} rows to {}; recorded {} answers into replay set {} ({} had no output)".format(count, path, recorded, target, skipped))
    return 0 if complete else 1


def restore_ceilings(previous_json):
    """Puts the ceilings that were in force before the run back (the previous values were read before they were changed)."""
    try:
        prev = json.loads(previous_json)
        ok, text = run_status('set sc=##class(Readback.Eval.Control).UseCeilings({},{},{},.prev)\n'.format(
            prev["perResultTokens"], prev["hourlyCostUsd"], prev["hourlyTokens"]) + STATUS_LINE)
        if not ok:
            say("the ceilings could not be restored:", text)
    except (ValueError, KeyError):
        say("the previous ceilings were not known, so they were not restored")


def clean_state():
    lines = iris('set ok=##class(Readback.Eval.Control).IsClean(.why)\nwrite "RB_CLEAN="_ok_"|"_$get(why),!')
    text = next((l for l in lines if l.startswith("RB_CLEAN=")), "RB_CLEAN=0|state unknown")[9:]
    flag, _, why = text.partition("|")
    return flag == "1", why


def run_replay(replay_set="default"):
    mode = container_mode()
    if mode != "replay":
        say("refusing: the product is in {} mode, so a provider key is configured and a replay could call the provider. Start the stack with the key empty. Nothing was sent.".format(mode or "unknown"))
        return 2
    clean, why = clean_state()
    if not clean:
        say("refusing: the state is not clean ({}). Start from a fresh stack.".format(why))
        return 2
    ok, text = run_status('set sc=##class(Readback.Eval.Control).UseReplaySet("{}")\n'.format(replay_set) + STATUS_LINE)
    if not ok:
        say("could not select the replay set:", text)
        return 1
    messages = all_messages()
    ids = {m[0] for m in messages}
    acks = mllp.send_many(messages, progress=lambda n, total: say("sent {} of {}".format(n, total)) if n % 100 == 0 or n == total else None)
    bad = [i for i, a in acks if a != "AA"]
    if bad:
        say("{} messages were not acknowledged AA: {}".format(len(bad), ", ".join(bad[:5])))
    complete = wait_for_traces(ids, stall_seconds=120, limit_seconds=1800)
    path, name, count = export_rows(None)
    say("exported {} rows of set {} to {}".format(count, replay_set, path))
    return 0 if complete else 1


def main(argv=None):
    parser = argparse.ArgumentParser(description="Run the evaluation through the running product and build the report.")
    sub = parser.add_subparsers(dest="command", required=True)
    live = sub.add_parser("live")
    live.add_argument("model")
    live.add_argument("--yes", action="store_true")
    live.add_argument("--resume", action="store_true")
    live.add_argument("--output-cap", type=int, default=None)
    live.add_argument("--set", dest="replay_set", default=None)
    live.add_argument("--pilot", type=int, default=None, help="send only about N subject cases (balanced across categories) with their history, record nothing")
    rep = sub.add_parser("replay")
    rep.add_argument("replay_set", nargs="?", default="default")
    sub.add_parser("report")
    args = parser.parse_args(argv)
    if args.command == "live":
        code = run_live(args.model, args.resume, args.yes, args.output_cap, args.replay_set, args.pilot, record_answers=not args.pilot)
    elif args.command == "replay":
        code = run_replay(args.replay_set)
    else:
        return build_reports()
    ran = args.command == "replay" or args.yes
    if args.command == "live" and args.pilot:
        return code  # a pilot measures; it never writes a report
    return (build_reports() or code) if (code == 0 and ran) else code


if __name__ == "__main__":
    sys.exit(main())
