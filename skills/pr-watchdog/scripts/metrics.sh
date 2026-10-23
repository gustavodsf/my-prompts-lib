#!/usr/bin/env bash
# Thin wrapper -- the accounting lives in metrics.py. The shell version mis-identified
# lanes (it matched the reconciler's transcript) and reported output tokens only, which is
# 0.6% of actual throughput.
exec python3 "$(dirname "${BASH_SOURCE[0]}")/metrics.py" "$@"
