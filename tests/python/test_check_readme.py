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
    block = gate.figure_blocks(REPORT)[0][2]
    changed = block.replace("148", "149", 1)
    assert any("figures" in line for line in failing(README.replace(block, changed)))


def test_a_report_that_disagrees_with_the_claims_fails():
    report = json.loads(json.dumps(REPORT))
    report["models"]["gpt-5.4"]["silencedCriticals"] = 1
    assert any("claim" in line for line in gate.check(README, report))


BEFORE, DELTA, GUARD = gate.load_companions()
KEY_LINES = gate.key_figures(REPORT, BEFORE, DELTA, GUARD)


def test_the_key_figures_block_is_the_generated_one():
    assert KEY_LINES and all(line in README for line in KEY_LINES)
    assert all(line.startswith("|") for line in KEY_LINES) and len(KEY_LINES) > 10


@pytest.mark.parametrize("line", KEY_LINES[2:])
def test_a_changed_key_figure_fails(line):
    digit = next(i for i in range(len(line) - 1, -1, -1) if line[i].isdigit())  # the last digit of the row is in a model column
    changed = line[:digit] + str((int(line[digit]) + 1) % 10) + line[digit + 1:]
    assert any("figures" in out and "Key figures" in out for out in failing(README.replace(line, changed, 1)))


def test_a_missing_key_figure_fails():
    assert any("Key figures" in out for out in failing(README.replace(KEY_LINES[0] + "\n", "", 1)))


def test_a_key_figures_block_not_generated_from_the_report_fails():
    report = json.loads(json.dumps(REPORT))
    report["models"]["gpt-5.4"]["reviewRate"] = 0.5
    assert any("Key figures" in out for out in gate.check(README, report, BEFORE, DELTA, GUARD))


def test_a_changed_companion_figure_fails():
    delta = json.loads(json.dumps(DELTA))
    delta["releasedCriticals"]["gpt-5.4-mini"]["withoutDeltaFloor"] = 20
    assert any("Key figures" in out for out in gate.check(README, REPORT, BEFORE, delta, GUARD))


@pytest.mark.parametrize("sentence", ["The released criticals fell from 19 to 2.", "The review rate is 27.6% now.", "It costs 3.1 times more."])
def test_an_evaluation_number_outside_the_blocks_fails(sentence):
    text = README.replace("### What the numbers say, and what they do not say\n", "### What the numbers say, and what they do not say\n\n" + sentence + "\n", 1)
    assert any("outside the figure blocks" in out for out in failing(text))


def test_the_dataset_numbers_may_be_stated_in_prose():
    assert not any("outside the figure blocks" in out for out in failing(README))


def test_a_closing_list_with_three_items_fails():
    out = failing(README + "- one more thing: [PENDING: publication]\n")
    assert any("pending" in line for line in out)


def test_the_video_link_is_required_in_the_fast_path():
    out = failing(README.replace("https://youtu.be/Kh7ZY3tUWs4", "[PENDING: publication]", 1))
    assert any("youtu.be" in line for line in out)


def test_a_video_link_in_another_format_fails():
    out = failing(README.replace("https://youtu.be/Kh7ZY3tUWs4", "https://www.youtube.com/watch?v=Kh7ZY3tUWs4", 1))
    assert any("youtu.be" in line for line in out)


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
    for _, _, block in gate.figure_blocks(REPORT):
        assert block in out and block in README


@pytest.mark.parametrize("needle", ["%DB_USER", "%EnsRole_AlertAdministrator", "port 80", "404"])
def test_the_accounts_roles_and_the_exposure_are_required(needle):
    out = failing(README.replace(needle, "X"))
    assert any("demo" in line and needle in line for line in out)


@pytest.mark.parametrize("phrase", ["deliberately broader", "not always the owner", "specific to the Readback", "system context"])
def test_the_framing_of_the_broad_roles_is_required(phrase):
    out = failing(README.replace(phrase, "something else"))
    assert any("demo" in line for line in out)


def mutate_in_section(model, old, new):
    """README with the first `old` replaced by `new`, inside the section of one model only."""
    head = f"#### {model}\n"
    start = README.index(head)
    end = README.find("\n#### ", start + 1)
    end = len(README) if end == -1 else end
    section = README[start:end]
    assert old in section
    return README[:start] + section.replace(old, new, 1) + README[end:]


@pytest.mark.parametrize("model", gate.MODELS)
def test_one_number_of_a_matrix_changed_in_one_model_fails(model):
    # The final matrices of the two models are equal: a changed copy must fail even though the other copy is intact.
    row = "| CRITICAL | 148 | 0 | 2 | 0 | 0 |"
    assert any("figures" in line for line in failing(mutate_in_section(model, row, "| CRITICAL | 147 | 0 | 2 | 0 | 0 |")))


@pytest.mark.parametrize("model", gate.MODELS)
def test_one_cost_value_changed_fails(model):
    line = next(l for l in gate.figure_lines(REPORT["models"][model]).splitlines() if "Cost per thousand" in l)
    for changed in (line[:-1] + ("9" if line[-1] != "9" else "8"), line + "1"):
        assert any("figures" in out for out in failing(mutate_in_section(model, line, changed)))


@pytest.mark.parametrize("model", gate.MODELS)
def test_one_latency_value_changed_fails(model):
    line = next(l for l in gate.figure_lines(REPORT["models"][model]).splitlines() if "Latency" in l)
    for changed in (line[:-1] + ("9" if line[-1] != "9" else "8"), line + "1"):
        assert any("figures" in out for out in failing(mutate_in_section(model, line, changed)))


def test_a_block_under_the_wrong_model_heading_fails():
    mini, big = gate.MODELS[0], gate.MODELS[1]
    block = dict((l, b) for _, l, b in gate.figure_blocks(REPORT))[f"{big} figures"]
    text = README.replace(block, "", 1) + "\n" + block + "\n"
    assert any("figures" in line and big in line for line in failing(text))


def test_a_changed_release_guard_figure_fails():
    guard = json.loads(json.dumps(GUARD))
    guard["models"]["gpt-5.4-mini"]["notClearCutReleasedWithoutGuard"] = 11
    assert any("Key figures" in out for out in gate.check(README, REPORT, BEFORE, DELTA, guard))



def test_the_hero_gif_is_required_above_the_fold():
    gif = "![The agent decides on a critical potassium, which stops at read-back, and on a borderline one, which goes to a person to review; replay mode, synthetic data](docs-assets/signature.gif)"
    assert gif in README
    assert any("hero" in out for out in failing(README.replace(gif, "")))
    assert any("hero" in out for out in failing(README.replace("![The agent decides on a critical potassium, which stops at read-back, and on a borderline one, which goes to a person to review; replay mode, synthetic data]", "![x]")))
    assert any("hero" in out for out in failing(README.replace(gif, "").replace("## For judges", gif + "\n\n## For judges", 1)))


def test_the_hero_gif_is_a_gif_of_reasonable_size():
    path = os.path.join(ROOT, "docs-assets", "signature.gif")
    data = open(path, "rb").read()
    assert data[:6] in (b"GIF87a", b"GIF89a") and len(data) < 3_000_000


def test_the_package_manifest_ships_the_agent_and_governance_classes():
    manifest = open(os.path.join(ROOT, "module.xml"), encoding="utf-8").read()
    assert '<Resource Name="Readback.PKG"/>' in manifest and '<FileCopy Name="data/config/"' in manifest
    for cls in ("Agent/Operation", "Agent/ToolHost", "Tools/ToolSet", "Governance/AuditPolicy", "Governance/ScopePolicy", "Governance/FloorPolicy", "Triage/ReleaseGuard", "Config/ReleaseGuard"):
        assert os.path.exists(os.path.join(ROOT, "src", "Readback", cls + ".cls")), cls
    assert os.path.exists(os.path.join(ROOT, "data", "config", "release-guard.json"))
    assert os.path.exists(os.path.join(ROOT, "data", "config", "agent-tools.json"))


def test_a_key_figures_row_for_one_model_is_a_column_not_a_line():
    assert KEY_LINES[0].count("|") == 4 and all(line.count("|") == 4 for line in KEY_LINES)


def test_the_bold_summary_is_required_and_has_no_number():
    summary = next(l for l in README.splitlines() if l.startswith("**Neither model"))
    assert any("summary" in out for out in failing(README.replace(summary + "\n", "", 1)))
    assert any("summary" in out and "number" in out for out in failing(README.replace(summary, summary.replace("Neither model", "Neither of the 2 models"), 1)))


def test_the_numbers_section_has_at_most_five_items():
    text = README.replace("### What the numbers say, and what they do not say\n", "### What the numbers say, and what they do not say\n\n- one\n- two\n", 1)
    assert any("summary" in out and "at most" in out for out in failing(text))


@pytest.mark.parametrize("command", gate.RUN_IT_COMMANDS)
def test_the_run_it_block_needs_its_five_commands(command):
    run = README.split("## Run it", 1)[1].split("## For judges", 1)[0]
    assert any("run-it" in out for out in failing(README.replace(run, run.replace(command, "xxxx"), 1)))


def test_the_run_it_block_links_to_the_full_steps():
    assert any("run-it" in out for out in failing(README.replace("(#required-by-the-organizers)", "(#nowhere)", 1)))


@pytest.mark.parametrize("name", gate.BONUSES)
def test_a_bonus_without_a_row_fails(name):
    table = README.split("## Technology bonuses", 1)[1].split("## Feedback", 1)[0]
    row = next(l for l in table.splitlines() if l.startswith("|") and name in l.split("|")[1])
    assert any("bonus" in out and name in out for out in failing(README.replace(row + "\n", "", 1)))


def test_a_bonus_that_names_a_missing_file_fails():
    assert any("bonus" in out and "does not exist" in out for out in failing(README.replace("src/Readback/Notify/Pager.cls", "src/Readback/Notify/Nothing.cls", 1)))


def test_embedded_python_must_name_the_class_with_python_methods_and_its_caller():
    assert any("bonus" in out for out in failing(README.replace("src/Readback/Demo/Generator.cls", "src/Readback/Notify/Pager.cls", 1)))
    assert any("bonus" in out for out in failing(README.replace("`[ Language = python ]`", "`python`", 1)))


def test_the_feedback_links_the_four_reports():
    assert any("feedback" in out for out in failing(README.replace("issues/41", "issues/40", 1)))
    assert any("feedback" in out for out in failing(README.replace("reported from this project;", "reported from this project; no issue has been filed;", 1)))
