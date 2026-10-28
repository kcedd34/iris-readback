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
    assert set(rows[0]) == set(record.FIELDS)
    assert rows[0]["source"] == "recorded" and rows[0]["answer"] == '{"decision":"CRITICAL"}' and rows[0]["latencyMs"] == 2231
    assert rows[0]["replaySet"] == "default" and rows[0]["model"] == "m-large" and rows[0]["inputTokens"] == 708


def test_a_call_with_no_output_is_not_recorded_but_an_invalid_answer_is():
    rows = record.from_rows([live("OK"), live("EMPTY", raw=""), live("SKIPPED", called=0, raw=""), live("INVALID", raw="not json", valid=0)], "default")
    assert [r["messageControlId"] for r in rows] == ["OK", "INVALID"]


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
