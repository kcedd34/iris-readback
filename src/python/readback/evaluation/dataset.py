"""The evaluation dataset: synthetic lab results with the decision a clinician following the policy expects.

    python -m readback.evaluation.dataset --out data/eval

Writes dataset.jsonl (one row per message) and DATASET.md (the construction rules). The expected decision of a case
is assigned by the construction rules below, never by a model. The same seed always gives the same file.
"""
import argparse
import json
import os
import sys

from readback.dataset import categories as cat
from readback.dataset import generator

SEED = 2026
PER_CATEGORY = 30

# category -> (what the builder produces, the expected decision, the policy passages the rule rests on)
RULES = (
    (cat.CLEAR_CRITICAL, "a value beyond a critical limit", "CRITICAL", "crit-potassium, crit-glucose, crit-hemoglobin, crit-sodium"),
    (cat.CONTEXTUAL_CRITICAL, "a value at 93 to 99% of the critical limit after a normal earlier result of the same patient",
     "CRITICAL", "ctx-earlier-results (a large change matters more than the absolute value), ctx-acute-drop for hemoglobin"),
    (cat.EXPLAINABLE_FALSE_CRITICAL, "potassium at or above 6.5 mmol/L with stable high earlier results (scheduled dialysis)",
     "CRITICAL", "ctx-dialysis-stable, review-agent-never-lowers"),
    (cat.ACUTE_DROP_IN_RANGE, "hemoglobin inside the critical limit, more than 3 g/dL below an earlier result of the last 24 hours",
     "CRITICAL", "ctx-acute-drop"),
    (cat.SAMPLE_PROBLEM, "critical potassium with a hemolysis index above 100", "CRITICAL",
     "recollect-communicate-anyway, recollect-indices"),
    (cat.RECOLLECT, "potassium 5.5 to 6.3 mmol/L (not critical) with a hemolysis index above 150", "RECOLLECT", "recollect-hemolysis"),
    (cat.AMBIGUOUS, "potassium 6.2 to 6.4 mmol/L (below the critical limit), elevated earlier results, hemolysis index 70 to 99",
     "NEEDS_REVIEW", "review-ambiguous"),
    (cat.NORMAL, "a value inside the normal range, no sample flags, no earlier results", "NON_CRITICAL", "no rule fires"),
)


def build(seed=SEED, per_category=PER_CATEGORY):
    """Returns the dataset rows: history before the subject it explains, 8 * per_category subject rows."""
    items = generator.generate(seed, per_category * len(cat.EVALUATION_CATEGORIES), profile="evaluation")
    rows = []
    for message_id, text, label in items:
        rows.append({
            "messageId": message_id,
            "role": label["role"],
            "patientId": label["patientId"],
            "category": label["category"],
            "expected": label["expected"],
            "seed": seed,
            "text": text,
        })
    return rows


def write(path, seed=SEED, per_category=PER_CATEGORY):
    rows = build(seed, per_category)
    with open(path, "wb") as handle:
        for row in rows:
            handle.write((json.dumps(row, sort_keys=True) + "\n").encode("ascii"))
    return len(rows)


def description(seed=SEED, per_category=PER_CATEGORY):
    lines = [
        "# Evaluation dataset",
        "",
        "Synthetic lab results for the evaluation of the triage agent. Every identifier is synthetic. The file `dataset.jsonl` has one JSON",
        "object per message: `messageId`, `role` (`subject` or `history`), `patientId`, `category`, `expected`, `seed` and `text` (the HL7 message).",
        "",
        "Seed {}, {} subject cases per category, {} subject cases in all; the history messages that a case needs come before it.".format(
            seed, per_category, per_category * len(cat.EVALUATION_CATEGORIES)),
        "",
        "## How the expected decision is assigned",
        "",
        "By the construction rules in this table, which rest on the synthetic policy passages in `data/policy/passages.jsonl`. It is never assigned",
        "by a model. A result critical by the rule table is expected CRITICAL whatever the sample quality or the history says, because the",
        "agent can never lower it (P-1 and P-2).",
        "",
        "| Category | How a case is built | Expected | Policy passages |",
        "|---|---|---|---|",
    ]
    for name, built, expected, passages in RULES:
        lines.append("| {} | {} | {} | {} |".format(name, built, expected, passages))
    lines += [
        "",
        "## Limits of the labels",
        "",
        "The labels come from one author reading the policy; there was no second annotator. The contextual-critical rule is the most open to",
        "disagreement: the policy says a large change matters more than the absolute value, and the rule turns that into CRITICAL. The history",
        "messages carry no expected decision and are not part of the matrices; they are processed and counted in cost and latency.",
        "",
    ]
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Write the evaluation dataset and its description.")
    parser.add_argument("--out", required=True, help="output directory (data/eval)")
    parser.add_argument("--seed", type=int, default=SEED)
    parser.add_argument("--per-category", type=int, default=PER_CATEGORY)
    args = parser.parse_args(argv)
    os.makedirs(args.out, exist_ok=True)
    count = write(os.path.join(args.out, "dataset.jsonl"), args.seed, args.per_category)
    with open(os.path.join(args.out, "DATASET.md"), "w") as handle:
        handle.write(description(args.seed, args.per_category))
    print("wrote {} rows and DATASET.md to {}".format(count, args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
