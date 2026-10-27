#!/usr/bin/env bash
# Runs the %UnitTest suites inside the compose service. Exits non-zero if any test fails.
set -uo pipefail
cd "$(dirname "$0")/../.."
out="$(docker compose exec -T iris iris session IRIS -U USER <<'OS' 2>&1
set ^UnitTestRoot="/opt/readback/tests/objectscript"
do ##class(%UnitTest.Manager).RunTest("Readback","/nodelete")
halt
OS
)"
printf '%s\n' "$out" | tail -40
if printf '%s' "$out" | grep -qE "Failed|FAILED|ERROR #"; then exit 1; fi
