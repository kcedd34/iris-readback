#!/usr/bin/env bash
# The README gate: the four items the organizers require, the sections, the figures against the evaluation report.
# Usage: src/ops/check-readme.sh [README.md]   |   src/ops/check-readme.sh --print-tables
exec python3 "$(dirname "$0")/check_readme.py" "$@"
