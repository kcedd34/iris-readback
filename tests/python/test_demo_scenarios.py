"""The demo scenarios a visitor can submit: every file exists, the subject is last and is a result, and the subject has
a recorded answer in the default replay set, so the public demo needs no key."""
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SAMPLES = os.path.join(ROOT, "data", "samples")
EXPECTED = {"CRITICAL", "NEEDS_REVIEW", "NON_CRITICAL", "RECOLLECT"}


def scenarios():
    with open(os.path.join(SAMPLES, "demo-scenarios.json")) as handle:
        return json.load(handle)["scenarios"]


def read(name):
    with open(os.path.join(SAMPLES, name), newline="") as handle:
        return handle.read().replace("\r\n", "\r").replace("\n", "\r")


def control_id(text):
    return text.split("\r")[0].split("|")[9]


def test_ids_are_unique_and_plain():
    ids = [s["id"] for s in scenarios()]
    assert len(ids) == len(set(ids))
    assert all(i.replace("-", "").isalnum() and i == i.lower() for i in ids)


def test_every_file_exists_and_names_a_plain_path():
    for scenario in scenarios():
        assert scenario["files"], scenario["id"]
        for name in scenario["files"]:
            assert ".." not in name and "\\" not in name
            assert name.count("/") <= 1 and (name.count("/") == 0 or name.split("/")[0] in ("generated", "demo")), name
            assert os.path.isfile(os.path.join(SAMPLES, name)), name


def test_labels_and_expected_are_english_and_known():
    for scenario in scenarios():
        assert scenario["label"] and scenario["label"].isascii()
        assert scenario["expected"] in EXPECTED, scenario["id"]
        assert scenario["analyte"].isalpha()


def test_the_subject_is_last_a_result_and_recorded():
    recorded = set()
    with open(os.path.join(ROOT, "data", "replay", "recordings.jsonl")) as handle:
        for line in handle:
            row = json.loads(line)
            if row["replaySet"] == "default":
                recorded.add(row["messageControlId"])
    for scenario in scenarios():
        texts = [read(name) for name in scenario["files"]]
        subject = texts[-1]
        assert "ORU^R01" in subject.split("\r")[0], scenario["id"]
        assert "OBX|" in subject, scenario["id"]
        assert control_id(subject) in recorded, "no recording for %s" % scenario["id"]
        # earlier results come first: their collection time is before the subject's
        times = [text.split("\r")[2].split("|")[7] for text in texts]
        assert times == sorted(times), "earlier results must come first in %s" % scenario["id"]
        # one patient per scenario
        patients = {text.split("\r")[1].split("|")[3] for text in texts}
        assert len(patients) == 1, scenario["id"]


def test_one_scenario_shows_the_floor_holding_the_agent():
    """The public demo must be able to show the held seal: the subject is critical by the rule table, and the recorded answer of
    the agent is below critical, so the floor policy refuses it."""
    scenario = next(s for s in scenarios() if s["id"] == "potassium-agent-tries-to-lower")
    subject = read(scenario["files"][-1])
    value = float(subject.split("\r")[3].split("|")[5])
    with open(os.path.join(ROOT, "data", "config", "critical-ranges.json")) as handle:
        limit = next(r["criticalHigh"] for r in json.load(handle)["ranges"] if r["analyteCode"] == "2823-3" and r["ageGroup"] == "adult")
    assert value >= limit, "the subject must be critical by value"
    with open(os.path.join(ROOT, "data", "replay", "recordings.jsonl")) as handle:
        rows = [json.loads(l) for l in handle]
    row = next(r for r in rows if r["replaySet"] == "default" and r["messageControlId"] == control_id(subject))
    assert json.loads(row["answer"])["severity"] < 3, "the recorded agent must answer below critical"
    assert scenario["expected"] == "CRITICAL"


def test_the_demo_sequence_includes_that_scenario():
    source = open(os.path.join(ROOT, "frontend", "src", "flow", "DemoSequence.tsx"), encoding="utf-8").read()
    assert "potassium-agent-tries-to-lower" in source
