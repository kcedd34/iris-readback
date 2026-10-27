"""End-to-end check of the skeleton production (spec SC-003, SC-004 and the duplicate edge case).

Sends 50 valid messages (25 by file, 25 over TCP), 10 malformed ones (5 and 5) and one duplicate,
then asserts on the instance: every valid message is persisted and logged within 10 seconds, no
malformed message is persisted, every rejection has a recorded reason, and nothing is lost.
Run through flow_check.sh with the compose service up.
"""
import os
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "src", "python"))
sys.path.insert(0, HERE)

from readback.dataset import generator  # noqa: E402
import send_tcp  # noqa: E402

DEADLINE_SECONDS = 10
# 50 valid messages plus two more sends of the duplicate.
EXPECTED_LOG_LINES = 52


def iris(script):
    """Runs ObjectScript in the instance and returns the lines that start with RB_."""
    proc = subprocess.run(["docker", "compose", "exec", "-T", "iris", "iris", "session", "IRIS", "-U", "USER"],
                          input=script + "\nhalt\n", capture_output=True, text=True, cwd=ROOT)
    return [line.strip() for line in proc.stdout.splitlines() if line.strip().startswith("RB_")]


def scalar(sql, name):
    lines = iris('set rs=##class(%SQL.Statement).%ExecDirect(,"{}") do rs.%Next() write "RB_{}=",rs.%GetData(1),!'.format(sql, name))
    return int(lines[0].split("=", 1)[1]) if lines else -1


def copy_into_inbox(directory):
    subprocess.run(["docker", "compose", "cp", directory + "/.", "iris:/data/in/"], check=True, capture_output=True, cwd=ROOT)


def mutate(text, kind):
    segments = text.rstrip("\r").split("\r")
    if kind == "wrong-type":
        segments[0] = segments[0].replace("ORU^R01", "ADT^A01")
    elif kind == "no-obx":
        segments = [s for s in segments if not s.startswith("OBX|")]
    elif kind == "no-pid":
        segments = [s for s in segments if not s.startswith("PID|")]
    elif kind == "empty-value":
        segments = [re.sub(r"^(OBX\|1\|NM\|[^|]*\|)\|[^|]*\|", r"\1||", s) if s.startswith("OBX|1|") else s for s in segments]
    return "\r".join(segments) + "\r"


def main():
    seed = int(time.time()) % 900000 + 1000
    subject_prefix = "RB{}-".format(seed)
    items = generator.generate(seed, 30)[:50]
    valid = [(mid, text) for mid, text, _ in items]
    assert len(valid) == 50, "generator returned fewer than 50 messages"
    kinds = ["wrong-type"] * 4 + ["no-obx"] * 3 + ["no-pid"] * 2 + ["empty-value"]
    expected_ack = {"wrong-type": "AR", "no-obx": "AE", "no-pid": "AE", "empty-value": "AE"}
    bad = []
    for number, kind in enumerate(kinds):
        mid = "BAD{}-{:02d}".format(seed, number)
        base = valid[number][1].replace(valid[number][0], mid)
        bad.append((mid, mutate(base, kind), kind))

    rejects_before = scalar("SELECT COUNT(*) FROM Ens_Util.Log WHERE Type=2 AND Text LIKE 'Rejected%'", "REJ")
    failures = []

    with tempfile.TemporaryDirectory() as workdir:
        file_dir = os.path.join(workdir, "in")
        os.makedirs(file_dir)
        tcp_valid, tcp_bad = [], []
        for number, (mid, text) in enumerate(valid):
            path = os.path.join(workdir, mid + ".hl7")
            with open(path, "wb") as handle:
                handle.write(text.encode("ascii"))
            if number % 2 == 0:
                os.replace(path, os.path.join(file_dir, mid + ".hl7"))
            else:
                tcp_valid.append(path)
        for number, (mid, text, kind) in enumerate(bad):
            path = os.path.join(workdir, mid + ".hl7")
            with open(path, "wb") as handle:
                handle.write(text.encode("ascii"))
            if number % 2 == 0:
                os.replace(path, os.path.join(file_dir, mid + ".hl7"))
            else:
                tcp_bad.append((path, kind))

        started = time.time()
        copy_into_inbox(file_dir)
        dup_path = tcp_valid[0]
        # One connection for all TCP traffic: the listener refuses new connections for a moment
        # after accepting one, so reconnecting between batches is flaky and tells us nothing.
        acks = send_tcp.send_many(tcp_valid + [p for p, _ in tcp_bad] + [dup_path, dup_path])
        acks_valid = acks[:len(tcp_valid)]
        acks_bad = acks[len(tcp_valid):len(tcp_valid) + len(tcp_bad)]
        dup = acks[-2:]
        for (path, ack), (_, kind) in zip(acks_bad, tcp_bad):
            if ack != expected_ack[kind]:
                failures.append("TCP malformed ({}) got {} expected {}".format(kind, ack, expected_ack[kind]))
        for path, ack in acks_valid:
            if ack != "AA":
                failures.append("TCP valid message got {} expected AA: {}".format(ack, path))
        if [a for _, a in dup] != ["AA", "AA"]:
            failures.append("duplicate submission acknowledgements: {}".format(dup))
        dup_id = os.path.basename(dup_path)[:-4]

    deadline = time.time() + DEADLINE_SECONDS
    persisted = logged = 0
    while time.time() < deadline:
        persisted = scalar("SELECT COUNT(DISTINCT MessageControlId) FROM Readback_Msg.LabResult WHERE MessageControlId LIKE '{}%'".format(subject_prefix), "PER")
        logged = scalar("SELECT COUNT(*) FROM Ens_Util.Log WHERE ConfigName='Readback.Outbound.LogOperation' AND Text LIKE 'Lab result {}%'".format(subject_prefix), "LOG")
        if persisted == 50 and logged >= EXPECTED_LOG_LINES:
            break
        time.sleep(1)
    elapsed = time.time() - started
    if persisted != 50:
        failures.append("persisted {} of 50 valid messages within {}s".format(persisted, DEADLINE_SECONDS))
    if logged < EXPECTED_LOG_LINES:
        failures.append("log operation reached {} times, expected {}".format(logged, EXPECTED_LOG_LINES))

    bad_persisted = scalar("SELECT COUNT(*) FROM Readback_Msg.LabResult WHERE MessageControlId LIKE 'BAD{}%'".format(seed), "BAD")
    if bad_persisted != 0:
        failures.append("{} malformed messages were persisted".format(bad_persisted))
    time.sleep(2)
    rejects = scalar("SELECT COUNT(*) FROM Ens_Util.Log WHERE Type=2 AND Text LIKE 'Rejected%'", "REJ") - rejects_before
    if rejects != 10:
        failures.append("{} rejection reasons recorded, expected 10".format(rejects))
    dup_rows = scalar("SELECT COUNT(*) FROM Readback_Msg.LabResult WHERE MessageControlId='{}'".format(dup_id), "DUP")
    if dup_rows < 3:
        failures.append("duplicate message produced {} records, expected at least 3 (original plus two sends)".format(dup_rows))
    trace = scalar("SELECT COUNT(*) FROM Ens.MessageHeader WHERE MessageBodyClassName='Readback.Msg.LabResult' AND TargetConfigName='Readback.Outbound.LogOperation'", "TRC")
    if trace < 50:
        failures.append("only {} lab results visible in the message trace".format(trace))

    print("persisted={} logged={} malformed_persisted={} rejections={} duplicate_rows={} trace={} elapsed={:.1f}s".format(
        persisted, logged, bad_persisted, rejects, dup_rows, trace, elapsed))
    if failures:
        print("FAILED:")
        for item in failures:
            print(" -", item)
        return 1
    print("flow check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
