"""OpenAI-compatible endpoint used only by tests.

Listens on 127.0.0.1:8099, answers /v1/chat/completions, logs each request body to
/tmp/mock-requests.jsonl, and picks its behavior from a MODE:<name> marker in the messages.
Modes: 500, 429, refusal, badjson, empty, nousage, slow, noncrit, recollect, echo500, echo401.
The echo modes put the received credential in the error text, as a provider that echoes it would. The default answer is a valid decision.

Tool modes (the agent has tools; a round with no tool message yet is the first round):
toolgood (history, change and sample quality in one round, then an answer that cites exactly the identifiers the tools returned),
toolpolicy (history and a policy search in one round, then the same kind of answer), toolhemo (a policy search for a hemolyzed sample),
toolquery (a policy search whose query is read from /tmp/mock-query),
toolnone (answers at once, no tool), toolbad (cites an identifier no tool returned), toolunknown (asks for a tool that does not exist),
toolmany (eight calls in one round), toolloop (a new call every round, forever), toolloopsame (the same call every round),
toollower (reads the change verdict and answers NON_CRITICAL anyway). The usage of a tool round grows with the rounds, so a test can
tell the sum of the rounds from the last round alone.
"""
import json
import re
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = "/tmp/mock-requests.jsonl"
VALID_DECISION = {
    "decision": "CRITICAL",
    "severity": 3,
    "rationale": "The value is above the critical limit.",
    "evidence": ["current-result"],
    "confidence": "high",
}


def tool_call(index, name, arguments=None):
    return {"id": "call_%d" % index, "type": "function", "function": {"name": name, "arguments": json.dumps(arguments or {})}}


def returned_ids(messages):
    """Every id the tool messages of the conversation carry, in order, so an answer can cite exactly what was returned."""
    ids = []
    for message in messages:
        if message.get("role") != "tool":
            continue
        content = message.get("content") or ""
        try:
            value = json.loads(content)
            if isinstance(value, str):
                value = json.loads(value)
        except ValueError:
            continue
        stack = [value]
        while stack:
            node = stack.pop(0)
            if isinstance(node, dict):
                if isinstance(node.get("id"), str) and node["id"] not in ids:
                    ids.append(node["id"])
                stack.extend(node.values())
            elif isinstance(node, list):
                stack.extend(node)
    return ids


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _send(self, code, payload):
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _tool_mode(self, mode, messages):
        rounds_done = sum(1 for m in messages if m.get("role") == "tool")
        # Parallel calls come back as several tool messages: count the assistant turns that asked, not the messages.
        turns = sum(1 for m in messages if m.get("role") == "assistant" and m.get("tool_calls"))
        usage = {"prompt_tokens": 120 + 30 * turns, "completion_tokens": 40, "total_tokens": 160 + 30 * turns}
        ids = returned_ids(messages)
        calls = None
        if mode == "toolgood" and turns == 0:
            calls = [tool_call(1, "get_patient_history"), tool_call(2, "get_delta_assessment"), tool_call(3, "get_sample_quality")]
        elif mode == "toolhemo" and turns == 0:
            calls = [tool_call(1, "search_policy", {"query": "hemolyzed sample with high potassium"})]
        elif mode == "toolquery" and turns == 0:
            # The query comes from a file the test writes, so a test can search for exactly the description of a stored case.
            try:
                with open("/tmp/mock-query") as handle:
                    query_text = handle.read().strip()
            except OSError:
                query_text = "potassium"
            calls = [tool_call(1, "search_policy", {"query": query_text})]
        elif mode == "toolpolicy" and turns == 0:
            calls = [tool_call(1, "get_patient_history"), tool_call(2, "search_policy", {"query": "potassium above the critical limit"})]
        elif mode == "toollower" and turns == 0:
            calls = [tool_call(1, "get_delta_assessment")]
        elif mode == "toolunknown" and turns == 0:
            calls = [tool_call(1, "no_such_tool")]
        elif mode == "toolmany" and turns == 0:
            calls = [tool_call(i, "get_sample_quality") for i in range(1, 9)]
        elif mode == "toolloop":
            calls = [tool_call(turns + 1, "get_patient_history", {"limit": 1 + (turns % 3)})]
        elif mode == "toolloopsame":
            calls = [tool_call(turns + 1, "get_sample_quality")]
        if calls:
            message = {"role": "assistant", "content": None, "tool_calls": calls}
            finish = "tool_calls"
        else:
            decision = dict(VALID_DECISION)
            decision["evidence"] = ["current-result"] + ids
            if mode == "toolbad":
                decision["evidence"] = ["current-result", "earlier-result-9"]
            if mode == "toollower":
                decision.update(decision="NON_CRITICAL", severity=0, rationale="Within the usual range.")
            message = {"role": "assistant", "content": json.dumps(decision)}
            finish = "stop"
        reply = {"id": "chatcmpl-mock", "object": "chat.completion", "created": 1, "model": "mock-model",
                 "choices": [{"index": 0, "message": message, "finish_reason": finish}], "usage": usage}
        self._send(200, reply)

    def do_GET(self):
        self._send(200, {"object": "list", "data": [{"id": "mock-model", "object": "model"}]})

    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        body = json.loads(raw or b"{}")
        with open(LOG, "ab") as handle:
            handle.write(json.dumps({"path": self.path, "auth": self.headers.get("Authorization"), "body": body}).encode() + b"\n")
        text = json.dumps(body.get("messages", []))
        usage = {"prompt_tokens": 120, "completion_tokens": 40, "total_tokens": 160}
        message = {"role": "assistant", "content": json.dumps(VALID_DECISION)}
        found = re.search(r"MODE:(tool\w+)", text)
        if found:
            return self._tool_mode(found.group(1), body.get("messages", []))
        if "MODE:slow" in text:
            time.sleep(8)
        credential = self.headers.get("Authorization") or ""
        if "MODE:echo500" in text:
            return self._send(500, {"error": {"message": "upstream failure for %s (Authorization: %s)" % (credential, credential), "type": "server_error"}})
        if "MODE:echo401" in text:
            return self._send(401, {"error": {"message": "Incorrect API key provided: %s. You can find your API key at the provider site." % credential.replace("Bearer ", ""), "type": "invalid_request_error"}})
        if "MODE:noncrit" in text:
            message["content"] = json.dumps(dict(VALID_DECISION, decision="NON_CRITICAL", severity=0, rationale="Within the usual range."))
        if "MODE:recollect" in text:
            message["content"] = json.dumps(dict(VALID_DECISION, decision="RECOLLECT", severity=0, rationale="The sample is hemolyzed."))
        if "MODE:500" in text:
            return self._send(500, {"error": {"message": "mock internal error", "type": "server_error"}})
        if "MODE:429" in text:
            return self._send(429, {"error": {"message": "mock rate limited", "type": "rate_limit"}})
        if "MODE:refusal" in text:
            message = {"role": "assistant", "content": None, "refusal": "I cannot help with that request."}
        if "MODE:badjson" in text:
            message["content"] = "this is not json"
        if "MODE:empty" in text:
            message["content"] = ""
        if "MODE:nousage" in text:
            usage = None
        reply = {"id": "chatcmpl-mock", "object": "chat.completion", "created": 1, "model": "mock-model",
                 "choices": [{"index": 0, "message": message, "finish_reason": "stop"}]}
        if usage:
            reply["usage"] = usage
        self._send(200, reply)


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 8099), Handler).serve_forever()
