"""The demo password with special characters, end to end on a clean stack (no key, no cost).

The password is written the way a person writes it in .env (the compose file that reads it), full of the characters that break
shells and templates: quotes, an apostrophe, a hash, a backslash, an ampersand, a semicolon, spaces inside, an exclamation mark and
a (doubled) dollar sign. Checks that the preflight accepts it, that the product receives it exactly, that the accounts accept it
through the workflow layer, that the read-only account behind the proxy works, and that the page carries it unchanged.
The stack is left down.
"""
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.request
import base64

from common import ROOT

LITERAL = "Sp3c!al \"q\" 'a'#h\\b &;x$y|z"
IN_ENV_FILE = LITERAL.replace("$", "$$")
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)
        print("FAIL:", message)


def fetch(url, user=None):
    request = urllib.request.Request(url)
    if user:
        request.add_header("Authorization", "Basic " + base64.b64encode(("%s:%s" % (user, LITERAL)).encode()).decode())
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, response.read().decode()
    except urllib.error.HTTPError as error:
        return error.code, error.read().decode()
    except OSError:
        return 0, ""


def main():
    with tempfile.TemporaryDirectory() as work:
        env_file = os.path.join(work, "env")
        with open(env_file, "w") as handle:
            handle.write("READBACK_DEMO_PASSWORD=%s\nREADBACK_PUBLISH_DEMO_ACCOUNTS=1\nOPENAI_API_KEY=\n" % IN_ENV_FILE)
        env = {k: v for k, v in os.environ.items() if k not in ("READBACK_DEMO_PASSWORD", "READBACK_PUBLISH_DEMO_ACCOUNTS")}
        env["OPENAI_API_KEY"] = ""
        env["READBACK_ENV_FILE"] = env_file
        env["READBACK_PREFLIGHT_PASSWORD_ONLY"] = "1"
        pre = subprocess.run([os.path.join(ROOT, "src/ops/preflight.sh")], cwd=ROOT, env=env, capture_output=True, text=True)
        check(pre.returncode == 0, "the preflight refused the special-character password: %s" % pre.stderr[-200:])
        compose = ["docker", "compose", "--env-file", env_file]
        subprocess.run(compose + ["down", "-v"], cwd=ROOT, env=env, capture_output=True)
        up = subprocess.run(compose + ["up", "-d", "--build", "--force-recreate"], cwd=ROOT, env=env, capture_output=True, text=True)
        check(up.returncode == 0, "the stack did not start: %s" % up.stderr[-300:])
        verify = subprocess.run([os.path.join(ROOT, "src/ops/verify.sh"), "300"], cwd=ROOT, env=env, capture_output=True, text=True)
        check(verify.returncode == 0, "the production did not start: %s" % verify.stderr[-200:])
        got = subprocess.run(compose + ["exec", "-T", "iris", "printenv", "READBACK_DEMO_PASSWORD"], cwd=ROOT, env=env, capture_output=True, text=True).stdout.rstrip("\n")
        check(got == LITERAL, "the product received a different password than the one written (%d characters, expected %d)" % (len(got), len(LITERAL)))
        portal = os.environ.get("READBACK_PORTAL_PORT", "52790")
        deadline = time.time() + 360
        status = 0
        while time.time() < deadline:
            status, _ = fetch("http://127.0.0.1:%s/workflow/rest/user-info" % portal, "communicator1")
            if status == 200:
                break
            time.sleep(5)
        check(status == 200, "the account communicator1 cannot sign in to the workflow layer with the password (status %s)" % status)
        check(fetch("http://127.0.0.1:%s/readback/api/status" % portal, "observer")[0] == 200, "the observer account cannot read the status with the password")
        check(fetch("http://127.0.0.1:8080/readback/api/status")[0] == 200, "the read-only account behind the proxy does not work with the password")
        _, config = fetch("http://127.0.0.1:8080/ui-config.json")
        try:
            published = json.loads(config)["accounts"][0]["password"]
        except (ValueError, KeyError, IndexError):
            published = None
        check(published == LITERAL, "the page carries a different password than the one written")
        status, text = fetch("http://127.0.0.1:%s/readback/api/status" % portal, "observer")
        check(LITERAL not in text, "the status answer carries the password")
        subprocess.run(compose + ["down", "-v"], cwd=ROOT, env=env, capture_output=True)
    if failures:
        print("FAILED (%d)" % len(failures))
        return 1
    print("password check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
