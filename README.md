# Composed-machine benchmarks and cost model

Measurements and a small C++ model behind a proposal for a new modding entity
type in Factorio 2.1: a **composed machine**, whose parts (inventories, a
crafting timer, an energy source, fluid boxes) are fixed when the prototype
loads, which joins the update list only if one of its parts needs ticking, and
which reports to scripts through events instead of per-tick polling. The
proposal text itself is not in this repository. This repository holds the
numbers it cites and the tools that produced them, so they can be checked and
rerun.

There are two halves:

- **bench/**: headless `factorio --benchmark` runs of Factorio 2.1.24. Native
  entities at two sizes, eight entities built the way mods build compound
  entities today (hidden entities plus a Lua control script) next to a native
  twin, five public benchmark maps by mulark, and three large Pyanodon's saves.
- **model/**: one C++17 program that runs a Factorio-like tick (chests,
  inserters, furnaces and assemblers on shared electric networks) under several
  object layouts, checks that every layout ends in the same world state, and
  times them. It is not Factorio's code.

All times below are wall-clock per game update (one tick) unless noted. "Per
instance" means the update time of a world minus an empty world, divided by the
number of instances.

## Headline: emulated composed entity vs native, per instance

From `bench/RESULTS.md` section (b). N = 2000 instances, ns per instance per
tick. "whole" is Factorio's `wholeUpdate`; "e+s+gc" is `entityUpdate` +
`scriptUpdate` + `luaGarbageIncremental`. Ratio is composed / native on whole.
The entity specs are in `docs/ENTITIES.md`.

| composed | native comparison | composed whole | native whole | ratio | composed e+s+gc | native e+s+gc | composed scriptUpdate ns |
|---|---|---|---|---|---|---|---|
| cl-fluid-chest | native-fluid-chest | 83.3 | 22.1 | 3.77 | 77.3 | 17.5 | 59.1 |
| cl-fluid-chest | chests | 83.3 | 2.0 | 42.71 | 77.3 | 0.3 | 59.1 |
| cl-signal-chest | native-signal-chest | 412.5 | 93.4 | 4.41 | 402.3 | 89.9 | 300.5 |
| cl-fuelled-chest | native-fuelled-chest | 151.7 | 50.8 | 2.99 | 127.9 | 27.0 | 93.5 |
| cl-fuelled-chest | stone-furnace | 151.7 | 54.7 | 2.77 | 127.9 | 49.5 | 93.5 |
| cl-cold-box | native-cold-box | 541.7 | 15.5 | 34.90 | 521.0 | 12.2 | 466.4 |
| cl-cold-box | chests | 541.7 | 2.0 | 277.80 | 521.0 | 0.3 | 466.4 |
| cl-timed-converter | assembler | 776.5 | 100.3 | 7.75 | 763.8 | 92.8 | 624.5 |
| cl-timed-converter | stone-furnace | 776.5 | 54.7 | 14.20 | 763.8 | 49.5 | 624.5 |
| cl-seep-derrick | native-seep-derrick | 149.4 | 90.2 | 1.66 | 118.3 | 61.6 | 3.6 |
| cl-dig-site | electric-furnace | 60.4 | 46.9 | 1.29 | 57.0 | 42.5 | 1.4 |
| cl-dig-site | assembler | 60.4 | 100.3 | 0.60 | 57.0 | 92.8 | 1.4 |
| cl-signal-endpoint | native-signal-endpoint | 81.3 | 14.6 | 5.59 | 78.6 | 11.7 | 64.3 |

What this shows:

- For the five entities that are not crafters, the hidden native part costs
  what the same native entity costs in its own per-class column (for example
  Reactor 0.0516 vs 0.0514 ms for 2000 fuelled chests). The extra cost is
  `scriptUpdate` plus extra Lua garbage collection, that is, the polling script.
- The two crafters whose scripts are event-only (dig site, seep derrick) pay
  1-4 ns per instance in `scriptUpdate`. Their remaining gap is in the
  `AssemblingMachine` column of the shell entity; these runs do not isolate
  why.
- The timed converter and signal chest poll every instance on the same tick,
  so their median tick is close to native while the 95th percentile reaches
  5-10 ms. The per-instance figures use the mean, which spreads those spikes
  over all ticks.

## Native matrix

From `bench/RESULTS.md` section (a). Each cell is the machine plus two
inserters and two infinity chests (source and sink), except `chests`, which is
N bare wooden chests. `idle-furnace` is an electric furnace with nothing to
smelt.

Per instance, ns per tick, delta over the empty world:

| variant | N=2000 whole | N=2000 entity+script+GC | N=20000 whole | N=20000 entity+script+GC |
|---|---|---|---|---|
| assembler | 100.3 | 92.8 | 139.5 | 135.0 |
| chests | 2.0 | 0.3 | 0.5 | 0.1 |
| electric-furnace | 46.9 | 42.5 | 64.0 | 60.5 |
| idle-furnace | -0.9 | -0.3 | 2.3 | -0.1 |
| stone-furnace | 54.7 | 49.5 | 61.3 | 58.8 |

Whole world, ms per update (best of 5 runs):

| save | mean | median tick | p95 tick | spread | entityUpdate | top per-class |
|---|---|---|---|---|---|---|
| empty (baseline) | 0.106 | 0.099 | 0.151 | 6.4% | 0.003 | |
| chests N=2000 | 0.110 | 0.099 | 0.161 | 2.5% | 0.003 | |
| idle-furnace N=2000 | 0.104 | 0.099 | 0.145 | 6.0% | 0.003 | |
| electric-furnace N=2000 | 0.200 | 0.153 | 0.305 | 14.7% | 0.087 | Furnace 0.039, Inserter 0.024, InfinityContainer 0.020 |
| stone-furnace N=2000 | 0.216 | 0.188 | 0.309 | 18.5% | 0.100 | Furnace 0.064, Inserter 0.014, InfinityContainer 0.011 |
| assembler N=2000 | 0.307 | 0.212 | 1.114 | 3.5% | 0.186 | InfinityContainer 0.077, Inserter 0.070, AssemblingMachine 0.037 |
| chests N=20000 | 0.116 | 0.101 | 0.165 | 17.1% | 0.003 | |
| idle-furnace N=20000 | 0.152 | 0.144 | 0.199 | 4.8% | 0.003 | |
| electric-furnace N=20000 | 1.387 | 0.560 | 4.330 | 9.9% | 1.199 | Furnace 0.473, Inserter 0.423, InfinityContainer 0.298 |
| stone-furnace N=20000 | 1.331 | 0.767 | 3.026 | 12.8% | 1.168 | Furnace 0.668, Inserter 0.255, InfinityContainer 0.162 |
| assembler N=20000 | 2.897 | 1.306 | 14.176 | 2.3% | 2.679 | Inserter 1.121, InfinityContainer 1.059, AssemblingMachine 0.495 |

Passive and sleeping entities cost nothing measurable: 20000 chests and 20000
idle furnaces both sit at the empty-world floor.

## Pyanodon's saves: how much of a tick is Lua

From `bench/RESULTS.md` section (d). Three real pY bases, each run with its own
mod set (73-76 mods), 3600 ticks x 3 runs. ms per update.

| save | mods | mean (best run) | median tick | spread | entityUpdate | scriptUpdate | luaGC | Lua share of tick |
|---|---|---|---|---|---|---|---|---|
| pY 134 | 74 | 6.12 | 5.45 | 1.3% | 1.81 | 1.00 | 0.76 | 29 % |
| pY Fixed | 73 | 6.26 | 5.52 | 3.8% | 1.69 | 1.12 | 0.83 | 31 % |
| pY Season 3 A2 Fixed | 76 | 2.22 | 2.01 | 2.1% | 0.60 | 0.29 | 0.63 | 41 % |

"Lua share" is (`scriptUpdate` + `luaGarbageIncremental`) / mean. It is about
the size of the whole entity update. It belongs to every mod in the save, not
only to compound-entity emulation; per-mod attribution was not done. A census
of the Lua-composed entity families in each save (dig sites, seep derricks,
farms, hidden beacons and others) is in `bench/RESULTS.md` and
`bench/results/*.census.json`. The saves themselves are not included.

## mulark's public benchmark maps

From `bench/RESULTS.md` section (c). These maps were made and published by
**mulark** (https://mulark.github.io/, every test below is credited to mulark
on the site's test index) for Factorio performance testing. They are **not
redistributed here**: `bench/fetch_mulark.py` downloads them from mulark's
published locations and checks each file against the sha256 in mulark's
`factorio-benchmark-helper` manifest. No license is stated for the maps; credit
mulark when citing these numbers.

| map (saved with) | mean (best run) | median tick | spread | entityUpdate | top per-class |
|---|---|---|---|---|---|
| test-000060.no_primed.400x (1.1.107) | 3.947 | 3.360 | 1.4% | 2.683 | AssemblingMachine 1.732, Inserter 0.743, Loader 0.036 |
| test-000059.full_beacon.cloned (1.1.42) | 1.674 | 1.518 | 4.6% | 1.188 | Inserter 0.545, AssemblingMachine 0.244, Furnace 0.206 |
| test-000061.naive (1.1.107) | 0.703 | 0.667 | 2.2% | 0.511 | Inserter 0.256, Furnace 0.150, MiningDrill 0.066 |
| test-000066.infinity.cloned (2.0.60) | 0.789 | 0.653 | 9.1% | 0.697 | MiningDrill 0.346, Inserter 0.239, InfinityContainer 0.110 |
| test-000013.1_network (1.0.0) | 1.265 | 1.076 | 2.5% | 0.815 | Inserter 0.211, AssemblingMachine 0.102, Roboport 0.093 |

ms per update, 3600 ticks x 5 runs, first 600 ticks dropped. The site's
megabase maps are from 0.17/0.18 and do not load on 2.1, which refuses saves
older than 1.0.

## The C++ cost model

`model/model.cpp` runs the same workload under several layouts. v1 variants:

- **A** static: one hand-written class per entity type, one update list per
  type. The baseline.
- **B** composed: one class for every composed entity; each part is a pointer
  or bit tested in every update.
- **C** runtime ECS: each entity is a list of components updated through
  virtual calls, with lookups by tag.
- **D** templated composed: B with the parts as template parameters, so absent
  parts take no space and no test; one update list per part shape.

Every variant ends with the same hash of the full world state at every size,
in every repeat, under both compilers.

v1 ratios against A (`model/RESULTS.md`; min / median of 3 repeats, 60 warm-up
and 600 measured ticks):

| N | B/A g++ | C/A g++ | D/A g++ | B/A clang++ | C/A clang++ | D/A clang++ |
|---|---|---|---|---|---|---|
| 10k  | 1.051 / 1.099 | 2.184 / 2.327 | 1.004 / 1.007 | 1.055 / 1.055 | 2.188 / 2.213 | 0.995 / 0.992 |
| 100k | 1.051 / 1.047 | 2.336 / 2.333 | 0.995 / 0.998 | 1.056 / 1.058 | 2.325 / 2.296 | 1.004 / 1.007 |
| 1M   | 1.090 / 1.098 | 2.935 / 2.860 | 1.026 / 1.010 | 1.117 / 1.111 | 2.873 / 2.901 | 0.937 / 0.991 |

Read these as B/A 1.05-1.10, C/A 2.2-2.9 and growing with N, D/A 1.00 +/- 0.02.
B's chest object is 80 bytes against A's 16, and B's gap is widest at 1M where
the run is memory-bound, so the evidence points at object size rather than the
part checks themselves: a composed entity has to keep its shape out of the
object layout to match a hand-written class.

v2 adds optional parts that tick (an electric or heat output pushed when a
cycle finishes, a circuit enable flag, a trigger on finish). Baseline A2 is the
static design with a Generator and a Reactor class added. Ratios with shuffled
update lists (`model/RESULTS-v2.md`, min / median):

| N | compiler | B2/A2 | D1/A2 | D2/A2 | D2n/A2 |
|---|---|---|---|---|---|
| 10k  | g++     | 0.941 / 0.948 | 1.005 / 1.005 | 0.978 / 0.979 | 1.131 / 1.135 |
| 100k | g++     | 1.001 / 1.011 | 1.004 / 1.001 | 0.992 / 0.994 | 1.133 / 1.137 |
| 1M   | g++     | 1.077 / 1.078 | 0.958 / 0.954 | 0.956 / 0.963 | 1.004 / 0.995 |
| 10k  | clang++ | 0.956 / 0.960 | 1.014 / 1.009 | 1.009 / 0.994 | 1.146 / 1.127 |
| 100k | clang++ | 1.008 / 1.002 | 1.018 / 1.006 | 0.998 / 1.009 | 1.131 / 1.122 |
| 1M   | clang++ (1 rep) | 1.104 | 0.984 | 0.967 | 0.998 |

- **D1** keeps the v1 shapes, holds the output behind one pointer tested only
  when a cycle finishes, and tests the enable flag once per update: 0.95-1.02.
- **D2** multiplies shapes (six machine shapes, one update list each, no tests
  at all): 0.96-1.01. Multiplying shapes bought nothing measurable and cost
  about 100 bytes of code per extra shape.
- **B2** (the parts as runtime slots in one 112-byte class shared with passive
  chests) comes back to 1.08-1.12 at 1M entities.
- **The polymorphic-accessor trap (D2n).** If every template instantiation
  gets its own copy of the small functions inserters call on their targets
  (inventory and recipe accessors), the inserters' indirect calls go from one
  target to six, and the tick is 12-35% slower at 10k-100k entities (D2n/A2
  1.13-1.15 shuffled, up to 1.35 in group order). D2 avoids it by putting those
  accessors in a core class shared by every variant of a shape.

`model/RESULTS-v2.md` also explains the two visiting orders (group order
flatters any single-list layout; shuffled is the fair comparison) and the D1s
control that shows it.

## Reproducing

### Model (no Factorio needed)

```bash
cd model
make                     # g++ -O2 -march=native -std=c++17
./run.sh                 # 10k, 100k and 1M entities, all suites
./run.sh 100000 --repeats 5 --suite v2s
make clean && CXX=clang++ ./run.sh   # the clang column
```

Options and output columns are described in `model/README.md`. A 1M run of
every suite takes about seven minutes per repeat. Compare ratios, not absolute
numbers, between machines; the program exits non-zero if the variants' final
state hashes differ.

### Benchmarks

Requirements:

- A Factorio 2.1 install with the headless-capable binary at
  `$FACTORIO_DIR/bin/x64/factorio` (default `FACTORIO_DIR=~/factorio`), with
  Space Age. The numbers here are from 2.1.24.
- The owner's Factorio test harness, `factorio-harness` (its CLI is `fh`), on
  `PATH` or named by `$FH`. It is used only to build the synthetic worlds: it
  boots a server with the `component-lab` mod, runs the Lua builders in
  `bench/builds/` over RCON and saves the map. It expects its project
  directory at `$FACTORIO_DIR/ai-harness`, with `harness/component-lab.json`
  from this repository as `projects/component-lab.json` (with its `source` pointed at this repository's `mod/component-lab`) and the suite in
  `suites/component-lab/`. Benchmarking an existing save
  (`run_bench.py`, `bench_save.py`) does not need the harness.
- The `component-lab` mod in `mod/component-lab` (see `sync.sh`).
- Python 3, `taskset`, `curl`.

```bash
cd bench

# Native matrix, composed vs native, and mulark's maps (builds missing saves first)
./suite.py --group native   -n 2000  --ticks 3600 --runs 5 --skip 300 --cpus 8-11
./suite.py --group native   -n 20000 --ticks 3600 --runs 5 --skip 300 --cpus 8-11
./suite.py --group composed -n 2000  --ticks 3600 --runs 5 --skip 300 --cpus 8-11
./fetch_mulark.py                    # downloads and sha256-checks mulark's maps
./suite.py --group mulark            --ticks 3600 --runs 5 --skip 600 --cpus 8-11

# Any save with its own mod list (copied first; the original is not written)
./bench_save.py "$FACTORIO_DIR/saves/<save>.zip" --ticks 3600 --runs 3 --skip 300 --cpus 8-11
./census_save.py saves/real/<save>.zip <name>

# Everything above plus the pY saves, then regenerate RESULTS.md
./measure.sh
./report.py > RESULTS.md             # then append RESULTS.notes.md
```

`--cpus` pins Factorio with `taskset`; pick four logical CPUs. Each benchmark
appends one JSON line to `results/<name>.jsonl` with every run's statistics,
every non-zero timing column, load average, pinning and a note. `report.py`
builds `RESULTS.md` from those files. `bench/README.md` describes the world
layout, the output format of `--benchmark-verbose all` and how mods are
resolved for a save. The whole measurement run takes about 45 minutes of
benchmarking plus about 40 minutes of world builds.

## Hardware and conditions

- AMD Ryzen 7 9800X3D (8 cores, 16 threads, 96 MB L3), 60 GB RAM, Linux 6.17.
- Factorio 2.1.24, headless `--benchmark --benchmark-verbose all`, pinned with
  `taskset -c 8-11` (four logical CPUs, the second threads of physical cores
  0-3).
- Desktop file indexing and other background services were stopped for the
  benchmark passes; 1-minute load average 0.64 to 3.53 around the runs.
- Model: g++ 13.3 and clang++ 18.1, `-O2 -march=native`, unpinned, on the same
  machine while it was shared (load 0.9-3.6; see each results file).

## Caveats

- **Quiet box, not an isolated one.** The benchmarks ran on a desktop with
  background services reduced, not on a dedicated machine. Each case is run
  several times and the fastest run is reported, because interference only
  adds time. The run-to-run spread is printed next to every number; several
  composed cases have 20-27% spreads (dig site, signal endpoint, fuelled
  chest), so read small ratios with that in mind.
- **Means include spikes.** p95 is often 5-10x the median on worlds whose
  scripts poll on a shared tick. The per-instance figures use the mean.
- **The comparison twins are approximations.** Base game has no
  one-fluid-to-one-fluid assembler recipe, so the native seep derrick is a
  chemical plant on lubricant (1 s cycle against the derrick's 2 s). The native
  fuelled chest uses the emulation's own hidden reactor prototype with no
  script. Per-instance figures include each cell's feeding entities, which are
  identical within a pair.
- **The emulation can over-count.** For the cold box, the emulation's spoil
  pass is a per-tick Lua loop, while a native implementation would re-stamp
  spoil time once per transfer and cost nothing per tick; its 35x is an upper
  bound, not a prediction (`docs/ENTITIES.md`, cold box calibration).
- **The model is a model.** It is not Factorio's code. Its 1M-entity figures
  are memory-bound and moved by about 10% between runs on the shared L3. Its
  conclusions are about layout and dispatch, not absolute cost.
- **Small worlds sit on a floor.** Under about N = 200 every world costs about
  0.1 ms per update in worker-thread phases even with no belts or fluids;
  compare `entityUpdate` and the per-class columns there.
- `bench/RESULTS.notes.md` (appended to `RESULTS.md`) still contains one
  earlier bullet saying the pY runs had not happened yet; the pY paragraph at
  its end and section (d) supersede it.
- `bench/builds/` also contains builders for a second set of eight entities
  (`docs/TEST-ENTITIES-2.md`); results for those are not in this snapshot.

## Layout

```
README.md          this file
LICENSE            MIT
sync.sh            re-copies model/, bench/, docs/ (and mod/, harness/) from the working tree
model/             C++ cost model: model.cpp, Makefile, run.sh, README, RESULTS (v1), RESULTS-v2
bench/             benchmark tooling (Python), Lua world builders, census mod
bench/builds/      one Lua builder per world; _common/_grid/_cells are shared
bench/census-mod/  one-tick mod that counts entities by prototype in a save
bench/results/     raw results: one JSON line per benchmark run, census JSON per pY save
bench/RESULTS.md   generated report (sections a-d) plus the hand-written notes
docs/              ENTITIES.md (all sixteen emulated entities, summary), TEST-ENTITIES-2.md (second-pass specs)
mod/               component-lab, the Lua reference mod (filled by sync.sh)
harness/           the mod's test suites and harness project file (filled by sync.sh)
```

Saves, run directories and downloaded maps are not part of the repository
(`.gitignore`).

## License

MIT, see `LICENSE`. This covers the code and results in this repository, not
mulark's maps, the pY saves, or Factorio.
