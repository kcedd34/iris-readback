"""The evaluation report on a fixed, hand-counted sample: matrices, silenced and missed criticals, cost, latency, exit status."""
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "src", "python"))

from readback.evaluation import report  # noqa: E402

DATASET = [
    {"messageId": "S1", "role": "subject", "expected": "CRITICAL", "category": "clear-critical"},
    {"messageId": "S2", "role": "subject", "expected": "CRITICAL", "category": "explainable-false-critical"},
    {"messageId": "S3", "role": "subject", "expected": "CRITICAL", "category": "contextual-critical"},
    {"messageId": "S4", "role": "subject", "expected": "CRITICAL", "category": "contextual-critical"},
    {"messageId": "S5", "role": "subject", "expected": "RECOLLECT", "category": "recollect"},
    {"messageId": "S6", "role": "subject", "expected": "NEEDS_REVIEW", "category": "ambiguous"},
    {"messageId": "S7", "role": "subject", "expected": "NON_CRITICAL", "category": "normal"},
    {"messageId": "S8", "role": "subject", "expected": "NON_CRITICAL", "category": "normal"},
    {"messageId": "S9", "role": "subject", "expected": "CRITICAL", "category": "clear-critical"},
    {"messageId": "S10", "role": "subject", "expected": "NEEDS_REVIEW", "category": "ambiguous"},
    {"messageId": "S11", "role": "subject", "expected": "CRITICAL", "category": "sample-problem"},
    {"messageId": "S12", "role": "subject", "expected": "CRITICAL", "category": "clear-critical"},
    {"messageId": "H1", "role": "history", "expected": "", "category": "contextual-critical"},
]


def row(mid, floor, decision, severity, route, latency, cost=0.0033, valid=1, kind="", called=1, divergence="", model="m-large"):
    return {"messageControlId": mid, "mode": "live", "model": model, "promptVersion": "triage-v2", "agentCalled": called, "schemaValid": valid,
            "failureKind": kind, "floorSeverity": floor, "agentDecision": decision, "agentSeverity": severity, "finalSeverity": 3 if route == "readback" else 0,
            "route": route, "divergence": divergence, "inputTokens": 700, "outputTokens": 100, "costUsd": cost, "costKnown": 1, "latencyMs": latency}


# S12 has no row: a case that was never processed.
ROWS = [
    row("S1", 3, "CRITICAL", 3, "readback", 2000),
    row("S2", 3, "NON_CRITICAL", 0, "readback", 2200, divergence="agent below the floor"),
    row("S3", 0, "CRITICAL", 3, "readback", 2400),
    row("S4", 0, "NON_CRITICAL", 0, "release", 2600),
    row("S5", 0, "RECOLLECT", 1, "recollect", 2800),
    row("S6", 0, "", "", "review", 3000, cost=0.0, valid=0, kind="schema-invalid"),
    row("S7", 0, "NON_CRITICAL", 0, "release", 3200),
    row("S8", 0, "", "", "review", 800, cost=0.0, valid=0, kind="provider-error"),
    row("S9", 3, "", "", "readback", 30001, cost=0.0, valid=0, kind="timeout"),
    row("S10", 0, "", "", "review", 0, cost=0.0, valid=0, kind="budget", called=0),
    row("S11", 3, "RECOLLECT", 1, "readback", 3400, divergence="agent below the floor"),
    row("H1", 0, "NON_CRITICAL", 0, "release", 3600),
]


def figures(rows=ROWS):
    return report.compute_model(rows, report.expected_map(DATASET))


def test_agent_matrix_equals_the_hand_count():
    m = figures()["matrixAgent"]
    assert m["CRITICAL"] == {"CRITICAL": 2, "RECOLLECT": 1, "NEEDS_REVIEW": 0, "NON_CRITICAL": 2, "none": 2}
    assert m["RECOLLECT"] == {"CRITICAL": 0, "RECOLLECT": 1, "NEEDS_REVIEW": 0, "NON_CRITICAL": 0, "none": 0}
    assert m["NEEDS_REVIEW"]["none"] == 2 and sum(m["NEEDS_REVIEW"].values()) == 2
    assert m["NON_CRITICAL"] == {"CRITICAL": 0, "RECOLLECT": 0, "NEEDS_REVIEW": 0, "NON_CRITICAL": 1, "none": 1}


def test_final_matrix_equals_the_hand_count():
    m = figures()["matrixFinal"]
    assert m["CRITICAL"] == {"CRITICAL": 5, "RECOLLECT": 0, "NEEDS_REVIEW": 0, "NON_CRITICAL": 1, "none": 1}
    assert m["RECOLLECT"]["RECOLLECT"] == 1
    assert m["NEEDS_REVIEW"]["NEEDS_REVIEW"] == 2
    assert m["NON_CRITICAL"] == {"CRITICAL": 0, "RECOLLECT": 0, "NEEDS_REVIEW": 1, "NON_CRITICAL": 1, "none": 0}


def test_every_subject_case_is_in_a_cell_or_in_none():
    f = figures()
    for key in ("matrixAgent", "matrixFinal"):
        assert sum(sum(r.values()) for r in f[key].values()) == f["subjectCount"] == 12
    assert f["missingSubjects"] == ["S12"]


def test_no_silenced_critical_and_the_missed_one_is_listed_apart():
    f = figures()
    assert f["silencedCriticals"] == 0 and f["silencedCriticalIds"] == []
    assert f["missedCriticals"] == ["S4"]


def test_downgrade_attempts_count_rule_critical_results_the_agent_answered_below_critical():
    assert figures()["downgradeAttempts"] == 2  # S2 and S11; S9 had no valid answer and S1 agreed


def test_a_rule_critical_result_that_is_not_on_read_back_is_silenced():
    rows = [dict(r) for r in ROWS]
    rows[0]["route"] = "review"
    f = figures(rows)
    assert f["silencedCriticals"] == 1 and f["silencedCriticalIds"] == ["S1"]
    assert "S1" not in f["missedCriticals"]


def test_latency_percentiles_use_nearest_rank_over_the_calls_to_the_agent():
    f = figures()
    # 11 calls (S10 was skipped): sorted 800, 2000, 2200, 2400, 2600, 2800, 3000, 3200, 3400, 3600, 30001
    assert f["callCount"] == 11
    assert f["latencyP50Ms"] == 2800 and f["latencyP95Ms"] == 30001
    assert report.nearest_rank([1, 2, 3, 4], 50) == 2 and report.nearest_rank([5], 95) == 5 and report.nearest_rank([], 50) is None


def test_cost_per_thousand_is_the_mean_of_the_known_rows_times_a_thousand():
    f = figures()
    assert f["unknownCostRows"] == 0
    assert abs(f["costPerThousandUsd"] - 2.2) < 1e-9  # 8 rows of 0.0033 and 4 of 0, over 12 rows: 0.0264 / 12 * 1000


def test_a_model_without_a_price_has_unknown_cost_never_zero():
    rows = []
    for r in ROWS:
        r = dict(r)
        r["costKnown"], r["costUsd"] = 0, 0
        rows.append(r)
    f = figures(rows)
    assert f["costPerThousandUsd"] is None and f["unknownCostRows"] == 12
    built = report.build_report({"m-large": rows}, DATASET, [], {"seed": 1, "subjectCases": 12, "promptVersions": [], "runDate": "d"})
    assert built["models"]["m-large"]["price"] is None


def test_rates_and_failure_counts():
    f = figures()
    assert f["rowCount"] == 12
    assert abs(f["invalidRate"] - 1 / 12) < 1e-5 and abs(f["reviewRate"] - 3 / 12) < 1e-5 and abs(f["divergenceRate"] - 2 / 12) < 1e-5
    assert f["failureCounts"] == {"budget": 1, "provider-error": 1, "schema-invalid": 1, "timeout": 1}


def test_agreement_by_category():
    a = figures()["agreementByCategory"]
    assert a["clear-critical"] == {"cases": 3, "agentAgrees": 1, "finalAgrees": 2}
    assert a["contextual-critical"] == {"cases": 2, "agentAgrees": 1, "finalAgrees": 1}


def test_the_markdown_names_the_matrices_and_the_limits(tmp_path):
    built = report.build_report({"m-large": ROWS}, DATASET, [{"model": "m-large", "inputPerMillion": 2.5, "outputPerMillion": 15.0, "priceDate": "2026-10-28"}],
                                {"seed": 2026, "subjectCases": 12, "promptVersions": ["triage-v2"], "runDate": "2026-10-28"},
                                {"m-large": {"settings": "temperature 0", "ceilings": "per result 6000 tokens"}})
    path = tmp_path / "report.md"
    report.write_markdown(built, str(path))
    text = path.read_text()
    assert "Agent decision against the expected decision" in text and "Final decision (route)" in text
    assert "| expected \\ decided | CRITICAL | RECOLLECT | NEEDS_REVIEW | NON_CRITICAL | none |" in text
    assert "Run settings: temperature 0. Budget ceilings of the run: per result 6000 tokens." in text
    assert "Silenced criticals: **0**" in text and "one author" in text and "2.5 / 15.0 USD" in text and "2026-10-28" in text


def test_the_exit_status_is_non_zero_when_a_critical_is_silenced(tmp_path):
    def write(name, rows):
        path = tmp_path / name
        path.write_text("".join(json.dumps(r) + "\n" for r in rows))
        return str(path)
    dataset = write("dataset.jsonl", DATASET)
    prices = tmp_path / "prices.json"
    prices.write_text(json.dumps({"prices": [{"model": "m-large", "inputPerMillion": 2.5, "outputPerMillion": 15.0, "priceDate": "2026-10-28"}]}))
    out = tmp_path / "out"
    assert report.main(["--run", "m-large=" + write("ok.jsonl", ROWS), "--dataset", dataset, "--prices", str(prices), "--out", str(out), "--run-date", "2026-10-28"]) == 0
    silenced = [dict(r) for r in ROWS]
    silenced[0]["route"] = "review"
    assert report.main(["--run", "m-large=" + write("bad.jsonl", silenced), "--dataset", dataset, "--prices", str(prices), "--out", str(out), "--run-date", "2026-10-28"]) == 1


def test_the_same_input_gives_a_byte_identical_report(tmp_path):
    args = ["--run", "m-large=" + str(tmp_path / "rows.jsonl"), "--dataset", str(tmp_path / "dataset.jsonl"), "--prices", str(tmp_path / "prices.json"), "--run-date", "2026-10-28"]
    (tmp_path / "rows.jsonl").write_text("".join(json.dumps(r) + "\n" for r in ROWS))
    (tmp_path / "dataset.jsonl").write_text("".join(json.dumps(r) + "\n" for r in DATASET))
    (tmp_path / "prices.json").write_text(json.dumps({"prices": []}))
    report.main(args + ["--out", str(tmp_path / "a")])
    report.main(args + ["--out", str(tmp_path / "b")])
    assert (tmp_path / "a" / "report.json").read_bytes() == (tmp_path / "b" / "report.json").read_bytes()
    assert (tmp_path / "a" / "report.md").read_bytes() == (tmp_path / "b" / "report.md").read_bytes()


def test_a_regeneration_keeps_the_settings_and_date_of_the_report_already_written(tmp_path):
    (tmp_path / "rows.jsonl").write_text("".join(json.dumps(r) + "\n" for r in ROWS))
    (tmp_path / "dataset.jsonl").write_text("".join(json.dumps(r) + "\n" for r in DATASET))
    (tmp_path / "prices.json").write_text(json.dumps({"prices": []}))
    (tmp_path / "meta.json").write_text(json.dumps({"settings": "cap 400", "ceilings": "high"}))
    args = ["--run", "m-large=" + str(tmp_path / "rows.jsonl"), "--dataset", str(tmp_path / "dataset.jsonl"), "--prices", str(tmp_path / "prices.json"), "--out", str(tmp_path / "out")]
    report.main(args + ["--run-date", "2026-10-28", "--meta", "m-large=" + str(tmp_path / "meta.json")])
    first = (tmp_path / "out" / "report.json").read_bytes()
    report.main(args)  # no date and no meta: both come from the report already there
    assert (tmp_path / "out" / "report.json").read_bytes() == first


def test_the_tool_figures_and_the_movement_against_the_previous_report():
    expected = {"A": ("CRITICAL", "clear-critical"), "B": ("CRITICAL", "clear-critical"), "C": ("NON_CRITICAL", "normal")}
    rows = [
        {"messageControlId": "A", "agentCalled": 1, "schemaValid": 1, "route": "readback", "floorSeverity": 3, "agentDecision": "CRITICAL", "agentSeverity": 3,
         "rounds": 2, "toolCallCount": 3, "toolFailureCount": 0, "evidenceCheck": "ok", "policyRefusal": "", "toolCalls": [{"status": "ok"}] * 3, "costKnown": 1, "costUsd": 0.01, "latencyMs": 1000},
        {"messageControlId": "B", "agentCalled": 1, "schemaValid": 1, "route": "readback", "floorSeverity": 3, "agentDecision": "NON_CRITICAL", "agentSeverity": 0,
         "rounds": 2, "toolCallCount": 2, "toolFailureCount": 1, "evidenceCheck": "ok", "policyRefusal": "refused: lowered", "failureKind": "floor-policy-refusal",
         "toolCalls": [{"status": "ok"}, {"status": "refused"}], "costKnown": 1, "costUsd": 0.02, "latencyMs": 2000},
        {"messageControlId": "C", "agentCalled": 1, "schemaValid": 0, "route": "review", "floorSeverity": 0, "failureKind": "evidence-not-from-tools",
         "rounds": 1, "toolCallCount": 0, "toolFailureCount": 0, "evidenceCheck": "not-from-tools", "policyRefusal": "", "costKnown": 1, "costUsd": 0.01, "latencyMs": 500},
    ]
    m = report.compute_model(rows, expected)
    assert m["toolCalls"] == 5 and m["roundsMax"] == 2 and abs(m["roundsMean"] - 5 / 3) < 1e-3 and abs(m["toolCallsPerResult"] - 5 / 3) < 1e-3
    assert m["toolFailures"] == 1 and m["toolRefusals"] == 1 and m["floorPolicyRefusals"] == 1 and m["evidenceRejected"] == 1
    assert abs(m["invalidAnswerRate"] - 1 / 3) < 1e-5, "an answer rejected for evidence counts as invalid"
    before = {"models": {"m": dict(m, missedCriticals=["A", "B"], reviewRate=0.5, costPerThousandUsd=1.0, latencyP50Ms=900)}}
    after = {"models": {"m": dict(m, missedCriticals=[], reviewRate=0.25, costPerThousandUsd=3.0, latencyP50Ms=1500)}}
    mv = report.movement(after, before)["m"]
    assert mv["missedCriticals"] == {"previous": 2, "current": 0, "delta": -2}
    assert mv["costPerThousandUsd"]["delta"] == 2.0 and mv["latencyP50Ms"]["delta"] == 600, "a figure that got worse is listed like any other"
    assert report.movement(after, None)["m"]["reviewRate"]["previous"] is None, "no previous report means no previous value"
