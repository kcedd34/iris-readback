#!/usr/bin/env python3
"""The README gate: what the organizers require, the sections, the figures, the pending markers and a few things that must never appear.

Usage: check_readme.py [README.md] [--report data/eval/report.json]
       check_readme.py --print-tables     prints the figure blocks the README must hold, taken from the report
Exit 0 and "check-readme: ok" when every rule holds; exit 1 with one "check-readme: FAIL <rule>: <what>" line per failure.
Standard library only.
"""
import argparse
import json
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PENDING = "[PENDING: publication]"
IMAGE = "irishealth-community:2026.3.0AI.154.0"
CLASSES = ["CRITICAL", "RECOLLECT", "NEEDS_REVIEW", "NON_CRITICAL"]
COLUMNS = CLASSES + ["none"]
MODELS = ["gpt-5.4-mini", "gpt-5.4"]

# Level-2 headings in the order the README must have them, then the level-3 headings of the organizers' four items.
SECTIONS = [
    "Fast path", "Run it", "For judges", "Demo", "Required by the organizers", "What the production contains",
    "Technology bonuses", "Feedback on AI Hub EAP", "Idea DPI-I-689", "How it works", "Built with", "Author", "Still to publish",
]
REQUIRED_ITEMS = {
    "Early Access image and build": [IMAGE, "154"],
    "Load and rename the image": ["docker load", "docker tag"],
    "LLM provider and key variable": ["OpenAI", "OPENAI_API_KEY"],
    "Start and verify": ["docker compose up", "verify.sh"],
}
RUN_IT_COMMANDS = ["docker load", "cp .env.example .env", "src/ops/preflight.sh", "docker compose up", "src/ops/verify.sh"]
BONUSES = ["PEX", "Workflow Engine", "Custom outbound adapter", "Embedded Python", "Vector Search", "Docker", "IPM", "MCP server", "Online demo", "DPI-I-689"]
MAX_NUMBERS_ITEMS = 5
FEEDBACK_ISSUES = 5
ACCOUNTS = ["communicator1", "communicator2", "observer"]
DEMO_URL = "http://109.123.244.170/"
IDEA_URL = "https://ideas.intersystems.com/ideas/DPI-I-689"

# Portuguese letters and words, written as escapes so that no Portuguese text sits in the repository.
PORTUGUESE_LETTERS = re.compile("[\u00e1\u00e0\u00e2\u00e3\u00e9\u00ea\u00ed\u00f3\u00f4\u00f5\u00fa\u00e7\u00c1\u00c0\u00c2\u00c3\u00c9\u00ca\u00cd\u00d3\u00d4\u00d5\u00da\u00c7]")
PORTUGUESE_WORDS = re.compile("(?i)\\b(n\u00e3o|para|uma|dos|das|voc\u00ea|tamb\u00e9m|s\u00e3o|ent\u00e3o|porque)\\b")
KEY_SHAPED = re.compile(r"(?m)sk-[A-Za-z0-9_-]{20,}|^\s*[A-Z_]*KEY\s*=\s*\S+")
ALL_TO_HUMAN = re.compile(r"(?i)\b(every|all)\s+(error|mistake|miss(ed)?(\s+critical)?)s?\b[^.]{0,60}\b(human|person|people)\b")


JUDGES = "For judges"
KEY_FIGURES = "Key figures"
# Numbers the judges' section may state outside the figure blocks: the dataset (240 cases, 30 in each of 8 categories, seed 2026)
# and the two parameters of the release guard, which are product settings and not results.
ALLOWED_NUMBERS = {"240", "30", "8", "2026", "93", "100"}


def load_report(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def load_companions(report_path=None):
    """The round before the tools, the effect of the delta floor and the effect of the release guard, kept next to the report."""
    folder = os.path.dirname(report_path) if report_path else os.path.join(ROOT, "data", "eval")
    return load_report(os.path.join(folder, "report-before-tools.json")), load_report(os.path.join(folder, "delta-floor.json")), load_report(os.path.join(folder, "release-guard-effect.json"))


def load_ablation(report_path=None):
    folder = os.path.dirname(report_path) if report_path else os.path.join(ROOT, "data", "eval")
    return load_report(os.path.join(folder, "ablation.json"))


ABLATION_HEADING = "Ablation: which layer does what"
# (key in the ablation file, label, whether the arrangement has an agent and so one row per model)
ABLATION_ROWS = (
    ("value", "Range rule only", False),
    ("valueGuard", "Range rule and release guard, no agent", False),
    ("deterministic", "Range rule, change rule and release guard, no agent", False),
    ("agent", "Range rule, guard and agent without the change rule; the agent saw the rule's verdict", True),
    ("agentWithoutVerdict", "The same, but the agent saw the earlier values and the variation, not the verdict", True),
    ("full", "The full product", True),
)


def ablation_lines(ablation):
    """The ablation table, one row per arrangement (and per model when an agent is in it), generated from data/eval/ablation.json."""
    lines = ["| Arrangement | Model | Contextual criticals: read-back / sent to a person / released | Uncertain results released | Rule-critical silenced | False criticals | Review rate |",
             "|---|---|---|---|---|---|---|"]
    for key, label, per_model in ABLATION_ROWS:
        if key == "agentWithoutVerdict":
            entries = [(name, ablation["agentWithoutVerdict"]["models"][name]) for name in MODELS if name in ablation["agentWithoutVerdict"]["models"]]
        elif per_model:
            entries = [(name, ablation["models"][name][key]) for name in MODELS]
        else:
            entries = [("none", ablation["models"][MODELS[0]][key])]
        for name, x in entries:
            c = x["contextualCriticals"]
            lines.append(f"| {label} | {name} | {c['readback']} / {c['review']} / {c['released']} | {x['uncertainReleased']} of {x['uncertainCases']} | {x['silencedCriticals']} | {x['falseCriticals']} | {x['reviewRate'] * 100:.1f}% |")
    return lines


def ablation_numbers(ablation):
    """Every whole number the ablation file states in its figures: the prose of the judges' section may use these."""
    found = set()

    def walk(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if key in ("origin", "arrangements", "definitions", "caveat", "recordingsSha256"):
                    continue
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)
        elif isinstance(node, int) and not isinstance(node, bool):
            found.add(str(node))
    walk(ablation)
    return found


DPI_ROWS = ("A session per request", "Model and prompt version", "Tokens, cost and latency", "Tool calls", "Retrieval", "Errors and policy refusals", "Human outcome")


def api_routes():
    """(method, url pattern) of every route of the REST dispatch classes, with each :name turned into :."""
    found = set()
    folder = os.path.join(ROOT, "src", "Readback", "API")
    for name in os.listdir(folder):
        if name.endswith(".cls"):
            with open(os.path.join(folder, name), encoding="utf-8") as handle:
                for url, method in re.findall(r'<Route Url="([^"]+)" Method="([A-Z]+)"', handle.read()):
                    found.add((method, re.sub(r":\w+", ":", url)))
    return found


def api_source():
    folder = os.path.join(ROOT, "src", "Readback", "API")
    text = ""
    for name in os.listdir(folder):
        if name.endswith(".cls"):
            with open(os.path.join(folder, name), encoding="utf-8") as handle:
                text += handle.read()
    return text


def dpi_map_problems(section):
    """The tracing map of the idea section: one row per item, and every endpoint, class and field it cites exists in the source."""
    problems = []
    rows = [l for l in section.splitlines() if l.startswith("|")]
    if not rows or [c.strip() for c in rows[0].strip("|").split("|")] != ["What an LLM tracing tool records", "Where it is in Readback"]:
        return ["the idea section needs the table 'What an LLM tracing tool records | Where it is in Readback'"]
    first = [r.strip("|").split("|")[0].strip() for r in rows[2:]]
    for label in DPI_ROWS:
        if label not in first:
            problems.append(f"the tracing map has no row '{label}'")
    routes, source = api_routes(), api_source()
    for token in re.findall(r"`([^`]+)`", "\n".join(rows[2:])):
        endpoint = re.fullmatch(r"(?:(GET|POST) )?/readback/api(/\S*)", token)
        if endpoint:
            method, path = endpoint.group(1) or "GET", re.sub(r"\{\w+\}", ":", endpoint.group(2))
            if (method, path) not in routes:
                problems.append(f"the tracing map cites {token}, which is not a route of the REST API")
        elif re.fullmatch(r"Readback(\.\w+)+", token):
            if not os.path.exists(os.path.join(ROOT, "src", *token.split(".")) + ".cls"):
                problems.append(f"the tracing map cites the class {token}, which does not exist")
        elif re.fullmatch(r"[a-z]+(?:[A-Z][a-z]+)*", token) and token not in ("status",):
            if f'"{token}"' not in source and f".{token} =" not in source and f".{token}=" not in source:
                problems.append(f"the tracing map cites the field {token}, which the REST API does not return")
    return problems


def key_figures(report, before, delta, guard, ablation=None):
    """The figures the prose of the README is allowed to rely on, as a table with one row per metric and one column per model, generated from the report and its companions."""
    rows = {}
    ablation = ablation if ablation is not None else load_ablation()

    def put(label, name, value):
        rows.setdefault(label, {})[name] = value

    for name in MODELS:
        now, old = report["models"][name], before["models"][name]
        floor = delta["releasedCriticals"][name]
        effect = guard["models"][name]
        final = now["matrixFinal"]["CRITICAL"]
        released_now = now["matrixFinal"]["RECOLLECT"]["NON_CRITICAL"] + now["matrixFinal"]["NEEDS_REVIEW"]["NON_CRITICAL"]
        contextual_now = now["agreementByCategory"]["contextual-critical"]
        contextual_old = old["agreementByCategory"]["contextual-critical"]
        put("Rule-critical results silenced", name, now["silencedCriticals"])
        put("Criticals released as non-critical, delta floor off, then on (first round, recorded answers replayed)", name, f"{floor['withoutDeltaFloor']} to {floor['withDeltaFloor']}")
        put("Criticals released as non-critical in the current round", name, final["NON_CRITICAL"])
        put("Residual contextual criticals: not detected / sent to a person", name, f"{len(now['missedCriticals'])} / {final['NEEDS_REVIEW']}")
        blind = ablation["agentWithoutVerdict"]["models"].get(name)
        total = ablation["contextualCriticalCases"]
        put(f"Contextual criticals the agent put in read-back without the rule's verdict, then sent to a person (of {total})", name, f"{blind['contextualCriticals']['readback']} / {blind['contextualCriticals']['review']}" if blind else "not run")
        put("False criticals the agent created without the rule's verdict", name, blind["falseCriticals"] if blind else "not run")
        put(f"Contextual criticals ending critical, without tools, then with tools (of {contextual_now['cases']})", name, f"{contextual_old['finalAgrees']} to {contextual_now['finalAgrees']}")
        put("Downgrade attempts held by the floor, without tools, then with tools", name, f"{old['downgradeAttempts']} to {now['downgradeAttempts']}")
        put("Review rate, without tools, then with tools", name, f"{old['reviewRate'] * 100:.1f}% to {now['reviewRate'] * 100:.1f}%")
        put("Releases held for a person by the release guard", name, now["releaseGuardHolds"])
        put("Results not clear-cut released as non-critical, guard off, then on (recorded answers replayed)", name, f"{effect['notClearCutReleasedWithoutGuard']} to {released_now}")
        put("Review rate without the release guard", name, f"{effect['reviewRateWithoutGuard'] * 100:.1f}%")
        put("Tool calls per result", name, f"{now['toolCallsPerResult']:.2f}")
        put("Invalid answers", name, f"{now['invalidRate'] * 100:.1f}%")
    lines = ["| Metric | " + " | ".join(MODELS) + " |", "|---|" + "---|" * len(MODELS)]
    lines += [f"| {label} | " + " | ".join(str(values[name]) for name in MODELS) + " |" for label, values in rows.items()]
    return lines


def strip_for_numbers(body):
    """The judges' section without what is allowed to hold numbers: tables, the figure blocks, the key figures, code, model and prompt names."""
    kept, in_code, skip_figures = [], False, False
    for line in body.splitlines():
        if line.startswith("```"):
            in_code = not in_code
            continue
        if in_code or line.lstrip().startswith("|"):
            continue
        if re.match(r"^###\s+", line):
            skip_figures = line.strip() == f"### {KEY_FIGURES}"
        if skip_figures or re.match(r"^- (Cost per thousand|Latency p50|Silenced criticals|Missed criticals|Downgrade attempts by)", line):
            continue
        kept.append(line)
    text = "\n".join(kept)
    text = re.sub(r"gpt-[\w.]+(-mini)?|triage-v\d+|build \d+|DPI-I-\d+|release-guard|1/0\.93", "", text)
    return text


def matrix_table(matrix):
    lines = ["| expected \\ decided | " + " | ".join(COLUMNS) + " |", "|---|" + "---|" * len(COLUMNS)]
    for expected in CLASSES:
        row = matrix[expected]
        lines.append(f"| {expected} | " + " | ".join(str(row[column]) for column in COLUMNS) + " |")
    return "\n".join(lines)


def figure_lines(model):
    return "\n".join([
        f"- Cost per thousand results (USD): {model['costPerThousandUsd']:.4f}",
        f"- Latency p50 / p95 (ms, recorded): {model['latencyP50Ms']} / {model['latencyP95Ms']}",
        f"- Silenced criticals: {model['silencedCriticals']}",
        f"- Missed criticals (expected critical, not critical by rule, not sent to read-back): {len(model['missedCriticals'])}",
        f"- Downgrade attempts by the agent on rule-critical results (kept critical): {model['downgradeAttempts']}",
    ])


def figure_blocks(report):
    """The blocks, per model, that the README must contain line for line, under the heading of that model."""
    blocks = []
    for name in MODELS:
        model = report["models"][name]
        blocks.append((name, f"{name} final matrix", matrix_table(model["matrixFinal"])))
        blocks.append((name, f"{name} agent matrix", matrix_table(model["matrixAgent"])))
        blocks.append((name, f"{name} figures", figure_lines(model)))
    return blocks


def model_sections(text):
    """{model name: the lines under its '#### name' heading, up to the next heading}. The models' matrices can be equal,
    so a block only counts under the heading of its own model."""
    out, current = {}, None
    for line in text.splitlines():
        m = re.match(r"^#{1,4}\s+(.+?)\s*$", line)
        if m:
            current = m.group(1) if line.startswith("#### ") else None
            if current is not None:
                out[current] = []
        elif current is not None:
            out[current].append(line.rstrip())
    return out


def holds_block(lines, block):
    """True when the block's lines appear in order, as whole lines, one right after the other."""
    wanted = block.splitlines()
    return any(lines[i:i + len(wanted)] == wanted for i in range(len(lines) - len(wanted) + 1))


def sections_of(text):
    """Returns ({level-2 title: body}, {level-3 title: body}, [level-2 titles in order])."""
    two, three, order = {}, {}, []
    current2 = current3 = None
    for line in text.splitlines():
        m2 = re.match(r"^##\s+(.+?)\s*$", line)
        m3 = re.match(r"^###\s+(.+?)\s*$", line)
        if m2 and not line.startswith("###"):
            current2, current3 = m2.group(1), None
            two[current2] = ""
            order.append(current2)
        elif m3:
            current3 = m3.group(1)
            three[current3] = ""
            if current2 is not None:
                two[current2] += line + "\n"
        else:
            if current3 is not None:
                three[current3] += line + "\n"
            if current2 is not None:
                two[current2] += line + "\n"
    return two, three, order


def list_items(body):
    return [line for line in body.splitlines() if re.match(r"^\s*([-*]|\d+\.)\s+\S", line)]


def check(text, report, before=None, delta=None, guard=None, ablation=None):
    failures = []
    ablation = ablation if ablation is not None else load_ablation()
    if before is None or delta is None or guard is None:
        before, delta, guard = load_companions()

    def fail(rule, what):
        failures.append(f"check-readme: FAIL {rule}: {what}")

    two, three, order = sections_of(text)

    # 1. The thesis is the first sentence after the title.
    body_lines = [l for l in text.splitlines() if l.strip()]
    first = next((l for l in body_lines if not l.startswith("#")), "")
    if not (re.search(r"(?i)\braise", first) and re.search(r"(?i)never (lower|downgrade)", first) and "read-back" in first.lower()):
        fail("thesis", "the first line after the title must say the agent can raise a critical, never lower it, and that nobody is notified without a read-back")

    # The signature GIF sits above the fold, before the first section, with a description, and the file is there.
    head = text.split("\n## ", 1)[0]
    if not re.search(r"!\[[^\]]{20,}\]\(docs-assets/signature\.gif\)", head):
        fail("hero", "the signature GIF with a description must come before the first section")
    elif not os.path.exists(os.path.join(ROOT, "docs-assets", "signature.gif")):
        fail("hero", "docs-assets/signature.gif is missing")

    # 2. The sections, in order.
    positions = []
    for title in SECTIONS:
        if title not in two:
            fail("section", f"missing section '{title}'")
        else:
            positions.append(order.index(title))
    if positions != sorted(positions):
        fail("order", "the sections are not in the required order")

    # 3. The four items the organizers require.
    for heading, tokens in REQUIRED_ITEMS.items():
        if heading not in three:
            fail("required-item", f"missing the heading '{heading}'")
            continue
        for token in tokens:
            if token not in three[heading]:
                fail("required-item", f"'{heading}' does not contain '{token}'")

    # The read-only MCP server: its tools, the refusal of the read-back as a decision, the access, and what was and was not tested.
    mcp = three.get("Read-only MCP server", "")
    for needle in ("list_pending_criticals", "explain_decision", "read_evaluation", "read_ablation", "Readback_MCP", "iris-mcp-server", "src/Readback/MCP/Service.cls", "src/Readback/MCP/Tools.cls"):
        if needle not in mcp:
            fail("mcp", f"the MCP section must mention '{needle}'")
    if not (re.search(r"(?i)deliberately not exposed", mcp) and re.search(r"(?i)never closes a critical", mcp) and re.search(r"(?i)security decision, not a gap", mcp)):
        fail("mcp", "the MCP section must state that the read-back is deliberately not exposed, that an AI assistant never closes a critical, and that it is a security decision and not a gap")
    if not (re.search(r"MCP Inspector", mcp) and "tests/e2e/mcp_client_check.sh" in mcp and re.search(r"(?i)type 18", mcp) and re.search(r"(?i)What was tested", mcp)):
        fail("mcp", "the MCP section must name the client that was verified (the MCP Inspector), the check that runs it, the web application type 18 and what was tested")
    for path in re.findall(r"`(tests/e2e/\w+\.(?:py|sh))`", mcp):
        if not os.path.exists(os.path.join(ROOT, path)):
            fail("mcp", f"the MCP section cites {path}, which does not exist")
    for path in re.findall(r"`(src/Readback/MCP/\w+\.cls)`", mcp):
        if not os.path.exists(os.path.join(ROOT, path)):
            fail("mcp", f"the MCP section cites {path}, which does not exist")
    if re.search(r"(?i)\btools?\b[^.]{0,40}\b(confirm|close)s? (a|the) read-back", mcp) and not re.search(r"(?i)no tool confirms", mcp):
        fail("mcp", "the MCP section seems to offer a tool that confirms the read-back")

    # Demo: address, accounts, replay note, hourly reset.
    demo = two.get("Demo", "")
    if DEMO_URL not in demo:
        fail("demo", f"the demo address {DEMO_URL} is missing")
    for account in ACCOUNTS:
        if account not in demo:
            fail("demo", f"the demonstration account '{account}' is missing")
    if "replay" not in demo.lower() or "reset every hour" not in demo.lower():
        fail("demo", "the demo must say it runs in replay mode and is reset every hour")
    for needle in ("%DB_USER", "%EnsRole_AlertAdministrator", "port 80", "404"):
        if needle not in demo:
            fail("demo", f"the demo section must state the accounts' roles and the exposure: '{needle}' is missing")
    if not re.search(r"(?i)deliberately broader", demo) or not re.search(r"(?i)\bnot always the owner\b", demo):
        fail("demo", "the demo section must say the roles are deliberately broader than production and why the confirming person is not always the owner of the alert")
    if not re.search(r"(?i)specific to the Readback", demo) or not re.search(r"(?i)system context", demo):
        fail("demo", "the demo section must say what production would use: roles specific to the Readback and closing the alert in a system context")

    # 4. The figures equal the report; the claims about it hold.
    sections = model_sections(text)
    for model_name, label, block in figure_blocks(report):
        if not holds_block(sections.get(model_name, []), block):
            fail("figures", f"the block '{label}' is missing under its model heading or differs from data/eval/report.json (run check_readme.py --print-tables)")
    for name in MODELS:
        model = report["models"][name]
        if model["silencedCriticals"] != 0:
            fail("claim", f"the report shows {model['silencedCriticals']} silenced criticals for {name}; the README claims zero")
        if len(model["missedCriticals"]) != 2:
            fail("claim", f"the report shows {len(model['missedCriticals'])} residual criticals for {name}; the README says 2")
    results = two.get(JUDGES, "")
    expected = key_figures(report, before, delta, guard, ablation)
    held = [line.rstrip() for line in three.get(KEY_FIGURES, "").splitlines() if line.strip()]
    if held != expected:
        fail("figures", f"the '{KEY_FIGURES}' block is missing or differs from the report, line by line (run check_readme.py --print-tables)")
    for number in re.findall(r"\d[\d.,]*", strip_for_numbers(results)):
        if number.strip(".,") not in ALLOWED_NUMBERS | ablation_numbers(ablation):
            fail("figures", f"the '{JUDGES}' section states the number {number.strip('.,')} outside the figure blocks; evaluation numbers come only from the generated blocks")
    if not re.search(r"(?i)zero.{0,60}silenced|no .{0,60}silenced", results):
        fail("claim", "the judges' section must say that no rule-critical result was silenced")
    if not re.search(r"(?i)generator", results) or not re.search(r"(?i)calibrat", results):
        fail("claim", "the judges' section must say the delta limits were calibrated knowing the generator")

    for problem in dpi_map_problems(two.get("Idea DPI-I-689", "")):
        fail("idea", problem)
    precedent = two.get("What the production contains", "")
    if not (re.search(r"(?i)confirmation", precedent) and re.search(r"(?i)completed review", precedent) and re.search(r"(?i)nothing that no person confirmed enters the pool", precedent)):
        fail("claim", "the architecture must say that a person's confirmation (a matching read-back or a completed review) is what lets a case into the pool of similar cases, and that nothing else enters it")

    # The ablation table is generated from data/eval/ablation.json, and its full-product row agrees with the report.
    held_ablation = [line.rstrip() for line in three.get(ABLATION_HEADING, "").splitlines() if line.strip().startswith("|")]
    if held_ablation != ablation_lines(ablation):
        fail("ablation", f"the '{ABLATION_HEADING}' table is missing or differs from data/eval/ablation.json, line by line (run check_readme.py --print-tables)")
    rule_critical = ablation["ruleCriticalCases"]
    for name in MODELS:
        routed = report["models"][name]["matrixFinal"]["CRITICAL"]["CRITICAL"] - rule_critical
        if ablation["models"][name]["full"]["contextualCriticals"]["readback"] != routed:
            fail("ablation", f"the full-product row of {name} in data/eval/ablation.json does not agree with the report")
    said = three.get("What the numbers say, and what they do not say", "")
    items = list_items(said)
    guard_released = str(ablation["models"][MODELS[0]]["valueGuard"]["contextualCriticals"]["released"])
    blind = ablation["agentWithoutVerdict"]["models"]
    if len(items) < 5 or not re.search(r"(?i)deterministic", items[1] if len(items) > 1 else "") or guard_released not in (items[1] if len(items) > 1 else ""):
        fail("claim", f"the second item of 'What the numbers say' must say the safety comes from the deterministic layers and that {guard_released} contextual criticals would be released without the change rule")
    third = items[2] if len(items) > 2 else ""
    if not re.search(r"(?i)not a safety net", third) or not re.search(r"(?i)verdict", third):
        fail("claim", "the third item of 'What the numbers say' must say the agent is not a safety net and name the rule's verdict")
    for name in MODELS:
        x = blind.get(name)
        if not x:
            fail("claim", f"data/eval/ablation.json has no run without the verdict for {name}")
            continue
        part = re.search(re.escape(name) + r"(?!-)[^;.]*", third)
        wanted = [x["contextualCriticals"]["readback"], x["contextualCriticals"]["review"], x["falseCriticals"]]
        found = [int(n) for n in re.findall(r"\d+", part.group(0))] if part else []
        if not all(w in found for w in wanted):
            fail("claim", f"the third item of 'What the numbers say' must state, for {name}, {wanted[0]} in read-back, {wanted[1]} sent to a person and {wanted[2]} false criticals, as data/eval/ablation.json has")
    fourth = items[3] if len(items) > 3 else ""
    if not re.search(r"(?i)three times", fourth):
        fail("claim", "the fourth item of 'What the numbers say' must say what the agent adds and that it costs about three times as much and takes about three times as long")
    for name in MODELS:
        cost = report["models"][name]["costPerThousandUsd"] / before["models"][name]["costPerThousandUsd"]
        latency = report["models"][name]["latencyP50Ms"] / before["models"][name]["latencyP50Ms"]
        if not (2.5 <= cost <= 3.5 and 2.5 <= latency <= 3.5):
            fail("claim", f"'about three times' does not hold for {name}: cost x{cost:.2f}, latency x{latency:.2f} against the round before the tools")
    fifth = items[4] if len(items) > 4 else ""
    if not (re.search(r"(?i)synthetic", fifth) and re.search(r"(?i)single author|one author", fifth) and re.search(r"(?i)generator", fifth)):
        fail("claim", "the fifth item of 'What the numbers say' must state the caveats: synthetic, a single author, limits set on the generator")
    # The Visual Trace shows the agent's step, not each tool call: only a tool that calls another operation (the policy search) appears there.
    for sentence in re.split(r"(?<=[.!?])\s+", text):
        if (re.search(r"(?i)visual trace", sentence) and re.search(r"(?i)\b(each|every|all)\b[^.]{0,30}\btool calls?\b", sentence)
                and re.search(r"(?i)\bsteps?\b", sentence) and not re.search(r"(?i)\b(not|only|except|never)\b", sentence)):
            fail("claim", "the README says every tool call is a step of the Visual Trace; the session shows the agent's step, and only the policy search, which calls another operation, also appears there")
    if re.search(r"(?i)raised by the agent alone|the agent alone raised", text):
        fail("claim", "the agent-alone figure came from a run in which the agent saw the rule's verdict and is not stated")
    first_screen = " ".join(l for l in head.splitlines())
    if not (re.search(r"(?i)rules? (guarantee|ensure)", first_screen) and re.search(r"(?i)agent explains", first_screen) and re.search(r"(?i)decided alone", first_screen)):
        fail("thesis", "the first screen must say that the rules guarantee the safety, the agent explains, and the evaluation shows what would happen if the agent decided alone")

    # The summary sentence in bold before the key figures carries no number: the numbers are in the table, generated.
    lead = results.split(f"### {KEY_FIGURES}", 1)[0]
    bold = [l.strip() for l in lead.splitlines() if re.fullmatch(r"\*\*[^*]+\*\*", l.strip())]
    if not bold:
        fail("summary", f"the '{JUDGES}' section needs a one-sentence summary in bold before '{KEY_FIGURES}'")
    elif any(re.search(r"\d", l) for l in bold):
        fail("summary", "the bold summary must not state numbers; the numbers are in the generated table")
    if len(list_items(said)) > MAX_NUMBERS_ITEMS:
        fail("summary", f"'What the numbers say' has {len(list_items(said))} items, at most {MAX_NUMBERS_ITEMS}")

    # Run it: five commands right after the Fast path, linking to the full steps.
    run = two.get("Run it", "")
    for command in RUN_IT_COMMANDS:
        if command not in run:
            fail("run-it", f"the 'Run it' block does not contain '{command}'")
    if "(#required-by-the-organizers)" not in run:
        fail("run-it", "the 'Run it' block must link to the full steps in 'Required by the organizers'")
    code = re.findall(r"```[^\n]*\n(.*?)```", run, re.S)
    if len([l for l in "\n".join(code).splitlines() if l.strip() and not l.lstrip().startswith("#")]) != 5:
        fail("run-it", "the 'Run it' code block must have exactly five command lines")
    if not re.search(r"(?i)from clone to a working panel in \d+(\.\d+)? minutes? on a clean machine, with the image already loaded", run):
        fail("run-it", "the 'Run it' section must state the measured time: 'from clone to a working panel in N minutes on a clean machine, with the image already loaded'")

    # Technology bonuses: each bonus named, with where it is used and a file that exists.
    bonus = two.get("Technology bonuses", "")
    for name in BONUSES:
        row = next((l for l in bonus.splitlines() if l.startswith("|") and name in l.split("|")[1]), None)
        if row is None:
            fail("bonus", f"the 'Technology bonuses' table has no row for '{name}'")
            continue
        for path in re.findall(r"`([^`\s]+\.[A-Za-z]+|Dockerfile)`", row):
            if "/" in path or path in ("Dockerfile",) or path.endswith((".xml", ".yml")):
                if not os.path.exists(os.path.join(ROOT, path)):
                    fail("bonus", f"the row '{name}' names {path}, which does not exist")
    python_row = next((l for l in bonus.splitlines() if l.startswith("|") and "Embedded Python" in l.split("|")[1]), "")
    if "Language = python" not in python_row or "src/Readback/Demo/Generator.cls" not in python_row or "src/Readback/API/Flow.cls" not in python_row:
        fail("bonus", "the Embedded Python row must name the class with the Python methods and the class that calls it")
    elif not re.search(r"src/Readback/Demo/Generator\.cls", python_row) or "[ Language = python ]" not in open(os.path.join(ROOT, "src/Readback/Demo/Generator.cls"), encoding="utf-8").read():
        fail("bonus", "the class named for Embedded Python has no method with [ Language = python ]")
    elif "Generator" not in open(os.path.join(ROOT, "src/Readback/API/Flow.cls"), encoding="utf-8").read():
        fail("bonus", "the class named as the caller of the Python generator does not call it")

    # Feedback: the reports are linked, none is said to be pending.
    feedback = two.get("Feedback on AI Hub EAP", "")
    links = set(re.findall(r"intersystems-community/ai-hub-eap/issues/(\d+)", feedback)) - {"40"}
    if len(links) < FEEDBACK_ISSUES:
        fail("feedback", f"the feedback section links {len(links)} reported issues besides issue 40, it must link {FEEDBACK_ISSUES}")
    if re.search(r"(?i)no issue has been filed|none has been (filed|reported)", feedback):
        fail("feedback", "the feedback section still says that no issue has been filed")

    # Idea justification.
    idea = two.get("Idea DPI-I-689", "")
    if IDEA_URL not in idea or "Community Opportunity" not in idea:
        fail("idea", "the idea section needs the idea link and its status 'Community Opportunity'")

    # Author.
    if "Carlos Eduardo Dias Duarte" not in two.get("Author", ""):
        fail("author", "the author section must name Carlos Eduardo Dias Duarte")

    # 5. Pending markers only in the Fast path and the closing list, and the closing list has exactly two items.
    closing = two.get("Still to publish", "")
    if len(list_items(closing)) != 2:
        fail("pending", f"the closing list has {len(list_items(closing))} items, it must have exactly 2 (Open Exchange and the IPM package)")
    if not re.search(r"(?m)^- Video[^\n]*https://youtu\.be/[\w-]+", two.get("Fast path", "")):
        fail("pending", "the Fast path must link the video as https://youtu.be/...")
    allowed = two.get("Fast path", "") + closing
    if text.count(PENDING) != allowed.count(PENDING):
        fail("pending", f"'{PENDING}' appears outside the Fast path and the closing list")
    if text.count(PENDING) == 0:
        fail("pending", f"no '{PENDING}' marker: the unpublished links must be marked")

    # 6. Things that must never appear.
    if KEY_SHAPED.search(text):
        fail("secret", "something that looks like a key value is in the README")
    if "_SYSTEM" in text:
        fail("secret", "an administrator account name is in the README")
    if re.search(r"(?i)\bsix (axes|domains)\b", text):
        fail("claim", "the contest does not ask for 'six axes' or 'six domains'")
    if ALL_TO_HUMAN.search(text):
        fail("claim", "the README must never say that every error goes to a human")

    # 7. English only.
    for number, line in enumerate(text.splitlines(), 1):
        if PORTUGUESE_LETTERS.search(line) or PORTUGUESE_WORDS.search(line):
            fail("language", f"line {number} does not look English: {line.strip()[:70]}")
    return failures


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("readme", nargs="?", default=os.path.join(ROOT, "README.md"))
    parser.add_argument("--report", default=os.path.join(ROOT, "data", "eval", "report.json"))
    parser.add_argument("--print-tables", action="store_true")
    args = parser.parse_args(argv)
    report = load_report(args.report)
    if args.print_tables:
        for name in MODELS:
            print(f"#### {name}\n")
            model = report["models"][name]
            print("Final decision (route) against the expected decision:\n")
            print(matrix_table(model["matrixFinal"]) + "\n")
            print("Agent decision against the expected decision:\n")
            print(matrix_table(model["matrixAgent"]) + "\n")
            print(figure_lines(model) + "\n")
        print(f"### {KEY_FIGURES}\n")
        ablation = load_ablation(args.report)
        print("\n".join(key_figures(report, *load_companions(args.report), ablation)) + "\n")
        print(f"### {ABLATION_HEADING}\n")
        print("\n".join(ablation_lines(ablation)) + "\n")
        return 0
    if not os.path.exists(args.readme):
        print(f"check-readme: FAIL file: {args.readme} does not exist")
        return 1
    with open(args.readme, encoding="utf-8") as handle:
        text = handle.read()
    failures = check(text, report, *load_companions(args.report), load_ablation(args.report))
    for line in failures:
        print(line)
    if failures:
        return 1
    print("check-readme: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
