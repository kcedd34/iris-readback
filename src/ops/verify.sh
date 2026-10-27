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
    exit 0
  fi
  sleep 5
done
echo "verify: the Readback production did not start within ${timeout}s. See: docker compose logs iris" >&2
exit 1
