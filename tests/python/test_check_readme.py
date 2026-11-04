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
    out = failing(README.replace("https://youtu.be/ML2pBgBkqUo", "[PENDING: publication]", 1))
    assert any("youtu.be" in line for line in out)


def test_a_video_link_in_another_format_fails():
    out = failing(README.replace("https://youtu.be/ML2pBgBkqUo", "https://www.youtube.com/watch?v=ML2pBgBkqUo", 1))
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
    summary = next(l for l in README.splitlines() if l.startswith("**The safety comes from"))
    assert any("summary" in out for out in failing(README.replace(summary + "\n", "", 1)))
    assert any("summary" in out and "number" in out for out in failing(README.replace(summary, summary.replace("The safety comes from", "The safety of the 2 layers comes from"), 1)))


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


def test_the_feedback_links_the_reports():
    assert any("feedback" in out for out in failing(README.replace("issues/41", "issues/40", 1)))
    assert any("feedback" in out for out in failing(README.replace("reported from this project;", "reported from this project; no issue has been filed;", 1)))


def test_the_run_it_time_statement_is_required():
    out = failing(README.replace("from clone to a working panel in", "from clone to a panel in", 1))
    assert any("measured time" in line for line in out)


def test_an_ablation_table_not_generated_from_the_file_fails():
    out = failing(README.replace("| The full product | gpt-5.4 |", "| The full product | gpt-5.4x |", 1))
    assert any("ablation" in line for line in out)


def test_the_agent_alone_figure_is_not_stated():
    out = failing(README.replace("## Demo\n", "## Demo\n\nContextual criticals raised by the agent alone: many.\n", 1))
    assert any("agent-alone" in line for line in out)


def test_the_third_item_must_carry_the_numbers_of_the_run_without_the_verdict():
    out = failing(README.replace("sends 23 to a person", "sends 22 to a person", 1))
    assert any("third item" in line for line in out)


def test_the_first_screen_must_say_the_rules_guarantee_the_safety_and_the_agent_explains():
    out = failing(README.replace("The rules guarantee the safety and the agent explains.", "", 1))
    assert any("first screen" in line for line in out)


def test_the_cost_claim_is_checked_against_the_report():
    cheap = json.loads(json.dumps(REPORT))
    cheap["models"]["gpt-5.4"]["costPerThousandUsd"] = 1.0
    assert any("about three times" in line for line in gate.check(README, cheap))


def test_the_key_figures_state_the_run_without_the_verdict_and_not_the_agent_alone_row():
    assert "raised by the agent alone" not in README
    assert "without the rule's verdict" in README


def test_saying_that_every_tool_call_is_a_visual_trace_step_fails():
    out = failing(README.replace("## Demo\n", "## Demo\n\nIn the platform's Visual Trace each tool call is a step of the session.\n", 1))
    assert any("Visual Trace" in line and "policy search" in line for line in out)


def test_the_precise_statement_about_the_visual_trace_passes():
    assert "the policy search, which calls another operation, also appears in the Visual Trace" in README
    assert failing(README) == []


def test_the_tracing_map_passes_and_checks_something():
    section = gate.sections_of(README)[0]["Idea DPI-I-689"]
    assert gate.dpi_map_problems(section) == []
    assert "GET /readback/api/indicators" in section and "Readback.Trace.ToolCall" in section


@pytest.mark.parametrize("old,new,needle", [
    ("GET /readback/api/indicators", "GET /readback/api/telemetry", "not a route"),
    ("Readback.Trace.ToolCall", "Readback.Trace.ToolCalls", "does not exist"),
    ("`passageIds`", "`passageNumbers`", "does not return"),
    ("| Retrieval |", "| Searching |", "no row 'Retrieval'"),
])
def test_a_tracing_map_that_cites_something_that_does_not_exist_fails(old, new, needle):
    out = failing(README.replace(old, new, 1))
    assert any("idea" in line and needle in line for line in out)


def test_the_precedent_sentence_is_required_in_the_architecture():
    out = failing(README.replace("Nothing that no person confirmed enters the pool", "Anything may enter the pool", 1))
    assert any("pool of similar cases" in line for line in out)


def test_the_mcp_section_must_state_the_refusal_of_the_read_back():
    out = failing(README.replace("This is a security decision, not a gap.", "This is a gap.", 1))
    assert any("mcp" in line and "security decision" in line for line in out)


def test_the_mcp_section_must_name_the_verified_client_and_the_check():
    out = failing(README.replace("MCP Inspector", "some client"))
    assert any("mcp" in line and "verified" in line for line in out)
    out = failing(README.replace("tests/e2e/mcp_client_check.sh", "tests/e2e/not_there.sh"))
    assert any("mcp" in line for line in out)


def test_the_mcp_section_must_list_the_four_tools():
    out = failing(README.replace("read_ablation", "read_other"))
    assert any("mcp" in line and "read_ablation" in line for line in out)


def test_the_mcp_bonus_row_is_required():
    out = failing(README.replace("| MCP server |", "| Something |", 1))
    assert any("MCP server" in line for line in out)


def test_the_start_section_must_say_that_only_the_start_script_starts_the_production():
    out = failing(README.replace("In the container only the start script", "In the container the start script", 1))
    assert any("start" in line and "start script" in line for line in out)


def test_a_file_cited_in_the_start_section_must_exist():
    out = failing(README.replace("tests/e2e/start_check.sh", "tests/e2e/no_such_check.sh"))
    assert any("start" in line for line in out)


REPRODUCE = open(os.path.join(ROOT, "REPRODUCE.md"), encoding="utf-8").read()


def test_the_finished_reproduce_file_passes():
    assert gate.reproduce_problems(REPRODUCE, README) == []


@pytest.mark.parametrize("title", gate.REPRODUCE_SECTIONS)
def test_a_missing_reproduce_section_fails(title):
    out = gate.reproduce_problems(REPRODUCE.replace(f"## {title}", "## Renamed"), README)
    assert any(title in line for line in out)


def test_the_readme_must_link_the_reproduce_file():
    assert any("link" in line for line in gate.reproduce_problems(REPRODUCE, README.replace("(REPRODUCE.md)", "(x)")))


@pytest.mark.parametrize("original, replacement, needle", [
    ("src/ops/evaluate.sh replay", "src/ops/nothere.sh replay", "nothere.sh"),
    ("data/config/price-table.json", "data/config/no-prices.json", "no-prices.json"),
    ("python3 -m readback.evaluation.ablation", "python3 -m readback.evaluation.nothing", "readback.evaluation.nothing"),
    ("evaluate.sh replay gpt-5.4-mini", "evaluate.sh replay gpt-9", "gpt-9"),
    ("src/ops/evaluate.sh live gpt-5.4 --variant no-verdict", "src/ops/evaluate.sh live gpt-5.4 --variant no-verdict --non" "sense", "--non" "sense"),
    ("READBACK_MCP_PORT", "READBACK_NO" "T_A_VARIABLE", "READBACK_NO" "T_A_VARIABLE"),
    ("`tests/e2e/triage_check.sh`", "`tests/e2e/triage_missing.sh`", "triage_missing.sh"),
])
def test_a_command_file_or_variable_that_does_not_exist_fails(original, replacement, needle):
    assert original in REPRODUCE
    out = gate.reproduce_problems(REPRODUCE.replace(original, replacement, 1), README)
    assert any(needle in line for line in out)


def test_a_placeholder_left_in_the_reproduce_file_fails():
    assert any("BATTERY" "_MINUTES" in line for line in gate.reproduce_problems(REPRODUCE + "\nabout BATTERY" "_MINUTES minutes\n", README))


def test_the_readme_citing_a_missing_file_fails():
    out = failing(README + "\nSee `src/ops/not-there.sh`.\n")
    assert any("cited" in line and "not-there.sh" in line for line in out)


@pytest.mark.parametrize("original", ["after the instance restarts", "does not match is refused"])
def test_the_readme_must_keep_the_restart_and_the_readback_steps(original):
    out = failing(README.replace(original, "xxxx", 1))
    assert any(("ipm-restart" in line or "readback-steps" in line) for line in out)


@pytest.mark.parametrize("original", ["passes on build 154 and on build 109", "SECURITY" "RESOURCE", "Found when moving to build 109"])
def test_the_readme_must_keep_the_tested_builds_and_the_difference(original):
    out = failing(README.replace(original, "xxxx"))
    assert any(("tested-builds" in line or "build-difference" in line) for line in out)
