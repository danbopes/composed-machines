# Entity update cost model

One C++17 file, `model.cpp`, that runs a small Factorio-like factory (chests,
inserters and crafting machines on shared electric networks) under several
object layouts, times the tick, and checks that every layout ends in exactly the
same world state. It is not Factorio's code. It exists to answer one question:
what does it cost, per entity per tick, to build machines out of optional parts
instead of hand-written classes?

## Build and run

```bash
make                     # g++ -O2 -march=native
./run.sh                 # 10k, 100k and 1M entities, all suites
./run.sh 100000 --repeats 5 --suite v2s
make CXX=clang++ -B      # or build with clang
```

Options: sizes as bare numbers; `--ticks N` (600), `--warm N` (60), `--repeats N`
(3), `--seed N`; `--suite` takes a comma list of `v1`, `v2`, `v2s`; `--only`
takes a comma list of variant names (the suite's baseline always runs). A 1M run
of every suite takes about seven minutes per repeat.

## Variants

v1 workload (no optional parts that tick):

- **A** static: one hand-written class per entity type, one bucket per type,
  the way the engine does it today. The baseline.
- **B** composed: one class for every entity, each part a pointer or bit tested
  in every update.
- **C** runtime ECS: each entity is a list of components updated through virtual
  calls, with lookups by tag (the 2018 design that was rejected).
- **D** templated composed: B's idea with the parts as template parameters, so
  absent parts take no space and no test. One bucket per shape.

v2 workload (machines may also have an electric or heat output, a circuit
enable flag and a trigger on cycle finish):

- **A2** static: the v2 parts as the engine would add them, a Generator and a
  Reactor class, and an enable flag on every crafting machine.
- **B2** composed: B with more slots.
- **D1** templated, v1 shapes: one machine shape; the output is one pointer
  tested only when a cycle finishes, and the enable flag is tested once per
  update.
- **D2** templated, shapes multiply: one shape and one bucket per combination
  of output kind and circuit enable (six machine shapes in this workload).
- **D2n** D2 without the shared core: every shape gets its own copy of the
  functions inserters call. It measures a trap, not a design.
- **D1s** control: D1's code visiting machines in D2's order.

`v2` visits every bucket in group (spatial) order. `v2s` shuffles every update
list first, so no layout benefits from the workload's repeating pattern.

## Reading the output

- `ns/e-t` is nanoseconds per entity per tick, divided by all N entities, the
  40% passive chests included.
- `min` is the fastest repeat, `median` the middle one. Interference only ever
  adds time, so the minimum is the cleaner number. A large gap between the two
  means the machine was busy.
- `ratio X/A` compares each variant with its suite's baseline in the same run.
  Compare ratios, not absolute numbers, between runs or machines.
- The checksum must be identical for every variant of a suite. The program exits
  non-zero if it is not.
- 1M entities is past the L3 cache of most machines, so those numbers measure
  memory more than code.

Results and their interpretation: `RESULTS.md` (v1) and `RESULTS-v2.md` (v2).
