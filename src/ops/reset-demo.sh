#!/usr/bin/env bash
# Resets the public demo to a clean start: removes the containers and the data volume, then starts the stack again
# from the images already built. Run it from cron, hourly. Nothing is confirmed on anyone's behalf: the read-back
# queue is emptied by removing the cases, never by closing them. The stack comes back in the mode its .env sets.
set -euo pipefail
cd "${READBACK_HOME:-/root/iris-readback}"
exec 9>/tmp/readback-reset.lock
flock -n 9 || exit 0
docker compose down -v --timeout 20
docker compose up -d
echo "$(date -u +%FT%TZ) demo reset"
