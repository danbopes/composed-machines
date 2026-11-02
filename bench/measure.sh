#!/bin/bash
# The quiet-box measurement run behind RESULTS.md, as one command.
# Builds whatever saves are missing, then benchmarks everything pinned to
# CPUS, then writes RESULTS.md. Expect ~45 min of benchmarking on a quiet box.
set -eu
cd "$(dirname "$0")"
CPUS=${CPUS:-8-11}
NOTE=${NOTE:-quiet box}
T=3600
./suite.py --group native -n 2000  --ticks $T --runs 5 --skip 300 --cpus $CPUS --note "$NOTE"
./suite.py --group native -n 20000 --ticks $T --runs 5 --skip 300 --cpus $CPUS --note "$NOTE"
./suite.py --group composed -n 2000 --ticks $T --runs 5 --skip 300 --cpus $CPUS --note "$NOTE"
./suite.py --group mulark --ticks $T --runs 5 --skip 600 --cpus $CPUS --note "$NOTE"
for s in "pY 134" "pY Season 3 A2 Fixed" "pY Fixed"; do
  ./bench_save.py "${FACTORIO_DIR:-$HOME/factorio}/saves/$s.zip" --ticks $T --runs 3 --skip 300 \
    --cpus $CPUS --note "$NOTE"
  # Counts do not change between reruns; the census costs ~5 min per save.
  [ -f "results/${s// /_}.census.json" ] || ./census_save.py "saves/real/${s// /_}.zip" "${s// /_}"
done
./report.py > RESULTS.md
