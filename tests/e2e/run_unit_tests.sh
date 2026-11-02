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
printf '%s\n' "$out" | grep -E "Test[A-Za-z0-9]+ failed|FAILED|ERROR #|Some tests|All PASSED|Readback.Test.* (passed|failed)" | sed 's/^ *//'
echo "Test methods passed: $(printf '%s\n' "$out" | grep -cE '^ +Test[A-Za-z0-9]+ passed'), failed: $(printf '%s\n' "$out" | grep -cE '^ +Test[A-Za-z0-9]+ failed')"
# The verdict is the summary the runner prints, not a search for error text: tests that assert an error print benign "ERROR #" lines.
# A here-string, not a pipe: with pipefail a pipe into grep -q fails with SIGPIPE on a long output and the condition turns false.
if ! grep -q "All PASSED" <<< "$out"; then exit 1; fi
if [ "$(printf '%s\n' "$out" | grep -cE '^ +Test[A-Za-z0-9]+ failed')" -gt 0 ]; then exit 1; fi
if grep -qE "^Some tests FAILED" <<< "$out"; then exit 1; fi
