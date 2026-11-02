"""The evaluation report: confusion matrices, silenced and missed criticals, cost and latency, per model.

    python -m readback.evaluation.report --run gpt-5.4=rows-large.jsonl --run gpt-5.4-mini=rows-small.jsonl \\
        --dataset data/eval/dataset.jsonl --prices data/config/price-table.json --out data/eval

A run file is the export of the trace of one model (src/Readback/Eval/Export.cls), one JSON object per line. The definitions
are those of contracts/evaluation.md; where they overlap with the indicators endpoint they are the same (cost per thousand,
nearest-rank percentiles, the invalid, review and divergence rates), so the two never disagree. The exit status is non-zero when a
silenced critical is found: that is a safety defect, not a result.
"""
import argparse
import datetime
import json
import math
import os
import sys

DECISIONS = ("CRITICAL", "RECOLLECT", "NEEDS_REVIEW", "NON_CRITICAL")
COLUMNS = DECISIONS + ("none",)
ROUTE_TO_DECISION = {"readback": "CRITICAL", "recollect": "RECOLLECT", "review": "NEEDS_REVIEW", "release": "NON_CRITICAL"}

# The figures of the first live run of gpt-5.4 through the product (26 sample messages), kept beside the evaluation's.
FIRST_LIVE_RUN = {"model": "gpt-5.4", "calls": 26, "schemaValid": 26, "latencyP50Ms": 2231, "latencyP95Ms": 3268,
                  "costPerThousandUsd": 3.3306, "inputTokensP50": 708, "outputTokensP50": 100}


def _int(value, default=None):
    if value is None or value == "":
        return default
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return default


def _float(value, default=None):
    if value is None or value == "":
        return default
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _truthy(value):
    return str(value).lower() in ("1", "true")


def nearest_rank(values, percent):
    """The value at position ceiling(percent * n / 100) of the sorted list; None for an empty list."""
    if not values:
        return None
    ordered = sorted(values)
    rank = -(-percent * len(ordered) // 100)
    return ordered[min(max(int(rank), 1), len(ordered)) - 1]


def _empty_matrix():
    return {expected: {column: 0 for column in COLUMNS} for expected in DECISIONS}


def load_jsonl(path):
    with open(path) as handle:
        return [json.loads(line) for line in handle if line.strip()]


def expected_map(dataset_rows):
    """message id -> (expected decision, category) for the subject rows."""
    return {r["messageId"]: (r["expected"], r["category"]) for r in dataset_rows if r["role"] == "subject"}


def agent_column(row):
    """The decision the agent answered, or 'none' when there is no valid answer (invalid, refused, timed out, error, skipped)."""
    if not _truthy(row.get("agentCalled")) or not _truthy(row.get("schemaValid")):
        return "none"
    decision = row.get("agentDecision")
    return decision if decision in DECISIONS else "none"


def compute_model(rows, expected):
    """Every figure of one model's run. rows: the exported trace rows; expected: expected_map of the dataset."""
    by_id = {}
    for row in rows:
        by_id.setdefault(row["messageControlId"], row)
    matrix_agent, matrix_final = _empty_matrix(), _empty_matrix()
    silenced, missed, missing = [], [], []
    downgrades = 0
    agreement = {}
    for message_id, (wanted, category) in sorted(expected.items()):
        row = by_id.get(message_id)
        tally = agreement.setdefault(category, {"cases": 0, "agentAgrees": 0, "finalAgrees": 0})
        tally["cases"] += 1
        if row is None:
            missing.append(message_id)
            matrix_agent[wanted]["none"] += 1
            matrix_final[wanted]["none"] += 1
            continue
        agent = agent_column(row)
        final = ROUTE_TO_DECISION.get(row.get("route"), "none")
        matrix_agent[wanted][agent] += 1
        matrix_final[wanted][final] += 1
        tally["agentAgrees"] += agent == wanted
        tally["finalAgrees"] += final == wanted
        floor = _int(row.get("floorSeverity"), 0)
        if floor >= 3 and row.get("route") != "readback":
            silenced.append(message_id)
        if wanted == "CRITICAL" and floor < 3 and row.get("route") != "readback":
            missed.append(message_id)
        if floor >= 3 and agent != "none" and (agent != "CRITICAL" or _int(row.get("agentSeverity"), 3) < floor):
            downgrades += 1

    count = len(by_id)
    called = [r for r in by_id.values() if _truthy(r.get("agentCalled"))]
    latencies = [_int(r.get("latencyMs")) for r in called if _int(r.get("latencyMs")) is not None]
    known = [r for r in by_id.values() if _truthy(r.get("costKnown"))]
    failures = {}
    for r in by_id.values():
        if r.get("failureKind"):
            failures[r["failureKind"]] = failures.get(r["failureKind"], 0) + 1
    invalid = sum(1 for r in by_id.values() if not _truthy(r.get("schemaValid")) and r.get("failureKind") in ("schema-invalid", "empty-or-refused"))
    cost = None
    if known:
        cost = round(sum(_float(r.get("costUsd"), 0.0) for r in known) / len(known) * 1000, 6)
    models = sorted({r.get("model") for r in by_id.values() if r.get("model")})
    # The investigation with tools: calls and rounds per result the agent was asked about, the calls that did not succeed, the
    # floor policy's refusals, and the answers rejected for evidence no tool returned (counted as invalid answers too).
    calls_made = sum(_int(r.get("toolCallCount"), 0) for r in called)
    rounds = [_int(r.get("rounds"), 1) for r in called]
    refused_calls = sum(1 for r in called for c in (r.get("toolCalls") or []) if c.get("status") == "refused")
    invalid_answers = sum(1 for r in called if r.get("failureKind") in ("schema-invalid", "empty-or-refused", "evidence-not-from-tools"))
    tools = {
        "toolCalls": calls_made,
        "toolCallsPerResult": round(calls_made / len(called), 4) if called else None,
        "roundsMean": round(sum(rounds) / len(rounds), 4) if rounds else None,
        "roundsMax": max(rounds) if rounds else None,
        "toolFailures": sum(1 for r in called if _int(r.get("toolFailureCount"), 0) > 0),
        "toolRefusals": refused_calls,
        "floorPolicyRefusals": sum(1 for r in called if r.get("policyRefusal")),
        "evidenceRejected": sum(1 for r in called if r.get("evidenceCheck") == "not-from-tools"),
        "limitReached": sum(1 for r in called if r.get("failureKind") == "tool-limit"),
        "invalidAnswerRate": round(invalid_answers / len(called), 6) if called else None,
    }
    return {
        **tools,
        "model": models[0] if len(models) == 1 else ",".join(models),
        "rowCount": count,
        "subjectCount": len(expected),
        "missingSubjects": missing,
        "callCount": len(called),
        "matrixAgent": matrix_agent,
        "matrixFinal": matrix_final,
        "silencedCriticals": len(silenced),
        "silencedCriticalIds": silenced,
        "missedCriticals": missed,
        "downgradeAttempts": downgrades,
        "costPerThousandUsd": cost,
        "unknownCostRows": count - len(known),
        "latencyP50Ms": nearest_rank(latencies, 50),
        "latencyP95Ms": nearest_rank(latencies, 95),
        "invalidRate": round(invalid / count, 6) if count else None,
        "reviewRate": round(sum(1 for r in by_id.values() if r.get("route") == "review") / count, 6) if count else None,
        "divergenceRate": round(sum(1 for r in by_id.values() if r.get("divergence")) / count, 6) if count else None,
        "failureCounts": dict(sorted(failures.items())),
        "agreementByCategory": dict(sorted(agreement.items())),
        "promptVersions": sorted({r.get("promptVersion") for r in by_id.values() if r.get("promptVersion")}),
    }


MOVEMENT_KEYS = (("missedCriticals", lambda m: len(m["missedCriticals"])), ("silencedCriticals", lambda m: m["silencedCriticals"]),
                 ("downgradeAttempts", lambda m: m["downgradeAttempts"]), ("reviewRate", lambda m: m["reviewRate"]),
                 ("divergenceRate", lambda m: m["divergenceRate"]), ("invalidRate", lambda m: m["invalidRate"]),
                 ("costPerThousandUsd", lambda m: m["costPerThousandUsd"]), ("latencyP50Ms", lambda m: m["latencyP50Ms"]),
                 ("latencyP95Ms", lambda m: m["latencyP95Ms"]),
                 ("expectedCriticalReadback", lambda m: m["matrixFinal"]["CRITICAL"]["CRITICAL"]),
                 ("expectedCriticalAgentAlone", lambda m: m["matrixAgent"]["CRITICAL"]["CRITICAL"]))


def movement(current, previous):
    """Each headline figure of a model against the same figure of the previous report: previous, current and the difference, the
    ones that got worse included. A model that has no previous figure is listed with the previous value empty."""
    out = {}
    for name, now in current["models"].items():
        before = (previous or {}).get("models", {}).get(name)
        figures = {}
        for key, getter in MOVEMENT_KEYS:
            try:
                new = getter(now)
            except (KeyError, TypeError):
                new = None
            try:
                old = getter(before) if before else None
            except (KeyError, TypeError):
                old = None
            delta = round(new - old, 6) if isinstance(new, (int, float)) and isinstance(old, (int, float)) else None
            figures[key] = {"previous": old, "current": new, "delta": delta}
        out[name] = figures
    return out


def build_report(runs, dataset_rows, prices, header, meta=None, previous=None):
    """runs: model name -> exported rows. prices: the rows of price-table.json. header: seed, run date, prompt versions.
    meta: model name -> {"settings": text, "ceilings": text}, the settings and budget ceilings of that model's run."""
    meta = meta or {}
    expected = expected_map(dataset_rows)
    price_by_model = {p["model"]: p for p in prices}
    models = {}
    for name, rows in runs.items():
        figures = compute_model(rows, expected)
        price = price_by_model.get(name)
        figures["price"] = None if price is None else {"inputPerMillion": price.get("inputPerMillion"),
                                                       "outputPerMillion": price.get("outputPerMillion"), "priceDate": price.get("priceDate")}
        figures["runSettings"] = meta.get(name, {}).get("settings", "")
        figures["budgetCeilings"] = meta.get(name, {}).get("ceilings", "")
        models[name] = figures
    report = {"header": header, "models": models, "firstLiveRun": FIRST_LIVE_RUN}
    if previous:
        report["movement"] = movement(report, previous)
        report["previousPromptVersions"] = previous.get("header", {}).get("promptVersions", [])
    return report


def _fmt(value, digits=None):
    if value is None:
        return "unknown" if digits == "cost" else "n/a"
    if digits == "cost":
        return "{:.4f}".format(value)
    if digits == "rate":
        return "{:.1%}".format(value)
    return str(value)


def _matrix_table(matrix):
    lines = ["| expected \\ decided | " + " | ".join(COLUMNS) + " |", "|---|" + "---|" * len(COLUMNS)]
    for expected in DECISIONS:
        lines.append("| {} | ".format(expected) + " | ".join(str(matrix[expected][c]) for c in COLUMNS) + " |")
    return lines


def write_json(report, path):
    with open(path, "w") as handle:
        json.dump(report, handle, indent=2, sort_keys=True)
        handle.write("\n")


def write_markdown(report, path):
    h = report["header"]
    out = ["# Evaluation report", "",
           "Dataset seed {}, {} subject cases per model, prompt version {}, run date {}.".format(
               h.get("seed"), h.get("subjectCases"), ", ".join(h.get("promptVersions", [])) or "n/a", h.get("runDate")),
           "",
           "How to read it. Each case went through the whole product (floor, retrieval, agent, composition, budget). The agent matrix compares "
           "the decision the agent answered with the expected one; `none` means no valid answer (invalid, refused, timed out, provider error, "
           "budget skipped) or a case that was never processed. The final matrix compares the route the product chose (read-back is CRITICAL, "
           "recollect is RECOLLECT, review is NEEDS_REVIEW, release is NON_CRITICAL). A silenced critical is a result critical by the rule table "
           "whose final route is not read-back; it must be zero. A missed critical is an expected-critical result that was not critical by rule and "
           "that no layer sent to read-back: an error of the agent, listed by case. A downgrade attempt is a rule-critical result for which the "
           "agent answered less than critical (the composition keeps it critical).", ""]
    for name, m in report["models"].items():
        price = m.get("price")
        out += ["## {}".format(name), "",
                "Price per million tokens (input / output): {} (dated {}).".format(
                    "unknown" if not price else "{} / {} USD".format(price["inputPerMillion"], price["outputPerMillion"]),
                    "n/a" if not price else price["priceDate"]), "",
                "Run settings: {}. Budget ceilings of the run: {}.".format(m.get("runSettings") or "n/a", m.get("budgetCeilings") or "n/a"), "",
                "### Agent decision against the expected decision", ""] + _matrix_table(m["matrixAgent"]) + [
                "", "### Final decision (route) against the expected decision", ""] + _matrix_table(m["matrixFinal"]) + ["",
                "### Figures", "",
                "- Silenced criticals: **{}**{}".format(m["silencedCriticals"], "" if not m["silencedCriticalIds"] else " ({})".format(", ".join(m["silencedCriticalIds"]))),
                "- Missed criticals (expected CRITICAL, not critical by rule, not sent to read-back): {}{}".format(
                    len(m["missedCriticals"]), "" if not m["missedCriticals"] else " ({})".format(", ".join(m["missedCriticals"]))),
                "- Downgrade attempts by the agent on rule-critical results: {}".format(m["downgradeAttempts"]),
                "- Cost per thousand results (USD): {} (rows of unknown cost: {})".format(_fmt(m["costPerThousandUsd"], "cost"), m["unknownCostRows"]),
                "- Latency p50 / p95 (ms, recorded): {} / {}".format(_fmt(m["latencyP50Ms"]), _fmt(m["latencyP95Ms"])),
                "- Invalid answer rate: {}; human review rate: {}; rule-versus-agent divergence rate: {}".format(
                    _fmt(m["invalidRate"], "rate"), _fmt(m["reviewRate"], "rate"), _fmt(m["divergenceRate"], "rate")),
                "- Agent calls: {} of {} messages; failures by kind: {}".format(m["callCount"], m["rowCount"], m["failureCounts"] or "none"),
                "- Investigation with tools: {} tool calls ({} per result), {} rounds a result on average (most {}), {} results with a call that did not succeed ({} refused by a policy), {} stopped at the limit".format(
                    m.get("toolCalls", 0), _fmt(m.get("toolCallsPerResult")), _fmt(m.get("roundsMean")), _fmt(m.get("roundsMax")), m.get("toolFailures", 0), m.get("toolRefusals", 0), m.get("limitReached", 0)),
                "- Floor policy refusals of an answer that would have lowered a critical: {}; answers rejected for evidence no tool returned: {}; invalid answer rate with the evidence rule: {}".format(
                    m.get("floorPolicyRefusals", 0), m.get("evidenceRejected", 0), _fmt(m.get("invalidAnswerRate"), "rate")),
                "- Subject cases never processed: {}".format(len(m["missingSubjects"])), "",
                "| category | cases | agent agrees | final agrees |", "|---|---|---|---|"]
        for category, t in m["agreementByCategory"].items():
            out.append("| {} | {} | {} | {} |".format(category, t["cases"], t["agentAgrees"], t["finalAgrees"]))
        out.append("")
    b = report["firstLiveRun"]
    out += ["## Comparison", "", "| | " + " | ".join(report["models"]) + " | first live run of {} ({} sample messages) |".format(b["model"], b["calls"]),
            "|---|" + "---|" * (len(report["models"]) + 1)]
    for label, key, digits in (("Cost per thousand (USD)", "costPerThousandUsd", "cost"), ("Latency p50 (ms)", "latencyP50Ms", None),
                               ("Latency p95 (ms)", "latencyP95Ms", None), ("Invalid answer rate", "invalidRate", "rate"),
                               ("Human review rate", "reviewRate", "rate"), ("Silenced criticals", "silencedCriticals", None)):
        base = b.get(key, "")
        out.append("| {} | ".format(label) + " | ".join(_fmt(m[key], digits) for m in report["models"].values()) + " | {} |".format(
            _fmt(base, digits) if base != "" else "n/a"))
    if report.get("movement"):
        out += ["", "## Movement against the previous report", "",
                "Prompt version before: {}; now: {}. Every figure is listed, the ones that got worse included.".format(
                    ", ".join(report.get("previousPromptVersions", [])) or "n/a", ", ".join(report["header"].get("promptVersions", [])) or "n/a"), ""]
        for name, figs in report["movement"].items():
            out += ["### {}".format(name), "", "| figure | previous | current | change |", "|---|---|---|---|"]
            for key, f in figs.items():
                out.append("| {} | {} | {} | {} |".format(key, _fmt(f["previous"]), _fmt(f["current"]), _fmt(f["delta"])))
            out.append("")
    out += ["", "## Limits", "",
            "- The expected decision of every case comes from construction rules written in `DATASET.md`, by one author; there was no second annotator.",
            "- The provider is not guaranteed to be deterministic at the settings used. The recorded run is the published one, and replay reproduces it.",
            "- Cost is computed from the recorded token counts and the dated price above; a model with no price shows `unknown`, never zero.", ""]
    with open(path, "w") as handle:
        handle.write("\n".join(out))


def main(argv=None):
    parser = argparse.ArgumentParser(description="Build the evaluation report from exported trace rows.")
    parser.add_argument("--run", action="append", required=True, help="MODEL=FILE with the exported rows of one run; repeat per model")
    parser.add_argument("--dataset", required=True)
    parser.add_argument("--prices", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--seed", type=int, default=2026)
    parser.add_argument("--run-date", default=None, help="date of the recorded run; defaults to the one in an existing report, else today")
    parser.add_argument("--meta", action="append", default=[], help="MODEL=FILE.json with {settings, ceilings} of that model's run; optional")
    parser.add_argument("--previous", default=None, help="the report of the previous round (report.json); the report then carries the movement of each figure against it")
    args = parser.parse_args(argv)
    runs = {}
    for item in args.run:
        name, _, path = item.partition("=")
        runs[name] = load_jsonl(path)
    dataset_rows = load_jsonl(args.dataset)
    run_date = args.run_date
    existing = os.path.join(args.out, "report.json")
    previous = json.load(open(existing)) if os.path.exists(existing) else {}
    if run_date is None:
        run_date = previous.get("header", {}).get("runDate")
    run_date = run_date or datetime.date.today().isoformat()
    # The settings and ceilings of a run are not in the exported rows: they come from the run's own meta file, or from the
    # report already written, so a replay regenerates the same text as the live run.
    meta = {name: {"settings": m.get("runSettings", ""), "ceilings": m.get("budgetCeilings", "")} for name, m in previous.get("models", {}).items()}
    for item in args.meta:
        name, _, path = item.partition("=")
        meta[name] = json.load(open(path))
    versions = sorted({r.get("promptVersion") for rows in runs.values() for r in rows if r.get("promptVersion")})
    header = {"seed": args.seed, "subjectCases": sum(1 for r in dataset_rows if r["role"] == "subject"), "promptVersions": versions,
              "runDate": run_date}
    prices = json.load(open(args.prices))["prices"]
    older = json.load(open(args.previous)) if args.previous else None
    report = build_report(runs, dataset_rows, prices, header, meta, older)
    os.makedirs(args.out, exist_ok=True)
    write_json(report, os.path.join(args.out, "report.json"))
    write_markdown(report, os.path.join(args.out, "report.md"))
    bad = {name: m["silencedCriticals"] for name, m in report["models"].items() if m["silencedCriticals"]}
    if bad:
        print("SILENCED CRITICALS FOUND (a safety defect, not a result): {}".format(bad), file=sys.stderr)
        return 1
    print("report written to {}".format(args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
