"""The ablation: which layer of the product catches what, measured by replaying the recorded answers, with no provider call.

    python -m readback.evaluation.ablation --out data/eval/ablation.json

Five arrangements of the same layers, for each recorded model, over the 240 subject cases of the evaluation dataset:

    value          the critical-range rule only: floor 3 goes to read-back, everything else is released
    valueGuard     the range rule and the release guard: floor 3 goes to read-back, a release the guard holds goes to a person, the rest is released
    agent          the range rule, the release guard and the agent with its tools, without the change (delta) rule
    deterministic  the range rule, the change rule and the release guard, without the agent (everything deterministic)
    full           the product: range rule, change rule, agent with tools, composition, release guard

and one more row of `agent`, measured in a paid run in which the change tool gave the agent the earlier values and the variation but
neither the rule's verdict nor its limit (`agentWithoutVerdict`, src/Readback/Eval/NoVerdictTools.cls).

The layers are the product's own, restated here from the same configuration files (data/config) and the recorded answers
(data/replay/recordings.jsonl): the floor (Readback.Triage.Floor), the change rule (Readback.Triage.Delta), the answer check
(Readback.Triage.AgentOutput, Readback.Governance.Evidence, Readback.Governance.FloorPolicy), the release guard and the
composition (Readback.Triage.Composer). The arrangement `full` is checked against the confusion matrix of the report
(data/eval/report.json): it must give the same final decision for every case, so the restatement cannot drift from the product.

The agent was recorded with the change tool available, so its answers in `agent` saw the verdict of the change rule as information;
what is removed there is the rule's power to raise the floor, not the information. The "rules only" arrangements have no agent and no
review route: a result is either critical by rule or released, which is what a plain rule-based system does.
"""
import argparse
import datetime
import hashlib
import json
import os
import sys

from readback.evaluation import report as rep

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
DECISIONS = ("CRITICAL", "RECOLLECT", "NEEDS_REVIEW", "NON_CRITICAL")
CONFIDENCES = ("low", "medium", "high")
FIELDS = ("decision", "severity", "rationale", "evidence", "confidence")
RATIONALE_MAX = 400
GLUCOSE_MGDL_TO_MMOLL = 1 / 18.0156
ARRANGEMENTS = ("value", "valueGuard", "agent", "deterministic", "full")
NO_VERDICT_RECORDINGS = "data/eval/ablation-no-verdict.jsonl"


def _read_json(path):
    with open(os.path.join(ROOT, path)) as handle:
        return json.load(handle)


def _read_jsonl(path):
    with open(os.path.join(ROOT, path)) as handle:
        return [json.loads(line) for line in handle if line.strip()]


def sha(path):
    with open(os.path.join(ROOT, path), "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()[:16]


# ---- the case, read from the HL7 text the way the normalizer reads it

def parse_case(row):
    segments = [s.split("|") for s in row["text"].split("\r") if s]
    case = {"id": row["messageId"], "role": row["role"], "category": row["category"], "expected": row["expected"], "indices": []}
    seen = False
    for f in segments:
        if f[0] == "PID" and "patient" not in case:
            case["patient"], case["birth"] = f[3].split("^")[0], f[7]
        elif f[0] == "OBR" and "collected" not in case:
            case["collected"] = datetime.datetime.strptime(f[7][:14], "%Y%m%d%H%M%S")
        elif f[0] == "OBX":
            code, value = f[3].split("^")[0], f[5]
            if code in ("HEMOLYSIS_INDEX", "LIPEMIA_INDEX", "ICTERUS_INDEX"):
                case["indices"].append((code, value))
            elif not seen:
                seen = True
                case.update(code=code, text=value, unit=f[6])
    born = datetime.datetime.strptime(case["birth"], "%Y%m%d")
    when = case["collected"]
    case["age"] = when.year - born.year - ((when.month, when.day) < (born.month, born.day))
    value = float(case["text"])
    case["value"] = value
    if case["code"] == "2345-7" and case["unit"] == "mg/dL":
        case["effective"], case["unit_effective"], case["factor"] = value * GLUCOSE_MGDL_TO_MMOLL, "mmol/L", GLUCOSE_MGDL_TO_MMOLL
    else:
        case["effective"], case["unit_effective"], case["factor"] = value, case["unit"], 1.0
    return case


def age_group(age):
    return "neonate" if age < 1 else "child" if age < 18 else "adult"


def range_row(ranges, case):
    group = age_group(case["age"])
    for wanted in (group, "adult"):
        for r in ranges:
            if (r["analyteCode"], r["unit"], r["ageGroup"]) == (case["code"], case["unit_effective"], wanted):
                return r
    return None


def value_floor(ranges, case):
    r = range_row(ranges, case)
    if r is None:
        return 0
    v = case["effective"]
    if (r.get("criticalLow") is not None and v <= r["criticalLow"]) or (r.get("criticalHigh") is not None and v >= r["criticalHigh"]):
        return r["floorSeverity"]
    return 0


def delta_floor(rules, cases, case):
    rule = next((r for r in rules if r["analyteCode"] == case["code"]), None)
    if rule is None or case["unit_effective"] != rule["unit"] or case["value"] == 0:
        return 0
    start = case["collected"] - datetime.timedelta(hours=rule["windowHours"])
    best = None
    for other in cases:
        if other["id"] == case["id"] or other.get("patient") != case["patient"] or other["code"] != case["code"] or other["unit"] != case["unit"]:
            continue
        if not (start <= other["collected"] < case["collected"]):
            continue
        change = (case["value"] - other["value"]) * case["factor"]
        magnitude = -change if rule["direction"] == "fall" else change if rule["direction"] == "rise" else abs(change)
        best = magnitude if best is None or magnitude > best else best
    return rule["floorSeverity"] if best is not None and best > rule["maxChange"] else 0


def release_guard_holds(ranges, guard, case, floor):
    """The release guard on a case whose floor is zero: a sample index above its limit, an index that is not a number, or a value in the borderline band."""
    if floor > 0:
        return True
    for code, value in case["indices"]:
        try:
            number = float(value)
        except ValueError:
            return True
        for limit in guard["sampleQualityLimits"]:
            if limit["code"] == code and number > limit["limit"]:
                return True
    r = range_row(ranges, case)
    if r is None:
        return False
    v, fraction = case["effective"], guard["borderlineFraction"]
    if r.get("criticalHigh") is not None and v >= r["criticalHigh"] * fraction:
        return True
    if r.get("criticalLow") is not None and v <= r["criticalLow"] / fraction:
        return True
    return False


# ---- the agent's recorded answer, checked as the product checks it

def returned_ids(calls):
    ids = set()

    def walk(node):
        if isinstance(node, list):
            for item in node:
                walk(item)
        elif isinstance(node, dict):
            for key, value in node.items():
                if isinstance(value, (dict, list)):
                    walk(value)
                elif key == "id" and value:
                    ids.add(value)
    for call in calls:
        if call.get("status") == "ok":
            try:
                walk(json.loads(call["result"]))
            except (ValueError, KeyError):
                pass
    return ids


def agent_answer(recording):
    """(decision, severity, failure kind) of one recorded answer; the decision is None when there is no usable answer."""
    if recording is None:
        return None, 0, "no-recorded-answer"
    if recording.get("failureKind"):
        return None, 0, recording["failureKind"]
    text = (recording.get("answer") or "").strip()
    if not text:
        return None, 0, "empty-or-refused"
    try:
        obj = json.loads(text)
    except ValueError:
        return None, 0, "schema-invalid"
    if not isinstance(obj, dict) or set(obj) != set(FIELDS):
        return None, 0, "schema-invalid"
    severity = obj["severity"]
    if (obj["decision"] not in DECISIONS or isinstance(severity, bool) or not isinstance(severity, (int, float)) or severity != int(severity)
            or not 0 <= severity <= 3 or not isinstance(obj["rationale"], str) or len(obj["rationale"]) > RATIONALE_MAX
            or not isinstance(obj["evidence"], list) or not all(isinstance(e, str) for e in obj["evidence"])
            or obj["confidence"] not in CONFIDENCES):
        return None, 0, "schema-invalid"
    allowed = returned_ids(recording.get("toolCalls") or []) | {"current-result"}
    if any(e not in allowed for e in obj["evidence"]):
        return None, 0, "evidence-not-from-tools"
    kind = "low-confidence" if obj["confidence"] == "low" else ""
    return obj["decision"], int(severity), kind


def compose(floor, decision, severity, kind, guard_holds):
    """Readback.Triage.Pipeline.Decide and Readback.Triage.Composer.Compose on one case; returns the route."""
    usable = decision is not None
    if usable and kind == "" and decision == "NON_CRITICAL" and floor == 0 and severity == 0 and guard_holds:
        kind = "release-guard"
    final = max(floor, severity if usable else 0)
    if final == 3:
        return "readback"
    failed = (not usable) or kind != ""
    if failed and not usable:
        return "review"
    if decision == "CRITICAL" and severity < 3:
        return "review"
    if final in (1, 2):
        return "review"
    if decision == "NEEDS_REVIEW":
        return "review"
    if failed:
        return "review"
    if decision == "RECOLLECT" and floor < 3:
        return "recollect"
    if final == 0 and decision == "NON_CRITICAL":
        return "release"
    return "review"


# ---- the arrangements

def route_for(arrangement, floors, recording, guard_holds):
    value, delta = floors
    if arrangement == "value":
        return "readback" if value >= 3 else "release"
    if arrangement == "valueGuard":
        return "readback" if value >= 3 else "review" if guard_holds(value) else "release"
    if arrangement == "deterministic":
        floor = max(value, delta)
        return "readback" if floor >= 3 else "review" if guard_holds(floor) else "release"
    floor = max(value, delta) if arrangement == "full" else value
    decision, severity, kind = agent_answer(recording)
    return compose(floor, decision, severity, kind, guard_holds(floor))


def summarize(rows):
    """rows: (case, value floor, route) of every subject case."""
    contextual = [r for r in rows if r[0]["expected"] == "CRITICAL" and r[1] < 3]
    out = {
        "contextualCriticals": {"cases": len(contextual)},
        "silencedCriticals": sum(1 for c, v, route in rows if v >= 3 and route != "readback"),
        "falseCriticals": sum(1 for c, v, route in rows if c["expected"] != "CRITICAL" and route == "readback"),
        "reviewRate": round(sum(1 for r in rows if r[2] == "review") / len(rows), 6),
        "recollectRate": round(sum(1 for r in rows if r[2] == "recollect") / len(rows), 6),
    }
    for route in ("readback", "review", "recollect", "release"):
        out["contextualCriticals"][route] = sum(1 for r in contextual if r[2] == route)
    out["contextualCriticals"]["released"] = out["contextualCriticals"].pop("release")
    out["uncertainReleased"] = sum(1 for c, v, route in rows if c["expected"] in ("RECOLLECT", "NEEDS_REVIEW") and route == "release")
    out["uncertainCases"] = sum(1 for c, v, route in rows if c["expected"] in ("RECOLLECT", "NEEDS_REVIEW"))
    out["releasedAnyCritical"] = sum(1 for c, v, route in rows if c["expected"] == "CRITICAL" and route == "release")
    return out


def agent_alone(subjects, floors, recordings):
    """What the agent said on its own, before the composition, on the cases the range rule does not catch: how many it called critical (severity 3)."""
    contextual = [c for c in subjects if c["expected"] == "CRITICAL" and floors[c["id"]][0] < 3]
    out = {"cases": len(contextual), "criticalAnswers": 0, "byCategory": {}}
    for c in contextual:
        decision, severity, _ = agent_answer(recordings.get(c["id"]))
        hit = decision == "CRITICAL" and severity == 3
        out["criticalAnswers"] += hit
        tally = out["byCategory"].setdefault(c["category"], {"cases": 0, "criticalAnswers": 0})
        tally["cases"] += 1
        tally["criticalAnswers"] += hit
    return out


def run(root_files=None):
    dataset = _read_jsonl("data/eval/dataset.jsonl")
    cases = [parse_case(r) for r in dataset]
    subjects = [c for c in cases if c["role"] == "subject"]
    ranges = _read_json("data/config/critical-ranges.json")["ranges"]
    rules = _read_json("data/config/delta-rules.json")["rules"]
    guard = _read_json("data/config/release-guard.json")
    floors = {c["id"]: (value_floor(ranges, c), delta_floor(rules, cases, c)) for c in subjects}
    recordings = {}
    for r in _read_jsonl("data/replay/recordings.jsonl"):
        recordings.setdefault(r["model"], {})[r["messageControlId"]] = r
    no_verdict = {}
    if os.path.exists(os.path.join(ROOT, NO_VERDICT_RECORDINGS)):
        for r in _read_jsonl(NO_VERDICT_RECORDINGS):
            no_verdict.setdefault(r["model"], {})[r["messageControlId"]] = r
    result = {}
    without_verdict = {}
    final_routes = {}
    for model in sorted(recordings):
        result[model] = {}
        for arrangement in ARRANGEMENTS:
            table = []
            for c in subjects:
                route = route_for(arrangement, floors[c["id"]], recordings[model].get(c["id"]),
                                  lambda floor, c=c: release_guard_holds(ranges, guard, c, floor))
                table.append((c, floors[c["id"]][0], route))
            result[model][arrangement] = summarize(table)
            if arrangement == "agent":
                result[model][arrangement]["agentAlone"] = agent_alone(subjects, floors, recordings[model])
            if arrangement == "full":
                final_routes[model] = {c["id"]: route for c, _, route in table}
        if model in no_verdict:
            table = []
            for c in subjects:
                route = route_for("agent", floors[c["id"]], no_verdict[model].get(c["id"]),
                                  lambda floor, c=c: release_guard_holds(ranges, guard, c, floor))
                table.append((c, floors[c["id"]][0], route))
            without_verdict[model] = summarize(table)
            without_verdict[model]["agentAlone"] = agent_alone(subjects, floors, no_verdict[model])
    return result, final_routes, subjects, floors, without_verdict


def check_against_report(final_routes, subjects):
    """The arrangement `full` against the report's final confusion matrices; returns the list of disagreements."""
    report = _read_json("data/eval/report.json")
    problems = []
    for model, routes in final_routes.items():
        matrix = rep._empty_matrix()
        for c in subjects:
            matrix[c["expected"]][rep.ROUTE_TO_DECISION[routes[c["id"]]]] += 1
        for expected, row in matrix.items():
            for column, count in row.items():
                if report["models"][model]["matrixFinal"][expected][column] != count:
                    problems.append(f"{model}: expected {expected}, final {column}: report {report['models'][model]['matrixFinal'][expected][column]}, ablation {count}")
    return problems


def build(today=None):
    result, final_routes, subjects, floors, without_verdict = run()
    problems = check_against_report(final_routes, subjects)
    if problems:
        raise SystemExit("ablation: the arrangement 'full' does not reproduce the report:\n" + "\n".join(problems))
    return {
        "origin": {
            "what": "Replay of the recorded answers of the agent with tools (triage-v3) through four arrangements of the product's layers; no provider call.",
            "recordings": "data/replay/recordings.jsonl", "recordingsSha256": sha("data/replay/recordings.jsonl"),
            "dataset": "data/eval/dataset.jsonl", "datasetSha256": sha("data/eval/dataset.jsonl"),
            "configuration": ["data/config/critical-ranges.json", "data/config/delta-rules.json", "data/config/release-guard.json"],
            "checkedAgainst": "data/eval/report.json (the final confusion matrices; the arrangement 'full' reproduces them for both models)",
            "tool": "src/python/readback/evaluation/ablation.py",
        },
        "measuredOn": today or datetime.date.today().isoformat(),
        "subjectCases": len(subjects),
        "ruleCriticalCases": sum(1 for c in subjects if floors[c["id"]][0] >= 3),
        "contextualCriticalCases": sum(1 for c in subjects if c["expected"] == "CRITICAL" and floors[c["id"]][0] < 3),
        "arrangements": {
            "value": "range rule only; critical goes to read-back, the rest is released",
            "valueGuard": "range rule + release guard, without the agent; a release the guard holds goes to a person",
            "agent": "range rule + release guard + agent with tools + composition, without the change rule; the agent's change tool gave it the rule's verdict",
            "deterministic": "range rule + change rule + release guard, without the agent",
            "full": "the product: range rule + change rule + agent with tools + composition + release guard",
        },
        "agentWithoutVerdict": {
            "what": "the arrangement 'agent' with answers recorded in a paid run where the change tool gave the earlier values and the variation, without the verdict or the limit of the change rule",
            "recordings": NO_VERDICT_RECORDINGS, "models": without_verdict,
        },
        "definitions": {
            "uncertainReleased": "subject cases expected RECOLLECT or NEEDS_REVIEW that were released automatically",
            "contextualCriticals": "subject cases expected CRITICAL that the range rule does not catch (floor below 3); released = automatic release, not sent to read-back or to a person",
            "silencedCriticals": "cases the range rule holds at floor 3 that did not go to read-back",
            "falseCriticals": "cases expected not critical that went to read-back",
            "reviewRate": "share of the subject cases routed to a person for review",
        },
        "caveat": "The change-rule limits were set knowing the range of the dataset generator, so its coverage is partly by construction. The agent's recorded answers saw the change tool's verdict; the arrangement without the rule removes its power to raise the floor, not that information.",
        "models": result,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--out", default=os.path.join(ROOT, "data/eval/ablation.json"))
    parser.add_argument("--date", default=os.environ.get("ABLATION_DATE"), help="the measuredOn date; ABLATION_DATE does the same, so the output can be made identical to the shipped file")
    args = parser.parse_args(argv)
    data = build(args.date)
    with open(args.out, "w") as handle:
        json.dump(data, handle, indent=2, sort_keys=False)
        handle.write("\n")
    print("wrote", args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
