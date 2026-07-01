#!/usr/bin/env bash
# The locked, locally-validated matrix configuration for the final Azure run. This just exports the
# config and calls run-matrix.sh, so the VM runs exactly what was validated on the laptop.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export MEMS="1g 2g" CPUS="1 2" RUNS=5 \
  PRELOAD_ACCOUNTS=300000 PRELOAD_TX=4 IO_DELAY=5 VUS=100 STMT_LIMIT=50 \
  WARMUP=30s MEASURE=60s

exec bash "$HERE/run-matrix.sh"
