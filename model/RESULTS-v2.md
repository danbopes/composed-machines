# ComposedMachine performance model: the v2 part axes

This extends the model described in `RESULTS.md`, and that file still defines A, B, C, D, the
v1 workload and the equivalence hash. Everything here comes from one build of `model.cpp`.

## The question

v1 measured the templated composed machine (D) at D/A 1.00, but only with the v1 part set. v2 adds
optional parts that tick:

- an **energy output** of kind none, electric or heat, pushed into a buffer when a cycle finishes;
- a **circuit enable** flag, set outside the entity update, which puts the machine to sleep;
- a **trigger on finish**, a cheap call that does nothing unless the part is present.

The review asked whether these axes bring back variant B's cost (null checks on every update)
unless shapes multiply, and what multiplying shapes costs.

## What was added

**Workload.** Chests, inserters and recipes are the same as in v1. The machines also get:

- **Electric output, 30% of machines.** On each finished cycle the machine pushes 40 kJ into its
  own output buffer. A separate network pass drains up to 1 kJ per buffer per tick, as a generator.
- **Heat output, 20%.** On each finished cycle the machine pushes heat into its own heat buffer.
  A separate pass decays every heat buffer towards ambient (1/32 of the excess per tick), shaped
  like `HeatBufferManager`. A machine has at most one output kind.
- **Circuit enable, 25%.** A control-behaviour pass runs before the entity updates every 30
  ticks and writes the flag; it is off one period in three. A disabled machine skips its update
  entirely, energy included.
- **Trigger on finish, 20%.** A per-machine counter is incremented when a cycle finishes. Every
  variant calls `fireTrigger(ptr)`, which costs one test when the part is absent.

Parts are drawn independently per machine from the seed, so overlaps occur. The
order-independence rule from v1 still holds: the drain, decay and control passes are separate
loops. The checksum covers everything v1 covers, plus each enable flag, output buffer and trigger
count, and the total energy drained. **All v2 variants produce the same hash at every N, in every
repeat, under both compilers** (10k `1e76f7c22662830e`, 100k `4027b36c67e59762`, 1M
`5699179d01754719`). The v1 hashes did not change.

**Variants** (A2 is the baseline):

| | layout | per-update cost of the v2 parts |
|---|---|---|
| **A2** static | `Furnace`, `AssemblingMachine`, plus hand-written `Generator` and `Reactor` classes (one bucket each). The engine tests a crafting machine's control behaviour in every update, so every A2 machine carries the enable flag. | enable test on every update; output pushes compiled in per type |
| **B2** composed | B plus an enable flag and three pointers (electric, heat, trigger). One 112-byte class for chests and machines alike. | part bits and pointers tested on every update |
| **D1** templated, v1 shapes | the v1 machine shape, plus the enable flag (always present) and one `EnergyOutput*` behind a virtual `push()` | one enable test per update; output pointer tested only when a cycle finishes |
| **D2** templated, shapes multiply | `Composed<Input, Energy, Timer, Fluid, Out, Circuit>`: **6 ticking machine shapes** (none / electric / heat, times circuit on or off), each with its own bucket, plus the chest shape (7 in all; v1 instantiated 2) | none: absent parts compile away |
| **D2n** | D2, but every shape has its own copy of the functions inserters call (`pickupInventory`, `dropInventory`, `dropRecipe`), which is what a template does by default | as D2 |
| **D1s** control | D1's code, visiting machines in the order D2's six buckets visit them | as D1 |

**Two visiting orders.** The v1 workload repeats one 10-entity pattern in every group. A single
bucket visited in group order therefore sees burner/electric and the three recipes alternate
perfectly, and the branch predictor learns that pattern. Splitting machines into several buckets
breaks it. `v2` keeps group order, as v1 did. `v2s` shuffles every update list (inserters and
every machine bucket) before running, so no layout benefits from the pattern. **`v2s` is the fair
comparison**: a real active list built up over a long game has no such pattern.

## Object sizes (`sizeof`, x86-64, same under both compilers)

| shape | A2 | B2 | D1 | D2 |
|---|---:|---:|---:|---:|
| chest | 16 | 112 | 16 | 16 |
| machine, no output, no circuit | 80 | 112 | 88 | 72 |
| machine, no output, circuit | 80 | 112 | 88 | 80 |
| machine, electric or heat output, no circuit | 88 | 112 | 88 | 80 |
| machine, electric or heat output, circuit | 88 | 112 | 88 | 88 |

For comparison, the v1 sizes were 16 for the chest in A and D (80 in B) and 64 for the machine
(80 in B).

## Setup

The machine and compilers are the same as for v1: Ryzen 7 9800X3D, g++ 13.3, clang++ 18.1,
`-O2 -march=native`. Each run used 60 warm-up ticks and 600 measured ticks. Variants ran in turn
inside each repeat, with no pinning.

- **Repeats.** 10k and 100k used 3 repeats under both compilers. At 1M, g++ used **2 repeats** and
  clang++ **1 repeat**, with only the v2 suites and without D1s, to keep the whole run under 30
  minutes (it took 18.5 minutes).
- **Load.** The load average was 0.9 at the start and 1.2 after the small sizes. It rose to 2.4
  during the g++ 1M run, because other work was running on the box, and was 1.5 at the end. The
  1M figures are the noisiest.

## Results: ns per entity-tick (min of repeats, all N entities)

| N | suite | A2 | B2 | D1 | D2 | D2n | D1s |
|---|---|---:|---:|---:|---:|---:|---:|
| 10k  | v2 group, g++    |  7.91 |  7.12 |  6.55 |  7.78 | 10.69 |  7.98 |
| 10k  | v2s shuffled, g++ | 11.58 | 10.90 | 11.63 | 11.32 | 13.09 | |
| 100k | v2 group, g++    |  9.95 |  9.37 |  8.24 | 10.06 | 12.95 | 10.17 |
| 100k | v2s shuffled, g++ | 14.58 | 14.60 | 14.64 | 14.46 | 16.52 | |
| 1M   | v2 group, g++    | 33.03 | 35.83 | 30.91 | 32.16 | 33.80 | 32.57 |
| 1M   | v2s shuffled, g++ | 40.13 | 43.20 | 38.44 | 38.36 | 40.27 | |

The same runs gave these v1 figures (A static): 5.90 at 10k, 7.14 at 100k and 28.40 at 1M.

## Ratios against the baseline (min / median)

v1 suite (B/A, C/A, D/A), same binary, same session:

| N | B/A g++ | C/A g++ | D/A g++ | B/A clang++ | C/A clang++ | D/A clang++ |
|---|---|---|---|---|---|---|
| 10k  | 1.049 / 1.054 | 2.155 / 2.218 | 0.998 / 1.009 | 1.041 / 1.043 | 2.219 / 2.247 | 0.994 / 1.011 |
| 100k | 1.074 / 1.057 | 2.343 / 2.335 | 1.003 / 0.985 | 1.034 / 1.044 | 2.375 / 2.368 | 1.008 / 1.008 |
| 1M   | 1.130 / 1.129 | 3.073 / 3.060 | 0.999 / 0.988 | (not re-run) | | |

v2, **shuffled lists (the fair comparison)**, against A2:

| N | compiler | B2/A2 | D1/A2 | D2/A2 | D2n/A2 |
|---|---|---|---|---|---|
| 10k  | g++     | 0.941 / 0.948 | 1.005 / 1.005 | 0.978 / 0.979 | 1.131 / 1.135 |
| 100k | g++     | 1.001 / 1.011 | 1.004 / 1.001 | 0.992 / 0.994 | 1.133 / 1.137 |
| 1M   | g++     | 1.077 / 1.078 | 0.958 / 0.954 | 0.956 / 0.963 | 1.004 / 0.995 |
| 10k  | clang++ | 0.956 / 0.960 | 1.014 / 1.009 | 1.009 / 0.994 | 1.146 / 1.127 |
| 100k | clang++ | 1.008 / 1.002 | 1.018 / 1.006 | 0.998 / 1.009 | 1.131 / 1.122 |
| 1M   | clang++ (1 rep) | 1.104 | 0.984 | 0.967 | 0.998 |

v2, **group order**, against A2:

| N | compiler | B2/A2 | D1/A2 | D2/A2 | D2n/A2 | D1s/A2 |
|---|---|---|---|---|---|---|
| 10k  | g++     | 0.900 / 0.914 | 0.828 / 0.835 | 0.983 / 0.986 | 1.351 / 1.350 | 1.009 / 1.012 |
| 100k | g++     | 0.942 / 0.934 | 0.829 / 0.827 | 1.011 / 1.015 | 1.302 / 1.307 | 1.022 / 1.014 |
| 1M   | g++     | 1.085 / 1.123 | 0.936 / 0.973 | 0.974 / 0.998 | 1.023 / 1.052 | 0.986 / 1.042 |
| 10k  | clang++ | 0.938 / 0.941 | 0.826 / 0.826 | 0.983 / 0.985 | 1.227 / 1.239 | 0.995 / 0.994 |
| 100k | clang++ | 0.942 / 0.941 | 0.821 / 0.823 | 0.992 / 0.989 | 1.207 / 1.203 | 0.995 / 0.997 |
| 1M   | clang++ (1 rep) | 1.105 | 0.914 | 0.924 | 0.949 | |

## Code size

These are symbol sizes from `nm -S`. The update functions are inlined into each world's `tick()`,
and `craftCore` stays out of line, shared by every shape and every variant (590 bytes under g++,
757 under clang++).

| `World::tick()` | g++ | clang++ |
|---|---:|---:|
| A2 (4 machine buckets) | 811 | 1198 |
| B2 (1 bucket) | 555 | 830 |
| D1 (1 bucket) | 523 | 894 |
| D2 (6 buckets) | 1051 | 1390 |

In this model, multiplying shapes costs about 500 bytes of loop and glue code for five extra
shapes, roughly 100 bytes each. That is small because the compiler kept the crafting step out of
line. If a real `update` (several KB) were inlined once per shape, the footprint would grow by
that size times the shape count. The model does not test that case.

D2n has six copies of the three 5-9 byte accessors where D2 has one. The bytes do not matter, but
the number of distinct addresses does (see below).

## How the costs were separated

Timing the inserter loop and the machine loops separately, at 100k with g++ in group order,
showed this:

- **D2 against D1s (same visiting order).** The machine loops cost the same (5.01 against 4.97
  ns/e-t). Six homogeneous buckets cost nothing over one bucket visited in the same order.
- **D1 against D1s.** The machine loop costs 3.06 ns/e-t in group order and 4.97 in D2's order.
  D1's 17% lead over A2 in group order is therefore the workload's repeating pattern being
  predicted, not a property of D1. With shuffled lists it disappears (D1/A2 1.00).
- **D2n against D2.** The whole extra cost is in the inserter loop (7.64 against 4.68 ns/e-t). An
  inserter reaches its targets through `Entity` virtuals. With one copy of each accessor, the
  indirect call has one target. With six template copies it has six, in no predictable order.
  A2 avoids this without trying, because `Generator` and `Reactor` inherit the accessors from
  `CraftingMachine`. D2 avoids it by putting them in a core class that is instantiated once per
  v1 shape and shared by every v2 variant of that shape.

## Answer: shapes multiply, or a null check at the push?

> Measured with the v2 parts that tick (an electric or heat output pushed on cycle finish, a
> circuit enable that puts the machine to sleep, a trigger on finish), the composed machine stays
> at parity with hand-written classes either way, provided passive entities keep their small
> layout. Variant D1 keeps the four v1 shapes, holds the energy output behind one pointer tested
> only at the cycle-finish push, and tests the enable bit once per update. It ran at 0.95-1.02 of
> the static baseline with shuffled update lists. Variant D2 multiplies shapes: six machine
> shapes, one bucket each, so no test at all. It ran at 0.96-1.01. Multiplying shapes bought
> nothing measurable. It cost about 100 bytes of code per extra shape and one more slot in the
> type order for each, and it carries a trap. If each instantiation gets its own copy of the
> functions other entities call (inventory and recipe accessors), the indirect calls those
> entities make become polymorphic, and the tick got 12-35% slower at 10k-100k entities. Variant
> B's cost does come back if the parts become runtime slots in a class shared with passive
> entities (B2: 1.08-1.12 at 1M, where the 112-byte chest costs cache lines), but not from the
> tests themselves. The step-confined null check is the better choice: as fast as multiplying
> shapes, with a quarter of the shapes.

## Caveats

- **A2 already pays an enable test in every update**, because the engine checks a crafting
  machine's control behaviour there. "D1 matches A2" means D1 matches today's design, not a
  hypothetical static class with no test at all. D2's shapes without a circuit drop that test,
  and the gain did not show up in these numbers.
- **The pushes are rare.** Cycles take 30-64 ticks, so a test at the push runs on 2-3% of
  updates. A part that had to act every tick (a generator whose output depends on its buffer
  every tick, say) would be a per-update test and would need measuring again.
- **The group-order numbers flatter any single-bucket layout.** In group order, D1 and B2 beat A2
  at 10k-100k. That is the workload's repeating pattern being predicted, which the D1s control
  and the shuffled suite show. The v1 D/A = 1.00 result had the same property, but A and D shared
  the same bucket structure, so it did not bias their comparison.
- **The 1M numbers are noisy.** They come from a shared L3 and from runs at load 2.4 for g++, and
  clang++ ran only one repeat. Read B2/A2 at 1M as "about 1.1" and D1, D2 and D2n as "1.00 ±
  0.05".
- **C was not extended to v2.** Its v1 figure (2.2-3.1x) stands.
- **Everything in the `RESULTS.md` "cannot say about the real engine" list still applies.** There
  are no belts, fluids, real circuit networks or entity sizes. The control-behaviour pass here
  writes a flag. The real one evaluates a circuit condition, and that cost is the same for every
  variant.
- **Only 6 of the design's possible shapes are exercised.** The question of a modded game with
  dozens of shapes is still open: the bucket count, the type-order slots, and per-shape inlining
  of a large update.
