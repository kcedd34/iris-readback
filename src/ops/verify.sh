#!/usr/bin/env bash
# Waits until the Readback production is running, then exits 0. Exits non-zero with a message otherwise.
# Usage: verify.sh [timeout-seconds] (runs on the host against the compose service).
set -uo pipefail
timeout="${1:-180}"
deadline=$((SECONDS + timeout))
while [ "$SECONDS" -lt "$deadline" ]; do
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
echo "verify: the Readback production did not start within ${timeout}s. See: docker compose logs iris" >&2
exit 1
