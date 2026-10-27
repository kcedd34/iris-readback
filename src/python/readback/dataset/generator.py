"""Deterministic generator of labeled synthetic HL7 ORU^R01 lab results.

    python -m readback.dataset.generator --seed 7 --count 200 --out ./out

Writes one .hl7 file per message and a labels.jsonl. The same seed and count always produce
byte-identical output. Every value is synthetic. --count counts subject cases; cases that need
history also write earlier results for the same patient, marked role "history" in the labels.
"""
import argparse
import datetime
import json
import os
import random
import re
import sys

from readback.dataset import categories as cat

MIN_COUNT, MAX_COUNT = 1, 10000
BASE_TIME = datetime.datetime(2026, 3, 1, 8, 0, 0)

# Formats of real identifiers that must never appear in generated output.
REAL_IDENTIFIER_PATTERNS = (
    re.compile(r"\b\d{3}\.\d{3}\.\d{3}-\d{2}\b"),  # Brazilian taxpayer number, formatted
    re.compile(r"\b\d{11}\b"),  # 11 digits in a row, unformatted taxpayer or similar
    re.compile(r"\b\d{3}-\d{2}-\d{4}\b"),  # US social security number
    re.compile(r"\b\d{10}\b"),  # 10 digits in a row, provider identifier or similar
    re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+"),  # e-mail address
    re.compile(r"\(\d{2,3}\)\s?\d{4,5}-\d{4}"),  # phone number
)


def contains_real_identifier(text):
    """True when text contains something shaped like a real identifier."""
    return any(pattern.search(text) for pattern in REAL_IDENTIFIER_PATTERNS)


def _hl7_time(moment):
    return moment.strftime("%Y%m%d%H%M%S")


def _flag(spec, value):
    if value >= spec["crit_high"]:
        return "HH"
    if value <= spec["crit_low"]:
        return "LL"
    if value > spec["high"]:
        return "H"
    if value < spec["low"]:
        return "L"
    return "N"


def _format_value(spec, value):
    return "{:.{}f}".format(value, spec["decimals"])


def render_message(message_id, patient_number, analyte, value, collected, indices, note, sent):
    """Builds one ORU^R01 as text with carriage-return segment separators."""
    spec = cat.ANALYTES[analyte]
    patient_id = "SYN{:07d}".format(patient_number)
    range_text = "{}-{}".format(spec["low"], spec["high"])
    code = "{}^{}^LN".format(spec["code"], spec["name"])
    segments = [
        "MSH|^~\\&|SYNLAB|SYNFAC|READBACK|SYNFAC|{}||ORU^R01|{}|P|2.5".format(_hl7_time(sent), message_id),
        "PID|1||{}^^^SYN^MR||SYNTHETIC^PATIENT{}||19{:02d}0101|{}".format(patient_id, patient_number, 40 + patient_number % 50, "FM"[patient_number % 2]),
        "OBR|1|||{}|||{}".format(code, _hl7_time(collected)),
        "OBX|1|NM|{}||{}|{}|{}|{}|||F".format(code, _format_value(spec, value), spec["unit"], range_text, _flag(spec, value)),
    ]
    for number, (index_code, index_value) in enumerate(sorted(indices.items()), start=2):
        segments.append("OBX|{}|NM|{}^{}^L||{}|index||||F".format(number, index_code, index_code.replace("_", " ").capitalize(), index_value))
    if note:
        segments.append("NTE|1||{}".format(note))
    return "\r".join(segments) + "\r"


def generate(seed, count):
    """Returns a list of (message_id, text, label) tuples, deterministic for (seed, count)."""
    rng = random.Random(seed)
    out = []
    for index in range(count):
        category = cat.CATEGORIES[index % len(cat.CATEGORIES)]
        builder, analytes = cat.BUILDERS[category]
        case = builder(rng, analytes[rng.randrange(len(analytes))])
        number = index + 1
        subject_time = BASE_TIME + datetime.timedelta(minutes=7 * index)
        collected = subject_time - datetime.timedelta(minutes=10)
        for step, (hours_before, old_value) in enumerate(case.history, start=1):
            history_id = "RB{}-{:05d}H{}".format(seed, number, step)
            old_collected = collected - datetime.timedelta(hours=hours_before)
            text = render_message(history_id, number, case.analyte, old_value, old_collected, {}, "", old_collected + datetime.timedelta(minutes=10))
            out.append((history_id, text, _label(history_id, case, seed, number, "history")))
        message_id = "RB{}-{:05d}".format(seed, number)
        text = render_message(message_id, number, case.analyte, case.value, collected, case.indices, case.note, subject_time)
        out.append((message_id, text, _label(message_id, case, seed, number, "subject")))
    for _, text, _ in out:
        if contains_real_identifier(text):
            raise ValueError("generated text matches a real identifier pattern")
    return out


def _label(message_id, case, seed, number, role):
    return {
        "messageId": message_id,
        "category": case.category,
        "seed": seed,
        "file": message_id + ".hl7",
        "role": role,
        "patientId": "SYN{:07d}".format(number),
        "analyte": case.analyte,
    }


def write_dataset(seed, count, out_dir):
    items = generate(seed, count)
    os.makedirs(out_dir, exist_ok=True)
    for message_id, text, _ in items:
        with open(os.path.join(out_dir, message_id + ".hl7"), "wb") as handle:
            handle.write(text.encode("ascii"))
    with open(os.path.join(out_dir, "labels.jsonl"), "wb") as handle:
        for _, _, label in items:
            handle.write((json.dumps(label, sort_keys=True) + "\n").encode("ascii"))
    return len(items)


def main(argv=None):
    parser = argparse.ArgumentParser(description="Generate labeled synthetic HL7 ORU^R01 lab results.")
    parser.add_argument("--seed", type=int, required=True, help="seed for the random generator")
    parser.add_argument("--count", type=int, required=True, help="number of subject cases, {} to {}".format(MIN_COUNT, MAX_COUNT))
    parser.add_argument("--out", required=True, help="output directory")
    args = parser.parse_args(argv)
    if not MIN_COUNT <= args.count <= MAX_COUNT:
        print("error: --count must be between {} and {}, got {}".format(MIN_COUNT, MAX_COUNT, args.count), file=sys.stderr)
        return 2
    written = write_dataset(args.seed, args.count, args.out)
    print("wrote {} messages and labels.jsonl to {}".format(written, args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
