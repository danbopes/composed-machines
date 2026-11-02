#!/usr/bin/env bash
# Build and run the model. Extra args go to the binary, e.g. ./run.sh 10000 --ticks 120
set -euo pipefail
cd "$(dirname "$0")"
command -v g++ >/dev/null || export CXX=clang++
make -s
./model "$@"
