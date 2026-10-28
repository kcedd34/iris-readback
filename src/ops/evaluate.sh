#!/usr/bin/env bash
# Runs the evaluation through the running product and builds the report in data/eval/.
#
#   src/ops/evaluate.sh live <model> [--yes] [--resume] [--output-cap N]   needs the key in the container; paid; prints the estimate first
#   src/ops/evaluate.sh replay [replaySet]                                needs no key; refuses when a key is configured
#   src/ops/evaluate.sh report                                            rebuilds data/eval/report.* from the rows of the runs already made
#
# Start from a fresh stack for every run (docker compose down -v, then up). The key is never printed or written.
set -euo pipefail
cd "$(dirname "$0")/../.."
PYTHON="${PYTHON:-python3}"
PYTHONPATH="src/python${PYTHONPATH:+:$PYTHONPATH}" exec "$PYTHON" -m readback.evaluation.runner "$@"
