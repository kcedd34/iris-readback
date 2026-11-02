"""Turns the export of a live run into replay recordings.

A recording keeps only what replay needs: the answer as the provider gave it, the token counts, the latency and the names of the
model and the prompt version. An answer that is present but invalid against the schema is recorded as it came, and replay judges it
invalid again. A call that returned no output at all (provider error, timeout, empty answer) is recorded as a failure: the recording
carries the failure kind and the fixed reason instead of an answer, and replay reproduces that failure, so a replayed run equals the
live one. Only a case the budget kept from calling the agent has nothing to record. Rows of other replay sets in the file are left as
they are. A value that looks like a credential stops the write.
"""
import json
import os
import re
import sys

FIELDS = ("replaySet", "messageControlId", "promptVersion", "model", "answer", "inputTokens", "outputTokens", "latencyMs", "source", "failureKind", "failureReason", "toolCalls", "rounds")
KEY_PATTERNS = (re.compile(r"sk-[A-Za-z0-9_*.\-]{8,}"), re.compile(r"Bearer\s+[A-Za-z0-9._~+/=\-]{8,}"), re.compile(r"(?i)api[_ -]?key\s*[:=]\s*\S{8,}"))


def has_key_shape(text):
    return any(p.search(text) for p in KEY_PATTERNS)


def _truthy(value):
    return str(value).lower() in ("1", "true")


PLATFORM_PREFIX = "ERROR #5001: "


def _reason(failure, text):
    """The fixed reason of a failure as replay must hand it back. The trace holds the reason with one prefix the product added."""
    if failure == "provider-error" and text.startswith(PLATFORM_PREFIX):
        return text[len(PLATFORM_PREFIX):]
    return text


def from_rows(rows, replay_set):
    """The recordings of the rows that hold a valid answer. Raises ValueError for replayed rows or credential-shaped values."""
    out = []
    for row in rows:
        if row.get("mode") != "live":
            raise ValueError("row {} is not from a live run: a replay cannot be recorded".format(row.get("messageControlId")))
        if not _truthy(row.get("agentCalled")):
            continue
        failure = None
        kind = row.get("failureKind")
        if kind in ("tool-failure", "tool-limit"):
            # The investigation failed: replay hands back the same failure, and keeps the answer if there was one.
            failure = kind
        elif not row.get("rawOutput"):
            failure = kind if kind in ("provider-error", "timeout") else "empty-output"
        recording = {
            "replaySet": replay_set,
            "messageControlId": row["messageControlId"],
            "promptVersion": row["promptVersion"],
            "model": row["model"],
            "answer": row.get("rawOutput") or "",
            "inputTokens": int(row.get("inputTokens") or 0),
            "outputTokens": int(row.get("outputTokens") or 0),
            "latencyMs": int(row["latencyMs"]) if row.get("latencyMs") not in (None, "") else 0,
            "source": "recorded",
            "rounds": int(row.get("rounds") or 1),
        }
        calls = [{"seq": c["seq"], "tool": c["tool"], "arguments": c.get("arguments", ""), "result": c.get("result", ""), "status": c["status"],
                  "reason": c.get("reason", ""), "durationMs": int(c.get("durationMs") or 0)} for c in (row.get("toolCalls") or [])]
        if calls:
            recording["toolCalls"] = calls
        if failure:
            recording["failureKind"] = failure
            recording["failureReason"] = _reason(failure, row.get("failureReason") or "")
        if calls and has_key_shape(json.dumps(calls)):
            raise ValueError("a credential-shaped value in the tool calls of {}".format(row["messageControlId"]))
        for name, value in recording.items():
            if isinstance(value, str) and has_key_shape(value):
                raise ValueError("a credential-shaped value in {} of {}".format(name, row["messageControlId"]))
        out.append(recording)
    return out


def merge(existing, new, replay_set):
    """The existing rows without the set being replaced, plus the new rows, in a fixed order."""
    kept = [r for r in existing if r.get("replaySet", "default") != replay_set]
    rows = kept + new
    return sorted(rows, key=lambda r: (r.get("replaySet", "default"), r["messageControlId"], r["promptVersion"]))


def write(path, rows):
    with open(path, "w") as handle:
        for row in rows:
            handle.write(json.dumps({k: row[k] for k in FIELDS if k in row}, sort_keys=True) + "\n")


def from_export(export_path, replay_set, out_path):
    """Reads the export, replaces the set in out_path and returns (recorded, skipped)."""
    with open(export_path) as handle:
        rows = [json.loads(line) for line in handle if line.strip()]
    new = from_rows(rows, replay_set)
    existing = []
    if os.path.exists(out_path):
        with open(out_path) as handle:
            existing = [json.loads(line) for line in handle if line.strip()]
    write(out_path, merge(existing, new, replay_set))
    return len(new), len(rows) - len(new)


def main(argv=None):
    import argparse
    parser = argparse.ArgumentParser(description="Write recordings from the export of a live run.")
    parser.add_argument("--export", required=True)
    parser.add_argument("--set", required=True, dest="replay_set")
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)
    try:
        recorded, skipped = from_export(args.export, args.replay_set, args.out)
    except ValueError as error:
        print("not recorded: {}".format(error), file=sys.stderr)
        return 1
    print("recorded {} answers into set {} ({} rows were not called by the agent)".format(recorded, args.replay_set, skipped))
    return 0


if __name__ == "__main__":
    sys.exit(main())
