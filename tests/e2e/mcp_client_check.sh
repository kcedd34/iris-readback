#!/usr/bin/env bash
# A real MCP session with the product's read-only server, through the platform's own gateway (iris-mcp-server, shipped in the image) and a standard
# MCP client (the MCP Inspector, in command-line mode, in a throwaway Node container that shares the network of the IRIS container).
# Needs the stack running, READBACK_DEMO_PASSWORD, and network once for the Inspector package. Nothing is installed in the repository or the image.
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${READBACK_DEMO_PASSWORD:?READBACK_DEMO_PASSWORD is not set}"
fail() { echo "mcp client check FAILED: $*" >&2; exit 1; }
INSPECTOR="@modelcontextprotocol/inspector@2.13.0"
NODE_IMAGE="node:24.22.2-alpine"
cid="$(docker compose ps -q iris)"
[ -n "$cid" ] || fail "the iris service is not running"

# The gateway's configuration goes in through the standard input, so the password is never on a command line. It ends itself after four minutes.
docker compose exec -T iris sh -c 'cat > /tmp/mcp-client-check.toml' <<TOML
[[iris]]
name = "readback"
[iris.server]
host = "127.0.0.1"
port = 1972
username = "observer"
password = "${READBACK_DEMO_PASSWORD}"
[[iris.endpoints]]
path = "/readback/mcp"
TOML
docker compose exec -d iris sh -c 'timeout 240 /usr/irissys/bin/iris-mcp-server -c /tmp/mcp-client-check.toml -t http://127.0.0.1:8000 --log-level warn run > /tmp/mcp-client-check.log 2>&1'
auth="$(printf 'observer:%s' "$READBACK_DEMO_PASSWORD" | base64 -w0)"

inspect() {  # inspect <extra header args...> -- <inspector args...>
  docker run --rm --network "container:$cid" -e AUTH="$auth" "$NODE_IMAGE" sh -c "npx -y $INSPECTOR --cli http://127.0.0.1:8000/mcp --transport http $*" 2>&1 | grep -v '^npm notice'
}
hdr='--header "Authorization: Basic $AUTH"'

# The gateway needs a few seconds to be up.
tools=""
for _ in $(seq 1 20); do
  tools="$(inspect "$hdr --method tools/list" || true)"
  printf '%s' "$tools" | grep -q 'readback_mcp_' && break
  sleep 3
done
for name in list_pending_criticals explain_decision read_evaluation read_ablation; do
  printf '%s' "$tools" | grep -q "\"readback_mcp_$name\"" || fail "the tool $name is not listed by the gateway: $tools"
done
[ "$(printf '%s' "$tools" | grep -c '"name": "readback_mcp_')" = "4" ] || fail "the gateway lists other than the four read tools: $tools"
printf '%s' "$tools" | grep -o '"name": "readback_mcp_[a-z_]*"' | sed 's/.*readback_mcp_//' | grep -qiE 'confirm|close|complete|ack|review' && fail "a tool that confirms or closes is listed"

pending="$(inspect "$hdr --method tools/call --tool-name readback_mcp_list_pending_criticals")"
printf '%s' "$pending" | grep -q '"isError": false' || fail "the pending criticals could not be read: $pending"
printf '%s' "$pending" | grep -qE 'SYN[0-9]{6,}' && fail "the pending criticals carry a patient identifier"

evaluation="$(inspect "$hdr --method tools/call --tool-name readback_mcp_read_evaluation")"
printf '%s' "$evaluation" | grep -q 'silencedCriticals' || fail "the evaluation could not be read: $evaluation"

refused="$(inspect "$hdr --method tools/call --tool-name readback_mcp_confirm_readback" || true)"
printf '%s' "$refused" | grep -q 'tool_not_found' || fail "the call of a tool that confirms the read-back was not answered with tool_not_found: $refused"

# An account without the Readback_MCP resource is listed no tool either.
other="$(printf 'communicator1:%s' "$READBACK_DEMO_PASSWORD" | base64 -w0)"
stranger="$(docker run --rm --network "container:$cid" -e AUTH="$other" "$NODE_IMAGE" sh -c "npx -y $INSPECTOR --cli http://127.0.0.1:8000/mcp --transport http --header \"Authorization: Basic \$AUTH\" --method tools/list" 2>&1 | grep -v '^npm notice' || true)"
printf '%s' "$stranger" | grep -q 'readback_mcp_' && fail "the gateway listed the tools to an account without the Readback_MCP resource: $stranger"

anonymous="$(docker run --rm --network "container:$cid" "$NODE_IMAGE" sh -c "npx -y $INSPECTOR --cli http://127.0.0.1:8000/mcp --transport http --method tools/list" 2>&1 | grep -v '^npm notice' || true)"
printf '%s' "$anonymous" | grep -q 'readback_mcp_' && fail "the gateway listed the tools to a caller without credentials: $anonymous"

docker compose exec -T iris sh -c 'rm -f /tmp/mcp-client-check.toml' >/dev/null 2>&1 || true
echo "mcp client check passed"
