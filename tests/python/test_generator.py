"""Tests for the synthetic dataset generator: determinism, coverage, validation, identifier safety."""
import filecmp
import json
import os
import subprocess
import sys

import pytest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SRC = os.path.join(ROOT, "src", "python")
sys.path.insert(0, SRC)

from readback.dataset import categories as cat  # noqa: E402
from readback.dataset import generator  # noqa: E402

SIX = set(cat.CATEGORIES)


def run_cli(*args):
    env = dict(os.environ, PYTHONPATH=SRC)
    return subprocess.run([sys.executable, "-m", "readback.dataset.generator", *args], capture_output=True, text=True, env=env)


def files_in(directory):
    return sorted(os.listdir(directory))


def test_same_seed_is_byte_identical(tmp_path):
    a, b = tmp_path / "a", tmp_path / "b"
    generator.write_dataset(7, 40, str(a))
    generator.write_dataset(7, 40, str(b))
    assert files_in(a) == files_in(b)
    for name in files_in(a):
        assert filecmp.cmp(a / name, b / name, shallow=False), name


def test_different_seed_differs(tmp_path):
    a, b = tmp_path / "a", tmp_path / "b"
    generator.write_dataset(1, 40, str(a))
    generator.write_dataset(2, 40, str(b))
    assert (a / "labels.jsonl").read_bytes() != (b / "labels.jsonl").read_bytes()
    assert (a / "RB1-00001.hl7").read_bytes() != (b / "RB2-00001.hl7").read_bytes()


def test_all_six_categories_in_200_cases(tmp_path):
    generator.write_dataset(3, 200, str(tmp_path))
    labels = [json.loads(line) for line in (tmp_path / "labels.jsonl").read_text().splitlines()]
    subjects = [row for row in labels if row["role"] == "subject"]
    assert len(subjects) == 200
    assert {row["category"] for row in subjects} == SIX
    for row in labels:
        assert set(row) == {"messageId", "category", "seed", "file", "role", "patientId", "analyte"}
        assert (tmp_path / row["file"]).exists()


def test_messages_are_valid_oru_r01(tmp_path):
    generator.write_dataset(5, 30, str(tmp_path))
    for name in files_in(tmp_path):
        if not name.endswith(".hl7"):
            continue
        segments = (tmp_path / name).read_bytes().decode().split("\r")
        assert segments[0].startswith("MSH|^~\\&|")
        assert segments[0].split("|")[8] == "ORU^R01"
        assert any(s.startswith("PID|") for s in segments)
        assert any(s.startswith("OBX|1|") for s in segments)


@pytest.mark.parametrize("count", ["0", "-5", "10001"])
def test_invalid_count_exits_nonzero_and_writes_nothing(tmp_path, count):
    out = tmp_path / "out"
    result = run_cli("--seed", "1", "--count", count, "--out", str(out))
    assert result.returncode != 0
    assert "--count must be between 1 and 10000" in result.stderr
    assert not out.exists()


def test_cli_writes_output(tmp_path):
    result = run_cli("--seed", "1", "--count", "6", "--out", str(tmp_path / "o"))
    assert result.returncode == 0, result.stderr
    assert (tmp_path / "o" / "labels.jsonl").exists()


def test_no_real_identifier_patterns(tmp_path):
    generator.write_dataset(11, 200, str(tmp_path))
    for name in files_in(tmp_path):
        text = (tmp_path / name).read_bytes().decode()
        assert not generator.contains_real_identifier(text), name
    for name in files_in(tmp_path):
        if name.endswith(".hl7"):
            pid = [s for s in (tmp_path / name).read_bytes().decode().split("\r") if s.startswith("PID|")][0]
            assert pid.split("|")[3].startswith("SYN")


@pytest.mark.parametrize("sample", ["123.456.789-09", "12345678909", "123-45-6789", "someone@example.com", "(11) 91234-5678", "1234567890"])
def test_identifier_check_detects_real_formats(sample):
    assert generator.contains_real_identifier("PID|1||" + sample)


def test_category_semantics(tmp_path):
    items = generator.generate(9, 120)
    by_cat = {}
    for _, text, label in items:
        if label["role"] == "subject":
            by_cat.setdefault(label["category"], []).append(text)
    assert all(by_cat[c] for c in SIX)
    for text in by_cat[cat.SAMPLE_PROBLEM]:
        index = int(next(s for s in text.split("\r") if "HEMOLYSIS_INDEX" in s).split("|")[5])
        assert index > cat.HEMOLYSIS_LIMIT
    for text in by_cat[cat.ACUTE_DROP_IN_RANGE]:
        assert "718-7" in text
