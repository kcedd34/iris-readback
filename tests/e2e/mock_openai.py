"""OpenAI-compatible endpoint used only by tests.

Listens on 127.0.0.1:8099, answers /v1/chat/completions, logs each request body to
/tmp/mock-requests.jsonl, and picks its behavior from a MODE:<name> marker in the messages.
Modes: 500, 429, refusal, badjson, empty, nousage, slow, noncrit, recollect, echo500, echo401.
The echo modes put the received credential in the error text, as a provider that echoes it would. The default answer is a valid decision.
"""
import json
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
