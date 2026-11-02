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
    # The workflow REST layer (the person's task list) installs after the production starts and needs network once. Wait for it,
    # but never fail on it: without network the read-back rule and the tasks still work through the engine.
    wf_deadline=$((SECONDS + 240))
    while [ "$SECONDS" -lt "$wf_deadline" ]; do
      wf="$(docker compose exec -T iris iris session IRIS -U USER 2>/dev/null <<'OS'
write "RB_WF=",##class(%Dictionary.CompiledClass).%ExistsId("isc.wf.REST"),!
halt
OS
)"
      if printf '%s' "$wf" | grep -q "RB_WF=1"; then
        echo "Workflow REST layer is installed."
        exit 0
      fi
      sleep 5
    done
    echo "Workflow REST layer is not installed yet (it installs after the start and needs network once); the person's task list may take a minute or stay unavailable." >&2
    exit 0
  fi
  sleep 5
done
echo "verify: the Readback production did not start within ${timeout}s. See: docker compose logs iris" >&2
exit 1
