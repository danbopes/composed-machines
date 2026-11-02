# ComposedMachine performance model: results

This is a model, not Factorio. It is one C++17 program (`model.cpp`) that runs a
Factorio-like tick under four architectures with the same workload, and checks that all
four end in the same world state.

- **A STATIC** (Factorio today): `Container` (passive), `Furnace`, `AssemblingMachine`
  (both share the crafting-machine update), `Inserter`. Each type has its own bucket, and the
  bucket loops call `update` statically, the way the engine's per-type update loop does. Every
  machine and inserter owns a heap-allocated `EnergySource*` (Electric or Burner) and calls
  it virtually.
- **B COMPOSED** (the proposal, runtime parts): one `final` `ComposedMachine` class. Its
  parts (input/output inventory, timer, `EnergySource*`, fluid box) are pointers or bits
  fixed at construction. Every instance carries every slot, and `update()` checks each one.
  It has one bucket of its own. Chest-only instances never join the active list.
- **C RUNTIME-ECS** (the 2018 idea): each entity holds a `std::vector<Component*>`. One
  heterogeneous active list is walked, calling virtual `update()` on every component.
  Components look up their siblings, and the components of the entities they target, by tag
  when they need them.
- **D TEMPLATED COMPOSED** (the proposal, parts as template parameters): the same idea as B,
  but `Composed<Input, Energy, Timer, Fluid>` is a separate instantiation per part shape,
  chosen once at construction. Absent parts are empty bases, so the empty-base optimisation
  makes them take zero bytes, and their checks disappear through `if constexpr`. Each
  ticking shape has its own homogeneous bucket, and the tick loop makes a direct call per
  bucket with no branch. Chest shapes are in no list.

The `Inserter` class is the same in A, B and D. It reaches its targets through
`Entity` virtuals, as a real inserter that can target any entity type would.

## Workload (identical across A/B/C/D)

Each group has 10 entities: 4 chests (40%), 3 inserters (30%) and 3 machines (30%). The
chain is ore chest -> inserter -> furnace (ore->plate, 64 t) -> inserter -> assembler
(2 plate->gear, 30 t) -> inserter -> sink chest. A third machine (plate+gear->widget, 45 t)
starts with its input preloaded. Burner and electric machines are split half and half. The
rules are real ones: slot-based inventories with stack sizes, matching-stack-first
insertion, an automated insertion limit of 2x the recipe amount, inserter swing timers and
hand sizes, and inserters that draw energy. There are 8 shared electric networks; two are
undersized and stay in brownout the whole run (1326 network-ticks). Burners take coal from
their own fuel inventory.

Entities and their inventories are allocated with `new` in shuffled order and iterated in
group (spatial) order. This makes the loops chase pointers across the heap the way a
long-lived save would.

**Equivalence check.** The final state is hashed: every inventory slot, every craft
progress value, every inserter hand and timer, and every energy buffer. All four
architectures produce the same hash at every N, in every repeat, under both g++ and clang++
(10k `4bcca1bb533038e8`, 100k `b3451b0b8358d2b8`, 1M `bc17955372e7bdb4`). C walks entities
in a different order from the others, so the model makes each tick independent of order: a
slot remembers what was added and removed in the current tick, and with one putter and one
taker per inventory every operation depends only on the state at the start of the tick.
That bookkeeping costs the same in all four architectures.

## Object sizes (`sizeof`, x86-64)

| shape | A static | B composed | D templated |
|---|---:|---:|---:|
| chest | 16 (`Container`) | 80 (`ComposedMachine`) | 16 (`Composed<chest>`) |
| machine | 64 (`Furnace` / `AssemblingMachine`) | 80 (`ComposedMachine`) | 64 (`Composed<machine>`) |

These are the objects themselves. Inventories and energy sources are separate heap
allocations in every architecture.

## Setup

- AMD Ryzen 7 9800X3D (8C/16T, 96 MB L3, 8 MB L2), 60 GB RAM, Linux 6.17.
- g++ 13.3.0 and clang++ 18.1.3, both with `-O2 -march=native -std=c++17`.
- 60 warm-up ticks, 600 measured ticks, 3 repeats, with A, B, C and D run in turn inside each
  repeat. Timing uses `std::chrono::steady_clock`. No pinning.
- **The box was shared.** Load average was 2.6-3.6 during these runs (other Factorio
  instances were running), and that load shares the L3.

## Results: g++ 13.3 (2026-11-02, load average 2.7-3.5)

ns/e-t is nanoseconds per entity per tick, divided by **all** N entities, including the
passive 40%. 60% of entities are active.

| N | arch | min ns/tick | median ns/tick | min ns/e-t | median ns/e-t |
|---|---|---:|---:|---:|---:|
| 10k  | A static   |     60,384 |     61,027 |  6.04 |   6.10 |
| 10k  | B composed |     63,436 |     67,096 |  6.34 |   6.71 |
| 10k  | C rt-ecs   |    131,873 |    141,990 | 13.19 |  14.20 |
| 10k  | D templated |    60,626 |     61,462 |  6.06 |   6.15 |
| 100k | A static   |    751,159 |    754,631 |  7.51 |   7.55 |
| 100k | B composed |    789,128 |    790,401 |  7.89 |   7.90 |
| 100k | C rt-ecs   |  1,754,879 |  1,760,875 | 17.55 |  17.61 |
| 100k | D templated |   747,653 |    752,856 |  7.48 |   7.53 |
| 1M   | A static   | 33,961,795 | 35,037,850 | 33.96 |  35.04 |
| 1M   | B composed | 37,026,518 | 38,478,235 | 37.03 |  38.48 |
| 1M   | C rt-ecs   | 99,693,264 | 100,200,634 | 99.69 | 100.20 |
| 1M   | D templated | 34,835,026 | 35,394,176 | 34.84 |  35.39 |

## Ratios against A (min / median)

| N | B/A g++ | C/A g++ | D/A g++ | B/A clang++ | C/A clang++ | D/A clang++ |
|---|---|---|---|---|---|---|
| 10k  | 1.051 / 1.099 | 2.184 / 2.327 | 1.004 / 1.007 | 1.055 / 1.055 | 2.188 / 2.213 | 0.995 / 0.992 |
| 100k | 1.051 / 1.047 | 2.336 / 2.333 | 0.995 / 0.998 | 1.056 / 1.058 | 2.325 / 2.296 | 1.004 / 1.007 |
| 1M   | 1.090 / 1.098 | 2.935 / 2.860 | 1.026 / 1.010 | 1.117 / 1.111 | 2.873 / 2.901 | 0.937 / 0.991 |

**How noisy is this?** Earlier runs on 2026-11-01 (without D, heavier load) gave B/A
1.04-1.15 and C/A 2.2-2.5, with one disturbed outlier (C/A 6.9 at 100k) that did not
reproduce. The 1M figures move by about 10% between runs because of the shared L3. The
clang 1M D/A minimum of 0.937 is within that noise; the median, 0.991, is the number to use.
Read D/A as "1.00 ± 0.02", B/A as "1.05-1.10", and C/A as "2.2-2.9, growing with N".

## Interpretation (cautious)

**D versus B: object size or branches?** D is the same proposal as B, with two changes:
absent parts take no space, and their checks are gone. That alone brings the composed
design from B's 5-11% overhead to parity with the hand-written classes (D/A 0.99-1.03 under
both compilers, at every N). This model cannot cleanly split the two causes, because D
removes the extra size and the extra branches together. The evidence leans towards
**object size**:

- B's gap is widest at 1M (about 1.10 against 1.05 at 10k-100k), where the run is bound by
  memory. That is the pattern extra cache lines produce, not well-predicted branches, which
  cost about the same at any N.
- B's chest is 5x larger than A's (80 against 16 bytes). Inserters touch chests every tick
  even though chests never update.
- B's part checks take one fixed path per instance for its whole lifetime, so the branch
  predictor handles them almost for free. That most likely accounts for the remaining
  ~5% at small N, together with the larger machine object.

The practical conclusion: a composed machine has to keep its shape out of the object layout
(per-shape types or buckets, or at least a separate small passive class) to match today's
cost. Once it does, this model shows no cost to composition itself.

**What the model supports**

- **The 2018 rejection holds up in this model.** A runtime component list with
  heterogeneous virtual dispatch and lookups by tag costs about 2.2-2.9x the static design,
  and the gap grows with N. This matches Rseding91's argument about dispatch and cache
  misses, and his point that "everything touches everything" applies: inserters look into
  their targets' components every tick.
- **A static composed class is a different thing from that ECS.** Put in a type bucket with
  parts fixed at prototype load, it costs 5-10% done naively (B) and nothing measurable when
  the parts are template parameters (D).
- **The part that is already polymorphic is not new overhead.** The `EnergySource*` virtual
  call is present in A, B and D alike, because the real engine already does it.

**What the model cannot say about the real engine**

- **It is not Factorio's code or data layout.** Real entities are much larger (position,
  bounding box, circuit connections, quality, health, and so on), so B's extra 16-64 bytes
  would weigh relatively less there. This is untested.
- **It leaves out most of a real tick.** There are no belts, fluids, trains, robots, the
  circuit network, pollution, chunk activity or sleeping entities. In the real game,
  inserters and machines are only part of update time.
- **D's per-shape buckets have a cost the model barely exercises.** The workload has only
  one ticking shape. A modded game with many shapes would mean more buckets and more
  template instantiations (larger code, more instruction-cache pressure), and every new
  shape needs a fixed slot in the type order, the equivalent of an per-type update slot.
- **The order-independence bookkeeping is a modelling device.** It adds the same work to all
  four architectures, which makes the absolute ns figures, and every ratio, less extreme.
- **The 1M figures sit past a cache cliff.** At about 35 ns/e-t against about 7.5 at 100k,
  the working set has outgrown the shared 96 MB L3, so 1M numbers depend heavily on this
  machine and its load.
- **Generous assumptions for C.** Passive chests are excluded from its active list too, and
  lookups are short linear scans. Archetype ECS designs or ones that cache lookups are
  different designs, not the one that was rejected.
- **Single-threaded.** No parallel update was modelled.

## v2 axes

`RESULTS-v2.md` re-measures D with the v2 parts that tick: an electric or heat output, a circuit
enable and a trigger on finish. It also compares multiplying shapes (D2, six machine shapes) with
keeping the v1 shapes and testing the output pointer only at the cycle-finish push (D1). Both stay
at A's cost: D1/A2 and D2/A2 are 0.95-1.02 with shuffled update lists. The template has to share
the accessors that inserters call across shapes, otherwise the tick is 12-35% slower. B2 (runtime
slots, a 112-byte chest) is 1.08-1.12 at 1M. The v1 hashes above did not change.

## Files

- `model.cpp`: the program (shared rules, then A, B, C and D, then the v2 parts and A2, B2, D1, D2, then the driver). Prints the
  `sizeof` table at start-up.
- `Makefile`: `make` builds `model` with g++ `-O2 -march=native`.
- `run.sh`: builds (falls back to clang++ if g++ is missing) and runs. Arguments are passed
  through, e.g. `./run.sh 100000 --ticks 300 --repeats 5`. `--suite v1|v2|v2s` (comma list)
  and `--only` select what runs; see `README.md`.
