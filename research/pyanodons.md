# Pyanodons: catalogue of script-driven entities

Source: the highest version of each mod in the author's local mod library (the mod's zip from the portal): pyalienlife 3.1.8, pycoalprocessing 3.1.8,
pyindustry 3.1.6, pyalternativeenergy 3.2.11, pyrawores 3.1.4, pypetroleumhandling 3.1.5, pyfusionenergy 3.1.6,
pyhightech 3.1.5, pypostprocessing 3.1.7. Everything below comes from reading `control.lua`, `scripts/**` and the
matching prototypes. Nothing was run. pyfusionenergy has no control stage. pyrawores and pyhightech have only
wiki pages plus the per-tick dispatcher stub. pyindustry's script only resets tank rotation.

Part vocabulary used in the "replacement" column (from the proposed component entity):
**INV** = prototype-declared inventories (any count, filters, per-inventory role) · **ES** = energy source part
(electric / burner / fluid / void / *custom-curve*) · **FB** = fluid boxes · **PROG** = progress timer / work cycle ·
**MOD** = module slots / intrinsic effects · **CC** = circuit connector · **EV** = per-prototype opt-in events
(e.g. `on_cycle_finished`, `on_inventory_changed`, `on_status_changed`, `on_fluid_threshold`) · **COND** = engine-evaluated
enable condition (daylight, fluid present, inventory not empty) feeding the entity's status/diode.

---

## 1. How pypostprocessing's tick dispatcher works

Files: `pypostprocessing/control.lua` (the central scheduler) and `pypostprocessing/lib/events.lua` (the library
every pY mod `require`s).

* `py.on_event` collects handlers into a local table. `py.finalize_events()` folds each event's handlers into one
  closure and does the real `script.on_event` / `script.on_nth_tick` registrations once. Raw
  `script.on_nth_tick` is frowned on (the metatable on `py.mod_nth_tick_funcs` errors on direct assignment).
* `py.register_on_nth_tick(N, name, mod, fn)` records `{tick=N, mod=mod}` in a mod-local `function_list`. On the
  **first on_tick** of a session each mod does `remote.call("on_nth_tick","add", function_list)`.
  pypostprocessing stores the result in `py.nth_tick_funcs` and accumulates `py.nth_tick_total += 2 * sum(1/N)`.
* Scheduling state is `storage.nth_tick_order[tick] = { {func, delay}, ... }`, seeded at
  `ceil(game.tick/N)*N` the first time a mod queries.
* **Every tick, every pY mod that has functions** (pyal, pyae, pycp, pyph, plus the empty stubs in pyro and pyht)
  calls `remote.call("on_nth_tick","query", mod, tick)`. That is **6 cross-mod remote calls per tick**, each
  returning a copied Lua table. The first query of a tick computes the whole tick for every mod and caches it
  in `query_funcs` (keyed by `check_tick`). The others return their slice.
* Per tick it runs **at most `ceil(nth_tick_total)` functions**. With the current registrations the total is
  2 x 0.504, which is about 1.008, so the cap is **2 nth-tick functions per tick across all pY mods**. Any function
  over the cap is pushed to tick+1 and its `delay` is recorded. The next occurrence is then scheduled at
  `tick + N - delay`, so the long-run period stays N. N is therefore a *period*, not a `tick % N` phase.
  The point is to keep the heavy batch functions from landing on the same tick.
* Each function that runs is a **batch over every instance of its kind**. Two exceptions spread the work:
  Farming121 does 1/8 of the farms per call, and wind updates at most 101 turbines per call. All other loops
  touch every registered entity in one go. Per-tick cost is low, but each function spikes in proportion to the
  number of instances.
* `py.delayed_event(delay, name, params)` is a separate one-shot timer mechanism, stored in
  `storage.on_tick[tick]` and pcall'd. Every mod that uses the lib checks it each tick.
* Other per-tick overhead from the **library itself, in each of the ~8 mods that require it** (pypp, pyal, pyae,
  pycp, pyph, pyro, pyht, pyindustry):
  * the `events.lua` on_tick: loops `storage.ignored_players` and checks `storage.on_tick[tick]`;
  * the `alerts.lua` on_tick: **`pairs()` over every stored custom alert every tick**, re-raising the ones whose
    `offset == tick % 600`. This is O(alerts) per tick per mod. pyal registers an alert for every farm with an
    empty module slot, and pycp registers one for every machine with beacon interference;
  * the `lib.lua` on_tick: a one-time global-message check that still runs every tick.
* There is a generic compound-entity framework in `pypostprocessing/lib/compound-entities.lua`
  (`py.compound_attach_entity_to`: a data-stage attach list carried through `mod-data`, plus control-stage
  child/parent maps, GUI hooks and build/destroy cleanup). **None of the nine mods uses it.** Every compound
  entity below is hand-rolled.

### Registered nth-tick functions (N = period)

| Mod | Name | N | What it iterates |
|---|---|---|---|
| pyal | update-guis | 7 | connected players with an open dig-site/bioport GUI |
| pyal | Oculua43 | 43 | every active ocula (chart tag redraw) |
| pyal | Vatbrain | 41 | every vat-brain |
| pyal | update-caravans | 60 | every caravan |
| pyal | Digosaurus | 61 | every dig site |
| pyal | Farming121 | 121 | 1/8 of all farms per call (each farm about every 968 ticks) |
| pyal | update-biofluid | 143 | every bioport + every requester (+ provider sort) |
| pyal | Oculua221 | 221 | connected players (logistic requests) + every ipod |
| pyal | update-mounts | 239 | every mount vehicle |
| pyal | update-ulric-man | 397 | transformed players |
| pyal | bhoddos-turd-update | 423 | every bhoddos culture (only if that TURD path is chosen) |
| pyae | aerial9 | 9 | players with an aerial GUI open |
| pyae | thermosolar | 55 | every lrf-panel + stirling concentrator |
| pyae | heliostat | 60 | every solar tower |
| pyae | sut | 60 | every solar updraft tower |
| pyae | wind | 61 | planets, plus up to 101 turbines (animation direction) |
| pyae | tidal | 83 | planets only |
| pyae | aerial117 | 117 | every aerial base |
| pyae | aerial301 | 301 | network refresh flag |
| pyae | aerialfuckinghuge | 216001 | sets refresh flag |
| pycp | pond153 / pond154 | 153 / 154 | every tailings pond / pending pollution tiles |
| pycp | wiki | 60 | statistics GUI |
| pycp | generator-equipment-autofill | 251 | connected players |
| pyph | drills | 67 | every oil/tar/gas derrick on a bitumen seep |

Raw `on_tick` handlers outside the dispatcher: pyal slaughterhouse recipe GUI (per player watching a machine,
polling `get_recipe()` to detect "recipe cleared"); bhoddos and the 2.1.11 migration use
`script.on_nth_tick(game.tick+120, ...)` as a **one-shot timer** and unregister themselves.

---

## 2. Entity catalogue

Columns: core engine type, and why it was chosen · hidden parts · behaviour emulated · tick strategy ·
per-instance work per run · proposed replacement.

### pyalienlife

**Dino dig site (`dino-dig-site`) + digosaurs**: `scripts/digosaurus/digosaurus.lua`
* Core: `assembling-machine` with `fixed_recipe = "digosaurus-hidden-recipe"` and 4 `module_slots`. It is
  **permanently `disabled_by_script = true`**. The type was chosen only for the shell: electric energy source
  and buffer, a module inventory (reused as **creature slots**, `get_module_inventory()`), the crafter_output
  inventory (reused as the **ore output**), crafter_trash (where non-food gets dumped), a relative GUI, and the
  `products_finished` counter.
* Hidden: `dino-dig-site-food-input` (`container`, 2 slots, collision mask empty) for food. Per trip: one
  `unit` digosaur plus one `digosaurus-mineable-proxy` (`simple-entity`) as the attack target.
* Behaviour: a creature-based miner. It scans the ores in range on build. Each cycle it eats one food item, sends
  a unit to a random ore, and on return inserts ore (scaled by food value and creature bonus), depletes the
  resource and updates production stats.
* Tick: N=61 batch over every site, plus `on_ai_command_completed` per unit leg (2 per trip).
* Per instance per run: validity loop over the module slots, `food_inventory.get_contents()`, a scan of the
  food slots for non-food, energy checks, a `draw_error_sprite` render object (TTL 61) whenever idle, and
  `get_item_count()` on the output. When dispatching: `find_random_scanned_ore` first does an **O(#ores) scan to
  find max_index**, then random probing. It also creates 2 entities per trip and writes stats.
* Replace with: INV (food, creature, output, trash as declared inventories), ES electric, PROG (trip timer
  instead of real units, or keep units as optional visuals), MOD (creature slots as a typed slot inventory),
  EV `on_cycle_finished`, which yields ore. COND for no-food / no-creature / no-ore, so the engine status
  replaces the render sprites.

**Bioport / provider-tank / requester-tank / vessel (Biofluid network)**: `scripts/biofluid/biofluid.lua`
* Core: bioport = `assembling-machine` (fixed hidden recipe, void energy, 1 module slot, `disabled_by_script`),
  used for its **input inventory** (robots + food), **output inventory** (guano), module effects (consumption)
  and GUI. Provider/requester tanks = **`furnace`** with void energy, zero item inventories, a 100k fluid box
  plus a 1-unit fluid box, `disabled_by_script`. The furnace type is used only because it gives a fluid box,
  `custom_status` and a crafting GUI. Vessels are pipes / pipe-to-ground (biofluid-only fluid boxes).
  `custom_status` is forced to a green "Working".
* Hidden: `unit` creatures (gobachov/huzu/chorkok) as flying couriers. They carry fluid in Lua state, not in an
  entity.
* Behaviour: a logistics network for fluids. Requesters are filled to a set amount (with temperature conditions
  and priority) from providers, through couriers that eat food and produce guano.
* Tick: N=143 batch, `on_ai_command_completed` per leg, and **`Biofluid.built_pipe()` rebuilds every network
  (O(all biofluid entities) plus `get_fluid_box_neighbours`) on every build of any biofluid entity**. It also
  works around a `get_fluid_segment_id` bug (forum t=120459 cited in source; falls back to `math.random`).
* Per run: `render_error_icons` over every bioport (status function + sprite), a scan of every requester for
  unfulfilled requests, then **per request**: building `providers_by_contents` (`get_fluid` per provider), a
  `table.sort` of providers whose comparator calls `get_fluid` twice per comparison (O(P log P) API calls),
  `order_by_distance` sorting every bioport by distance (another sort per request), and `inventory.remove`
  / `create_entity` / `set_command` per dispatch. Pickup and dropoff do `set_fluid` on both tanks.
* Replace with: FB with a network id part, INV, ES burner (food as fuel, with module consumption effect),
  EV `on_fluid_below_threshold` for requesters (push model instead of polling), PROG for courier trips.
  An engine "fluid logistic" part is the big win but is out of scope. Even FB + EV removes the polling.

**Caravans (caravan, flyavan, fluidavan, nukavan) + outposts**: `scripts/caravan/**`
* Core: `unit` (chosen for pathfinding and commands). Outposts are `container` / `storage-tank`.
* Hidden: **script inventories** (`game.create_inventory(size)`) for cargo and fuel, because units have none.
  The fuel "burner" is the Lua `fuel_bar` counter (`eat()` in impl/control.lua).
* Behaviour: a train-like schedule with actions and interrupts (load/unload, wait for item counts, circuit
  conditions) and food as fuel. The GUI is fully custom.
* Tick: N=60 batch over every caravan (table.sort of the queue when invalidated), plus `on_ai_command_completed`.
* Per run: validity, fuel check plus error sprite, one action evaluation (inventory transfers and counts), and
  a repath when distance > sqrt(1000).
* Replace with: INV and ES burner on a unit-like core (the main ask: **units cannot have inventories or energy
  sources**), EV `on_command_completed` is already present. A schedule part is not part of this proposal.

**ipod + ocula**: `scripts/ocula/ocula.lua`
* Core: ipod = `container` (filtered to ocula). ocula = `unit`.
* Hidden: per-ocula script inventory (1 slot), a chart tag, a beam entity, and alt-mode render objects.
* Behaviour: personal logistics outside roboport coverage. Couriers fetch requested items from a logistic network.
* Tick: N=221 per connected player (walks every requester section and filter, iterates **every construction
  robot in the network per filter**) plus per ipod status sprites. N=43 **destroys and recreates a chart tag for
  every active ocula**.
* Replace with: INV on a unit core, EV. Mostly per-player cost, not per instance.

**Vat brain (`vat-brain`)**: `scripts/vatbrain/vatbrain.lua`
* Core: `assembling-machine`. Hidden: `hidden-beacon-vatbrain` (`beacon`, void energy).
* Behaviour: projects a beacon effect whose tier depends on the current recipe, and only while the machine is
  working.
* Tick: N=41 batch. Per instance: `get_recipe()`, `status`, toggling `disabled_by_script` on the beacon, and a
  module swap when the tier changes.
* Replace with: MOD (an *emitted* effect part: "while working, broadcast effect X chosen by recipe") plus EV
  `on_recipe_changed` / `on_status_changed`.

**Farms (every animal/plant/fungus farm, ~45 base names x mk01-04 + TURD variants)**: `scripts/farming/farming.lua`
* Core: `assembling-machine` (vanilla). The script only enforces "needs a module".
* Behaviour: status "requires module X" plus a custom alert when the module inventory is empty.
* Tick: N=121, 1/8 batch (each farm about every 968 ticks): `get_module_inventory().is_empty()` plus a
  `custom_status` write. Hidden cost: each module-less farm sits in `storage.alerts`, which **the alerts
  on_tick walks every tick**.
* Replace with: COND "module inventory not empty" as an engine status (a required-slot flag), no Lua.
  Very high instance counts in late pY saves make this a good benchmark target.

**TURD hidden beacons**: `scripts/turd/turd.lua`
* Core: any upgraded machine. Hidden: `hidden-beacon-turd` (`beacon`, void, non-destructible, non-operable)
  created **per machine** to apply the tech-tree bonus as a module effect.
* Tick: none (research events, build/destroy). Cost is engine-side: one beacon entity per upgraded machine
  (memory, beacon/receiver links, effect recalculation) and on research changes a full machine sweep.
* Replace with: MOD as an intrinsic per-entity effect (an `effect_receiver.base_effect` settable per instance
  or per force/recipe at runtime). No hidden entity.

**Bhoddos culture (TURD path 1)**: `scripts/turd/bhoddos.lua`. `assembling-machine`. N=423 per culture:
`crafting_progress` read plus RNG, occasionally spawns an atomic rocket. A one-shot `on_nth_tick(future)` makes
the entity destructible again. Replace with EV `on_cycle_started/finished` with a random effect (or a
trigger-effect on craft).

**Mounts (crawdad, dingrido, phadaisus, spidertron)**: `scripts/mounts/mounts.lua`. `car` / `spider-vehicle`
with a forced `py-mount-generator` equipment. N=239: per equipment, move burner fuel into equipment energy by
hand. Replace with ES burner, so the vehicle's burner feeds its grid (a vehicle burner-to-grid link).

**Wyrmhole**: `linked-container` + `wyrmhole-skin` (`lamp`) as a visual layer. Event-only. Replace with a
graphics layer / working visualisation part.

**Mega farm**: `rocket-silo` (for launch-a-satellite = harvest). Event-only: places wood fences and landfill,
and on launch creates resource entities in a 23x23 area. Not a tick cost.

**Slaughterhouse and other "recipe picker" machines**: custom recipe GUI. Raw on_tick per player that has a
machine open, polling `get_recipe()`. Replace with EV `on_recipe_changed`.

**Ulric man**: `character` swap on a timer (N=397). Per player, not an entity part.

### pyalternativeenergy

**Aerial turbines (`aerial-blimp-mk01..04`) + aerial base**: `scripts/aerial.lua`
* Turbine core: `unit` (flies around). Hidden: **one `accumulator` per (electric network x turbine tier)**
  (`<name>-accumulator`), credited with energy proportional to distance flown.
* Base: `constant-combinator` (placed item, reads input signals) + `aerial-base-animation`
  (`electric-energy-interface`, for power draw/visual) + `aerial-base-chest` (`container`). That is three
  entities faking one machine with an inventory, an energy source and circuit I/O.
* Also tracks **every electric pole and power switch** (on_built) to size the airspace.
* Tick: `on_ai_command_completed` per flight leg (find_target, accumulate). N=117 per base: reads circuit
  signals, releases/stores turbines, sums accumulator energy, writes 10 combinator slots. N=301 network refresh.
* Replace with: INV + ES (electric) + CC (read/write signals) on one core, EV `on_circuit_changed`. The turbine
  generation is ES with a custom output curve fed by script.

**Wind turbines (hawt / vawt / multiblade)**
* Core: **`solar-panel` with `solar_coefficient_property = "py-wind-speed"`**. The engine already does the power.
  Hidden: `<name>-collision` (`simple-entity-with-force`) whose `created_effect` area trigger cancels placement
  too close to another turbine. Animated turbines are replaced by `-blank` plus a script-drawn animation per
  wind direction.
* Tick: N=61, global (one surface property write per planet), plus at most 101 turbines re-checking animation.
* This is the **success case**: one prototype parameter (`solar_coefficient_property`) removed the per-instance
  power loop. Cite it as a precedent for parts. What remains is a placement-spacing rule and orientation-driven
  graphics.

**Tidal (`tidal-mk01..04`)**: placer, then `simple-entity-with-owner` (visual) + hidden `<name>-solar`
(`solar-panel`, `solar_coefficient_property = "py-tide-height"`). Global tick only (N=83). Replace with
ES (solar-like curve) on the visible entity, removing the 2-entity split.

**Solar tower (`solar-tower-building`) + heliostats**: `scripts/thermosolar/heliostat.lua`
* Core: `boiler`. Heliostats: `simple-entity-with-owner` x 33 rotation variants (`solar-tower-panel0..`),
  **destroyed and recreated to rotate the sprite** toward the tower.
* Tick: N=60 per tower: `set_fluid(3, solar-concentration at daylight x efficiency temperature)`. The script is
  the fluid source.
* Replace with: ES or FB "generated fluid" part driven by a daylight curve, times a script-set efficiency
  multiplier.

**Solar updraft tower (`sut`)**: `electric-energy-interface`. Hidden: `sut-placement-distance`, plus one
`sut-panel-N` entity per glass tile (shine effect). N=60 per tower: writes `power_production` /
`electric_buffer_size` from daylight, `disabled_by_script` at night, and spawns a smoke entity. Replace with ES
electric output with a daylight curve and a script-set scale.

**LRF panel / stirling concentrator**: `boiler`. N=55: `disabled_by_script` and `custom_status` written for
**every panel every run** (even when unchanged), from the nauvis daylight (multi-surface TODO). Replace with
COND "requires daylight >= x" on the energy source.

**Microwave receiver**: `electric-energy-interface`, `power_production` set on build/launch. Event-only
(O(receivers) recalculation). Fine as is; the part would be ES with a script-set output.

### pycoalprocessing

**Tailings pond**: `scripts/tailings-pond.lua`. `storage-tank` (+ tank-rotation reset). N=153 per pond:
`get_fluid`, `get_fluid_capacity`, `get_fluid_segment_capacity`, gas venting (pollute), overflow to polluted
tiles, `set_fluid`, and a fill-level sprite re-render when the level changes. N=154 applies tiles and spawns
`ninja-tree`s. Replace with FB + EV `on_fluid_threshold` (full / above 99%), a fluid-void-with-pollution part,
and engine fill-level graphics (storage-tank already has fluid-level visualisation in some forms).

**AM/FM beacons (`beacon-AMx-FMy`, `diet-beacon-*`)**: `scripts/beacons.lua`. 25+25 beacon variants. The
frequency is encoded in the **entity name**, and changing it fast-replaces the entity. Receivers are disabled with
an alert on interference. Event-only. Replace with an instance setting on the beacon plus an engine exclusivity
rule. Not a tick cost.

**Programmable inserter**: `inserter` + `py-dynamic-inserter-target` (`proxy-container`) to target a specific
inventory. Event-only. Native 2.x `proxy-container` already covers it.

### pypetroleumhandling

**Oil derrick / tar extractor / natural gas derrick on bitumen seeps**: `scripts/bitumen.lua`
* Core: `mining-drill` (so it mines the seep resource). Hidden: `<name>-base` = **`assembling-machine` with
  `fixed_recipe = "drilling-fluids"`, void energy, `selection_box` 0, kept `disabled_by_script` forever**. It
  exists only to provide a **fluid input box** for drilling fluid, because the drill's own fluid box is already
  used for output.
* Behaviour: the drill runs only while drilling fluid >= 50 is present. Each cycle consumes 10 fluid and
  accumulates a bonus that sizes the patch created when the seep depletes (then explodes).
* Tick: N=67 batch. Per instance: validity, `get_fluid_contents()`, `extract_fluid`, a production-stats
  `on_flow`, writes to `disabled_by_script` / `custom_status`, and **a new `rendering.draw_text` object every run
  (TTL 68) per derrick**.
* Replace with: FB (second input box on the drill) consumed as a *requirement / fuel* (ES fluid-burner with a
  filter, or COND "fluid >= x" plus PROG consumption), and EV `on_cycle_finished` to accumulate the bonus.
  Removes one hidden assembler per derrick.

### pyindustry / pyrawores / pyhightech / pyfusionenergy
No script entities beyond tank rotation (event-only). pyro and pyht still pay the per-tick `remote.call` query
plus the lib on_tick overhead for nothing.

---

## 3. Ranking by expected per-instance UPS cost (highest first)

This ranking comes from reading the code. Per-run work is divided by N, and engine work forced by the emulation
(units, hidden entities, render objects) is counted. Benchmark against the pY saves to confirm.

1. **Biofluid (bioport / requester / provider)**: O(P log P) `get_fluid` in sort comparators plus a bioport
   distance sort *per unfulfilled request* every 143 ticks, a courier unit pathing per delivery, and an
   O(N) network rebuild on any biofluid build. It scales superlinearly with network size.
2. **Dino dig site**: N=61, about 10 API calls plus an inventory get_contents per site, an O(#ores) scan per
   dispatch, 2 entity creations and 2 AI callbacks per trip, and a unit pathing per active digosaur. Up to 4 units
   per site.
3. **Caravans**: N=60 per caravan with schedule/action evaluation and inventory transfers on script inventories,
   plus unit pathing.
4. **Aerial turbines + bases**: continuous unit flight with a Lua callback per leg. The base reads signals and
   writes 10 combinator slots every 117 ticks. Plus pole tracking on every pole build.
5. **Oil/tar/gas derricks on seeps**: N=67, a fluid read/extract, stats, 2 property writes and **1 new render
   object per derrick per run**, plus a hidden assembler entity each. Common in pY saves (dozens to hundreds).
6. **Tailings pond**: N=153, 3-4 fluid API calls and occasional tile work.
7. **Vat brain**: N=41 (frequent), 3-4 calls per instance plus a hidden beacon.
8. **LRF panel / stirling**: N=55, 2 unconditional property writes per instance. Can be numerous.
9. **Solar tower / SUT**: N=60, 1-3 writes per instance (few instances). The SUT spawns smoke each run.
10. **Ocula**: per-player cost (logistic section scan x construction robots) plus a chart-tag churn per ocula
    every 43 ticks.
11. **Farms**: per instance about 2 calls every ~968 ticks, **plus an O(alerts) per-tick walk** in the alerts
    lib for each module-less farm. Tiny per instance, but the count is the largest of any script entity.
12. **TURD hidden beacons**: zero Lua per tick, but one extra beacon entity per upgraded machine (engine
    memory/effect cost, cleanup sweeps on research). Counts can be in the hundreds or thousands.
13. **Mounts, bhoddos cultures, ulric**: long periods, few instances.
14. **Wind / tidal**: effectively zero per instance (engine `solar_coefficient_property`). Only global
    property writes and capped animation updates.
15. **Event-only**: microwave receiver, wyrmhole, mega farm, AM/FM beacons, programmable inserter, tank
    rotation.

Fixed overhead regardless of entity counts: 6 `remote.call` per tick (dispatcher queries), about 8 lib on_tick
handlers (each walks its mod's `storage.alerts` and `ignored_players`), and at most 2 batch functions per tick.

---

## 4. What this says about the proposed parts

* The most common hidden part is **"an assembling-machine used only as a shell"**: dig site, bioport, derrick
  base, and the furnace-as-tank for provider/requester. Each is permanently `disabled_by_script`. They want
  inventories, an energy source, fluid boxes, module slots and a GUI, **without a recipe**. This is exactly the
  proposed composable entity.
* The second is **"units can't hold things or burn fuel"** (caravan, ocula, biofluid couriers, aerial turbines).
  Script inventories and Lua fuel counters fill the gap. INV + ES (burner) on a moving core is the requested part.
* The third is **"script as an energy / fluid source with a custom curve"** (SUT, heliostat tower, microwave,
  aerial accumulators, lrf daylight gating). `solar_coefficient_property` already proved that a declarative
  coefficient removes the Lua loop (wind, tidal). An ES part with a property- or script-set multiplier
  generalises it.
* The fourth is **missing events**, which force polling: `on_recipe_changed` (slaughterhouse GUI, vatbrain),
  `on_status_changed` / `on_cycle_finished` (derrick bonus, dig site yield, bhoddos), fluid thresholds
  (tailings pond, requester tanks), and a **one-shot timer** (bhoddos and migration use
  `on_nth_tick(future)` hacks; pypp built `delayed_event`). That last one was requested on the forum as
  `script.once_at_tick`.
* **Intrinsic per-entity effects** (TURD, vatbrain) are currently a beacon entity per machine.

## 5. Candidate test-mod entities (pY-shaped)
1. "Dig site": a recipe-less core with INV(food, creature-slot, output) + ES electric + PROG + EV on_cycle_finished
   (no units). Compare against the pY dig-site loop.
2. "Seep derrick": a mining core with a second FB consumed per cycle (COND fluid>=50), no hidden assembler.
3. "Biofluid requester tank": FB + EV `on_fluid_below(threshold)`, replacing 143-tick polling.
4. "Caravan-lite": a unit core with INV + burner ES.
5. "Daylight boiler": a boiler with COND daylight (replaces the thermosolar 55-tick loop) and a "SUT" ES with a
   daylight curve times a script scale.
6. "Required-module farm": an assembler with COND "module slot non-empty" as an engine status (replaces
   Farming121 plus alerts).
7. "Intrinsic-effect machine": MOD base_effect settable at runtime (replaces the TURD/vatbrain hidden beacons).

## 6. Forum threads (search excerpts only; not fetched)
* "Modding Hackes", <https://forums.factorio.com/viewtopic.php?p=372666>: modding-interface request listing the
  hidden helper entities (lamps, radars, turrets) modders bolt on, asking for the attributes on the primary
  entity instead.
* `script.once_at_tick`, <https://forums.factorio.com/viewtopic.php?p=575195>: a one-shot timer request, matching
  the bhoddos / pypp `delayed_event` workarounds.
* "[2.0.16] get_fluid_segment_id does not work for assembling machines" (answered "not a bug"),
  <https://forums.factorio.com/viewtopic.php?p=635583>: related to the biofluid `get_fluid_segment_id` workaround
  (source cites t=120459).
* pY's own mod-portal report of a "hidden-beacon" locale leak and robots tripping over TURD hidden beacons,
  <https://mods.factorio.com/mod/pyalienlife/discussion/605b3f18ca01f0e1ac00c4fc>.
