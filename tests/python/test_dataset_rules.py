"""The evaluation dataset: determinism, size, and the construction rule of every category, checked against the values."""
import json
import os
import re
import sys

import pytest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "src", "python")
sys.path.insert(0, SRC)

from readback.dataset import categories as cat  # noqa: E402
from readback.dataset import generator  # noqa: E402
from readback.evaluation import dataset  # noqa: E402

EXPECTED_BY_CATEGORY = {
    "clear-critical": "CRITICAL", "contextual-critical": "CRITICAL", "explainable-false-critical": "CRITICAL",
    "acute-drop-in-range": "CRITICAL", "sample-problem": "CRITICAL", "recollect": "RECOLLECT",
    "ambiguous": "NEEDS_REVIEW", "normal": "NON_CRITICAL",
}


@pytest.fixture(scope="module")
def rows():
    return dataset.build()


def value_of(text):
    """The first OBX numeric value and the hemolysis index (or None) of a message."""
    value, hemolysis = None, None
    for segment in text.split("\r"):
        fields = segment.split("|")
        if fields[0] == "OBX" and "HEMOLYSIS_INDEX" in fields[3]:
            hemolysis = float(fields[5])
        elif fields[0] == "OBX" and value is None:
            value = float(fields[5])
    return value, hemolysis


def subjects(rows):
    return [r for r in rows if r["role"] == "subject"]


def history_of(rows, subject):
    prefix = subject["messageId"] + "H"
    return [value_of(r["text"])[0] for r in rows if r["messageId"].startswith(prefix)]


def analyte_of(row):
    code = re.search(r"OBX\|1\|NM\|([^^]+)\^", row["text"]).group(1)
    return next(a for a, spec in cat.ANALYTES.items() if spec["code"] == code)


def critical_by_rule(analyte, value):
    spec = cat.ANALYTES[analyte]
    return value <= spec["crit_low"] or value >= spec["crit_high"]


def test_deterministic_for_a_seed():
    assert dataset.build() == dataset.build()
    assert dataset.build(seed=7, per_category=2) != dataset.build(seed=8, per_category=2)


def test_240_subject_rows_and_30_per_category(rows):
    subject_rows = subjects(rows)
    assert len(subject_rows) == 240
    for category in cat.EVALUATION_CATEGORIES:
        assert sum(r["category"] == category for r in subject_rows) == 30, category


def test_expected_decision_per_category(rows):
    for r in subjects(rows):
        assert r["expected"] == EXPECTED_BY_CATEGORY[r["category"]], r["messageId"]


def test_history_rows_have_no_expected_and_come_first(rows):
    seen = set()
    for r in rows:
        if r["role"] == "history":
            assert r["expected"] == ""
            assert r["messageId"].split("H")[0] not in seen, "history after its subject"
        else:
            seen.add(r["messageId"])


def test_critical_categories_are_critical_by_rule_except_the_contextual_ones(rows):
    for r in subjects(rows):
        value, _ = value_of(r["text"])
        rule = critical_by_rule(analyte_of(r), value)
        if r["category"] in ("clear-critical", "explainable-false-critical", "sample-problem"):
            assert rule, "{} {} should be critical by rule".format(r["messageId"], value)
        else:
            assert not rule, "{} {} should not be critical by rule".format(r["messageId"], value)


def test_contextual_and_acute_cases_have_the_earlier_result_that_explains_them(rows):
    for r in subjects(rows):
        value, _ = value_of(r["text"])
        earlier = history_of(rows, r)
        if r["category"] == "acute-drop-in-range":
            assert earlier and earlier[0] - value > 3.0, r["messageId"]
        if r["category"] == "contextual-critical":
            assert len(earlier) == 1, r["messageId"]
        if r["category"] in ("recollect", "normal", "clear-critical", "sample-problem"):
            assert not earlier, r["messageId"]


def test_sample_flags(rows):
    for r in subjects(rows):
        _, hemolysis = value_of(r["text"])
        if r["category"] == "sample-problem":
            assert hemolysis is not None and hemolysis > 100
        elif r["category"] == "recollect":
            assert hemolysis is not None and hemolysis > 150
        elif r["category"] == "ambiguous":
            assert hemolysis is not None and 70 <= hemolysis <= 99
        elif r["category"] in ("normal", "clear-critical"):
            assert hemolysis is None


def test_ambiguous_and_recollect_potassium_stay_below_the_limit(rows):
    for r in subjects(rows):
        value, _ = value_of(r["text"])
        if r["category"] == "ambiguous":
            assert 6.2 <= value < 6.5
        if r["category"] == "recollect":
            assert 5.5 <= value <= 6.3


def test_normal_values_are_inside_the_normal_range(rows):
    for r in subjects(rows):
        if r["category"] == "normal":
            spec = cat.ANALYTES[analyte_of(r)]
            value, _ = value_of(r["text"])
            assert spec["low"] <= value <= spec["high"], r["messageId"]


def test_no_real_identifier_pattern(rows):
    for r in rows:
        assert not generator.contains_real_identifier(r["text"]), r["messageId"]
        assert r["patientId"].startswith("SYN")


def test_the_sample_set_still_regenerates_byte_for_byte(tmp_path):
    out = tmp_path / "gen"
    generator.write_dataset(42, 12, str(out))
    committed = os.path.join(ROOT, "data", "samples", "generated")
    for name in sorted(os.listdir(str(out))):
        if os.path.exists(os.path.join(committed, name)):
            assert open(os.path.join(str(out), name), "rb").read() == open(os.path.join(committed, name), "rb").read(), name


def test_the_committed_dataset_file_is_the_one_the_seed_gives():
    path = os.path.join(ROOT, "data", "eval", "dataset.jsonl")
    committed = [json.loads(line) for line in open(path)]
    assert committed == dataset.build()
    assert open(os.path.join(ROOT, "data", "eval", "DATASET.md")).read() == dataset.description()
