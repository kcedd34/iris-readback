"""Development fixtures for the current prompt version, built from the recorded answers that ship with the product.

The shipped recordings are real answers of an earlier prompt version. The replay key includes the prompt version, so until the
evaluation is redone they match nothing. For the checks that exercise the replay mechanism (not the numbers), this turns each
recorded answer into a row of the current version: the evidence identifiers the answer cites are given the tool calls that
would have returned them, and the answer keeps its decision, severity, rationale, tokens and latency. Every row is marked
`fixture`; no figure may rest on them and the shipped file is never written.
"""
import json


def tool_calls(evidence):
    hist, passages, cases, indices, delta = [], [], [], [], False
    for item in evidence:
        if item == "current-result":
            continue
        if item.startswith("earlier-result-"):
            hist.append(item)
        elif item.startswith("sample-index-"):
            indices.append(item)
        elif item.startswith("similar-case-"):
            cases.append(item)
        elif item == "delta-assessment":
            delta = True
        else:
            passages.append(item)
    calls = []

    def add(tool, result):
        calls.append({"seq": len(calls) + 1, "tool": tool, "arguments": "{}", "result": json.dumps(result, sort_keys=True),
                      "status": "ok", "reason": "", "durationMs": 5})

    if hist:
        add("get_patient_history", {"found": len(hist), "earlier": [{"id": h, "value": "n/a", "unit": "", "collectedAt": ""} for h in hist]})
    if delta:
        add("get_delta_assessment", {"id": "delta-assessment", "comparable": True, "floorVerdict": "critical by change"})
    if passages or cases:
        add("search_policy", {"available": True, "indexVersion": "fixture",
                              "passages": [{"id": p, "text": "(fixture)", "score": 0.5} for p in passages],
                              "similarCases": [{"id": c, "text": "(fixture)", "decision": "CRITICAL", "route": "readback", "traceId": ""} for c in cases]})
    if indices:
        add("get_sample_quality", {"indices": [{"id": i, "code": "", "value": ""} for i in indices]})
    return calls


def convert(row, version):
    out = dict(row, promptVersion=version, source="fixture")
    if not row.get("answer"):
        return out
    answer = json.loads(row["answer"])
    evidence = [e.strip("[]") for e in answer.get("evidence", [])]
    answer["evidence"] = evidence
    out["answer"] = json.dumps(answer, sort_keys=True)
    calls = tool_calls(evidence)
    out["toolCalls"] = calls
    out["rounds"] = 2 if calls else 1
    return out


def write(shipped_path, out_path, version):
    """Writes the fixtures; returns the number of rows."""
    with open(shipped_path) as handle:
        rows = [json.loads(line) for line in handle if line.strip()]
    with open(out_path, "w") as handle:
        for row in rows:
            handle.write(json.dumps(convert(row, version), sort_keys=True) + "\n")
    return len(rows)
