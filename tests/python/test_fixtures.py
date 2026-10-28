"""Tests for the replay fixtures: deterministic, one per message, valid against the schema, shaped by category."""
import json
import os
import sys

import pytest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "src", "python")
sys.path.insert(0, SRC)

from readback.dataset import categories as cat  # noqa: E402
from readback.dataset import fixtures  # noqa: E402
from readback.dataset import generator  # noqa: E402

DECISIONS = {"CRITICAL", "RECOLLECT", "NEEDS_REVIEW", "NON_CRITICAL"}
CONFIDENCES = {"low", "medium", "high"}


@pytest.fixture(scope="module")
def dataset(tmp_path_factory):
    out = tmp_path_factory.mktemp("data")
    generator.write_dataset(21, 60, str(out))
    return str(out)


def labels_of(directory):
    with open(os.path.join(directory, "labels.jsonl")) as handle:
        return [json.loads(line) for line in handle if line.strip()]


def test_deterministic(dataset, tmp_path):
    a = fixtures.build(os.path.join(dataset, "labels.jsonl"))
    b = fixtures.build(os.path.join(dataset, "labels.jsonl"))
    assert a == b
    fixtures.write(a, str(tmp_path / "a.jsonl"))
    fixtures.write(b, str(tmp_path / "b.jsonl"))
    assert (tmp_path / "a.jsonl").read_bytes() == (tmp_path / "b.jsonl").read_bytes()


def test_one_recording_per_message_including_history(dataset):
    rows = fixtures.build(os.path.join(dataset, "labels.jsonl"))
    labels = labels_of(dataset)
    assert [r["messageControlId"] for r in rows] == [l["messageId"] for l in labels]
    assert any(l["role"] == "history" for l in labels)


def test_every_answer_is_valid_against_the_schema(dataset):
    for item in fixtures.build(os.path.join(dataset, "labels.jsonl")) + fixtures.hand_samples():
        body = json.loads(item["answer"])
        assert set(body) == {"decision", "severity", "rationale", "evidence", "confidence"}
        assert body["decision"] in DECISIONS
        assert body["severity"] in (0, 1, 2, 3)
        assert len(body["rationale"]) <= 400
        assert isinstance(body["evidence"], list) and all(isinstance(e, str) for e in body["evidence"])
        assert body["confidence"] in CONFIDENCES


def test_answers_follow_the_category(dataset):
    rows = {r["messageControlId"]: json.loads(r["answer"]) for r in fixtures.build(os.path.join(dataset, "labels.jsonl"))}
    seen = set()
    for label in labels_of(dataset):
        body = rows[label["messageId"]]
        if label["role"] == "history":
            assert (body["decision"], body["severity"]) == ("NON_CRITICAL", 0)
            continue
        category = label["category"]
        seen.add(category)
        if category in (cat.CLEAR_CRITICAL, cat.CONTEXTUAL_CRITICAL):
            assert (body["decision"], body["severity"]) == ("CRITICAL", 3)
        elif category == cat.EXPLAINABLE_FALSE_CRITICAL:
            assert (body["decision"], body["severity"]) == ("NON_CRITICAL", 0)
        elif category == cat.ACUTE_DROP_IN_RANGE:
            assert (body["decision"], body["severity"]) == ("CRITICAL", 3)
            assert "earlier-result-1" in body["evidence"]
        elif category == cat.SAMPLE_PROBLEM:
            assert body["decision"] == "RECOLLECT" and "sample-index-hemolysis" in body["evidence"]
        elif category == cat.AMBIGUOUS:
            assert body["decision"] == "NEEDS_REVIEW" and body["confidence"] == "low"
    assert seen == set(cat.CATEGORIES)


def test_every_row_is_labeled_as_a_fixture(dataset):
    for item in fixtures.build(os.path.join(dataset, "labels.jsonl")) + fixtures.hand_samples():
        assert item["source"] == "fixture"
        assert item["replaySet"] == "default"
        assert item["promptVersion"] == "triage-v2"


def test_hand_samples_cover_both_sample_messages():
    ids = [r["messageControlId"] for r in fixtures.hand_samples()]
    assert ids == ["RBSAMPLE0001", "RBSAMPLE0002"]


def test_cli_writes_the_file(dataset, tmp_path):
    out = tmp_path / "recordings.jsonl"
    assert fixtures.main(["--labels", os.path.join(dataset, "labels.jsonl"), "--out", str(out), "--with-samples"]) == 0
    lines = out.read_text().splitlines()
    assert len(lines) == len(labels_of(dataset)) + 2


def passage_ids():
    with open(os.path.join(ROOT, "data", "policy", "passages.jsonl")) as handle:
        return {json.loads(line)["id"] for line in handle if line.strip()}


def test_every_cited_policy_passage_exists(dataset):
    known = passage_ids()
    cited = set()
    for item in fixtures.build(os.path.join(dataset, "labels.jsonl")) + fixtures.hand_samples():
        for evidence in json.loads(item["answer"])["evidence"]:
            if evidence.startswith(("crit-", "recollect-", "ctx-", "unit-", "review-")):
                cited.add(evidence)
    assert cited, "the fixtures cite no policy passage"
    assert cited <= known, "unknown passages cited: %s" % sorted(cited - known)


def test_categories_cite_their_passage(dataset):
    rows = {r["messageControlId"]: json.loads(r["answer"]) for r in fixtures.build(os.path.join(dataset, "labels.jsonl"))}
    expected = {cat.EXPLAINABLE_FALSE_CRITICAL: "ctx-dialysis-stable", cat.ACUTE_DROP_IN_RANGE: "ctx-acute-drop",
                cat.SAMPLE_PROBLEM: "recollect-hemolysis", cat.AMBIGUOUS: "review-ambiguous"}
    for label in labels_of(dataset):
        if label["role"] == "history":
            continue
        body = rows[label["messageId"]]
        if label["category"] in expected:
            assert expected[label["category"]] in body["evidence"]
        else:
            assert any(e.startswith("crit-") for e in body["evidence"])
