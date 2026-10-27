#!/usr/bin/env bash
# End-to-end flow check: 50 valid and 10 malformed HL7 messages through the running production.
# Requires: docker compose up -d, src/ops/verify.sh passing, python3.
set -euo pipefail
cd "$(dirname "$0")/../.."
exec python3 tests/e2e/flow_check.py
