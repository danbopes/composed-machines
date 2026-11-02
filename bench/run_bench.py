#!/usr/bin/env python3
"""Run `factorio --benchmark` on a save in an isolated mod/write directory.

The mod directory is built from the save's own mod list (exact versions where
available) and `--sync-mods` is run in it so startup settings match the save.
Nothing outside bench/runs/<name>/ is written; the save is only read.

Factorio prints per-tick timings in nanoseconds when --benchmark-verbose is
given. Per run we keep mean/median/p95 of wholeUpdate and the mean of every
non-zero category; across runs the headline is the fastest run's mean, since
interference from other load only ever adds time. One JSON line per invocation
is appended to results/<name>.jsonl.
"""
import argparse
import json
import os
import platform
import statistics
import subprocess
import sys
import time
from pathlib import Path

from benchlib import BINARY, RESULTS, RUNS, build_run_dir, sync_settings

# Columns worth a line in the summary table, in display order. Everything
# non-zero is still kept in the JSON.
HEADLINE = ["wholeUpdate", "gameUpdate", "entityUpdate", "electricHeatFluidCircuitUpdate",
            "electricNetworkUpdate", "fluidFlowUpdate", "transportLinesUpdate",
            "controlBehaviorUpdate", "trains", "trainPathFinder", "logisticManagerUpdate",
            "constructionManagerUpdate", "pollutionUpdate", "chartRefresh", "chartUpdate",
            "luaGarbageIncremental", "scriptUpdate", "crcComputation"]


def parse(output: str) -> dict:
    """Split Factorio's benchmark output into per-run summaries and tick rows."""
    summaries, runs, cur = [], {}, None
    header = None
    for raw in output.splitlines():
        line = raw.strip()
        if line.startswith("Performed "):
            # "Performed 100 updates in 6.514 ms"
            parts = line.split()
            summaries.append({"updates": int(parts[1]), "total_ms": float(parts[4])})
        elif line.startswith("avg:"):
            # "avg: 0.065 ms, min: 0.034 ms, max: 0.191 ms"
            f = line.replace(",", "").split()
            summaries[-1].update(avg_ms=float(f[1]), min_ms=float(f[4]), max_ms=float(f[7]))
        elif line.startswith("checksum:"):
            summaries[-1]["checksum"] = int(line.split()[1])
        elif line.startswith("run ") and line.endswith(":"):
            cur = int(line[4:-1])
            runs[cur] = []
        elif line.startswith("tick,"):
            header = [c for c in line.split(",") if c]
        elif cur is not None and header and line.startswith("t") and line[1:2].isdigit():
            vals = line.split(",")
            row = {"tick": int(vals[0][1:])}
            for k, v in zip(header[1:], vals[1:]):
                if v:
                    row[k] = int(v)
            runs[cur].append(row)
    return {"summaries": summaries, "runs": [runs[k] for k in sorted(runs)]}


def run_stats(rows: list, skip: int) -> dict:
    rows = rows[skip:]
    if not rows:
        return {}
    cols = [k for k in rows[0] if k not in ("tick", "timestamp")]
    means = {}
    for c in cols:
        m = sum(r.get(c, 0) for r in rows) / len(rows) / 1e6
        if m > 0:
            means[c] = round(m, 5)
    whole = sorted(r["wholeUpdate"] / 1e6 for r in rows)
    return {
        "ticks": len(rows),
        "mean_ms": round(statistics.fmean(whole), 5),
        "median_ms": round(statistics.median(whole), 5),
        "p95_ms": round(whole[min(len(whole) - 1, int(0.95 * len(whole)))], 5),
        "min_tick_ms": round(whole[0], 5),
        "category_mean_ms": means,
    }


def benchmark(save: Path, name: str, ticks: int, runs: int, verbose: str, skip: int,
              sync: bool, cpus: str | None, timeout: int, note: str | None,
              drop_missing: bool = False) -> dict:
    root = RUNS / name
    t0 = time.monotonic()
    run = build_run_dir(save, root)
    if run["missing"] and not drop_missing:
        raise SystemExit("missing mods, cannot load this save (--drop-missing loads it "
                         "without them):\n  " + "\n  ".join(run["missing"]))
    for m in run["missing"]:
        print(f"   warning: dropping missing mod: {m}")
    for s in run["substituted"]:
        print(f"   warning: version substituted: {s}")
    if sync:
        out = sync_settings(run, save, timeout=timeout)
        if "Mods synced" not in out:
            raise SystemExit("--sync-mods failed:\n" + out)
    setup_s = time.monotonic() - t0

    cmd = [str(BINARY), "--config", str(run["config"]), "--mod-directory", str(run["mods"]),
           "--benchmark", str(save), "--benchmark-ticks", str(ticks),
           "--benchmark-runs", str(runs), "--disable-audio", "--disable-migration-window"]
    if verbose:
        cmd += ["--benchmark-verbose", verbose]
    if cpus:
        cmd = ["taskset", "-c", cpus] + cmd
    load = os.getloadavg()
    t1 = time.monotonic()
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    wall = time.monotonic() - t1
    out = proc.stdout + proc.stderr
    (root / "factorio-output.txt").write_text(out)
    parsed = parse(out)
    if proc.returncode != 0 or len(parsed["summaries"]) != runs:
        tail = "\n".join(l for l in out.splitlines() if not l.startswith("t"))[-3000:]
        raise SystemExit(f"benchmark failed (rc={proc.returncode}, "
                         f"{len(parsed['summaries'])}/{runs} runs):\n{tail}")

    per_run = []
    for i, summ in enumerate(parsed["summaries"]):
        entry = dict(summ)
        if i < len(parsed["runs"]):
            entry.update(run_stats(parsed["runs"][i], skip))
        per_run.append(entry)
    key = "mean_ms" if "mean_ms" in per_run[0] else "avg_ms"
    best = min(per_run, key=lambda r: r[key])
    means = [r[key] for r in per_run]
    return {
        "name": name, "save": str(save), "when": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "factorio": run["header"]["map_version"], "mods": len(run["header"]["mods"]),
        "substituted": run["substituted"], "dropped": run["missing"], "ticks": ticks, "runs": runs, "skip": skip,
        "verbose": verbose, "cpus": cpus, "note": note,
        "best_mean_ms": best[key], "median_of_means_ms": round(statistics.median(means), 5),
        "spread_pct": round(100 * (max(means) - min(means)) / min(means), 1) if min(means) else 0,
        "best_categories_ms": best.get("category_mean_ms", {}),
        "per_run": per_run, "loadavg_before": load, "loadavg_after": os.getloadavg(),
        "host": platform.node(),
        "setup_s": round(setup_s, 1), "bench_wall_s": round(wall, 1),
    }


def print_table(res: dict) -> None:
    print(f"\n{res['name']}: {res['ticks']} ticks x {res['runs']} runs "
          f"(skip {res['skip']}), setup {res['setup_s']} s, bench {res['bench_wall_s']} s, "
          f"loadavg {res['loadavg_before'][0]:.1f}")
    print(f"  {'run':>3} {'mean ms':>9} {'median':>9} {'p95':>9} {'factorio avg':>12} {'min':>7} {'max':>7}")
    for i, r in enumerate(res["per_run"], 1):
        print(f"  {i:>3} {r.get('mean_ms', 0):>9.4f} {r.get('median_ms', 0):>9.4f} "
              f"{r.get('p95_ms', 0):>9.4f} {r['avg_ms']:>12.3f} {r['min_ms']:>7.3f} {r['max_ms']:>7.3f}")
    print(f"  best mean {res['best_mean_ms']:.4f} ms/update, spread +/-{res['spread_pct']}%")
    cats = res["best_categories_ms"]
    if cats:
        print("  category (best run, mean ms/tick):")
        shown = [c for c in HEADLINE if c in cats]
        rest = sorted((c for c in cats if c not in HEADLINE), key=lambda c: -cats[c])
        for c in shown + rest:
            print(f"    {c:<32} {cats[c]:>9.4f}")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("saves", nargs="+", type=Path, help="save .zip file(s)")
    ap.add_argument("--name", help="result name (default: save file stem; single save only)")
    ap.add_argument("--ticks", type=int, default=1000)
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--skip", type=int, default=0,
                    help="drop the first K ticks of each run from the per-tick stats")
    ap.add_argument("--verbose", default="all",
                    help="--benchmark-verbose value ('' to disable; default all)")
    ap.add_argument("--no-sync", action="store_true", help="skip --sync-mods")
    ap.add_argument("--drop-missing", action="store_true",
                    help="load the save without mods that are not available (Factorio "
                         "removes them on load), e.g. editor helpers like region-cloner")
    ap.add_argument("--cpus", help="pin with taskset -c, e.g. 8-11")
    ap.add_argument("--timeout", type=int, default=3600, help="seconds per Factorio invocation")
    ap.add_argument("--note", help="free text stored with the result")
    args = ap.parse_args(argv)
    if args.name and len(args.saves) > 1:
        ap.error("--name needs a single save")
    RESULTS.mkdir(exist_ok=True)
    for save in args.saves:
        save = save.resolve()
        name = args.name or save.stem.replace(" ", "_")
        res = benchmark(save, name, args.ticks, args.runs, args.verbose, args.skip,
                        not args.no_sync, args.cpus, args.timeout, args.note,
                        args.drop_missing)
        with open(RESULTS / f"{name}.jsonl", "a") as fh:
            fh.write(json.dumps(res) + "\n")
        print_table(res)
    return 0


if __name__ == "__main__":
    sys.exit(main())
