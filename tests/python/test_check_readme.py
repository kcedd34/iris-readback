"""The README gate: it passes on the finished README and fails when anything it protects is taken away or changed."""
import json
import os
import subprocess
import sys

import pytest

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "src", "ops"))
import check_readme as gate  # noqa: E402

README = open(os.path.join(ROOT, "README.md"), encoding="utf-8").read()
REPORT = gate.load_report(os.path.join(ROOT, "data", "eval", "report.json"))


def failing(text):
    return gate.check(text, REPORT)


def test_the_finished_readme_passes():
    assert failing(README) == []


@pytest.mark.parametrize("heading", list(gate.REQUIRED_ITEMS))
def test_a_missing_required_item_fails(heading):
    out = failing(README.replace(f"### {heading}", "### Something else"))
    assert any("required-item" in line and heading in line for line in out)


@pytest.mark.parametrize("token", ["docker load", "docker tag", "OPENAI_API_KEY", "verify.sh", gate.IMAGE])
def test_a_required_item_without_its_command_fails(token):
    out = failing(README.replace(token, "xxxx"))
    assert any("required-item" in line for line in out)


@pytest.mark.parametrize("section", gate.SECTIONS)
def test_a_missing_section_fails(section):
    out = failing(README.replace(f"## {section}\n", "## Renamed\n", 1))
    assert any(("section" in line and section in line) for line in out)


def test_a_thesis_that_does_not_come_first_fails():
    lines = README.splitlines()
    i = next(n for n, l in enumerate(lines) if l.strip() and not l.startswith("#"))
    lines[i] = "A nice project."
    assert any("thesis" in line for line in failing("\n".join(lines)))


def test_a_changed_figure_fails():
    block = gate.figure_blocks(REPORT)[0][1]
    changed = block.replace("148", "149", 1)
    assert any("figures" in line for line in failing(README.replace(block, changed)))


def test_a_report_that_disagrees_with_the_claims_fails():
    report = json.loads(json.dumps(REPORT))
    report["models"]["gpt-5.4"]["silencedCriticals"] = 1
    assert any("claim" in line for line in gate.check(README, report))


def test_the_reduction_sentences_are_required():
    assert any("from 19 to 2" in line for line in failing(README.replace("from 19 to 2", "from 19 to 3")))
    assert any("from 7 to 2" in line for line in failing(README.replace("from 7 to 2", "from 7 to 3")))


def test_a_closing_list_with_four_items_fails():
    out = failing(README + "- one more thing: [PENDING: publication]\n")
    assert any("pending" in line for line in out)


def test_a_pending_marker_outside_the_allowed_places_fails():
    out = failing(README.replace("## Demo\n", "## Demo\n\nSoon: [PENDING: publication]\n", 1))
    assert any("pending" in line and "outside" in line for line in out)


def test_unmarked_missing_links_fail():
    out = failing(README.replace("[PENDING: publication]", ""))
    assert any("pending" in line for line in out)


@pytest.mark.parametrize("extra", [
    "OPENAI_API_KEY=" + "sk-" + "a" * 30,
    "key: sk-" + "b" * 40,
    "user _" + "SYSTEM",
    "the " + "six axes of the contest",
    "every error goes to a human person",
    "Isto n\u00e3o \u00e9 ingl\u00eas",
    "a a\u00e7\u00e3o",
])
def test_things_that_must_never_appear_fail(extra):
    assert failing(README + "\n" + extra + "\n")


def test_the_empty_key_example_is_not_a_secret():
    assert failing(README + "\nOPENAI_API_KEY=\n") == []


def test_the_command_line_exit_codes(tmp_path):
    gate_py = os.path.join(ROOT, "src", "ops", "check_readme.py")
    ok = subprocess.run([sys.executable, gate_py], capture_output=True, text=True)
    assert ok.returncode == 0 and ok.stdout.strip() == "check-readme: ok"
    bad = tmp_path / "README.md"
    bad.write_text("# x\n\nNothing here.\n", encoding="utf-8")
    ko = subprocess.run([sys.executable, gate_py, str(bad)], capture_output=True, text=True)
    assert ko.returncode == 1 and "check-readme: FAIL" in ko.stdout
    missing = subprocess.run([sys.executable, gate_py, str(tmp_path / "none.md")], capture_output=True, text=True)
    assert missing.returncode == 1


def test_the_printed_tables_are_what_the_readme_holds():
    out = subprocess.run([sys.executable, os.path.join(ROOT, "src", "ops", "check_readme.py"), "--print-tables"], capture_output=True, text=True).stdout
    for _, block in gate.figure_blocks(REPORT):
        assert block in out and block in README


@pytest.mark.parametrize("needle", ["%DB_USER", "%EnsRole_AlertAdministrator", "port 80", "404"])
def test_the_accounts_roles_and_the_exposure_are_required(needle):
    out = failing(README.replace(needle, "X"))
    assert any("demo" in line and needle in line for line in out)


@pytest.mark.parametrize("phrase", ["deliberately broader", "not always the owner", "specific to the Readback", "system context"])
def test_the_framing_of_the_broad_roles_is_required(phrase):
    out = failing(README.replace(phrase, "something else"))
    assert any("demo" in line for line in out)
