"""Browser checks of the flow UI against the running replay stack (no provider key).

Needs the stack up (docker compose up -d --build, key empty, READBACK_DEMO_PASSWORD set) and Node. Installs the frontend
packages with `npm ci --ignore-scripts` and the test browser once. Parts run: flow, task, public, a11y, demo, alerts (PARTS env, default all).
RUNS sets how many times the critical case is submitted in the flow part (default 5; the full measure of SC-002 and SC-003 is 20).
Screenshots go to .local/ui/ (not committed).
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dev_fixtures  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FRONTEND = os.path.join(ROOT, "frontend")


def run(cmd, **kw):
    return subprocess.run(cmd, cwd=FRONTEND, text=True, capture_output=True, **kw)


def main():
    if not os.path.isdir(os.path.join(FRONTEND, "node_modules")):
        proc = run(["npm", "ci", "--ignore-scripts"])
        if proc.returncode:
            print("FAIL: npm ci failed:", proc.stderr[-400:])
            return 1
    verify = run(["npm", "run", "verify"])
    sys.stdout.write("\n".join(l for l in verify.stdout.splitlines() if "gzipped" in l or "contrast" in l or "external" in l or "Tests" in l) + "\n")
    if verify.returncode:
        print("FAIL: npm run verify failed (build, 300 KB budget, contrast, external addresses, unit tests):", (verify.stdout + verify.stderr)[-500:])
        return 1
    proc = run(["npx", "playwright", "install", "chromium"])
    if proc.returncode:
        print("FAIL: the test browser could not be installed:", proc.stderr[-400:])
        return 1
    try:
        if dev_fixtures.use_current_version_recordings():
            print("replay: the shipped recordings are of an earlier prompt version, development fixtures of the current one are loaded")
    except RuntimeError as error:
        print("FAIL:", error)
        return 1
    parts = os.environ.get("PARTS", "flow,task,public,a11y,demo,alerts").split(",")
    env = dict(os.environ, SHOT_DIR=os.path.join(ROOT, ".local", "ui"), OPENAI_API_KEY="")
    code = 0
    plain = [p for p in parts if p != "public"]
    if plain:
        code = subprocess.run(["node", "tests/e2e/ui-check.mjs"], cwd=FRONTEND, env=dict(env, PARTS=",".join(plain)), text=True).returncode
    if "public" in parts and code == 0:
        # The public part runs twice: accounts not published (the default), then published, and the stack is put back.
        for published in ("0", "1"):
            up = subprocess.run(["docker", "compose", "up", "-d", "ui"], cwd=ROOT, env=dict(env, READBACK_PUBLISH_DEMO_ACCOUNTS=published), capture_output=True, text=True)
            if up.returncode:
                print("FAIL: the interface service could not be restarted:", up.stderr[-300:])
                code = 1
                break
            subprocess.run(["sleep", "3"])
            code = subprocess.run(["node", "tests/e2e/ui-check.mjs"], cwd=FRONTEND, env=dict(env, PARTS="public", EXPECT_PUBLISHED=published), text=True).returncode
            if code:
                break
        subprocess.run(["docker", "compose", "up", "-d", "ui"], cwd=ROOT, env=dict(env, READBACK_PUBLISH_DEMO_ACCOUNTS="0"), capture_output=True, text=True)
    return code


if __name__ == "__main__":
    sys.exit(main())
