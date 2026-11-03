"""The ablation: the arrangement 'full' reproduces the report, the file on disk is what the code makes, and the layers do what they are for."""
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "src", "python"))

from readback.evaluation import ablation  # noqa: E402

FILE = json.load(open(os.path.join(ROOT, "data", "eval", "ablation.json")))


def test_the_file_is_what_the_code_makes():
    assert ablation.build(FILE["measuredOn"]) == FILE


def test_the_full_arrangement_reproduces_the_report():
    result, routes, subjects, _, _ = ablation.run()
    assert ablation.check_against_report(routes, subjects) == []


def test_no_arrangement_silences_a_rule_critical_result():
    for model in FILE["models"].values():
        assert all(a["silencedCriticals"] == 0 for a in model.values())


def test_the_range_rule_alone_releases_every_contextual_critical():
    for model in FILE["models"].values():
        assert model["value"]["contextualCriticals"]["released"] == FILE["contextualCriticalCases"]


def test_the_full_product_releases_no_critical():
    for model in FILE["models"].values():
        assert model["full"]["releasedAnyCritical"] == 0


def test_the_composition_never_lets_the_agent_lower_a_floor():
    for decision, severity in (("NON_CRITICAL", 0), ("RECOLLECT", 0), ("NEEDS_REVIEW", 1), ("CRITICAL", 3)):
        assert ablation.compose(3, decision, severity, "", False) == "readback"
