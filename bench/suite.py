#!/usr/bin/env python3
"""One command for the native baseline matrix: build (if needed) and benchmark
every variant at one cell count.

    ./suite.py -n 2000 --ticks 3600 --runs 5        # the quiet-box run
    ./suite.py -n 200 --ticks 300 --runs 2 --rebuild
    ./suite.py --group composed -n 2000 --ticks 3600 --runs 5   # cl-* vs native twins
    ./suite.py --group composed --only cl-hearth,cl-brazier -n 2000   # just those + their twins
    ./suite.py --group mulark --ticks 3600 --runs 5    # mulark's public maps
    ./suite.py --group all ...                         # both

In the composed group a twin is every PAIRS entry that is a grid cell
(native-*, poll-*, beacon-*, reactor-*); twins that are native-matrix variants
(stone-furnace, assembler, chests, ...) come from the native group at the same n.
Saves are named <variant>-<n>; an existing save is reused unless --rebuild.
The mulark group is every map in saves/mulark/manifest.json that loads on
2.1.24 (fetch_mulark.py downloads them); it runs with --drop-missing because
those saves carry editor helper mods (region-cloner) that are not installed.
"""
import argparse
import json
import subprocess
import sys

import run_bench
from benchlib import BENCH, SAVES
from make_save import COMPOSED, NATIVE_MATRIX as VARIANTS, PAIRS


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--group", choices=["native", "composed", "mulark", "all"], default="native")
    ap.add_argument("--skip", type=int, default=0, help="passed to run_bench.py")
    ap.add_argument("-n", "--cells", type=int, default=2000)
    ap.add_argument("--variants", default=",".join(VARIANTS))
    ap.add_argument("--rebuild", action="store_true")
    ap.add_argument("--settle", type=int, default=1800)
    ap.add_argument("--ticks", type=int, default=1000)
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--cpus")
    ap.add_argument("--note")
    ap.add_argument("--only", help="composed group: comma-separated cl-* names; build and "
                                   "benchmark only these and their twins")
    args = ap.parse_args()
    only = [n for n in (args.only or "").split(",") if n]
    unknown = [n for n in only if n not in COMPOSED]
    if unknown:
        ap.error(f"--only: not composed entities: {', '.join(unknown)} (known: {', '.join(COMPOSED)})")
    if only and args.group != "composed":
        ap.error("--only applies to --group composed")

    extra = ["--ticks", str(args.ticks), "--runs", str(args.runs), "--skip", str(args.skip)]
    extra += ["--cpus", args.cpus] if args.cpus else []
    extra += ["--note", args.note] if args.note else []

    if args.group in ("mulark", "all"):
        manifest = json.loads((SAVES / "mulark/manifest.json").read_text())
        maps = [str(SAVES / "mulark" / n) for n, m in manifest.items() if m.get("loads_on_2_1_24")]
        rc = run_bench.main(maps + extra + ["--drop-missing"])
        if rc or args.group == "mulark":
            return rc

    if args.group == "composed":
        # empty baseline + every composed entity + its same-layout native twin
        composed = only or COMPOSED
        names = ["empty"] + composed + sorted({n for c in composed for n in PAIRS.get(c, [])
                                                if n not in VARIANTS})
        saves = []
        for v in names:
            n = 0 if v == "empty" else args.cells
            save = SAVES / f"{v}-{n}.zip"
            if args.rebuild or not save.exists():
                rc = subprocess.call([sys.executable, str(BENCH / "make_save.py"), v, "-n", str(n),
                                      "--name", f"{v}-{n}", "--settle", str(max(args.settle, 3600))])
                if rc != 0:
                    return rc
            saves.append(str(save))
        return run_bench.main(saves + extra)

    saves = []
    for v in args.variants.split(","):
        name = f"{v}-{args.cells}"
        save = SAVES / f"{name}.zip"
        if args.rebuild or not save.exists():
            rc = subprocess.call([sys.executable, str(BENCH / "make_save.py"), v, "-n",
                                  str(args.cells), "--name", name, "--settle", str(args.settle)])
            if rc != 0:
                print(f"make_save failed for {v} (rc {rc})", file=sys.stderr)
                return rc
        saves.append(str(save))
    return run_bench.main(saves + extra)


if __name__ == "__main__":
    sys.exit(main())
