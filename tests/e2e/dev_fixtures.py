"""Gives a running stack replay recordings of the current prompt version while the shipped ones are of an earlier one.

The shipped recordings are real answers of an earlier prompt version, and the replay key holds the version, so until the evaluation
is redone they match nothing and every replayed case would end as "no recorded answer". Checks that exercise the replay mechanism or
the screens (not the numbers) call this: it loads, into the default replay set of the running stack, fixtures of the current
version built from those recorded answers (marked `fixture`, see fixtures_v3.py). Once the shipped file is of the current version
it does nothing. The shipped file is never written.
"""
import json
import os
import tempfile

import fixtures_v3
import make_hostile
from common import ROOT, compose, iris


def use_current_version_recordings():
    """Returns True when fixtures were loaded, False when the shipped recordings already match, and raises when they could not be loaded."""
    shipped = os.path.join(ROOT, "data", "replay", "recordings.jsonl")
    with open(shipped) as handle:
        versions = {json.loads(line)["promptVersion"] for line in handle if line.strip()}
    if versions == {make_hostile.prompt_version()}:
        return False
    with tempfile.TemporaryDirectory() as work:
        out = os.path.join(work, "fixtures-v3.jsonl")
        fixtures_v3.write(shipped, out, make_hostile.prompt_version())
        compose("cp", out, "iris:/tmp/fixtures-v3.jsonl")
    lines = iris('set sc=##class(Readback.Replay.Recording).LoadFile("/tmp/fixtures-v3.jsonl",.n,0)\n'
                 'write "RB_FIX="_n_"|"_$select($system.Status.IsOK(sc):"ok",1:$system.Status.GetErrorText(sc)),!')
    if not any(l.startswith("RB_FIX=") and l.endswith("|ok") for l in lines):
        raise RuntimeError("the development fixtures did not load: %s" % lines)
    return True
