"""The messages of the demo are made by Embedded Python inside IRIS, and they are the messages the command line generator makes.

For every message of every demo scenario: the text returned by Readback.Demo.Generator in the container equals, byte for byte, the
text the generator outside IRIS makes for the same profile, seed and count. Then one scenario is submitted through the platform's own
API and the production accepts and decides every message it generated, each under a case id of its own. Needs READBACK_DEMO_PASSWORD.
"""
import base64
import json
import os
import sys
import time

from common import ROOT, iris, query, wait_for
from readback.dataset import generator
import ui_api_check as api

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)
        print("FAIL:", message)


def inside(spec, message_id):
    lines = iris('set t=##class(Readback.Demo.Generator).Message("%s",%d,%d,"%s")\nwrite "RB_TEXT="_$System.Encryption.Base64Encode(t,1),!' % (spec["profile"], spec["seed"], spec["count"], message_id))
    for line in lines:
        if line.startswith("RB_TEXT="):
            return base64.b64decode(line.split("=", 1)[1]).decode("ascii") if len(line) > 8 else ""
    return None


def main():
    with open(os.path.join(ROOT, "data", "samples", "demo-scenarios.json")) as handle:
        scenarios = json.load(handle)["scenarios"]
    outside = {}
    compared = 0
    for scenario in scenarios:
        spec = scenario["generator"]
        key = (spec["profile"], spec["seed"], spec["count"])
        if key not in outside:
            outside[key] = {mid: text for mid, text, _ in generator.generate(spec["seed"], spec["count"], spec["profile"])}
        for message_id in scenario["messages"]:
            made = inside(spec, message_id)
            check(made is not None and made != "", "Embedded Python made nothing for %s" % message_id)
            check(made == outside[key][message_id], "the text of %s made inside IRIS differs from the generator outside it" % message_id)
            compared += 1
    print("compared %d messages, inside IRIS against outside" % compared)
    # An argument the generator must refuse gives nothing.
    check(inside({"profile": "nosuchprofile", "seed": 1, "count": 1}, "RB1-00001") == "", "an unknown profile made a message")

    # Accepted by the production: submit a scenario with history, twice, and see every message decided under its own id.
    if not api.PASSWORD:
        print("FAIL: READBACK_DEMO_PASSWORD is not set")
        return 1
    ids = []
    for _ in range(2):
        status, text, _took = api.call(api.API, "observer", "POST", "/flow/submit", {"scenarioId": "potassium-agent-tries-to-lower"})
        check(status == 200, "the submit answered %s: %s" % (status, text[:100]))
        ids += (api.js(text) or {}).get("controlIds", [])
        time.sleep(1.5)
    check(len(ids) == 8 and len(set(ids)) == 8, "two submissions of a 4-message scenario must give 8 distinct case ids: %s" % ids)
    for control_id in ids:
        rows = wait_for(lambda cid=control_id: query("SELECT Route FROM Readback_Trace.Decision WHERE MessageControlId='%s'" % cid, ["Route"]) or None, 120)
        check(bool(rows), "the production did not decide %s" % control_id)
    print("decided: %d messages under %d distinct case ids" % (len(ids), len(set(ids))))
    if failures:
        print("FAILED (%d)" % len(failures))
        return 1
    print("generator check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
