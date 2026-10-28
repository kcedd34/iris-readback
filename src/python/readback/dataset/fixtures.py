"""Deterministic replay fixtures for the synthetic dataset.

Reads a labels.jsonl and the .hl7 files next to it and writes one recording per message: the answer the agent
would plausibly give for that category, in the closed decision schema. These are hand-authored stand-ins,
labeled source "fixture", not recordings of a real provider. They are provisional: the evaluation feature
replaces them with real recorded answers once an evaluation has been run with a key. They cite policy passages
of data/policy/passages.jsonl by identifier, and a test checks that each cited identifier exists.

    python -m readback.dataset.fixtures --labels data/samples/generated/labels.jsonl --out data/replay/recordings.jsonl
"""
import argparse
import json
import os
import sys

from readback.dataset import categories as cat

PROMPT_VERSION = "triage-v2"
MODEL = "fixture"
INPUT_TOKENS = 120
OUTPUT_TOKENS = 40


def _segments(path):
    with open(path, "rb") as handle:
        return handle.read().decode("ascii").rstrip("\r").split("\r")


def _first_obx_value(path):
    for segment in _segments(path):
        if segment.startswith("OBX|1|"):
            return segment.split("|")[5]
    raise ValueError("no OBX|1 in " + path)


def _hemolysis_index(path):
    for segment in _segments(path):
        if segment.startswith("OBX|") and "HEMOLYSIS_INDEX" in segment:
            return segment.split("|")[5]
    return None


def answer(decision, severity, rationale, evidence, confidence):
    """The answer text exactly as a provider with strict structured output would return it."""
    text = {"decision": decision, "severity": severity, "rationale": rationale, "evidence": evidence, "confidence": confidence}
    assert len(rationale) <= 400
    return json.dumps(text, sort_keys=True)


def crit_passage(analyte):
    """The identifier of the policy passage that holds the critical limits of an analyte."""
    return {"2823-3": "crit-potassium", "2345-7": "crit-glucose", "718-7": "crit-hemoglobin", "2951-2": "crit-sodium"}[cat.ANALYTES[analyte]["code"]]


def for_subject(category, analyte, value, earlier, hemolysis):
    """The fixture answer of a subject case. earlier is a list of earlier values, newest first."""
    if category == cat.CLEAR_CRITICAL:
        return answer("CRITICAL", 3, "The value %s is beyond the critical limit and nothing earlier explains it." % value, ["current-result", crit_passage(analyte)], "high")
    if category == cat.CONTEXTUAL_CRITICAL:
        prior = earlier[0] if earlier else "unknown"
        return answer("CRITICAL", 3, "The value %s is close to the critical limit and moved from a normal earlier result of %s." % (value, prior), ["current-result", "earlier-result-1", crit_passage(analyte)], "medium")
    if category == cat.EXPLAINABLE_FALSE_CRITICAL:
        shown = ", ".join(earlier[:3]) if earlier else "none"
        return answer("NON_CRITICAL", 0, "The value %s is high but stable across the earlier results (%s); the note describes scheduled dialysis." % (value, shown), ["current-result", "earlier-result-1", "earlier-result-2", "earlier-result-3"][:1 + len(earlier[:3])] + ["ctx-dialysis-stable"], "high")
    if category == cat.ACUTE_DROP_IN_RANGE:
        prior = earlier[0] if earlier else "unknown"
        return answer("CRITICAL", 3, "Hemoglobin fell from %s to %s since the earlier result, an acute drop even though %s is inside the critical limit." % (prior, value, value), ["current-result", "earlier-result-1", "ctx-acute-drop"], "high")
    if category == cat.SAMPLE_PROBLEM:
        return answer("RECOLLECT", 1, "Potassium %s comes with a hemolysis index of %s, which can raise potassium in the tube; a new sample is advised." % (value, hemolysis), ["current-result", "sample-index-hemolysis", "recollect-hemolysis"], "medium")
    if category == cat.AMBIGUOUS:
        return answer("NEEDS_REVIEW", 1, "The value %s is near the limit with a moderate hemolysis index (%s) and a mildly high earlier result; a person should decide." % (value, hemolysis), ["current-result", "sample-index-hemolysis", "review-ambiguous"], "low")
    raise ValueError("unknown category " + category)


def for_history(value):
    return answer("NON_CRITICAL", 0, "The earlier result %s is within the expected range for this analyte." % value, ["current-result"], "high")


def row(message_id, text):
    return {"messageControlId": message_id, "promptVersion": PROMPT_VERSION, "replaySet": "default", "answer": text,
            "model": MODEL, "inputTokens": INPUT_TOKENS, "outputTokens": OUTPUT_TOKENS, "source": "fixture"}


def build(labels_path):
    """Recordings for every message of a generated dataset, in the order of the labels file."""
    base = os.path.dirname(labels_path)
    with open(labels_path, "rb") as handle:
        labels = [json.loads(line) for line in handle.read().decode().splitlines() if line.strip()]
    # Earlier values per patient: the history messages written for the same subject, newest first.
    history = {}
    for label in labels:
        if label["role"] == "history":
            history.setdefault(label["patientId"], []).append((label["messageId"], _first_obx_value(os.path.join(base, label["file"]))))
    rows = []
    for label in labels:
        path = os.path.join(base, label["file"])
        value = _first_obx_value(path)
        if label["role"] == "history":
            rows.append(row(label["messageId"], for_history(value)))
            continue
        earlier = [v for _, v in sorted(history.get(label["patientId"], []), key=lambda item: item[0])]
        rows.append(row(label["messageId"], for_subject(label["category"], label["analyte"], value, earlier, _hemolysis_index(path))))
    return rows


def hand_samples():
    """Fixtures for the two hand-written sample messages in data/samples."""
    return [
        row("RBSAMPLE0001", answer("CRITICAL", 3, "Potassium 6.9 mmol/L is above the critical limit and there is no earlier result.", ["current-result", "crit-potassium"], "high")),
        row("RBSAMPLE0002", answer("NEEDS_REVIEW", 1, "Hemoglobin 8.1 g/dL is inside the critical limit and there are no earlier results to compare with.", ["current-result", "review-ambiguous"], "low")),
    ]


def write(rows, out_path):
    with open(out_path, "wb") as handle:
        for item in rows:
            handle.write((json.dumps(item, sort_keys=True) + "\n").encode("ascii"))


def main(argv=None):
    parser = argparse.ArgumentParser(description="Write deterministic replay fixtures for a generated dataset.")
    parser.add_argument("--labels", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--with-samples", action="store_true", help="also add fixtures for the hand-written samples")
    args = parser.parse_args(argv)
    rows = build(args.labels)
    if args.with_samples:
        rows += hand_samples()
    write(rows, args.out)
    print("wrote {} recordings to {}".format(len(rows), args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
