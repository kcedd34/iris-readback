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
    "Fast path", "Demo", "Required by the organizers", "What the production contains", "Results",
    "Idea DPI-I-689", "How it works", "Built with", "Author", "Still to publish",
]
REQUIRED_ITEMS = {
    "Early Access image and build": [IMAGE, "154"],
    "Load and rename the image": ["docker load", "docker tag"],
    "LLM provider and key variable": ["OpenAI", "OPENAI_API_KEY"],
    "Start and verify": ["docker compose up", "verify.sh"],
}
ACCOUNTS = ["communicator1", "communicator2", "observer"]
DEMO_URL = "http://109.123.244.170/"
IDEA_URL = "https://ideas.intersystems.com/ideas/DPI-I-689"

# Portuguese letters and words, written as escapes so that no Portuguese text sits in the repository.
PORTUGUESE_LETTERS = re.compile("[\u00e1\u00e0\u00e2\u00e3\u00e9\u00ea\u00ed\u00f3\u00f4\u00f5\u00fa\u00e7\u00c1\u00c0\u00c2\u00c3\u00c9\u00ca\u00cd\u00d3\u00d4\u00d5\u00da\u00c7]")
PORTUGUESE_WORDS = re.compile("(?i)\\b(n\u00e3o|para|uma|dos|das|voc\u00ea|tamb\u00e9m|s\u00e3o|ent\u00e3o|porque)\\b")
KEY_SHAPED = re.compile(r"(?m)sk-[A-Za-z0-9_-]{20,}|^\s*[A-Z_]*KEY\s*=\s*\S+")
ALL_TO_HUMAN = re.compile(r"(?i)\b(every|all)\s+(error|mistake|miss(ed)?(\s+critical)?)s?\b[^.]{0,60}\b(human|person|people)\b")


def load_report(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


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
    """The blocks, per model, that the README must contain character for character."""
    blocks = []
    for name in MODELS:
        model = report["models"][name]
        blocks.append((f"{name} final matrix", matrix_table(model["matrixFinal"])))
        blocks.append((f"{name} agent matrix", matrix_table(model["matrixAgent"])))
        blocks.append((f"{name} figures", figure_lines(model)))
    return blocks


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


def check(text, report):
    failures = []

    def fail(rule, what):
        failures.append(f"check-readme: FAIL {rule}: {what}")

    two, three, order = sections_of(text)

    # 1. The thesis is the first sentence after the title.
    body_lines = [l for l in text.splitlines() if l.strip()]
    first = next((l for l in body_lines if not l.startswith("#")), "")
    if not (re.search(r"(?i)\braise", first) and re.search(r"(?i)never (lower|downgrade)", first) and "read-back" in first.lower()):
        fail("thesis", "the first line after the title must say the agent can raise a critical, never lower it, and that nobody is notified without a read-back")

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
    for label, block in figure_blocks(report):
        if block not in text:
            fail("figures", f"the block '{label}' is missing or differs from data/eval/report.json (run check_readme.py --print-tables)")
    for name in MODELS:
        model = report["models"][name]
        if model["silencedCriticals"] != 0:
            fail("claim", f"the report shows {model['silencedCriticals']} silenced criticals for {name}; the README claims zero")
        if len(model["missedCriticals"]) != 2:
            fail("claim", f"the report shows {len(model['missedCriticals'])} residual criticals for {name}; the README says 2")
    results = two.get("Results", "")
    for needle in ("from 19 to 2", "from 7 to 2"):
        if needle not in results:
            fail("claim", f"the Results section must say '{needle}'")
    if not re.search(r"(?i)zero.{0,60}silenced|no .{0,60}silenced", results):
        fail("claim", "the Results section must say that no rule-critical result was silenced")
    if not re.search(r"(?i)generator", results) or not re.search(r"(?i)calibrat", results):
        fail("claim", "the Results section must say the delta limits were calibrated knowing the generator")

    # Idea justification.
    idea = two.get("Idea DPI-I-689", "")
    if IDEA_URL not in idea or "Community Opportunity" not in idea:
        fail("idea", "the idea section needs the idea link and its status 'Community Opportunity'")

    # Author.
    if "Carlos Eduardo Dias Duarte" not in two.get("Author", ""):
        fail("author", "the author section must name Carlos Eduardo Dias Duarte")

    # 5. Pending markers only in the Fast path and the closing list, and the closing list has exactly three items.
    closing = two.get("Still to publish", "")
    if len(list_items(closing)) != 3:
        fail("pending", f"the closing list has {len(list_items(closing))} items, it must have exactly 3")
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
        return 0
    if not os.path.exists(args.readme):
        print(f"check-readme: FAIL file: {args.readme} does not exist")
        return 1
    with open(args.readme, encoding="utf-8") as handle:
        text = handle.read()
    failures = check(text, report)
    for line in failures:
        print(line)
    if failures:
        return 1
    print("check-readme: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
