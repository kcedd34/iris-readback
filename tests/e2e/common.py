"""Shared helpers for the end-to-end checks: run ObjectScript in the container, query tables, build HL7."""
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tests", "e2e"))
sys.path.insert(0, os.path.join(ROOT, "src", "python"))

SEP = "~~"


def compose(*args, check=True, extra_env=None, files=None):
    cmd = ["docker", "compose"]
    for f in files or []:
        cmd += ["-f", f]
    cmd += list(args)
    env = dict(os.environ, **(extra_env or {}))
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, check=check, env=env)


def iris(script):
    """Runs ObjectScript in USER and returns the output lines that start with RB_."""
    proc = subprocess.run(["docker", "compose", "exec", "-T", "iris", "iris", "session", "IRIS", "-U", "USER"],
                          input=script + "\nhalt\n", capture_output=True, text=True, cwd=ROOT)
    return [line.strip() for line in proc.stdout.splitlines() if line.strip().startswith("RB_")]


def query(sql, columns):
    """Runs a SELECT and returns a list of dicts. Newlines inside values are replaced by spaces."""
    names = [c.strip() for c in columns]
    cols = "".join('_"%s"_$Translate(rs.%%Get("%s"),$Char(10,13),"  ")' % (SEP, n) for n in names)
    script = ('set rs=##class(%SQL.Statement).%ExecDirect(,"' + sql.replace('"', '""') + '")\n'
              'if rs.%SQLCODE<0 write "RB_ERR "_rs.%Message,!\n'
              'while rs.%Next() { write "RB_ROW"' + cols + ',! }')
    rows = []
    for line in iris(script):
        if line.startswith("RB_ERR"):
            raise RuntimeError(line)
        if line.startswith("RB_ROW"):
            parts = line.split(SEP)[1:]
            rows.append(dict(zip(names, parts)))
    return rows


def scalar(sql):
    script = 'set rs=##class(%SQL.Statement).%ExecDirect(,"' + sql.replace('"', '""') + '") do rs.%Next() write "RB_N="_rs.%GetData(1),!'
    for line in iris(script):
        if line.startswith("RB_N="):
            return line.split("=", 1)[1]
    return ""


def oru(control_id, patient, code, name, value, unit, collected="20260301080000", dob="19700101", indices=None, ref="", sent="20260301083000"):
    """One ORU^R01 as text with carriage-return separators. indices: list of (code, value) sample-quality indices."""
    segments = [
        "MSH|^~\\&|SYNLAB|SYNFAC|READBACK|SYNFAC|%s||ORU^R01|%s|P|2.5" % (sent, control_id),
        "PID|1||%s^^^SYN^MR||SYNTHETIC^PATIENT||%s|F" % (patient, dob),
        "OBR|1|||%s^%s^LN|||%s" % (code, name, collected),
        "OBX|1|NM|%s^%s^LN||%s|%s|%s|||F" % (code, name, value, unit, ref),
    ]
    for number, (icode, ivalue) in enumerate(indices or [], start=2):
        segments.append("OBX|%d|NM|%s^%s^L||%s|index||||F" % (number, icode, icode.replace("_", " ").capitalize(), ivalue))
    return "\r".join(segments) + "\r"


def wait_for(predicate, seconds=30, interval=1.0):
    import time
    end = time.time() + seconds
    while time.time() < end:
        result = predicate()
        if result:
            return result
        time.sleep(interval)
    return None
