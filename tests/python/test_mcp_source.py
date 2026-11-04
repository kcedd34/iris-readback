"""The read-only MCP server, from its source: no tool writes, none confirms anything, and the refusal is stated."""
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MCP = os.path.join(ROOT, "src", "Readback", "MCP")


def source(name):
    with open(os.path.join(MCP, name), encoding="utf-8") as handle:
        return handle.read()


# What would write, close, confirm or complete: a save or delete of an object, a global set or kill, a write statement of SQL, a call that closes an
# alert or answers a task. The tool classes (Impl and Tools) may contain none of it.
FORBIDDEN = [r"%Save\b", r"%Delete", r"%DeleteId", r"\bKill\b", r"\bSet\s+\^", r"\bMerge\b", r"\bINSERT\b", r"\bUPDATE\b", r"\bDELETE\b", r"\bTSTART\b",
             r"Alerts\)\.Close", r"\.Confirm\(", r"\.Reviewed\b", r"ReadbackTask", r"ReviewTask", r"SendRequest", r"\.%Action", r"\$System\.OBJ"]


def test_the_tool_classes_contain_nothing_that_writes():
    for name in ("Impl.cls", "Tools.cls"):
        text = source(name)
        for pattern in FORBIDDEN:
            assert not re.search(pattern, text), f"{name} contains {pattern}"


def test_there_is_no_tool_that_confirms_closes_or_completes():
    names = re.findall(r'<Tool Name="([^"]+)"', source("Tools.cls"))
    assert names == ["list_pending_criticals", "explain_decision", "read_evaluation", "read_ablation"]
    for name in names:
        assert not re.search(r"confirm|close|complete|ack|readback_|reviewed|submit|send", name), name


def test_every_tool_is_marked_read_only():
    text = source("Tools.cls")
    assert text.count('<Tool Name=') == text.count('<Requirement Name="ReadOnly" Value="1"/>') == 4


def test_the_service_is_locked_to_its_resource_and_serves_only_the_read_tools():
    text = source("Service.cls")
    assert 'Parameter RESOURCE = "Readback_MCP"' in text and 'Parameter SPECIFICATION = "Readback.MCP.Tools"' in text


def test_the_role_that_opens_the_service_goes_to_the_read_only_account_only():
    with open(os.path.join(ROOT, "src", "Readback", "Workflow", "Setup.cls"), encoding="utf-8") as handle:
        setup = handle.read()
    assert 'tName="observer":"ReadbackMcp"' in setup
    assert "Role = \"ReadbackMcp\"" in source("Setup.cls")


def test_the_web_application_is_created_with_the_mcp_server_type_bit():
    text = source("Setup.cls")
    assert 'Set tProps("Type") = 18' in text and "+ 16" in text
