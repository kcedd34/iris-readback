#!/usr/bin/env bash
# Waits until the Readback production is running, then exits 0. Exits non-zero with a message otherwise.
# Usage: verify.sh [timeout-seconds] (runs on the host against the compose service).
set -uo pipefail
timeout="${1:-180}"
deadline=$((SECONDS + timeout))
# A production that is not running is said so as soon as the reason is in the log: the container stopped, restarted, or the start was aborted.
stopped() {
  local state reasons
  state="$(docker compose ps --all --format '{{.State}}' iris 2>/dev/null | head -1)"
  reasons="$(docker compose logs iris 2>&1 | grep -E 'READBACK (ABORTED|COMPILE|UNITS|START|CONFIG|ROLES|WEBAPP|MCP)' | tail -4 | cut -c1-300)"
  if [ -n "$state" ] && [ "$state" != "running" ]; then
    echo "verify: the production is not running: the iris container is $state." >&2
  elif [ -n "$reasons" ] && printf '%s' "$reasons" | grep -q 'READBACK \(ABORTED\|START\)'; then
    echo "verify: the production is not running: the start reported a failure." >&2
  else
    return 1
  fi
  [ -n "$reasons" ] && printf '%s\n' "$reasons" >&2
  echo "See: docker compose logs iris" >&2
  return 0
}
while [ "$SECONDS" -lt "$deadline" ]; do
  if stopped; then exit 1; fi
  out="$(docker compose exec -T iris iris session IRIS -U USER 2>/dev/null <<'OS'
write "RB_STATE=",##class(Ens.Director).IsProductionRunning("Readback.Production"),!
halt
OS
)"
  if printf '%s' "$out" | grep -q "RB_STATE=1"; then
    echo "Readback production is running."
    # The workflow REST layer (the person's task list) is installed while the image is built, so it is there now. Its absence is an error.
    wf="$(docker compose exec -T iris iris session IRIS -U USER 2>/dev/null <<'OS'
write "RB_WF=",##class(%Dictionary.CompiledClass).%ExistsId("isc.wf.REST"),!
halt
OS
)"
    if printf '%s' "$wf" | grep -q "RB_WF=1"; then
      echo "Workflow REST layer is installed."
      exit 0
    fi
    echo "verify: the Workflow REST layer is missing from the image. Rebuild it with network access: docker compose build --no-cache iris" >&2
    exit 1
  fi
  sleep 5
done
echo "verify: the production is not running: the Readback production did not start within ${timeout}s. See: docker compose logs iris" >&2
exit 1
