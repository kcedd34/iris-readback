#!/usr/bin/env bash
# Runs every check of the triage core, units, budget, retrieval and trace, in order, from a clean stack. Stops at the first failure.
# Needs: docker, the image irishealth-community:2026.3.0AI.154.0, python3 with pytest, network once for the IPM client.
set -euo pipefail
cd "$(dirname "$0")/../.."
export READBACK_DEMO_PASSWORD="${READBACK_DEMO_PASSWORD:-demo-pass-for-tests}"
export OPENAI_API_KEY=""
PY="${PYTHON:-python3}"
step() { printf '\n=== %s ===\n' "$1"; sleep 8; }

step "pre-flight";               src/ops/preflight.sh
step "clean stack, no key";      docker compose down -v >/dev/null 2>&1 || true
                                 docker compose up -d --build --force-recreate >/dev/null
                                 src/ops/verify.sh 240
step "unit suites";              tests/e2e/run_unit_tests.sh
step "java unit converter";      tests/java/run_java_tests.sh
step "python tests";             "$PY" -m pytest -q tests/python
step "units end to end";         "$PY" tests/e2e/units_check.py
step "budget";                   "$PY" tests/e2e/budget_check.py
step "retrieval";                "$PY" tests/e2e/retrieval_check.py
step "retrieval offline";        tests/e2e/offline_check.sh
step "replay";                   "$PY" tests/e2e/replay_check.py
step "read-back";                "$PY" tests/e2e/readback_check.py
step "hostile agent";            "$PY" tests/e2e/hostile_check.py
step "intake (feature 1)";       tests/e2e/flow_check.sh
step "trace and indicators";     "$PY" tests/e2e/trace_check.py
step "live path against a mock"; "$PY" tests/e2e/live_mock_check.py
printf '\nAll triage core, units, budget, retrieval and trace checks passed.\n'
