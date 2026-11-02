"""Recordings made from the export of a live run: only the listed fields, no credential, no failed call, other sets untouched."""
import json
import os
import sys

import pytest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "src", "python"))

from readback.evaluation import record  # noqa: E402


def live(mid, raw='{"decision":"CRITICAL"}', called=1, valid=1, **extra):
    row = {"messageControlId": mid, "mode": "live", "model": "m-large", "promptVersion": "triage-v2", "agentCalled": called,
           "schemaValid": valid, "rawOutput": raw, "inputTokens": 708, "outputTokens": 100, "latencyMs": 2231}
    row.update(extra)
    return row


def test_a_recording_has_exactly_the_listed_fields():
    rows = record.from_rows([live("A")], "default")
    assert set(rows[0]) == set(record.FIELDS) - {"failureKind", "failureReason", "toolCalls"}, "a result with no tool call carries no calls"
    assert rows[0]["source"] == "recorded" and rows[0]["answer"] == '{"decision":"CRITICAL"}' and rows[0]["latencyMs"] == 2231
    assert rows[0]["replaySet"] == "default" and rows[0]["model"] == "m-large" and rows[0]["inputTokens"] == 708


def test_an_invalid_answer_is_recorded_as_it_came_and_a_call_the_budget_skipped_is_not():
    rows = record.from_rows([live("OK"), live("SKIPPED", called=0, raw=""), live("INVALID", raw="not json", valid=0)], "default")
    assert [r["messageControlId"] for r in rows] == ["OK", "INVALID"]
    assert all("failureKind" not in r for r in rows)


def test_failed_calls_are_recorded_as_failures_with_the_fixed_reason():
    rows = record.from_rows([
        live("ERR", raw="", failureKind="provider-error", failureReason="ERROR #5001: ERROR #5001: provider said no", inputTokens=0, outputTokens=0),
        live("SLOW", raw="", failureKind="timeout", failureReason="no answer within 30 seconds", latencyMs=30010),
        live("EMPTY", raw="", failureKind="empty-or-refused", failureReason="empty answer")], "default")
    by_id = {r["messageControlId"]: r for r in rows}
    assert by_id["ERR"]["failureKind"] == "provider-error" and by_id["ERR"]["answer"] == ""
    assert by_id["ERR"]["failureReason"] == "ERROR #5001: provider said no", "one prefix the product adds is removed"
    assert by_id["SLOW"]["failureKind"] == "timeout" and by_id["SLOW"]["latencyMs"] == 30010
    assert by_id["EMPTY"]["failureKind"] == "empty-output"


def test_a_credential_in_a_failure_reason_is_refused():
    with pytest.raises(ValueError):
        record.from_rows([live("E", raw="", failureKind="provider-error", failureReason="ERROR #5001: sk-proj-abcdefghijklmnop")], "default")


@pytest.mark.parametrize("value", ["sk-proj-abcdefghijklmnop", "Bearer abcdefghijklmnop0123", "api_key: abcdefghijklmnop"])
def test_a_credential_shaped_value_is_refused(value):
    with pytest.raises(ValueError):
        record.from_rows([live("A", raw="echo " + value)], "default")


def test_a_replayed_row_cannot_be_recorded():
    with pytest.raises(ValueError):
        record.from_rows([live("A", mode="replay")], "default")


def test_merging_keeps_the_rows_of_another_set_and_replaces_the_set_written(tmp_path):
    out = tmp_path / "recordings.jsonl"
    other = {"replaySet": "gpt-5.4-mini", "messageControlId": "M1", "promptVersion": "triage-v2", "model": "m-small", "answer": "{}",
             "inputTokens": 1, "outputTokens": 1, "latencyMs": 5, "source": "recorded"}
    old_default = dict(other, replaySet="default", messageControlId="OLD", model="fixture", source="fixture")
    record.write(str(out), [other, old_default])
    export = tmp_path / "rows.jsonl"
    export.write_text("".join(json.dumps(r) + "\n" for r in [live("B"), live("A")]))
    recorded, skipped = record.from_export(str(export), "default", str(out))
    assert (recorded, skipped) == (2, 0)
    rows = [json.loads(l) for l in out.read_text().splitlines()]
    assert [(r["replaySet"], r["messageControlId"]) for r in rows] == [("default", "A"), ("default", "B"), ("gpt-5.4-mini", "M1")]
    assert not any(r["source"] == "fixture" for r in rows), "the provisional rows of the replaced set are gone"
    assert rows[2] == other, "the other set is untouched"


def test_writing_twice_gives_the_same_bytes(tmp_path):
    export = tmp_path / "rows.jsonl"
    export.write_text("".join(json.dumps(r) + "\n" for r in [live("B"), live("A")]))
    a, b = tmp_path / "a.jsonl", tmp_path / "b.jsonl"
    record.from_export(str(export), "default", str(a))
    record.from_export(str(export), "default", str(b))
    assert a.read_bytes() == b.read_bytes()


def test_the_command_line_returns_non_zero_for_a_credential(tmp_path, capsys):
    export = tmp_path / "rows.jsonl"
    export.write_text(json.dumps(live("A", raw="sk-proj-abcdefghijklmnop")) + "\n")
    assert record.main(["--export", str(export), "--set", "default", "--out", str(tmp_path / "out.jsonl")]) == 1
    assert not (tmp_path / "out.jsonl").exists(), "nothing is written when a credential is found"
    assert "not recorded" in capsys.readouterr().err


CALLS = [{"seq": 1, "tool": "get_patient_history", "arguments": "{}", "result": '{"found":1,"earlier":[{"id":"earlier-result-1"}]}', "status": "ok", "reason": "", "durationMs": 4},
         {"seq": 2, "tool": "get_delta_assessment", "arguments": "{}", "result": '{"id":"delta-assessment"}', "status": "ok", "reason": "", "durationMs": 2}]


def test_the_tool_calls_and_the_rounds_are_recorded_in_order():
    rows = record.from_rows([live("T", toolCalls=CALLS, rounds=2, inputTokens=1500, outputTokens=170)], "default")
    assert [c["tool"] for c in rows[0]["toolCalls"]] == ["get_patient_history", "get_delta_assessment"]
    assert rows[0]["rounds"] == 2 and rows[0]["inputTokens"] == 1500 and rows[0]["outputTokens"] == 170, "the tokens are the case totals"
    assert rows[0]["toolCalls"][0]["durationMs"] == 4 and rows[0]["toolCalls"][1]["status"] == "ok"
    assert "failureKind" not in rows[0]


def test_an_investigation_that_failed_is_recorded_with_its_answer_and_its_failure():
    bad = [{"seq": 1, "tool": "search_policy", "arguments": "{}", "result": "", "status": "refused", "reason": "denied", "durationMs": 0}]
    rows = record.from_rows([live("F", toolCalls=bad, rounds=2, failureKind="tool-failure", failureReason="tool search_policy refused: denied"),
                             live("L", raw="", rounds=3, failureKind="tool-limit", failureReason="the investigation reached its limit of rounds")], "default")
    by_id = {r["messageControlId"]: r for r in rows}
    assert by_id["F"]["failureKind"] == "tool-failure" and by_id["F"]["answer"] == '{"decision":"CRITICAL"}', "the answer is kept"
    assert by_id["F"]["toolCalls"][0]["status"] == "refused"
    assert by_id["L"]["failureKind"] == "tool-limit" and by_id["L"]["rounds"] == 3


def test_a_credential_inside_a_tool_call_is_refused():
    leak = [dict(CALLS[0], result='{"echo":"sk-proj-abcdefghijklmnopqrstuv"}')]
    with pytest.raises(ValueError):
        record.from_rows([live("K", toolCalls=leak, rounds=2)], "default")
