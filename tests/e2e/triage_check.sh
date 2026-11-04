#!/usr/bin/env bash
# Runs every check of the triage core, units, budget, retrieval, trace, evaluation, notification, the flow interface, the README gate and the package, in order, from a clean stack. Stops at the first failure.
# Needs: docker, the image irishealth-community:2026.3.0AI.154.0, python3 with pytest, node and npm (the interface checks), network once for the IPM client and the interface build.
set -euo pipefail
cd "$(dirname "$0")/../.."
export READBACK_DEMO_PASSWORD="${READBACK_DEMO_PASSWORD:-demo-pass-for-tests}"
export OPENAI_API_KEY=""
PY="${PYTHON:-python3}"
step() { printf '\n=== %s ===\n' "$1"; sleep 8; }

step "pre-flight";               src/ops/preflight.sh
step "password preflight";       tests/e2e/password_preflight_check.sh
step "clean stack, no key";      docker compose down -v >/dev/null 2>&1 || true
                                 docker compose up -d --build --force-recreate >/dev/null
                                 src/ops/verify.sh 240
step "unit suites";              tests/e2e/run_unit_tests.sh
step "bootstrap stops on a compile error"; tests/e2e/bootstrap_fail_check.sh
step "start waits for the Java gateway"; tests/e2e/start_check.sh
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
step "evaluation (replay)";      PYTHON="$PY" "$PY" tests/e2e/eval_check.py
step "notification";             PYTHON="$PY" "$PY" tests/e2e/notify_check.py
step "ui api";                   (cd tests/e2e && "$PY" ui_api_check.py)
step "ui proxy";                 (cd tests/e2e && "$PY" ui_proxy_check.py)
step "demo messages made by Embedded Python"; (cd tests/e2e && "$PY" generator_check.py)
step "read-only MCP server";      (cd tests/e2e && "$PY" mcp_check.py)
step "MCP client session (gateway and MCP Inspector)"; tests/e2e/mcp_client_check.sh
step "ui browser";               "$PY" tests/e2e/ui_check.py
step "live path against a mock"; "$PY" tests/e2e/live_mock_check.py
step "agent tools against a mock"; (cd tests/e2e && "$PY" tools_check.py)
step "agent governance against a mock"; (cd tests/e2e && "$PY" governance_check.py)
step "password with special characters"; (cd tests/e2e && "$PY" password_check.py)
step "readme gate";              src/ops/check-readme.sh
step "package on a clean instance"; tests/e2e/ipm_check.sh
printf '\nAll triage core, units, budget, retrieval, trace, evaluation, notification, flow interface, readme and package checks passed.\n'
