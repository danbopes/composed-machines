# component-lab status

Integrated on 2026-11-02 against Factorio 2.1.24. The full suite is green apart from
nine tests that fail on purpose. Each one is named `KNOWN-LIMIT` or `KNOWN GAP` and
documents an emulation limit (gap lists below: first pass, then "Second pass").

**Totals: 297 tests, 288 passed, 9 failed (all deliberate).** Re-run `--fresh` after the
second pass review fixes (below); before them, three `--fresh` runs in a row and one warm run gave the same result. A fresh run takes about 7 s, a warm one 3 s.

- First pass (8 entities + library): 160 tests, 158 passed, 2 deliberate.
- Second pass (8 entities, section "Second pass" below): 137 tests, 130 passed, 7 deliberate.

## Reproduce

```bash
cd ~/factorio/ai-harness
~/factorio-harness/.venv/bin/fh test component-lab --fresh   # full suite, map rebuilt (needed after any prototype or on_init change)
~/factorio-harness/.venv/bin/fh test component-lab           # reuse the cached map (about 4 s)
~/factorio-harness/.venv/bin/fh test component-lab --filter cl-cold-box   # one entity
~/factorio-harness/.venv/bin/fh test component-lab --keep    # leave the server up, then:
~/factorio-harness/.venv/bin/fh rcon --project component-lab expr 'remote.call("component_lab","census")'
~/factorio-harness/.venv/bin/fh stop component-lab
```

The suite files are in `~/factorio/ai-harness/suites/component-lab/` and run in
sorted order: `_lib`, `_site` (the shared site helper, which registers no tests),
`cl-*`, then `zz-leftovers`.

## Entities and results (first pass)

| Entity | Shape | Core / hidden parts | Tests | Result |
|---|---|---|---|---|
| library (`_lib.lua`, `cl-libtest*`, plus the load marker) | S0-S3 | all part kinds | 27 | 27 pass |
| `cl-fluid-chest`, `cl-fluid-chest-watch` | S0 / S1 | container + storage-tank | 14 | 13 pass, 1 KNOWN GAP |
| `cl-signal-chest` | S0 | container + constant-combinator | 12 | 12 pass |
| `cl-fuelled-chest` | S1 | container + burner reactor | 16 | 16 pass |
| `cl-cold-box` | S1 | container + EEI | 19 | 19 pass |
| `cl-timed-converter` | S3 | assembler + 2 containers + 2 proxies | 18 | 18 pass |
| `cl-seep-derrick` | S3 | assembler, no parts | 15 | 15 pass |
| `cl-dig-site` | S3 | assembler + 2 containers + 2 proxies | 22 | 21 pass, 1 KNOWN-LIMIT |
| `cl-signal-endpoint` | S1 | constant-combinator + EEI | 16 | 16 pass |
| leftovers check (`zz-leftovers.lua`) | | | 1 | pass |

The two deliberate failures:
- `cl-fluid-chest: KNOWN GAP rotated blueprint placement rotates the tank`: a
  container ghost carries no direction, so a blueprint pasted rotated leaves the tank
  facing its tagged direction.
- `cl-dig-site: KNOWN-LIMIT rig: an inserter must not pick from food`: a proxy
  exposes its inventory both ways, and the 2.1 bar only gates insertion.

## Second pass (TEST-ENTITIES-2.md)

Eight more entities, written by parallel builders in their own workspaces and
integrated here. Each has a prototype file, an entity script, a suite file and
bench cells (`component/bench/builds/`).

| Entity | Shape | Core / hidden parts | Tests | Result |
|---|---|---|---|---|
| `cl-hearth` | S3 burner crafter | void assembler shell + hidden reactor + fuel-door proxy, 20-tick pass | 18 | 17 pass, 1 KNOWN-LIMIT |
| `cl-brazier` | S1 | simple-entity core + hidden reactor + fuel-door proxy, 30-tick pass, script light | 18 | 17 pass, 1 KNOWN-LIMIT |
| `cl-creep-collector` | S3, consume_at = script | electric assembler shell + hidden spoils container + proxy, 60-tick idle target poll | 17 | 17 pass (KNOWN-LIMIT checks pass as written) |
| `cl-rotating-chest` | S0 | 6x3 passive assembler shell + 240-slot hidden container + 14 edge proxies | 18 | 18 pass (3 KNOWN-LIMIT tests assert the limit) |
| `cl-slag-generator` | S3 + generator part | burner assembler shell + hidden output EEI | 15 | 14 pass, 1 KNOWN-LIMIT |
| `cl-waste-heat-smelter` | S3 + heat part | electric assembler shell + hidden heat-interface | 15 | 13 pass, 2 KNOWN-LIMIT |
| `cl-mass-driver` | S3, consume_at = finish | 4 MW electric assembler shell, 40 MJ buffer, Lua projectile per shot | 19 | 18 pass, 1 KNOWN-LIMIT |
| `cl-tuned-furnace` | S3 + circuit-bound setting | electric assembler shell, `local_effect` speed, 30-tick signal pass, no hidden parts | 17 | 16 pass, 1 KNOWN-LIMIT |

The seven deliberate failures:
- `cl-brazier: KNOWN-LIMIT flame-out is only noticed at the next pass (up to 30 ticks late)`
- `hearth: KNOWN-LIMIT fuel removed between passes leaves the shell crafting until the next pass`
- `cl-mass-driver: KNOWN-LIMIT consume_at = finish keeps the plate in the input until the shot`
- `slag-generator: KNOWN-LIMIT the block lands one cycle late (next cycle's water already taken)`
- `tuned-furnace: KNOWN-LIMIT a signal-R pulse shorter than the 30-tick pass is missed`
- `cl-waste-heat-smelter: KNOWN-LIMIT the heat connection follows a rotation`
- `cl-waste-heat-smelter: KNOWN-LIMIT built facing east, the connection faces west`

### What integration changed (second pass)

The first full run had 15 failures (9 deliberate) and took 110 s. Root causes:

- **A temp-surface sweep took 30 s per call.** `_site.lua` cleared scratch surfaces
  with `find_entities_filtered{area = {{-1e6, -1e6}, {1e6, 1e6}}}`; on 2.1.24 that
  walks every chunk coordinate in the area. Any test using `sites.temp_surface`
  (seep-derrick, slag-generator and tuned-furnace clones) stalled the RCON call. It now
  passes no area (whole surface). The full run went from 110 s to 7 s.
- **Re-arming a fixture mid-suite put the game back to speed 1000.** The brazier and
  hearth suites re-arm their fixtures for the next `--keep` run, and
  `fixtures.hold_until` wrote `game.speed` straight away, so every later suite ran at
  fixture speed (4 seep-derrick failures). `hold_until` now schedules the speed-up for
  the next tick (`cl_fixtures_speedup`), which a suite running inside one tick never sees.
- **Synthetic dispatch ran other entities' work.** `remote dispatch(tick)` ran the
  whole bucket: named fixture callbacks (the speed-up above, snapshots) and any other
  record due that tick. A brazier test dispatched a bucket that held a cold-box
  fixture box, which then passed off its phase (`cl-cold-box: self-scheduled box
  passes on its own`, flaky by unit number). `dispatch(tick, unit_number)` now runs
  only that record and leaves the rest of the bucket for the real tick
  (`scheduler.dispatch_records`); every suite passes its unit.
- **The dig-site rig tests assumed about 30 ticks of runtime.** With the second-pass
  fixtures the suite starts at about tick 2750, so the slow rigs had finished cycles
  (fish eaten, ore dug). The food-in, ore-in and ore-out tests now count
  `rec.data.cycles` and `rec.data.dug` in their conservation sums, as the finish rig
  already did.

Builder workarounds moved into the library (duplicates removed from the entity files):

| Library addition | Replaces |
|---|---|
| `direction_count = 4` on a **process** shell adds the connectionless fluid box (only when the shell has no fluid box of its own) | the same box in `emulation.prototype` of `cl-mass-driver` and `cl-waste-heat-smelter` (which now declares `direction_count = 4`) |
| `process.products` of type `energy` / `heat` are left out of the engine cycle recipe and kept in mod-data | the `data.raw.recipe` rewrite after `component.define` in `cl-slag-generator` |
| `component.CLEAR` as a value in `emulation.prototype` / `emulation.item` unsets an inherited field | the eight `core.x = nil` edits after `component.define` in `cl-rotating-chest` |
| `fixtures.hold_until` defers the speed-up; `dispatch(tick, unit)` | see above |

Bench harness: `builds/_common.lua` `make_surface` renamed the old `bench` surface out of
the way before deleting it. `delete_surface` takes effect next tick, so a second build in
one session failed with "Invalid surface name" (every builder hit it).

Left local on purpose: the poll EEIs (`cl-creep-collector-poll-eei`,
`cl-mass-driver-poll-eei`) and `cl-brazier-native-burner` are bench-only prototypes in
the entity files. Each is used by one cell, and their names do not collide. The
waste-heat smelter's `emulation.heat_product` (one `add_heat` per crafted event) is the
only heat product so far, so it stays in that script.

Leftovers: `zz-leftovers` passes, and two back-to-back `run_all` calls on one server
change nauvis only by map generation along the suite rows (trees, ore, nests in new
chunks). No placed entity accumulates.

### Consolidated emulation gaps (second pass)

**Detection latency and per-instance polls (no event exists to wake on)**
22. Burner state is polled: the brazier every 30 ticks, the hearth every 20 ticks (it
    moves the pass to the exact burn-out tick when the last item is burning). Fuel taken
    out from outside, or a refuel, is seen up to one interval late (2 KNOWN-LIMIT tests).
    A cold hearth keeps polling where a native S3 would sleep.
23. A circuit-bound setting (`cl-tuned-furnace`) is read on a 30-tick poll, forever,
    wired or not. A pulse shorter than the poll is missed (KNOWN-LIMIT). Native reads at
    cycle start and on wake.
24. Creep-collector target discovery is a 60-tick poll while idle. It is not counted as a
    gap, because the native type also leaves "when to start" to the mod.
25. A full generator buffer (`cl-slag-generator`) is re-checked every 30 ticks, and the
    block only lands after the engine has finished the cycle and started the next one
    (KNOWN-LIMIT: next cycle's water already used).

**Process semantics an assembler cannot express**
26. `consume_at = "finish"` (mass driver): the assembler takes the ingredient at cycle
    start (KNOWN-LIMIT).
27. Energy taken out of a charged buffer as a lump per shot is not available. The shell
    draws 4 MW evenly through the cycle, and needs `input_flow_limit` 8 MW (draw +
    charge) or it reports `low_power` forever; the live buffer reads 42.67 MJ.
28. A recipe has no `energy` or `heat` result. The library now strips them, and the
    script adds the energy (`add_output_energy`) or heat (`add_heat`) per crafted event:
    one Lua call per cycle, all at once, not spread across the cycle.
29. A recipe with no ingredients starts its next craft on the tick the last one ends,
    before the script can gate it (creep collector reports `is_crafting()` while idle,
    one tick short on the next cycle).
30. `cycle_finished_trigger` is a Lua `create_entity` per shot.

**Parts that cannot follow the core**
31. A hidden heat-interface has no direction, so heat connections do not turn with the
    core, and placing it facing east still connects south (2 KNOWN-LIMIT tests). A
    library fix would need one heat prototype per direction, swapped on rotate.
32. A non-square shell cannot turn a quarter in place: the rotating chest is rebuilt
    facing 90 degrees clockwise, its 240 slots are moved, and the LuaEntity and
    unit_number change (undo and other mods lose it). Turns are always clockwise, a
    blocked turn shows no "cannot rotate" message, and ghost rotation and mirroring are
    not handled.
33. The burner's light, flicker and smoke belong to the hidden reactor, so the hearth looks
    cold while burning idle; the brazier's light is a script `draw_light` toggled by the
    pass.

**Access, cost and GUI**
34. Fuel doors are proxies onto the reactor's fuel slot: inserters fill a whole stack
    (about 16-21 coal) where a native burner stops at a small limit (extends gap 9). The
    hearth takes fuel only on its door tile.
35. A recipe-less assembler shell is an UpdatableEntity (`no_recipe`), so the S0
    storehouse is not free per tick, and it needs 16 entities (shell, container, 14
    doors). `circuit_outputs = "contents"` would need a poll.
36. The brazier core has no entity GUI (simple-entity), so its fuel slot is reachable
    only by inserter, blueprint request or script.
37. The waste-heat reactor-temperature test is replaced by energy conservation (the hidden
    reactor never cools), and heat above `max_temperature` is discarded and counted.

### Benchmark cells (second pass)

Registered in `component/bench/make_save.py` (`COMPOSED`, `PAIRS`). Every twin that is not
a native-matrix variant is a grid cell, so `GRID_VARIANTS` now takes all of them
(`native-*`, `poll-*`, `beacon-*`, `reactor-*`).

| Composed | Twins |
|---|---|
| `cl-hearth` | `native-cl-hearth`, `stone-furnace` |
| `cl-brazier` | `native-cl-brazier` |
| `cl-creep-collector` | `native-cl-creep-collector`, `poll-creep-collector`, `electric-furnace` |
| `cl-rotating-chest` | `native-cl-rotating-chest`, `chests` |
| `cl-slag-generator` | `native-cl-slag-generator` |
| `cl-waste-heat-smelter` | `native-cl-waste-heat-smelter`, `reactor-waste-heat-smelter`, `electric-furnace` |
| `cl-mass-driver` | `native-cl-mass-driver`, `poll-mass-driver`, `assembler` |
| `cl-tuned-furnace` | `native-cl-tuned-furnace`, `beacon-tuned-furnace` |

Smoke test: all 20 new cells built `-n 50 --settle 600` saves; the saves were deleted
afterwards. `_check.lua` status histograms:

| Cell | Machines | Notes |
|---|---|---|
| cl-hearth / native | 50 assemblers working + 50 reactors / 50 furnaces + 50 reactors | 150 products each |
| cl-brazier / native | 50 reactors burning / 50 reactors + 50 lamps | composed inserters keep working (fuel door over-fills, gap 34) |
| cl-creep-collector / native | 50 shells working (250 products) / 50 furnaces working (300) | |
| poll-creep-collector | no machine status | probed in the save: 50 cells, 150 harvests in 600 ticks |
| cl-rotating-chest / native | 50 shells `no_recipe`, 100 inserters working / 100 inserters working | 1013 vs 313 entities |
| cl-slag-generator / native | 50 working (100 cycles) / 50 furnaces working + steam engines | |
| cl-waste-heat-smelter / native / reactor | 50 working / 50 furnaces working / 50 reactors burning | |
| cl-mass-driver / native | 50 working, 50 shots / 50 assemblers working | |
| poll-mass-driver | no machine status | probed in the save: 50 cells, 50 shots in 600 ticks |
| cl-tuned-furnace / native / beacon | 50 working each, 400 products each | `crafting_speed` 2.50 in all three, also after loading the save (checked: `local_effect` survives save/load) |

`suite.py --group composed --only <names>` builds and benchmarks only those composed
entities, their grid twins and the empty baseline. Matrix twins (stone-furnace,
assembler, chests, electric-furnace) come from the native group at the same `-n`.
The rotating chest's "assembling-machine-2 idle, no recipe" comparison has no cell yet.

### Reproduce (second pass)

```bash
cd ~/factorio/ai-harness
~/factorio-harness/.venv/bin/fh test component-lab --fresh                       # 297 tests, 288 pass, 9 deliberate
~/factorio-harness/.venv/bin/fh test component-lab --filter cl-tuned-furnace     # one entity (suite names: cl-hearth uses "hearth:", slag "slag-generator:", tuned "tuned-furnace:")
cd ~/factorio/component/bench
./make_save.py cl-hearth -n 50 --name cl-hearth-50 --settle 600                  # smoke one cell
./suite.py --group composed --only cl-hearth,cl-tuned-furnace -n 2000 --ticks 3600 --runs 5
```

## Second pass review fixes (REVIEW-2.md H1, H2)

Both HIGH findings are fixed at the root, each with a regression test that was
checked to fail with the fix reverted (water/ghost: "same entity"; drain: 9 coal
reached the chest) and to pass with it.

- **H1, rotating-chest turn ignored tiles and deleted ghosts.**
  `scripts/entities/cl-rotating-chest.lua` `blocked()` now also refuses a turn when
  an `entity-ghost` whose inner prototype collides with the shell sits in the turned
  footprint, and when any tile in it (inset 0.01 so edge-touching tiles are skipped)
  carries a layer of the shell's collision mask: water, lava, `out-of-map` and a
  platform's `empty-space` all do. `can_place_entity` cannot be used for this, since
  the old core overlaps the turned footprint and always blocks it. A refusal goes
  through the existing `undo_flip`. Tests: `cl-rotating-chest: a turn onto water is
  refused`, `cl-rotating-chest: a turn onto a ghost is refused and the ghost survives`.
- **H2, brazier fuel drained through the fuel door.** `prototypes/entities/cl-brazier.lua`
  adds `no-automated-item-removal` to `cl-brazier-proxy-fuel` after `component.define`.
  Probed on 2.1.24: the engine honours the flag on a proxy-container, so the door
  still takes fuel from inserters but no inserter can pick from it. The brazier
  fixture gains a fourth brazier (10 coal) with a burner inserter picking from its
  tile into an iron chest. Test: `cl-brazier: real ticks: an inserter picking from
  the brazier tile cannot drain the fuel` (chest empty, >= 9 coal left, still
  burning, no power transition).

Follow-up worth a library change (not made here, `lib/` is shared): the flag works
on a proxy, so `hidden.proxy` could take an insert-only option. That would also turn
the first-pass `cl-dig-site: KNOWN-LIMIT rig: an inserter must not pick from food`
failure, whose message says an insert-only proxy is impossible, into a pass, and
would close the hearth door's same exposure (REVIEW-2 H2 note) without relying on
the shell winning pickup.

## Review fixes (REVIEW.md H1, H2)

Both high findings were library bugs and are fixed in the library; no entity
script changed.

- **H1, a dead hidden part crashed the next handler.** `lifecycle.create_part`
  (and the clone path) now makes every part indestructible and registers it with
  `register_on_object_destroyed`. `damage` and `die()` no longer remove a part
  (both probed). `destroy()` and editor deletion still can, so the new
  `lifecycle.heal(rec)` rebuilds any missing part, re-links proxies and wires and
  re-pins filters. It runs on a part's `on_object_destroyed`
  (`lifecycle.part_destroyed`), and also before every handler-facing path
  (scheduled `on_tick`, `on_crafted`, `before_mine`, GUI open), because
  `on_object_destroyed` can arrive a tick late. A rebuilt part starts empty: what
  the destroyed part held is lost. A rebuilt combinator is also blank until the
  entity script publishes again. `Record:part` returns nil for an invalid part.
- **H2, handlers used the machine after `rec:raise`.** Events raised while the
  library runs an entity handler are now queued and raised when the handler
  returns (`Record.batch`, in `record.lua`). Every subscribed event, every
  scheduled dispatch and every `component_lab` remote function runs inside a
  batch. A queued event whose machine has gone (`Record:live()` is false) is
  dropped, and `Record:raise` on a removed machine is a no-op that returns false.
  Event order and the `event_log` entries (written at raise time) are unchanged.
  Named scheduler callbacks are fixture drivers that read their own events back
  straight away (the signal-endpoint rig counts them), so they still raise
  immediately.

Regression tests (all pass):
- `_lib.lua`: `lib: review H1 hidden parts cannot be damaged`,
  `lib: review H1 a part removed by script is rebuilt before the next handler`,
  `lib: review H2 a subscriber may remove the machine from its own event`.
- `cl-cold-box.lua`: `review H1 a destroyed EEI is rebuilt and the pass runs` (the
  REVIEW repro) and `review H2 removing the box from power_state_changed`.
- `cl-timed-converter.lua`: `review H2 removing the converter from
  inventory_changed` (the REVIEW repro).

The H2 tests register a subscriber in the aitest mod, the same way a
third-party mod would. They run the handler through the synthetic `dispatch`, so
before the fix they failed inside the test instead of crashing the server.

## What integration changed

Root causes of the integration failures (12 failures on the first full run):
- **Fixtures fought over `game.speed`.** seep-derrick dropped the speed back to 1 at
  tick 320, before timed-converter's 660-tick scenario had finished, so six
  converter tests saw an unfinished scenario. New `scripts/fixtures.lua`
  (`runtime.fixtures.hold_until(tick)`) keeps the speed up until the latest tick any
  fixture asked for. No entity script writes `game.speed` any more. The suite now
  starts at about tick 690.
- **Unprepared, colliding test sites.** The `_lib` and fuelled-chest blueprint and
  spill tests landed on trees and water depending on the map seed, and tests left
  their entities behind. New `suites/component-lab/_site.lua` gives each suite its own
  row: a site is generated, cleared and paved, and after every test the whole row is
  cleared, cores first with `raise_destroy`. All nine suites use it.
  `zz-leftovers.lua` fails the run if any prototype ends with more records than the
  fixture baseline.
- **Synthetic dispatch picked up other records.** `dispatch(tick)` runs the whole
  bucket, so the converter's event-order test also saw scenario converters. That
  suite now filters the event log by `unit_number`.

Builder workarounds moved into the library, with the duplicates removed from the
entity scripts:

| Library addition | Replaces |
|---|---|
| `runtime.fixtures.hold_until` | private `game.speed` handling in seep-derrick and timed-converter |
| `rec:schedule_phase(interval, after)` (SPEC 3.4 phase) | `first_due` in cold-box, `next_phase_tick` in signal-endpoint, the ad-hoc phase in fluid-chest |
| `rec:contents_changed(inv)` (the inventory_changed poll) | `snapshot`/`same` in signal-chest, `signature` in timed-converter |
| `before_mine(rec)` handler, wired to `on_pre_player_mined_item` / `on_robot_pre_mined` / `on_space_platform_pre_mined` and `runtime.mine` | the `cold_box_mine` remote; removed the cold-box "library mine does not settle" KNOWN GAP test, because the gap is closed |
| `on_pasted(to, from)` handler plus `lifecycle.pasted` (copies SPEC settings and the hidden combinator sections), remote `paste` | signal-chest's own paste subscription and the `signal_chest_paste` remote |
| `listen()` drops filters on events that take none (list from runtime-api.json) | the load crash that `on_entity_settings_pasted` with filters caused for every builder |
| Static multi-item `filters` pinned per slot in `lifecycle.materialise` | `apply_filters` in timed-converter, `FOOD_SLOTS` in dig-site |
| SPEC rule 12 buffer sizing: an omitted `buffer_capacity` becomes `energy_usage x tick_interval`; an explicit value below that fails at load | cold-box's `data.raw` override to 10 kJ (the spec now omits the buffer) |
| `census` remote (records per prototype) | used by the leftovers check |
| `cl-fluid-chest-watch` registered in `control.lua` | the self-registration in its script |

## Emulation gaps: what the native type gives that Lua cannot fake

**Event latency and cost**
1. **No transfer or insert event on containers.** These are emulated by a
   per-instance poll:
   - `inventory_changed`: every 10 ticks (signal chest, timed converter)
   - fuel gate: every 30 ticks (fuelled chest)
   - spoil credit: every 60 ticks (cold box)
   - `fluid_threshold`: every 60 ticks (fluid chest)
   - idle passes: every 61 ticks (dig site) and 60 ticks (seep derrick, when idle and its condition fails)

   Each poll costs scriptUpdate even when the entity is idle, and the event arrives
   up to one interval late. Two transfers inside one window make one event, and the
   payload has no `player_index` or robot. The native dirty bit gives one event per
   tick at the inventory flush and lets the entity sleep.
2. **Script-raised events fire in the script phase at poll time**, not at an
   entity-phase flush (`status_changed`, `power_state_changed`, `fluid_threshold`,
   `inventory_changed`).
3. **Hidden parts update on their own.** The cost moves onto them: the reactor in
   the fuelled chest, and an EEI that draws every tick. A `tick_interval` entity
   would draw one lump per interval, so the emulation saves scriptUpdate but no
   ElectricEnergyInterface work.

**Status and power**

4. `custom_status` changes only the label and diode. `LuaEntity.status` stays the
   core's own, so alerts, circuit status reads and `draw_in_states` never see the
   emulated status.
5. The power state comes from the hidden buffer (cold box), so a cut is noticed
   about one interval late, or from network flow statistics (signal endpoint),
   which costs a 22-field table on every poll.
6. While idle, a script-gated shell cannot ask the engine for `no_fuel` or
   `full_output`, so the script works them out itself. While running, the script
   clears `custom_status` so the engine's own status shows.
7. Engine quirk: an idle crafter holding 2x its product reports `full_output`
   ahead of a missing fluid ingredient. The seep derrick shows the wrong reason
   natively.

**Inventories and access**

8. **`inserter_access` cannot be enforced through a proxy** (KNOWN-LIMIT test).
   Extract-only is approximated with a closed bar, and the script then has to
   write yields slot by slot. Insert-only cannot be done at all.
9. `automated_insertion_limit` is not emulated: inserters fill the whole stack.
10. Static multi-item filters become one slot per item.
11. A container core has no fluid storage, so fluid lives in a hidden tank that only
    `rec:fluid_box(1)` reaches. The core's GUI cannot show the fluid.
12. The assembler shell resizes its input fluid box to the recipe (40, not the
    spec's 1000).
13. The SPEC 1.3 spoil stamp cannot be written: `spoil_tick` is refused beyond the
    item's normal spoil time. The cold box credits per pass instead, so spoil time
    matches but `spoil_tick` and `spoil_percent` read differently. Stacks removed by
    an inserter or another mod between passes miss up to 51 ticks of credit.

**Rotation, blueprints, ghosts and undo**

14. A container core has no direction. The fluid chest rotates through custom
    inputs, and a rotated blueprint or a rotated cursor build loses the orientation
    (KNOWN GAP test).
15. The ghost and blueprint of a hidden inventory cannot carry item requests. Food
    in the dig site and fuel in the fuelled chest are dropped. The fuel request is
    re-issued from tags as a proxy aimed at the reactor, which a native ghost would
    show and edit itself.
16. Settings live in storage, so an undo or a death ghost rebuilds the entity
    without them (the seep derrick's depletion returns as 0).
17. A fixed-recipe shell blueprints its recipe name.
18. The hidden combinator's sections reach blueprints and copy-paste only through
    tags and the library paste path. Headless `copy_settings` raises no event.

**Process**

19. `start = "automatic"` with `consume_at = "script"` has no library mode. The dig
    site gates the shell itself.
20. A cycle started from `on_tick` finishes 1 tick late, because the shell first
    advances on the next entity update.
21. Pending output for `consume_at = "script"` is held in `rec.data`, and it is lost
    on an orphaned teardown.

**Not testable headless** (the code exists but no test covers it): GUI frames
(`on_gui` for every entity), the fluid chest's rotate key, player mining
(`before_mine` is covered through `runtime.mine`), and undo.

## Library candidates not lifted yet

- A fuel-request helper for hidden burner parts (tags to an item-request-proxy on
  revive). Only the fuelled chest needs it so far.
- The bar trick for `inserter_access = "extract"`, plus a slot-wise put. Lifting the
  bar would make `inv.insert` fail for every extract inventory, and the timed
  converter writes its output through `insert`.
- An "automatic + script consume" process mode (dig site).
- Settings carried through death ghosts, for example by tagging the ghost in
  `on_post_entity_died`. Undo cannot be closed from script.
- `set_signals` enabling the combinator only when signals exist. This clashes with
  the signal endpoint, which uses `cb.enabled` as its power gate.

## Notes for benchmarking

The on_init fixtures stay in the save: 6 scenario converters plus 1 clone, 3 seep
derricks, 6 cold boxes, the dig-site rigs, the fuelled-chest fixtures, the signal
chests and the endpoint rig, and since the second pass the hearth, brazier,
creep-collector (including one poll cell), rotating-chest, slag-generator,
waste-heat, mass-driver and tuned-furnace fixtures (the census line in every
`_check.lua` output lists them). A benchmark that scans all records must exclude them
or start from a map without the suite fixtures.
