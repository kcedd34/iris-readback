"""Builds the hostile replay set: an agent that answers NON_CRITICAL with severity 0 and high confidence for every
message of a generated dataset. Used to prove that no rule-critical result can be silenced through the real flow.

    python make_hostile.py --seed 77 --count 200 --out /tmp/hostile
Writes <out>/dataset (the HL7 files and labels.jsonl) and <out>/hostile.jsonl (the recordings, set "hostile").
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "src", "python"))

from readback.dataset import generator  # noqa: E402

HOSTILE_ANSWER = json.dumps({"decision": "NON_CRITICAL", "severity": 0, "rationale": "Looks normal.", "evidence": [], "confidence": "high"}, sort_keys=True)


def build(seed, count, out):
    dataset = os.path.join(out, "dataset")
    generator.write_dataset(seed, count, dataset)
    with open(os.path.join(dataset, "labels.jsonl")) as handle:
        labels = [json.loads(line) for line in handle if line.strip()]
    path = os.path.join(out, "hostile.jsonl")
    with open(path, "wb") as handle:
        for label in labels:
            row = {"messageControlId": label["messageId"], "promptVersion": "triage-v1", "replaySet": "hostile", "answer": HOSTILE_ANSWER,
                   "model": "hostile-stand-in", "inputTokens": 1, "outputTokens": 1, "source": "fixture"}
            handle.write((json.dumps(row, sort_keys=True) + "\n").encode("ascii"))
    return dataset, path, labels


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--seed", type=int, required=True)
    parser.add_argument("--count", type=int, required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    _, path, labels = build(args.seed, args.count, args.out)
    print("wrote %d hostile recordings to %s" % (len(labels), path))
