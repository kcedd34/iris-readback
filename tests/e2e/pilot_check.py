"""A pilot run against a local OpenAI-compatible mock (no real key, no cost).

Runs `evaluate.sh live gpt-5.4-mini --pilot 5` through the live path with the agent pointed at the mock, and fails if any file
under data/ is created, changed or removed: a pilot records nothing, so the recordings, the report and the settings files that
ship stay as they are. It also checks that the estimate is printed first and that nothing is sent without --yes.
The container is recreated without the test key at the end.
"""
import hashlib
import os
import subprocess
import sys
import time

from common import ROOT, compose
from live_mock_check import FILES, set_setting, start_stack

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)
        print("FAIL:", message)


def snapshot():
    """Path to hash of every file under data/, so a created, changed or removed file all show."""
    out = {}
    for folder, _, names in os.walk(os.path.join(ROOT, "data")):
        for name in names:
            path = os.path.join(folder, name)
            with open(path, "rb") as handle:
                out[os.path.relpath(path, ROOT)] = hashlib.sha256(handle.read()).hexdigest()
    return out


def evaluate(*args):
    return subprocess.run([os.path.join(ROOT, "src/ops/evaluate.sh"), "live", "gpt-5.4-mini", "--pilot", "5"] + list(args),
                          cwd=ROOT, capture_output=True, text=True, timeout=900)


def main():
    compose("down", "-v", "--timeout", "20")
    start_stack(FILES)
    compose("exec", "-d", "iris", "python3", "/opt/readback/tests/e2e/mock_openai.py")
    time.sleep(2)
    check(set_setting("Readback.Agent", "Adapter", "ProviderConfig", '{"api_key":"@{env:OPENAI_API_KEY}","base_url":"http://127.0.0.1:8099/v1/"}'), "could not point the agent item at the mock")
    time.sleep(3)

    before = snapshot()
    check(len(before) > 20, "the snapshot of data/ looks empty (%d files)" % len(before))

    dry = evaluate()
    print(dry.stdout.strip())
    check(dry.returncode == 0 and "estimated cost" in dry.stdout and "nothing was sent" in dry.stdout, "without --yes the estimate must print and nothing be sent: %s" % dry.stdout[-300:])
    check(snapshot() == before, "the run without --yes changed files under data/")

    run = evaluate("--yes")
    print(run.stdout.strip())
    check(run.returncode == 0, "the pilot did not finish: %s %s" % (run.returncode, run.stdout[-300:] + run.stderr[-300:]))
    check("nothing was recorded" in run.stdout, "the pilot must say it recorded nothing")
    after = snapshot()
    changed = sorted(p for p in set(before) | set(after) if before.get(p) != after.get(p))
    check(not changed, "the pilot changed files under data/: %s" % ", ".join(changed))
    check(os.path.exists(os.path.join(ROOT, ".local", "eval", "rows-gpt-5.4-mini.jsonl")), "the pilot did not export its rows to .local/eval")

    start_stack(["docker-compose.yml"], env={"OPENAI_API_KEY": ""})
    if failures:
        print("FAILED (%d):" % len(failures))
        for f in failures:
            print(" -", f)
        return 1
    print("pilot check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
