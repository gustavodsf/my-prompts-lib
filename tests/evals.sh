#!/usr/bin/env bash
# Static prompt evals must pass on every change.
set -euo pipefail
"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/evals/run.sh"
