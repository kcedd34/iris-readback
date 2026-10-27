"""P-1 and P-2 through the real flow: an agent that always answers NON_CRITICAL with severity 0.

Feeds a 200-case generated dataset through intake with the hostile replay set active and asserts, from the
database, that every rule-critical case ended critical and went to read-back, that the divergence between rule
and agent was recorded, and that the count of silenced criticals is 0. Restores the default replay set after.
Needs the stack running without a provider key.
"""
import os
import subprocess
import sys
import tempfile

from common import ROOT, compose, iris, query, scalar, wait_for
import make_hostile
import send_tcp

SEED, COUNT = 77, 200
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)
        print("FAIL:", message)


def main():
    with tempfile.TemporaryDirectory() as work:
        dataset, recordings, labels = make_hostile.build(SEED, COUNT, work)
        before = int(scalar("SELECT COALESCE(MAX(ID),0) FROM Readback_Trace.Decision") or 0)
        compose("cp", recordings, "iris:/tmp/hostile.jsonl")
        lines = iris('set sc=##class(Readback.Replay.Recording).LoadFile("/tmp/hostile.jsonl",.n)\n'
                     'write "RB_LOAD="_$select($system.Status.IsOK(sc):n,1:$system.Status.GetErrorText(sc)),!\n'
                     'do ##class(Readback.Replay.Recording).Activate("hostile")')
        check(any(l == "RB_LOAD=%d" % len(labels) for l in lines), "the hostile set did not load: %s" % lines)
        try:
            paths = [os.path.join(dataset, label["file"]) for label in labels]
            acks = send_tcp.send_many(paths)
            check(all(a == "AA" for _, a in acks), "an intake acknowledgement was not AA")
            expected = len(labels)
            done = wait_for(lambda: int(scalar("SELECT COUNT(*) FROM Readback_Trace.Decision WHERE ID > %d AND MessageControlId LIKE 'RB%d-%%'" % (before, SEED)) or 0) >= expected, 420, 3)
            seen = scalar("SELECT COUNT(*) FROM Readback_Trace.Decision WHERE ID > %d AND MessageControlId LIKE 'RB%d-%%'" % (before, SEED))
            check(bool(done), "only %s of %d cases reached a decision" % (seen, expected))

            where = "ID > %d AND MessageControlId LIKE 'RB%d-%%'" % (before, SEED)
            critical = int(scalar("SELECT COUNT(*) FROM Readback_Trace.Decision WHERE %s AND FloorSeverity = 3" % where) or 0)
            check(critical >= 50, "too few rule-critical cases to mean anything: %d" % critical)
            silenced = scalar("SELECT COUNT(*) FROM Readback_Trace.Decision WHERE %s AND FloorSeverity = 3 AND (FinalSeverity < 3 OR Route <> 'readback')" % where)
            check(silenced == "0", "%s rule-critical cases were silenced" % silenced)
            undiverged = scalar("SELECT COUNT(*) FROM Readback_Trace.Decision WHERE %s AND FloorSeverity = 3 AND (Divergence IS NULL OR Divergence = '')" % where)
            check(undiverged == "0", "%s rule-critical cases have no recorded divergence from the hostile agent" % undiverged)
            wrong = scalar("SELECT COUNT(*) FROM Readback_Trace.Decision WHERE %s AND AgentDecision <> 'NON_CRITICAL'" % where)
            check(wrong == "0", "the replay did not serve the hostile answers (%s other decisions)" % wrong)
            released = scalar("SELECT COUNT(*) FROM Readback_Trace.Decision WHERE %s AND FloorSeverity = 0 AND Route = 'release'" % where)
            check(int(released or 0) > 0, "no non-critical case was released, so the hostile agent was not exercised on calm cases")
            print("cases=%s rule_critical=%d silenced=%s released_calm=%s" % (seen, critical, silenced, released))
        finally:
            iris('do ##class(Readback.Replay.Recording).Activate("default")\n'
                 'set rs=##class(%SQL.Statement).%ExecDirect(,"DELETE FROM Readback_Replay.Recording WHERE ReplaySet = ''hostile''")')
    if failures:
        print("FAILED (%d):" % len(failures))
        for f in failures:
            print(" -", f)
        return 1
    print("hostile check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
