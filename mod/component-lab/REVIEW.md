# component-lab adversarial review (2026-11-02)

Scope: `lib/`, `scripts/` (runtime, lifecycle, scheduler, record, status, gui, fixtures, defs), every entity
script and prototype, and the suites in `ai-harness/suites/component-lab/`. Checked against SPEC.md and
TEST-ENTITIES.md.

Baseline: the full suite run from a private workspace (`component/mod/ws/review`, RCON 27200-27209) gave
**146 passed, 2 failed**. Both failures are the declared KNOWN-LIMIT tests (dig-site food pickup, rotated
fluid-chest blueprint). Every finding marked **confirmed** below was reproduced on a live 2.1.24 server
with the probe shown. Two of the probes crash the server, which is the finding. Re-run them with
`fh test component-lab --keep --filter zz:` and then `fh rcon --project component-lab file probe.lua`.

Line numbers are per file.

---

## HIGH

### H1. A hidden part that dies or is destroyed crashes the game on the next scheduled tick (confirmed)

- `scripts/lifecycle.lua:77-86` `create_part` leaves every part `destructible` (probe: `eei.destructible == true`).
- `scripts/runtime.lua:176-183` `dispatch` checks only `rec.entity.valid`, not the parts.
- `scripts/record.lua:47-49` `energy_entity()` returns `parts["energy:energy"]` even when it is invalid.
  `Record:inventory` (`record.lua:37-44`) returns nil for a dead inventory part, and every entity script
  dereferences that result unguarded.
- Only the core is registered with `register_on_object_destroyed`, and `on_entity_died` is filtered to core
  names (`runtime.lua:277`). Nothing notices that a part is gone.

**What fails.** The record keeps a dead part. The next `on_tick` handler indexes it, and the game stops
with "non-recoverable error". In the cold-box probe the crash came at `cl-cold-box.lua:56`
(`rec:energy_entity().disabled_by_script = empty`). The same thing happens with any script or editor
mass-delete, `die()` from another mod, or `/editor` removal of entities in an area.

Grenade splash does **not** reach the parts: ten grenades left all five cl-libtest parts at 1000 HP while a
wooden chest beside them died. Combat is therefore not the trigger. Script deaths are, and they are common
in modded saves.

```lua
local s = game.surfaces.nauvis
local core = s.create_entity{name="cl-cold-box", position={5000.5,5000.5}, force="player", raise_built=true}
core.get_inventory(defines.inventory.chest).insert{name="raw-fish", count=5}
remote.call("component_lab","parts",core.unit_number)["energy:energy"].damage(5000, "enemy")
-- within 60 ticks: server exits, cl-cold-box.lua:56 "LuaEntity API call when LuaEntity was invalid"
```

**Fix.** Set `entity.destructible = false` in `create_part` and in the clone path. Register parts with
`register_on_object_destroyed` too, and on a part's destruction either rebuild it from the def or tear the
whole machine down. Make `Record:part`, `energy_entity` and `inventory` return nil for invalid parts, and
have `dispatch` skip (or heal) a record with a missing part.

### H2. Handlers keep using the entity after `rec:raise(...)`, so a subscriber that removes the machine crashes the game (confirmed)

`script.raise_event` runs other mods' handlers synchronously. Several call sites go on touching
`rec.entity` or its inventories after raising:

- `scripts/entities/cl-timed-converter.lua:110-111`: `poll` raises `inventory_changed`, then `try_start`
  reads `rec.entity.disabled_by_script` (line 44).
- `scripts/runtime.lua:196-199`: `on_crafted` raises `cycle_finished`, then calls `h.on_cycle_finished`.
  dig-site's `dig()` and the converter's `finish()` then index the dead shell and inventories.
- `scripts/entities/cl-cold-box.lua:63-65`: raises `power_state_changed`, then `credit_inventory(inv, ...)`.
- (`record.lua` `start_cycle` and dig-site's `try_start` are safe only because `status.apply` checks
  validity.)

Removing a machine in response to its own event is a realistic pattern: "remove the derrick when
depletion hits N", or a recycler that mines finished machines.

```lua
local id = remote.call("component_lab","event_ids")["cl-timed-converter"].inventory_changed
script.on_event(id, function(e) if e.entity.valid then e.entity.destroy{raise_destroy=true} end end)
local c = game.surfaces.nauvis.create_entity{name="cl-timed-converter", position={6080.5,6000.5}, force="player", raise_built=true}
c.burner.inventory.insert{name="coal", count=5}
remote.call("component_lab","call",c.unit_number,"inventory","input").insert{name="iron-ore", count=1}
-- next tick: crash at cl-timed-converter.lua:44 via scheduler on_tick
```

**Fix.** Make `Record:raise` return `self:valid()`, and make every caller return early when it is false.
`dispatch` and `on_crafted` should re-check `rec.entity.valid` (and that `storage.cl.records[unit]` is
still `rec`) after each raise and before calling the next handler.

---

## MEDIUM

### M1. Teleporting a core leaves all its parts behind (confirmed)

`runtime.lua:249-293` subscribes to no teleport event, and a plain `LuaEntity.teleport` raises nothing.
Probe: `cl-libtest.teleport({+10, 0})` returns true and the core moves to x=5020.5. The proxy and tank stay
at x=5010.5. Inserters at the old spot keep feeding the moved machine through the stale proxy, and the tank
connects to pipes at the old spot. Cross-surface teleport is refused by the engine for these core types, so
this is a same-surface bug only. It matters for Picker Dollies, Factorissimo-style movers and
script_raised_teleported users.

**Fix.** Listen to `script_raised_teleported` and re-place parts (`part.teleport(part_position(core, part))`).
For silent teleports, use a cheap position check in the record's own poll, or accept and document the gap.

### M2. Force and quality are not propagated to parts (confirmed)

- `lifecycle.lua:77-86` creates parts without `quality`. Probe: a legendary cl-timed-converter has
  `inventory:input` at quality normal. SPEC's per-inventory `quality_affects_size` is honoured for the
  native inventory only (`lib/component.lua` `core.quality_affects_inventory_size`). `lib/hidden.lua:51-67`
  never sets it for hidden containers, and the parts are normal quality anyway.
- Changing `core.force` (capture, script, PvP scenarios) leaves parts on the old force. Probe:
  `core_force = review-other, proxy_force = player`. Inserters of the new force then cannot use the
  proxies. `on_forces_merged` is fine because the engine moves every entity.

**Fix.** Pass `quality = core.quality` in `create_part`, and set `quality_affects_inventory_size` on hidden
containers from the inventory spec. Re-sync `part.force` whenever a record is touched with a mismatched
force, or listen for `on_entity_changed_force` if it is used.

### M3. `lifecycle.mine` empties hidden inventories before `core.mine`, which can then fail (confirmed)

`lifecycle.lua:292-300` runs `move_out(rec, def, inventory, true)` first, then
`core.mine{inventory = inventory, raise_destroyed = true}`. `force` defaults to **false** (runtime-api:
"the mining operation fails when there isn't enough room"). The probe used cl-libtest with 8 distinct
stacks in the native chest, 5 steel in `extra`, and a 1-slot inventory. `mine` returned **false**, the core
is still standing, and `extra` is now empty: the steel went into the caller's inventory, and anything that
did not fit would have been spilled. A caller that retries with a bigger inventory, or destroys the scratch
inventory on failure, loses items.

**Fix.** Check room first (`inventory` free slots ≥ hidden stacks + native stacks + 1), or call
`core.mine{force = true}`. Alternatively, move the hidden contents only after `core.mine` succeeded, which
means doing it in the `script_raised_destroy` teardown with the inventory kept in a local upvalue.

### M4. `before_mine` runs on aborted mines; the cold box then raises a false `power_state_changed` and loses credit

`runtime.lua` maps `on_pre_player_mined_item` to `lifecycle.before_mine` (`lifecycle.lua:283-289`).
runtime-api says that event "is called even if the entity does not end up being removed", which happens
when a player mining a full chest cannot hold its contents. `cl-cold-box.lua:98-101` settles the stacks and
sets `data.powered = false`. At the next pass, `data.powered ~= powered` raises
`power_state_changed{powered = true}` with no preceding false, and the transition interval gets no credit.
The failed `lifecycle.mine` path from M3 does the same.

Repro (headless, through M3): put 16 distinct items in a powered cl-cold-box and call
`remote.call("component_lab","mine", core, game.create_inventory(1))`, which returns false. Turn the event
log on (`set_event_log(true)`). After the next pass, `event_log` holds one `power_state_changed` with
`powered=true` although the box never lost power.

**Fix.** Do the settlement in the `on_*_mined_entity` handler (buffer in hand, entity still valid), or
record a "settled at tick" marker instead of clobbering `powered`.

### M5. No record migration in `on_configuration_changed`

`runtime.lua:314-317` only runs `init_storage` and the fixture hooks. Two plausible changes then crash:

- A part is added to a prototype in a mod update (the dig-site trash inventory is the obvious next one).
  Existing records lack it, `rec:inventory("trash")` is nil, and the handler errors.
- A composed prototype is removed or renamed. Its records stay. If `on_object_destroyed` fires for the
  removed core, `lifecycle.teardown` reaches `move_out(rec, nil, ...)` → `hidden_inventories(rec, nil)`,
  which indexes `def.parts` on nil (`lifecycle.lua:262` has no nil guard).

**Fix.** On configuration change, walk `storage.cl.records`. Drop records whose name is no longer in
`defs.by_name`, destroying their valid parts. Materialise missing parts and destroy surplus ones by
comparing `rec.parts` against `def.parts`.

### M6. Test fixtures are built into every map, destroying whatever is at their coordinates

Every entity script registers an `init_hook` (`cl-cold-box.lua:265`, `cl-dig-site.lua:254`,
`cl-fluid-chest.lua:140`, `cl-fuelled-chest.lua:138`, `cl-seep-derrick.lua:139`, `cl-signal-chest.lua:178`,
`cl-signal-endpoint.lua:203`, `cl-timed-converter.lua:304`, `_libtest.lua:41`). The hooks run from
`on_init` **and** `on_configuration_changed`. They `destroy()` every entity in fixed areas: cold-box clears
enemies over 232x192 tiles at (-1600,-1600), dig-site clears 32x32 pads at y=-400, the converter clears
88x24 tiles at (2000,-640). `fixtures.hold_until` also sets `game.speed = 1000`.

Consequences:
- Adding the mod to any existing save wipes builds at those coordinates.
- Every bench save made with `make_save.py` (which boots this mod) carries about 40 fixture machines on
  nauvis that keep polling at 10/30/60/61-tick intervals. Emulation benchmark cells then measure fixture
  cost as well as the cell's own.

**Fix.** Arm fixtures only on request: a remote `arm_fixtures` the harness calls, a map setting, or a
dedicated `cl-fixtures` surface created on demand. Never arm them from `on_configuration_changed`.

### M7. The mining tests never touch the event-buffer path; the lifecycle tests miss TEST-ENTITIES' build/mine paths

- Every mining test calls `cl("mine", ...)`, i.e. `lifecycle.mine`, which drains hidden inventories itself
  before `LuaEntity.mine`: `_lib.lua:97,113`, `cl-fluid-chest.lua:201`, `cl-dig-site.lua:321`,
  `cl-fuelled-chest.lua:156`, `cl-timed-converter.lua:172`, `cl-signal-chest.lua:179`,
  `cl-signal-endpoint.lua:123`, `cl-seep-derrick.lua:91`, `cl-cold-box.lua:283`.
  `lifecycle.teardown(..., "mined", event.buffer)` therefore has no test. My robot-deconstruction probe
  (roboport + 10 construction robots, `order_deconstruction` on cl-libtest and cl-fuelled-chest) shows it
  works today: storage chest got both items, 3 copper, 5 steel, 7 coal, nothing on the ground, no parts
  left. That is a probe, not a regression test.
- `cl-seep-derrick.lua:77` "ghost revive (robot path)" uses `ghost.revive{raise_revive=true}`, which is
  `script_raised_revive`, not `on_robot_built_entity`.
- TEST-ENTITIES "Lifecycle tests" asks for `player.build_from_cursor`, `player.mine_entity`, robot build,
  "`on_object_destroyed` once for the core" and "clone to a second surface" for every entity. Only the
  seep derrick clones to a second surface, and it has no hidden parts. Cross-surface `clone_area` of
  cl-libtest works (probed: one set of parts at the destination, contents and wire carried), but nothing
  asserts it.

**Fix.** Add a robot-deconstruct test and a robot-build test (roboport fixture armed at init, read later,
like the other real-tick fixtures). Add a cross-surface clone for one parts-heavy entity. If the harness
can attach a character, add a player mine through `on_player_mined_entity`.

### M8. The leftover check cannot see leaked parts

`zz-leftovers.lua` compares only record counts, accepts `after <= before`, and calls `site.clean()` first.
`_site.lua:29-37` `clear()` destroys **every** entity in each touched row, orphan parts included, before
anyone looks. A teardown that forgot a part, or a clone that left a duplicate, is erased by the cleaner and
the suite stays green.

**Fix.** In `clear()`, before destroying, count entities whose name is in `remote.call(CL, "parts")`'s part
set (or `defs.part_names` exposed over remote) and have no owner (`owner_of` nil). Fail the test that left
them. In zz, assert zero unowned part entities on every surface.

### M9. Two permanently failing KNOWN-LIMIT tests keep the suite from ever going green

`cl-dig-site.lua:243` and `cl-fluid-chest.lua:332` fail by design, so `fh test` exits non-zero on every
run. A real regression shows up only as "3 failed instead of 2". The cold-box suite already does this right:
its KNOWN GAP tests assert that the gap exists and pass.

**Fix.** Rewrite both as tests that assert the current limited behaviour, named KNOWN GAP, so the suite
exits 0 and any change to the limit is noticed.

---

## LOW

### L1. Death and undo ghosts lose settings, bars and extra tags

Blueprint tags exist only through `on_player_setup_blueprint`. A death ghost or undo ghost rebuilds with
defaults (documented for the seep derrick). For death this is fixable: `on_post_entity_died` carries
`ghost`, so `ghost.tags = {component_lab = lifecycle.blueprint_tags(rec)}` (snapshot taken in `on_died`
before teardown) restores them on revive.

### L2. `apply_tags` trusts blueprint data

`lifecycle.lua:102-113` copies `tags.settings` values without the type, min and max checks that `set_setting`
applies, and calls `inv.set_bar(bar)` with no range check (line 109). `cl-fluid-chest` `apply_tags` sets a
raw `direction`. Blueprint strings are user-editable, and an inventory that shrinks in an update makes old
blueprints out of range. A bad bar or direction errors inside the build event. Clamp, type-check, and
ignore bad values.

### L3. Cores created without a build event never get parts, and nothing heals them

Fixtures call `lifecycle.materialise` by hand because on_init events are not delivered. Other mods that
`create_entity` a core without `raise_built` (map editors, blueprint sandboxes, movers) leave a bare core:
no record, a GUI with no frame, and hidden inventories missing for good. A lazy `materialise` in
`on_gui_opened` (`runtime.lua` `on_gui_opened`, where `rec` is nil) or in `runtime.get` for cores would
cover most real cases.

### L4. Proxies sit only at the configured offsets; inserters elsewhere target the shell

dig-site and timed-converter put proxies at the left and right middle tiles
(`prototypes/entities/cl-dig-site.lua:47-48`, `cl-timed-converter.lua:30-32`). Probe: a fast-inserter
dropping from the west into the dig site's middle-left tile targets `cl-dig-site-proxy-food`. One dropping
from the north into the top-middle tile targets the `cl-dig-site` shell, which refuses fish, so the
inserter stalls holding it. A native type accepts on every edge.

The dig-site rigs also assign `ins.drop_target = proxy` / `pickup_target = proxy` explicitly
(`scripts/entities/cl-dig-site.lua:225`). The "inserter drops fish into food" tests therefore never prove
that a player-placed inserter finds the proxy. The timed-converter inserter test does prove natural
targeting.

### L5. Rotated or flipped blueprints of the fluid chest keep the tank's tagged direction

Already a known failing test. A partial fix for cursor builds: `on_pre_build` carries `direction` and
`flip_horizontal/vertical`, so the rotation can be stashed per player and applied in `apply_tags`. Robot
builds of a rotated blueprint stay wrong.

### L6. The converter's pending output is silently lost on orphaned teardown

`cl-timed-converter.lua:114-123` `return_pending` spills only when `rec.entity.valid`. In the "orphaned"
mode the core is already gone and the pending stack vanishes, although the library spills hidden inventories
at a part's position in that mode. Spill at the same anchor.

### L7. The fluid chest's rotate input accepts any distance

`cl-fluid-chest.lua` `on_rotate_input` checks force but not `player.can_reach_entity`. A player can rotate a
tank across the map with the cursor over it. This is cosmetic in a lab and matches nothing native.

---

## Checked and fine

- **Robot deconstruction** returns the core, native contents, hidden inventories and burner fuel to storage,
  with no parts left (probed, see M7).
- **Cross-surface `clone_area`**: engine copies of parts are destroyed and fresh clones adopted, leaving
  exactly one set at the destination with contents and wire intact (probed). The `cloning_parts` guard works
  because `LuaEntity.clone` raises `on_entity_cloned` instantly (runtime-api `timeframe: instantly`).
- **Blueprint, deconstruction, upgrade and copy-paste exclusion**: parts carry `not-blueprintable`,
  `not-deconstructable`, `not-upgradable`, `no-copy-paste` and `not-selectable-in-game`; a blueprint over
  a core holds one entity (tested).
- **Fast-replace and upgrade-planner**: cores clear `fast_replaceable_group` and `next_upgrade`, so neither
  path can swap a core and strand parts. Assembler cores without fluid boxes refuse `rotate()` (probed:
  returns false), so proxy offsets cannot go stale through rotation.
- **Save/load**: `storage` holds only plain tables, LuaEntity references and the registered `Record`
  metatable. Records are keyed by `unit_number`, not by LuaEntity. `on_load` re-arms `on_tick` from
  `storage.cl.due` alone, so the conditional registration agrees across peers.
- **Determinism**: no `math.random`, `os` or `io`. Event ids are generated in sorted-name order at load.
  Every `pairs` that feeds game state iterates storage tables, whose order Factorio keeps deterministic.
- **on_tick cost**: `scheduler.dispatch` touches only `due[tick]` and disarms when `due` is empty. Stale
  entries left by reschedules are skipped by the `next_due` check.
- **SPEC / TEST-ENTITIES parts**: each prototype materialises the parts its entry lists. The deliberate
  deviations are documented in the prototype files: dig-site has no trash inventory, and the timed converter
  uses `results = {}` instead of a token item, which TEST-ENTITIES allows.
