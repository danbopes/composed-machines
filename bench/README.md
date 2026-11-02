# bench/ — headless `factorio --benchmark` tooling

Native baselines built in the component-lab harness server, plus real saves
(pY) benchmarked with their own mod list.

## Commands

```bash
cd bench

# Whole native matrix at one size: build missing saves, benchmark them all.
./suite.py -n 2000 --ticks 3600 --runs 5 --note "quiet box"      # the real run
./suite.py -n 200 --ticks 300 --runs 2 --settle 600 --rebuild    # what validation used

# One world: variants chests | stone-furnace | electric-furnace | assembler | idle-furnace
./make_save.py electric-furnace -n 2000            # -> saves/electric-furnace-2000.zip
./run_bench.py saves/electric-furnace-2000.zip --ticks 3600 --runs 5 [--cpus 8-11] [--skip 60]

# Real save, own mod list (copied to saves/real/ first; original untouched)
./bench_save.py "$FACTORIO_DIR/saves/pY 134.zip" --ticks 300 --runs 1
./bench_save.py "$FACTORIO_DIR/saves/pY Season 3 A2 Fixed.zip" --ticks 1000 --runs 3
./bench_save.py "$FACTORIO_DIR/saves/pY Fixed.zip" --ticks 1000 --runs 3
```

Results: one JSON line per invocation in `results/<name>.jsonl` (all per-run
stats, every non-zero timing category, loadavg, CPU pinning, note), plus a
table on stdout. Factorio's raw output for the last run of a save is kept at
`runs/<name>/factorio-output.txt`.

## How it works

- **make_save.py** boots `fh test component-lab --keep` (from `ai-harness/`),
  sends `builds/_common.lua` + `builds/<variant>.lua` (+ `_cells.lua`) through
  `fh rcon file` with an `ARGS` table prepended, lets the world tick
  `--settle` ticks (default 1800), runs `builds/_check.lua` (status histogram,
  products finished), then `fh stop`. The harness server's write dir is
  `~/factorio`, so `/server-save` would land in `~/factorio/saves`; instead the
  tool relies on Factorio saving the booted map (`run/component-lab/session.zip`)
  on SIGTERM and copies that to `saves/<name>.zip`. It refuses to run if a
  component-lab server is already up, unless `--reuse`.
  The non-library mods (aitest, component-lab) are pinned beside the save in
  `saves/<name>.mods/` so a later rerun loads the same code even though the
  component-lab mod is being developed. `saves/<name>.json` holds the build
  report and status check.
- **Worlds** go on a separate flat lab-tile surface `bench` (no resources,
  enemies, cliffs); enemies anywhere are removed, expansion/evolution off,
  pollution off (`--pollution` to keep it). Cells sit in 18x18 blocks around a
  substation (12 cells per block, substations 18 apart = one network), four
  electric-energy-interfaces feed it. Cell = infinity-chest source -> inserter
  -> machine -> inserter -> infinity-chest sink (`remove_unfiltered_items`).
  Measured: `direction = west` inserters pick up west and drop east on 2.1.24.
  | variant | machine | inserters | input |
  |---|---|---|---|
  | chests | N wooden chests, nothing else | - | - |
  | stone-furnace | stone-furnace (burner) | fast | iron-ore + coal |
  | electric-furnace | electric-furnace | fast | iron-ore |
  | assembler | assembling-machine-2, iron-gear-wheel | bulk (fast cannot feed 3 plates/s) | iron-plate |
  | idle-furnace | electric-furnace, empty source | fast | none |
  The `_check` histogram confirmed every active variant at 100% `working`
  machines and idle-furnace at 100% `no_ingredients` (both N=200 and N=2000).
- **run_bench.py** builds `runs/<name>/{mods,write,config.ini}`: symlinks for
  the save's mods (sidecar `.mods/` first, then `~/factorio/mods`, matching the
  recorded version numerically, else the highest with a warning), then
  `factorio --sync-mods` inside that isolated directory so `mod-settings.dat`
  matches the save's startup settings. Then `--benchmark --benchmark-verbose
  all`. `--disable-migration-window` is passed. Nothing is written to
  `~/factorio/{mods,saves,config}`.

## Output format (empirical, 2.1.24)

`--benchmark-verbose all` is accepted. For each run Factorio prints
`Performed N updates in X ms` / `avg: .. min: .. max: ..` / `checksum: ..`,
and after all runs a CSV block per run (`run k:` then a `tick,timestamp,...`
header) with one `t<tick>,...` row per tick. Values are **nanoseconds**.
Columns: `wholeUpdate latencyUpdate gameUpdate planetsUpdate
controlBehaviorUpdate transportLinesUpdate electricHeatFluidCircuitUpdate
electricNetworkUpdate heatNetworkUpdate fluidFlowUpdate entityUpdate
turretTargetAcquisition lightningUpdate tileHeatingUpdate pollutionUpdate
particleUpdate mapGenerator* spacePlatforms collectorNavMesh* crcComputation
consistencyScraper logisticManagerUpdate constructionManagerUpdate pathFinder
trains trainPathFinder commander chartRefresh luaGarbageIncremental
chartUpdate scriptUpdate`, then **per-entity-class update time** (`Inserter`,
`AssemblingMachine`, `Furnace`, `InfinityContainer`, `Loader`, `Radar`, ...
about 70 classes). Per-class columns sum to roughly `entityUpdate`.
The parser's mean of `wholeUpdate` matches Factorio's own `avg` to 3 decimals.

Per run the JSON keeps mean / median / p95 of wholeUpdate and the mean of each
non-zero column; `best_mean_ms` is the fastest run (interference only adds
time) and `spread_pct` the run-to-run range.

## Validation numbers — NOISY, not results

Taken 2026-11-01 with other analysis work, a C++ benchmark and (for some) a pY
load running; loadavg 9-12 on 16 cores. They prove the pipeline, nothing more.
300 ticks per run. ms per update.

| save | runs | best mean | spread | median tick | entityUpdate | per-class |
|---|---|---|---|---|---|---|
| chests-200 | 2 | 0.162 | 46% | 0.112 | 0.0022 | 0 |
| idle-furnace-200 | 2 | 0.165 | 14% | 0.108 | 0.0022 | 0.0001 |
| stone-furnace-200 | 2 | 0.203 | 58% | 0.085 | 0.0147 | Furnace 0.0083, Inserter 0.0017 |
| electric-furnace-200 | 2 | 0.246 | 4% | 0.191 | 0.0202 | Furnace 0.0072, Inserter 0.0054, InfinityContainer 0.0051 |
| assembler-200 | 2 | 0.189 | 7% | 0.163 | 0.0294 | InfinityContainer 0.0117, Inserter 0.0100, AssemblingMachine 0.0045 |
| electric-furnace-2000 | 2 | 0.353 | 0.1% | 0.196 | 0.1552 | (sum 0.152) |
| assembler-2000 | 2 | 0.515 | 21% | 0.251 | 0.3489 | (sum 0.345) |
| pY 134 (74 mods) | 1 | 19.95 | - | 18.91 | 6.527 | AssemblingMachine 2.46, Inserter 1.62, Loader 0.73, Radar 0.59 |

pY 134 also: trains 3.01, scriptUpdate 2.20, electricHeatFluidCircuit 1.89,
transportLines 1.84, controlBehavior 1.66, fluidFlow 1.65, luaGC 1.55.
Wall time: 12.7 s setup (sync-mods loads pY's data stage) + 29.5 s benchmark.
One substitution warning was a false positive (`0.1.1` vs zip `0.1.01`); the
version match is now numeric.

What the noise says about method:
- At N=200 every world sits on a ~0.1-0.15 ms floor made of
  `transportLinesUpdate` and `electricHeatFluidCircuitUpdate` even with no belts
  or fluids. Those phases run on worker threads, so on a loaded box this is
  thread wake-up/sync latency, not work. Compare **`entityUpdate` and the
  per-class columns**, not wholeUpdate, for small worlds; and use larger N.
- wholeUpdate mean is dominated by spikes (p95 is 5-10x the median here).
  Report median tick alongside mean.
- Idle furnaces cost the same as chests (entityUpdate 0.0022 vs 0.0022):
  sleeping entities are off the update list.

## mulark's public benchmark maps (`saves/mulark/`)

Source: mulark's Factorio benchmark site, https://mulark.github.io/ (test pages
under `tests/test-0000NN/`). The site links a public Google Drive folder
(https://drive.google.com/open?id=1rZo0oa4lQGdYYXyEbUnS0Cd8MD8DPpxf). The same
maps are mirrored on Backblaze B2 with sha256s in his
factorio-benchmark-helper `master.json`
(https://raw.githubusercontent.com/mulark/factorio-benchmark-helper/master/master.json).
**License/attribution:** neither the site nor either repo states a license.
The maps are published for download for benchmarking. Credit mulark (and the
named map authors) when citing numbers, and do not redistribute the files.
They are not included in this repository.

`./fetch_mulark.py` downloads with `curl -L` into `saves/mulark/`, checks the
sha256 against master.json, reads only the save header, and writes
`saves/mulark/manifest.json` (URL, bytes, sha256, map_version, mods, whether it
loads). Nothing in that directory is unzipped or executed. Total downloaded:
57 MB.

| file | URL | bytes | sha256 (prefix) | map_version | header mods | loads on 2.1.24 |
|---|---|---|---|---|---|---|
| test-000060.no_primed.400x.zip | https://f000.backblazeb2.com/file/mulark-maps/test-000060/test-000060.no_primed.400x.zip | 16835052 | 9a5362506756 | 1.1.107 | base, region-cloner 2.2.1 | yes |
| test-000059.full_beacon.cloned.zip | https://f000.backblazeb2.com/file/mulark-maps/test-000059/test-000059.full_beacon.cloned.zip | 11614213 | e06b4e99368a | 1.1.42 | base, creative-world-plus 0.0.11, region-cloner 2.1.3 | yes |
| test-000061.naive.zip | https://f000.backblazeb2.com/file/mulark-maps/test-000061/test-000061.naive.zip | 6528103 | 98495741e8f2 | 1.1.107 | base, region-cloner 2.2.1 | yes |
| test-000066.infinity.cloned.zip | https://drive.usercontent.google.com/download?export=download&confirm=t&id=1lHL46LbS5AtoZ1wyPBbdcQNKY-Xn8OBR | 1733087 | 04bdd2fdbeab | 2.0.60 | base, elevated-rails, quality, space-age, region-cloner 3.0.2, No_Power_Icons 2.0.4 | yes |
| test-000013.1_network.zip | https://f000.backblazeb2.com/file/mulark-maps/test-000013/test-000013.1_network.zip | 9859025 | 0f1732ea34a4 | 1.0.0 | base, region-cloner 1.2.8 | yes |
| UPS Wars 3 - mulark.10x -1M.zip | https://f000.backblazeb2.com/file/mulark-maps/UPS%20Wars%203%20-%201M/UPS%20Wars%203%20-%20mulark.10x%20-1M.zip | 10761767 | 31f5d7e0119e | 0.17.75 | (header predates saveheader's format) | **no**: "lower than the minimum input version (1.0.0-0)" |

- **No megabase from 1.0 or later is published there.** The megabase maps on
  the site (test-000055: flame_Sla 10k/20k, Stevetrov 10K trains, ...) and the
  UPS Wars 3 entries are 0.17/0.18, and 2.1.24 refuses anything below 1.0.0.
  The largest 1.0+ map found is test-000013.1_network: 32 bot-based
  speed-module-3 cells, each with about 24k solar panels. For a real megabase,
  use the pY saves.
- The saves carry editor helper mods that are not installed (region-cloner,
  creative-world-plus, No_Power_Icons). They load with `--drop-missing`, which
  lets Factorio remove them. That is how suite.py runs the group.
- The 2.0 map needs `recycler`, which 2.1 split out of quality/space-age.
  `build_run_dir` now enables builtin mods that an enabled builtin requires.
- 1.0/1.1 saves store level.dat chunks uncompressed. `benchlib.read_header`
  falls back to reading them raw.

Load check, 300 ticks x 1 run, 2026-11-02 (loadavg about 2, other work still
running, so the numbers are NOISY):

| map | ms/update (mean) | median tick | entityUpdate | top per-class (ms/tick) |
|---|---|---|---|---|
| test-000060.no_primed.400x | 5.074 | 4.368 | 3.641 | AssemblingMachine 2.269, Inserter 1.173, Loader 0.042 |
| test-000059.full_beacon.cloned | 2.030 | 1.768 | 1.588 | Inserter 0.739, AssemblingMachine 0.298, Furnace 0.281, MiningDrill 0.123 |
| test-000061.naive | 0.824 | 0.705 | 0.592 | Inserter 0.306, Furnace 0.159, MiningDrill 0.077 |
| test-000066.infinity.cloned | 0.860 | 0.851 | 0.786 | MiningDrill 0.353, Inserter 0.265, InfinityContainer 0.166 |
| test-000013.1_network | 3.106 | 1.834 | 1.098 | Inserter 0.292, AssemblingMachine 0.122, Roboport 0.102, Furnace 0.080 |

test-000013's mean includes about 1.6 ms of `mapGenerator` in the first
ticks. That is post-migration chunk work, not steady state. Use a long run with
`--skip` for this map.

```bash
./fetch_mulark.py                                   # idempotent; re-verifies sha256
./suite.py --group mulark --ticks 3600 --runs 5 --cpus 8-11
./bench_save.py saves/mulark/test-000060.no_primed.400x.zip --drop-missing --ticks 3600 --runs 5 --skip 600
```

## Composed (component-lab) vs native, and the measurement run

`./measure.sh` is the whole quiet-box run behind `RESULTS.md`. It builds any
missing saves, benchmarks everything with `taskset -c 8-11` (override with
`CPUS=`), 3600 ticks, 5 runs (3 on pY), first 300 ticks dropped, then runs
`report.py > RESULTS.md`. Hand-written interpretation lives in
`RESULTS.notes.md` and gets appended. Plan on about 45 min of benchmarking,
plus about 40 min of builds if nothing is built yet.

- `builds/cl-*.lua` place N of each component-lab test entity
  (`../docs/TEST-ENTITIES.md`) in a working setup, built with
  `raise_built = true` so the library makes the hidden parts. Each one has a
  `builds/native-*.lua` twin in the same layout, or reuses a matrix variant.
  `make_save.PAIRS` holds the mapping. `builds/_grid.lua` is the driver, and
  `BENCH.plan(n, w, h)` packs w x h cells into 18x18 substation blocks.
  `builds/empty.lua` is the zero-entity baseline that gets subtracted to give
  per-instance figures.
- `./suite.py --group composed -n 2000 ...` runs empty + composed + natives.
- `make_save.py` tolerates the suite's deliberate KNOWN-LIMIT failures. It
  checks the server is up, not the fh exit code.
- `census_save.py <save> [name]` counts entities by prototype in a save. It
  adds `census-mod/` to the save's isolated mod set for one `--benchmark` tick
  and writes `results/<name>.census.json`, with the pY script families from
  (a pY mod survey that is not included here) grouped. The save is never written. A pY save takes
  about 5 min.
- Since the project now loads space-age, all component-lab saves (the native
  matrix included) carry base + elevated-rails + quality + space-age + aitest +
  component-lab. Compare saves built with the same mod set only.

## Quiet-box rerun

```bash
./suite.py -n 2000 --ticks 3600 --runs 5 --rebuild --cpus 8-11 --note "quiet box"
./suite.py -n 20000 --ticks 3600 --runs 5 --cpus 8-11      # more signal above the floor
./suite.py --group mulark --ticks 3600 --runs 5 --cpus 8-11  # mulark's public maps
for s in "pY 134" "pY Season 3 A2 Fixed" "pY Fixed"; do
  ./bench_save.py "$FACTORIO_DIR/saves/$s.zip" --ticks 3600 --runs 3 --cpus 8-11
done
```
`--cpus` pins via taskset; pick a range of four (Factorio uses worker
threads). The 2000-cell builds take ~33 s each including 1800 settle ticks.
