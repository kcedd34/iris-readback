"""The read-only MCP server of the product, against the running replay stack (docker compose).

Over HTTP it proves the service is closed to everyone but the read-only account: no credentials are refused, an account without the role is
refused, the public proxy does not route it. In the platform's own tool manager it proves what the tools are: exactly four read tools, none that
confirms, none that writes (no table of the product changes by a call), and no answer that carries a patient identifier. Needs READBACK_DEMO_PASSWORD.
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

from common import iris, query, scalar, wait_for

PORT = os.environ.get("READBACK_PORTAL_PORT", "52790")
UI = os.environ.get("UI_URL", "http://127.0.0.1:8080")
PASSWORD = os.environ.get("READBACK_DEMO_PASSWORD", "")
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)
        print("FAIL:", message)


def http(url, user=None, method="GET", body=None):
    headers = {"Content-Type": "application/json"}
    if user:
        headers["Authorization"] = "Basic " + base64.b64encode(("%s:%s" % (user, PASSWORD)).encode()).decode()
    request = urllib.request.Request(url, method=method, data=None if body is None else json.dumps(body).encode(), headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return response.status, dict(response.headers), response.read().decode()
    except urllib.error.HTTPError as error:
        return error.code, dict(error.headers), error.read().decode()


def tool(name, **arguments):
    """Runs one tool in the platform's tool manager, as the MCP service would, and returns (answer text, error text)."""
    args = json.dumps(arguments).replace('"', '""')
    script = ('set mgr=##class(%AI.ToolMgr).%New() set sc=mgr.RegisterToolSet("Readback.MCP.Tools")\n'
              'try { set r=mgr.ExecuteTool("NAME",{}.%FromJSON("ARGS")) write "RB_OUT=",r.value,! } catch ex { write "RB_ERR=",ex.DisplayString(),! }').replace("NAME", name).replace("ARGS", args)
    lines = iris(script)
    out = next((l[7:] for l in lines if l.startswith("RB_OUT=")), None)
    err = next((l[7:] for l in lines if l.startswith("RB_ERR=")), None)
    return out, err


# The tables a tool could change. The production's own message headers and event log are not here: the alert engine writes to them on a timer while the check runs.
TABLES = ("Readback_Trace.Decision", "Readback_Trace.ToolCall", "Readback_Msg.LabResult", "Readback_Retrieval.IndexedCase", "Readback_Trace.ReadbackAttempt",
          "EnsLib_Workflow.TaskResponse")


def counts():
    return {t: scalar("SELECT COUNT(*) FROM " + t) for t in TABLES}


def main():
    if not PASSWORD:
        print("FAIL: READBACK_DEMO_PASSWORD is not set")
        return 1
    base = "http://127.0.0.1:%s/readback/mcp" % PORT

    # --- the service is closed: credentials, then the role, and the public proxy does not route it
    status, headers, _ = http(base + "/v1/services")
    check(status == 401, "the MCP service answered %s without credentials" % status)
    # An application of the MCP Server type is not served to a plain HTTP client that carries credentials (the web layer answers 404): the way in is the
    # platform's gateway, checked by mcp_client_check.sh. Here: nothing is served to a direct caller, whoever it is.
    for user in ("communicator1", "observer"):
        status, headers, body = http(base + "/v1/services", user)
        check(status in (403, 404, 502), "a direct HTTP call of %s was served (%s)" % (user, status))
        check("list_pending" not in body and "explain_decision" not in body, "a direct HTTP call of %s got the tool catalog" % user)
        status, _, body = http(base + "/v1/tool_call", user, "POST", {"tool": "list_pending_criticals", "args": {}})
        check(status in (403, 404, 502) and "pending" not in body, "a direct tool call of %s was served (%s)" % (user, status))
    for path in ("/readback/mcp/v1/services", "/readback/mcp/v1/tool_call", "/readback/mcp/v1/health"):
        status, _, body = http(UI + path, "observer", "POST" if path.endswith("tool_call") else "GET", {"tool": "list_pending_criticals", "args": {}} if path.endswith("tool_call") else None)
        check(status in (400, 401, 403, 404, 405), "the public proxy routed %s (%s)" % (path, status))
        check("list_pending" not in body, "the public proxy answered a tool call at %s" % path)

    # --- a case with a read-back pending and a decided one, to read
    status, _, body = http("http://127.0.0.1:%s/readback/api/flow/submit" % PORT, "observer", "POST", {"scenarioId": "potassium-critical-value"})
    check(status == 200, "the demo submission was not accepted: %s %s" % (status, body[:100]))
    control = (json.loads(body).get("controlIds") or [""])[0] if status == 200 else ""
    check(bool(wait_for(lambda: scalar("SELECT COUNT(*) FROM Readback_Trace.Decision WHERE MessageControlId = '%s' AND Route = 'readback'" % control) == "1", 90, 2)), "the submitted case was not decided")

    # --- what the tools are: exactly four, none that confirms
    lines = iris('set mgr=##class(%AI.ToolMgr).%New() set sc=mgr.RegisterToolSet("Readback.MCP.Tools") set st=mgr.GetToolStatuses() set i=st.%GetIterator() while i.%GetNext(.k,.t) { write "RB_TOOL=",t.name,"|",t.metadata.ReadOnly,! }')
    listed = [l[8:].split("|") for l in lines if l.startswith("RB_TOOL=")]
    check([n for n, _ in listed] == ["explain_decision", "list_pending_criticals", "read_ablation", "read_evaluation"] or sorted(n for n, _ in listed) == sorted(["list_pending_criticals", "explain_decision", "read_evaluation", "read_ablation"]),
          "the tools are not exactly the four read tools: %s" % listed)
    check(all(ro == "1" for _, ro in listed) and len(listed) == 4, "a tool is not marked read-only: %s" % listed)
    check(not any(w in n for n, _ in listed for w in ("confirm", "close", "complete", "ack", "readback_")), "there is a tool that confirms or closes: %s" % listed)
    for name in ("confirm_readback", "close_alert", "complete_task", "confirm"):
        out, err = tool(name)
        check(out is None and err and "ToolNotFound" in err, "calling the missing tool %s did not fail with ToolNotFound: %s %s" % (name, out, err))

    # --- no tool writes: no table of the product changes by calling every tool, twice
    before = counts()
    answers = []
    for name, args in (("list_pending_criticals", {}), ("explain_decision", {"controlId": control}), ("read_evaluation", {}), ("read_ablation", {})):
        for _ in range(2):
            out, err = tool(name, **args)
            check(out is not None and err is None, "%s failed: %s" % (name, err))
            answers.append((name, out or ""))
    after = counts()
    check(scalar("SELECT COUNT(*) FROM Ens.MessageHeader WHERE SourceConfigName LIKE '%MCP%' OR TargetConfigName LIKE '%MCP%'") == "0", "a tool sent a message through the production")
    check(before == after, "calling the tools changed a table: %s" % {t: (before[t], after[t]) for t in TABLES if before[t] != after[t]})

    # --- what they say
    by_name = dict(answers)
    pending = json.loads(by_name["list_pending_criticals"])
    check(any(p["controlId"] == control for p in pending["pending"]), "the pending list does not hold the case just decided")
    check(all(set(p) <= {"decisionId", "controlId", "analyte", "since", "taskId", "assignedTo", "mode", "alertLevel", "alertState"} for p in pending["pending"]), "a pending entry carries a field outside the contract")
    explain = json.loads(by_name["explain_decision"])
    check(explain["controlId"] == control and explain["route"] == "readback" and len(explain["explanation"]) >= 5, "the explanation is not the decision's: %s" % str(explain)[:200])
    check(any("Waiting for a person" in line for line in explain["explanation"]), "the explanation does not say a person must repeat the value")
    check(len(explain["toolCalls"]) > 0 or explain["mode"] == "replay", "the explanation lists no tool calls")
    evaluation = json.loads(by_name["read_evaluation"])
    check(set(evaluation["models"]) == {"gpt-5.4", "gpt-5.4-mini"} and all(m["silencedCriticals"] == 0 for m in evaluation["models"].values()), "the evaluation read is not the shipped report")
    ablation = json.loads(by_name["read_ablation"])
    check("agentWithoutVerdict" in ablation and "origin" not in ablation, "the ablation read is not the shipped file")

    # --- no patient identifier, in any answer, for any case the tool can be asked about
    identifiers = [r["PatientId"] for r in query("SELECT DISTINCT TOP 200 PatientId FROM Readback_Msg.LabResult", ["PatientId"]) if r["PatientId"]]
    blob = "".join(text for _, text in answers)
    cases = [r["MessageControlId"] for r in query("SELECT TOP 20 MessageControlId FROM Readback_Trace.Decision ORDER BY ID DESC", ["MessageControlId"])]
    for case in cases:
        out, err = tool("explain_decision", controlId=case)
        blob += out or ""
    check(not any(i in blob for i in identifiers), "an answer carries a patient identifier")
    check("patientId" not in blob.lower() and "PatientId" not in blob, "an answer carries a patient field")
    check(not __import__("re").search(r"SYN\d{6,}", blob), "an answer carries something shaped like a patient identifier")
    out, err = tool("explain_decision", controlId="SYN0000001")
    check(out is None and err, "a patient identifier was accepted as a case id")
    out, err = tool("explain_decision", controlId="x'; DROP TABLE y; --")
    check(out is None and err, "a value that is not a case id was accepted")

    if failures:
        print("FAILED (%d)" % len(failures))
        return 1
    print("mcp check passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
