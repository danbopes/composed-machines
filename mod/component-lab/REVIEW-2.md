# component-lab adversarial review, second pass (2026-11-02)

Scope: the eight TEST-ENTITIES-2 entities (`cl-rotating-chest`, `cl-brazier`, `cl-hearth`,
`cl-creep-collector`, `cl-tuned-furnace`, `cl-mass-driver`, `cl-slag-generator`,
`cl-waste-heat-smelter`): prototype files, entity scripts, suites. Also the library additions listed
under "Second pass additions" in README.md and "What integration changed (second pass)" in STATUS.md.
Checked against TEST-ENTITIES-2.md, V2-PARTS.md 1.1-1.4 and the first-pass REVIEW.md.

Probes ran on a fresh 2.1.24 map from `component/mod/ws/review` (RCON 27200):
`fh test component-lab --fresh --keep --filter zz:`, then `fh rcon --project component-lab file <probe>.lua`.
Findings marked **confirmed** were reproduced there. Probe entities were removed afterwards and the server
was stopped.

Line numbers are per file. Script paths are relative to `component/mod/component-lab/`. Suite paths are
relative to `ai-harness/suites/component-lab/`.

---

## HIGH

### H1. A rotating-chest turn ignores tiles and deletes ghosts in the new footprint (confirmed)

`scripts/entities/cl-rotating-chest.lua:56-64` (`blocked`) checks only for colliding **entities**. The
replacement is then built with `surface.create_entity` (`:97-100`), which runs no placement check, and
`preserve_ghosts_and_corpses` defaults to false.

**What fails.**
- A storehouse turns onto water, onto lava, or off the edge of a space platform. The native rotate
  refuses all three.
- Any entity ghost in the turned 3x6 footprint is deleted without warning. That is the player's
  planned build, and it vanishes with no undo.

**Repro (probe).** Pave a 24x24 area and make every row above `y = O.y - 1.5` water. Build
`cl-rotating-chest` at `{O.x, O.y + 0.5}` with `raise_built`. Put an `entity-ghost` (small-electric-pole)
at `{O.x + 0.5, O.y + 2.5}`, then call `remote.call("component_lab", "rotate", chest)`.
Result: `rotate_ok = true`, direction east, **6 water tiles under the turned chest**, `ghost_valid = false`.
For the same position and direction, `surface.can_place_entity` returns **false**.

**Fix.** Before building, also check tiles:
`surface.find_tiles_filtered{area = box, collision_mask = core.prototype.collision_mask.layers}`, and
`can_place_entity` for the out-of-map case. Count ghosts in the box as obstacles, or pass
`preserve_ghosts_and_corpses = true`. Refuse with `undo_flip` as the script already does for entities.

### H2. Any inserter whose pickup tile is a brazier drains its fuel through the fuel door (confirmed)

`prototypes/entities/cl-brazier.lua:15` puts `fuel_proxy_offset = true` on the core's only tile.
A proxy-container is a two-way door (first-pass gap 8). The core is a `simple-entity-with-owner` with no
inventory, so an inserter picking up from the brazier tile picks from the proxy, which means from the
reactor's fuel slot. A native burner never gives fuel to an inserter; inserters only take burnt results.

**What fails.** A brazier next to any inserter that faces away from it is emptied. It then flames out and
raises `power_state_changed{powered = false}` for a cause the native entity cannot have. No KNOWN-LIMIT
test documents this, and the brazier suite only checks the insertion direction (`cl-brazier.lua:331`).

**Repro (probe).** Build a brazier and put 10 coal in the reactor. Place a `burner-inserter` east of it
that picks from the brazier tile and drops into an iron chest. After 1058 ticks: brazier fuel 0, chest
9 coal (the 10th was burning). `pickup_target = "cl-brazier-proxy-fuel"`.

**Fix.** The emulation cannot make a proxy insert-only. Either add the `no-automated-item-removal` flag to
`<name>-proxy-fuel` in `lib/hidden.lua`, if the engine honours it on a proxy (probe it), or record a
KNOWN-LIMIT test that asserts the drain. The hearth's door has the same exposure on its door tile, but the
shell wins pickup there (the probe's inserter picked from `cl-hearth`), so only the brazier leaks today.

---

## MEDIUM

### M1. A turn destroys the rotated entity inside `on_player_rotated_entity` and raises nothing

`scripts/entities/cl-rotating-chest.lua:115-116`: `lifecycle.teardown(..., "destroyed")`, then
`core.destroy()` with no `raise_destroy`. The replacement (`:97`) is created with `raise_built = false`.

**What fails.**
- Every other mod's `on_player_rotated_entity` handler that runs after component-lab gets an invalid
  `event.entity`. This is the classic "event raised with a stale entity" crash for whichever mod
  indexes it first.
- No `script_raised_destroy` and no `script_raised_built` are raised. A mod that tracks storehouses
  (logistics overlays, LTN/Cybersyn-style registries, Bottleneck-style status mods) keeps a dead
  reference and never learns about the new one.
- These do not carry over to the new entity: deconstruction and upgrade marks, `last_user`, and any
  item-request-proxy aimed at the old core.
- The player's undo entry for the rotate refers to a destroyed entity. The scripted rebuild is not in
  the undo queue, so undoing the original placement later does nothing.

The KNOWN-LIMIT test (`cl-rotating-chest.lua:303`) covers the unit_number change. It does not cover the
stale event entity or the missing raises.

**Fix.** Defer the replacement to the next tick (`rec:schedule(1)` with the turn stored in `rec.data`), so
the rotate event finishes on a valid entity. Then destroy with `raise_destroy = true` (teardown is
idempotent once the record is gone) and create with `raise_built = true` (`materialise` is idempotent).
Copy `last_user` and the deconstruction mark across.

### M2. The hearth's fuel-door tile starves ore inserters (confirmed)

`prototypes/entities/cl-hearth.lua:21` puts the fuel door at `{-0.5, 0.5}`, inside the shell. An inserter
that drops onto that tile picks the proxy as its drop target. The proxy only accepts chemical fuel, so the
inserter never picks up ore.

**What fails.** A native stone furnace takes ore and fuel on every tile. The hearth takes ore on three
tiles and only fuel on the fourth. An ore inserter on the south-west tile starves the hearth for good,
with no status and no alert.

**Repro (probe).** Build a hearth with 5 coal. Put an iron chest with 10 iron ore south of the door tile,
and a burner inserter between them dropping north onto the door. After 274 ticks: `drop_target =
"cl-hearth-proxy-fuel"`, nothing held, 0 ore in the shell, 10 ore still in the chest.

**Fix.** Document it as a KNOWN-LIMIT test, or move the door outside the 2x2 (with the trade-offs of M5).
Gap 34's text ("takes fuel only on its door tile") understates it: the door tile also refuses everything
else.

### M3. Eight more fixture init hooks: the first-pass M6 is unresolved and now twice as large (confirmed)

Second-pass hooks: `cl-brazier.lua:150`, `cl-hearth.lua:195`, `cl-creep-collector.lua:332`,
`cl-tuned-furnace.lua:231`, `cl-mass-driver.lua:303`, `cl-slag-generator.lua:212`,
`cl-waste-heat-smelter.lua:118`, `cl-rotating-chest.lua:234`. Each runs from `on_init` **and**
`on_configuration_changed`. Each `destroy()`s every non-character entity in a fixed area:
- creep collector: 352x32 tiles at (-2616, 2704)
- mass driver: 368x80 at (-2040, 1560)
- tuned furnace: 52x18 at (-1008, 1472)
- slag generator: 102x20 at (-810, 1750)
- waste heat smelter: 72x18 at (-2408, 1832)
- hearth: 22x6 at (-523, 417)
- rotating chest: 16x16 at (-2808, 992)

Each also holds `game.speed = 1000`.

**What fails.**
- Adding the mod to an existing save wipes those areas.
- A fresh map holds **63 fixture machines and 41 scheduled keys** (probe: `census`, `storage.cl.due`).
  Braziers poll every 30 ticks, hearths every 20, tuned furnaces every 30, the creep poll walk every
  60, forever.
- `bench/make_save.py` boots this same map, so every bench save carries them. `report.py` subtracts the
  `empty-0` save, which carries them too, so the mean largely cancels. The variance does not.
- `storage.cl.creep_poll` mixes the fixture's poll cell into the `poll-creep-collector` column's walk.

**Fix.** As M6 recommended: arm fixtures only through a remote the harness calls, and never from
`on_configuration_changed`. `make_save.py` then does not call it.

### M4. Seven new deliberately failing tests: the first-pass M9 is unresolved and worse

STATUS: 9 failing on purpose, 7 of them new (`cl-brazier.lua:278`, `cl-hearth.lua:298`,
`cl-mass-driver.lua:290`, `cl-slag-generator.lua:262`, `cl-tuned-furnace.lua:257`,
`cl-waste-heat-smelter.lua:162`, `:176`). `fh test component-lab` therefore never exits 0, and a real
regression shows up only as "10 failed instead of 9".

The pass is not even consistent with itself. `cl-rotating-chest` (3 KNOWN-LIMITs) and
`cl-creep-collector` assert the limit and pass, which is what M9 asked for.

**Fix.** Rewrite the seven to assert the limited behaviour and pass. A change to the limit then fails.

### M5. The creep collector's spoils door is outside the machine, so a normally placed inserter never gets spoils

`prototypes/entities/cl-creep-collector.lua:14`: `proxy_offset = {2, 0}`, a tile **outside** the 3x3
footprint. The proxy has an empty collision mask and no selection box.

**What fails.**
- An output inserter placed against the east face sits **on** the door tile. Its pickup tile `{1, 0}`
  is inside the shell, and the README's measured fact says an inserter there targets the process shell.
  The shell has no products, so the inserter waits for ever. Spoils only come out through an inserter at
  `{3, 0}`, one tile away, which nobody would guess. (Inferred from the README probe; not re-probed.)
- Anything the player builds on that tile (a chest, a belt end, another machine's inserter) overlaps an
  invisible door.

The suite proves only the `{3, 0}` placement (`cl-creep-collector.lua:80`). It also checks the pickup
tile with `find_entities_filtered{position = ...}` instead of `inserter.pickup_target`, so it never shows
which entity the inserter actually takes from.

**Fix.** Assert `ins.pickup_target` for an inserter at `{2, 0}` and at `{3, 0}`, and record the
`{2, 0}` result as a KNOWN-LIMIT. Or give the process shell `no-automated-item-removal` (it has no
products, so nothing is lost) and move the door inside, as the passive shell does.

### M6. Tests that pass without proving what their names claim

- `cl-creep-collector.lua:294` "the Rampant poll cell harvests **at the same energy per unit**" asserts
  `harvested`, `targets` and `wood`. It never reads `poll_final.energy` or the poll network's source.
  The energy parity the name promises is untested.
- `cl-tuned-furnace.lua:109` "the speed floor follows effect_receiver.speed_limits" asserts
  `crafting_speed >= 0.2`. The engine's global -80% floor gives exactly that with no `speed_limits` at
  all. Use a `low` limit other than -0.8 (e.g. -0.5) and assert 0.5.
- `cl-creep-collector.lua:260` asserts `final.updatable == mid.updatable`. That holds whatever the value
  is. TEST-ENTITIES-2 asked to "assert what the shell reports": assert the value.
- `cl-rotating-chest.lua:318` "contents are not on the circuit network" never wires the shell or reads a
  signal. It checks a control-behaviour type and a prototype flag.
- `cl-brazier.lua:345`, `cl-hearth.lua:377`, `cl-rotating-chest.lua:353` ("re-arm the fixture") assert
  nothing about the entity. They destroy and rebuild fixtures mid-suite, which is the side effect that
  already broke integration once (STATUS, `game.speed` re-arm). They belong in a harness hook, not in
  the pass count.
- The brazier and hearth transition tests read `rec.data.power_log` and the library `event_log`. Both
  are written at raise time, not by an actual subscriber. Only the cold-box H2 test subscribes from
  another mod. A queued raise that `Record.batch` drops (machine gone) still appears in `event_log`.

---

## LOW

### L1. New polls are not phased, so equal machines built together poll on one tick

`cl-brazier.lua:208,212`, `cl-hearth.lua:173,218,221`, `cl-creep-collector.lua:79-101,117` and
`cl-slag-generator.lua:45,70` use `rec:schedule(n)`. Only `cl-tuned-furnace` uses `schedule_phase`, the
SPEC 3.4 helper the first pass added for exactly this.

**What fails.** A bench build places all 2000 cells in one `/sc` tick, so 2000 hearths land in one
bucket every 20 ticks. The same goes for any blueprint pasted by a player. The mean in `report.py` is
unaffected. The per-tick maximum and the "only the current bucket" cost are not what a native S3
(spread by its own wake times) would show.

### L2. A bound signal permanently overwrites the configured `rate`

`cl-tuned-furnace.lua:20`: `if signal > 0 then rec:set_setting("rate", signal) end`.

**What fails.** After the wire is removed or the signal drops to 0, the furnace keeps the last signal
value as its configured rate. A blueprint or copy-paste taken afterwards carries the circuit value, not
the player's setting. The comment cites the inserter's stack-size override, which does **not** overwrite
the configured stack size. V2-PARTS 1.3 says "writes the setting", so the spec is ambiguous here. The
emulation picks the reading that leaks circuit state into blueprints. `cl-tuned-furnace.lua:230` only
checks a unit that was never wired.

### L3. The creep collector reserves no target; a clone chases the source's tree

`cl-creep-collector.lua:93` stores the target in `rec.data`. Two collectors in range of one tree both
start a cycle on it. Both pay 800 kJ, and the second finds it gone (`finish`, `:105-110`). On clone,
`lifecycle.lua:171` deep-copies `rec.data`, so source and copy chase the same tree, and the suite asserts
that as correct (`cl-creep-collector.lua:183`, "target cloned"). The native type leaves "which target" to
the mod, but this script is the reference handler the bench measures. A per-surface reservation table
would make it honest.

### L4. The waste-heat smelter departs from its own spec in two places

- `prototypes/entities/cl-waste-heat-smelter.lua:15` carries the heat product as
  `emulation.heat_product`, although the library now supports `process.products` entries of
  `type = "heat"`. So `rec:spec().process.products` has no heat product, unlike the spec's proposed API.
- `:21` declares `direction_count = 4`, which TEST-ENTITIES-2 section 6 does not. That declaration is
  what makes the shell rotatable, and both deliberate failures (`cl-waste-heat-smelter.lua:162,176`)
  follow from it. Without it the shell has no fluid box and cannot rotate, matching the spec.

### L5. Fuel requests in blueprints are inconsistent

The brazier carries a fuel request (`cl-brazier.lua:214-229`). Its plan is the current stack count, so a
blueprint of a full brazier asks robots for 50 coal on every copy. The hearth carries none, although it
has the same hidden reactor. Lift the fuel-request helper (STATUS "Library candidates") or drop it from
both.

### L6. Rotating chest: the second native comparison is still missing

TEST-ENTITIES-2 section 4 names `assembling-machine-2` idle with no recipe as the shell-on-its-own
column. STATUS says it has no cell. Gap 35 (the shell is updatable) is therefore unmeasured on its own.

---

## Library changes in this pass: checked, no defect found

- `rotatable()` (connectionless fluid box), `component.CLEAR`, the passive shell
  (`no-automated-item-*` flags), `recipe_results` dropping energy and heat products, `eei_producer`,
  `heat_interface`, the `fuel_proxy_offset` part with `link()` targeting `defines.inventory.fuel`,
  `proxy_offsets` keys, `Record:has_fuel/read_signal/add_output_energy/add_heat`, remote `rotate`,
  `scheduler.dispatch_records`, the deferred `fixtures.hold_until`.
- `lifecycle.rotated` heals before teleporting, so a part removed between rotate and handler is rebuilt
  first.
- Clone, cross-surface clone, `script_raised_revive`, robot and platform build: every new entity goes
  through `materialise`/`cloned`. The slag generator and tuned furnace suites clone to a second surface.
  The rotating chest clone keeps facing, doors, bar and contents.
- Mining: the brazier's and hearth's reactor fuel and burnt result go to the buffer through
  `hidden_inventories`. The storehouse's 240 slots go to the buffer, and overflow is spilled.
- Blueprint, deconstruction and upgrade exclusion: every new part (generator EEI, heat interface, fuel
  door, 14 storehouse doors) is built by `hidden.entity` with the full hidden flag set. Cores clear
  `fast_replaceable_group`/`next_upgrade`, including the deep-copied `assembling-machine-2` storehouse.
- Save/load and determinism: storage holds only plain data, LuaEntity references, render object ids and
  registered Record metatables. The module-level caches (`burn_per_tick` in the hearth,
  `cycle_energy_cache` in the slag generator, `heat_joules` in the smelter) are pure functions of
  prototypes, so they agree on every peer. No `math.random`, `os` or `io`. The rotating chest's
  `reverting` flag is set and cleared within one call.
- on_tick: still only `due[tick]`. The per-tick fixture watchers (mass driver 720 ticks, slag
  generator until its tenth cycle) end on their own.
- Parts per TEST-ENTITIES-2: each entity uses the core and parts its section names. The deviations are
  documented in the prototype files: hearth, slag, tuned and smelter inventories are the shell's own
  slots; the mass driver draws 4 MW at an 8 MW input limit and fires an inert slug; the rotating chest
  rebuilds instead of rotating in place. The exceptions are L4 and L6.
