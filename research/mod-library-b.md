# Mod library survey B: compound-entity patterns (mods n-z and 0-9, excluding py*)

Scope: mod zips in the author's local mod library (downloaded from the mod portal) starting with n-z or a digit
(case-insensitive), minus `py*` (78 unique mods once duplicate versions are collapsed), plus the in-scope source checkouts
(project-cybersyn, QualityForBiters, RoboticsFacility, SpidertronPatrols, visible-planets, PipeVisualizer-Updated, YARM).
Method: extracted every `*.lua` from the zips, grepped control-stage code for `create_entity`, `on_nth_tick`, `on_tick`,
`proxy-container`, `linked-container`, `electric-energy-interface`, `fixed_recipe`, `simple-entity-with-owner`,
`relative_gui_type`, then read the hits by hand. Graphics, reskin, sound, QoL-GUI and calculator mods (reskins-*,
space-exploration-graphics*, Vibrant_paint, RateCalculator*, StatsGui, Todo-List, TaskList, RecipeBook, Tapeline, etc.)
had no compound patterns and were skipped after the grep.

API ground truth checked against `runtime-api.json` and `prototype-api.json` (2.1.24) published at lua-api.factorio.com.

## Headline findings

1. **planet-muluna is the richest example in this half of the library.** It contains three compound-entity families
   (heat assembling machine, burner roboport, telescope) plus a generic 623-line `scripts/compound-entities.lua` whose only
   job is to put wires and control-behaviour settings back on hidden children after blueprinting, rotating and flipping.
   Across the five compound files that comes to 1,929 lines. Muluna also *invents a custom prototype type*: in data-final-fixes it
   turns any `assembling-machine` flagged `is_heat_assembling_machine = true` into an assembler + hidden `reactor` pair,
   moving `heat_buffer`, `heating_radius`, connection patches and so on from the assembler onto the reactor
   (`prototypes/custom-prototypes/final-fixes/heat-assembling-machine-final-fix.lua`). That is a "choose your parts at
   prototype load" entity built by hand in data stage, which is exactly what the proposal would provide.
2. **2.1 already ships one per-prototype opt-in event, and a mod moved to it right away.**
   `RecipePrototype::raise_on_crafted` -> `LuaRecipePrototype::on_crafted_event` ("Currently this is only raised when recipe is crafted by a
   crafting machine"). Muluna's burner roboport code says: "Pre 2.1.12, this function was used in a loop on every refueler
   with low energy ... Now, it's done on crafting of a recipe that consumes fuel" (`scripts/burner-roboports.lua`). So the
   "per-prototype opt-in event instead of a per-tick Lua hook" half of the proposal already exists in the engine, and
   a real mod deleted its polling loop the day it shipped. It is the only `raise_*`/`*_event` hook of its kind in the 2.1 API.
3. **0-things is a 23k-line, 920 KB library whose only purpose is compound-entity lifecycle.** It comes from the
   project-cybersyn org and depends on `base >= 2.1.12`. Its README promises to keep a Thing's identity through ghost, revive,
   death, undo and redo, to manage parent-child sub-entities with relative position and orientation "with full support for in-world and in-blueprint rotation
   and flipping", to carry custom tags through blueprints, and to fire synthetic custom events. The existence of this library is evidence
   of how much glue the compound pattern needs.
4. **Hidden constant combinators as circuit output is the most common single hack** (Cybersyn, Recursive Blueprints
   deployer and scanner, Verbose-Engineering rocket silo, Muluna telescope, Nanobots roboport interface, PowerPlusPowerMeter).
   The core entity type either has no circuit connector or has the wrong kind, so a hidden `constant-combinator` gets
   script-wired to it and Lua writes signals into it on a timer.
5. **Polling cost shows up everywhere.** spoilage-scanner walks *every* registered entity *every tick* and filters with
   a modulo, so the loop is O(N) per tick even when only N/interval entities do work. nixie-tubes, SpidertronPatrols and
   Cybersyn round-robin over their entity lists, and PowerPlusPowerMeter defaults to every tick. None of them can ask the engine to "wake me
   when X changes".
6. **Engine types used as timers.** Nanobots2 spawns a hidden `radar` (`roboport-interface-scanner`) and uses its
   `on_sector_scanned` as a powered, energy-gated periodic callback. Muluna uses a hidden assembler's recipe completion
   (`on_crafted_event`) as a fuel-consumption tick.
7. **Per-entity settings get smuggled through engine fields so they survive blueprint and copy-paste.** Cybersyn
   (project-cybersyn, upstream repository) stores its station mode in the arithmetic combinator's `operation` and its flags as bits in
   `second_constant`, then replaces the vanilla GUI (`player.opened = main_window -- replace the default entity UI`).

## Pattern table

| Mod | Entity | Core engine type | Hidden parts (type) | Behaviour emulated | Update strategy | Engine feature that would remove the hack |
|---|---|---|---|---|---|---|
| planet-muluna 2.9.8 | heat assembling machines, e.g. `muluna-vacuum-heating-tower` | `assembling-machine` (fixed_recipe `muluna-vacuum-heating`) | `reactor` "heat-assembling-machine-X-reactor" (fluid energy source fed via `add_fluid_box_linked_connection`, heat buffer, circuit connector copied), selection_priority 49 vs a shrunk assembler box | A crafting machine whose output is **heat** (recipe makes a proxy fluid that the reactor burns) | Event only (build/destroy), plus `on_nth_tick(30)` retrying pending wires after blueprint build | Heat-output part (heat buffer + connections) on a crafter; one entity with several parts, so selection, wires and blueprints just work |
| planet-muluna | burner roboports (`Muluna.constants.vacuum_roboports`) | `roboport` (electric, `input_flow_limit = "0W"`) | `assembling-machine` "refueler" with a **fluid energy source** (propellant fuel category) and a dummy recipe with `raise_on_crafted`; linked fluid box | Roboport powered by fluid fuel instead of electricity | Long `on_nth_tick` (about 1200 to 2400 ticks) checking energy below 60% to re-enable the refueler; `on_crafted_event` adds 0.1 MJ * fluid per craft to `roboport.energy`; `custom_status` mirrored onto both | Pluggable energy-source part on any entity (fluid/burner roboport); energy-threshold event in place of polling |
| planet-muluna | telescopes | `assembling-machine` (recipe set per surface, `recipe_locked`) | `constant-combinator` (asteroid signal output) | Machine that only works at night/day/low pollution and outputs signals | Periodic update over all telescopes (registered delayed function) toggling `disabled_by_script`, `custom_status`, warning sprite | Circuit-output part writable from script; "working condition" callback or environment condition evaluated by the engine |
| planet-muluna | `compound-entities.lua` (generic) | n/a | n/a | Restores child wires, control-behaviour fields (copied with `pcall` field by field) and orientation after blueprint, rotate and flip, through bplib extract/positions events | 30-tick retry loop with lifetimes of 10 min (wires) and 60 min (orientation) | Single entity, so blueprints carry everything natively |
| 0-things 0.6.7 | library ("Things") | any | parent-child sub-entities declared in mod-data | Identity through ghost, death, undo and redo; relative child placement; blueprint tags; entity graphs; synthetic events | "Non-polling" event-driven, but 23k LOC | Engine-owned composite entity with persistent identity and custom tags |
| PowerPlusPowerMeter 1.1.0 | `power-meter-usage-combinator` | `constant-combinator` | 3 generator/interface entities `power-meter-interface-p1/p2/p3` (one per usage priority, refilled with `void-energy` fluid each update) | Electric network load per priority tier as circuit signals | `on_tick` (default) or `on_nth_tick(setting)` over the registry; rewrites the combinator parameters | Electric-network statistics readable as a circuit-output part; per-priority energy probe |
| SpidertronPatrols 2.7.x (zip + source checkout) | `sp-spidertron-dock` | `proxy-container` (`proxy_target_entity` = spidertron, `proxy_target_inventory` = trunk) | none (render sprites for open/close animation) | Dock that links its inventory to a parked spidertron | `on_tick` round-robin with `for_n_of` over docks, 20 per tick, area search for spider-vehicles; separate `on_nth_tick(5)` patrol wait timers; relative GUI on `proxy_container_gui` and `spider_vehicle_gui` | Proximity/area-enter event part; scheduled timer part ("wake at tick T"); custom animation state |
| rec-blue-plus 1.5.2 (Recursive Blueprints) | `blueprint-deployer`, `blueprint-deployer2`, `recursive-blueprints-scanner` | `container` (deployer); scanner is a combinator-like entity | `recursive-blueprints-hidden-io` (constant combinator, script-wired to the main entity) | Chest that reads circuit commands and deploys blueprints; scanner that outputs area counts | `on_tick` drives Deployer, AreaScanner and Deployer2 every tick, reading circuit inputs | Circuit connector part on a container with script read/write; `on_circuit_signal_changed` opt-in event |
| Verbose-Engineering 1.3.2 | rocket silos (all of type `rocket-silo`) | `rocket-silo` (recipe locked, randomised letter recipes) | `number-silo-circuit-helper` (constant combinator wired on every connector) | Re-implements assembler circuit modes (read contents, ingredients, recipe-finished, working) for the silo, with a custom GUI | `on_tick`, tracks `players_currently_opened` | Shared circuit-read modes as a reusable part on any crafter |
| Nanobots2 3.3.2 | `roboport-interface-main` | `roboport` (energy zeroed on build) | `roboport-interface-cc` (constant combinator), `roboport-interface-scanner` (**radar used as a timer**) | Circuit-controlled roboport actions (chop trees, pick up items, deconstruct finished miners) | `on_sector_scanned` of the hidden radar triggers `run_interface`; children relinked by `find_entities_filtered` at the same position, ghosts revived by hand | Powered timer part ("every N ticks while powered"); circuit-input part on roboport |
| rigor-module 1.1.21 | every crafting machine accepting the `rigor` module category | crafting machines | none; uses **prototype explosion** (N entity variants and N recipe variants per rigor level) and swaps the entity with `create_entity{fast_replace=true}`, copying inventories and fluids by hand | Module with a custom effect that changes recipe results | `on_tick` over machines whose GUI is open plus a "waiting" queue (no module-inserted event) | Module-inventory-changed event; scriptable module effect; no need for prototype variants |
| spoilage-scanner 1.1.0 | spoilage scanner | `constant-combinator` | none (targets the adjacent entity) | Sensor that reads spoil percentage of the facing inventory | `on_tick` iterates **all** entities **every tick** with a per-entity modulo for update and rescan | Engine-scheduled per-entity update interval (staggered); circuit-output part with a reader |
| nixie-tubes 2.1.0 | nixie tubes (numeric/alpha) | `lamp` | rendering sprites (no hidden entity in the 2.x port) | Display circuit value as digits | `on_tick` round-robin across controllers and alphas, `get_signal` polling | Circuit-signal-changed event; signal-driven sprite variation |
| project-cybersyn (source checkout) | `cybersyn-combinator` | `arithmetic-combinator` | `cybersyn-combinator-output` (constant combinator, no collision, `not-blueprintable`), wired to the combinator output connectors with `wire_origin.script` | Station controller with custom modes; mode stored in `operation`, settings as bit flags in `second_constant`; vanilla GUI replaced | `on_nth_tick` at the configured tps for the dispatcher and manager | Custom per-entity settings blob carried by blueprint, copy-paste and undo; own GUI hook in place of `player.opened` replacement; circuit-output part |
| Updated_Construction_Drones 2.0.4 | construction drones | `unit` | per-drone proxy chest created at a fixed off-map `proxy_position` and used as the drone's inventory | Unit that carries items | `on_tick` plus `on_ai_command_completed` | Inventory part on a unit |
| PlanetsLib 2.4.0 | ground diggers (forked from Maraxsis, ported from Muluna) | `assembling-machine` (planet recipe assigned on build) placed from a mining-drill item via custom-input interception | none | Drill that "mines" without a resource tile, recipe per planet | Event driven (custom build inputs, ghost conversion) | Per-surface recipe binding at prototype level; placement redirection |
| SpidertronEnhancements 1.11.0 | dummy spidertron (stored while the player rides a vehicle/train) | `spider-vehicle` | dummy spider entity moved with the vehicle | Spidertron "inside" another vehicle | `on_tick` | Out of scope (vehicle nesting), noted only |
| sun_heat_and_cooling 1.3.11 | `sun_heat_cooler_1/2` | (cooler entity) | particle source + ground-cables decal entity | Cosmetic layers (smoke, ground patch) | Event only | Extra graphics layer / particle emitter part |
| se-space-trains 1.1.5 | `space-train-battery-charging-station` | `assembling-machine` with `fixed_recipe` (data-only) | none | Electricity-to-fuel charger (recharges battery fuel items) | none (recipe) | Data-only; not a compound entity, recorded as a fixed-recipe-as-converter idiom |

Not compound (checked and dismissed): WideChests (merges and splits containers by replacement), textplates, quick-adjustable-inserters
(transient selectable `simple-entity-with-owner` for UI), QualityForBiters (replaces enemies with quality variants),
YARM, visible-planets, PipeVisualizer, valves (migration only), SeaBlock (map-gen chest), underground-pipe-pack, squeak-through,
RitnLib (event dispatch library), stdlib2, trainsaver.

## Recurring parts, ranked by how many mods fake them

1. **Circuit output/IO part on an entity that lacks it**: Cybersyn, rec-blue-plus (x2), Verbose-Engineering, Muluna telescope,
   Nanobots2, PowerPlusPowerMeter, spoilage-scanner. That is 7 mods.
2. **Polling loops that wait for a state change**: spoilage-scanner, nixie-tubes, rec-blue-plus, SpidertronPatrols, rigor-module,
   PowerPlusPowerMeter, Muluna burner roboports and telescopes. Each needs a different trigger (circuit change, energy threshold,
   module change, proximity, timer).
3. **Alternative energy source on a fixed-energy type**: Muluna burner roboport (fluid), Muluna heat assembler (heat *output*),
   Nanobots (zeroes roboport energy).
4. **Timer**: Nanobots (radar sector scan), SpidertronPatrols (nth_tick wait timers), Muluna (recipe craft as tick).
5. **Inventory on a type without one**: Construction Drones (proxy chest per unit), SpidertronPatrols (proxy-container to a vehicle).
6. **Persistent custom settings through blueprint, copy-paste and undo**: Cybersyn (bit-packing into combinator params),
   Muluna (bplib tags + 623-line restore), 0-things (whole library).

## Candidate test entities for the component test mod

- **Heat assembler**: crafter whose parts are {item inventory in/out, electric or fluid energy source, heat-output buffer}.
  This mirrors Muluna's heating tower without the hidden reactor.
- **Fuel roboport / fuelled beacon**: roboport-like logistics part + fluid/burner energy-source part. Mirrors Muluna's burner roboport.
- **Power probe combinator**: circuit-output part + electric network probe. Mirrors PowerPlusPowerMeter.
- **Spoilage sensor**: circuit-output part whose reader is an adjacent-inventory spoil query, updated on a declared interval
  by the engine. Mirrors spoilage-scanner.
- **Circuit deployer chest**: container inventory + circuit IO part + opt-in `on_circuit_changed` event. Mirrors rec-blue-plus.
- **Powered timer box**: electric energy source + progress timer part that raises an event every N ticks only while powered.
  Replaces Nanobots' hidden radar.
- **Dock / proximity chest**: inventory part + proximity-trigger part raising enter/leave events. Mirrors SpidertronPatrols.
- **Night telescope**: crafter + condition part (daytime/pollution) + circuit output. Mirrors Muluna telescopes.

## Threads to look for on the forums (search leads, not yet read)

- Requests for `on_circuit_signal_changed` / circuit change events (nixie-tubes, rec-blue-plus, spoilage-scanner all poll).
- Requests for `on_module_inserted` / module inventory change events (rigor-module polls open GUIs).
- Requests for non-electric roboports, burner beacons and fluid-powered roboports (Muluna works around this).
- Requests to let any entity have a circuit connector / constant-combinator output.
- `raise_on_crafted` request thread (2.1 precedent for per-prototype opt-in events).
- Rseding91 "Divorcing behavior from entities" (2018) for Wube's position.

## Forum corroboration (WebSearch excerpts only, threads not opened)

- "Workarounds for entity prototypes limited to ElectricEnergySource?" https://forums.factorio.com/viewtopic.php?p=703127
  Describes Muluna's burner roboport the same way this survey found it in the code: a roboport with `input_flow_limit` 0 plus a fluid-fuelled assembler that raises
  an event on craft. The answer given for why roboports stay electric-only is that their dynamic per-tick charging draw does not suit a fuel buffer.
- "Allow roboport energy_source = "burner"" https://forums.factorio.com/viewtopic.php?p=618737&t=115554 is the matching interface request.
- "Version 2.1.12" https://forums.factorio.com/viewtopic.php?p=700144 is the changelog that added `RecipePrototype::raise_on_crafted` and
  `ScriptTriggerEffectItem::custom_event`. A modder notes that putting it on the prototype avoids the performance cost. This is the precedent for per-prototype opt-in events.
- "Recipe Finished Trigger or Event" https://forums.factorio.com/viewtopic.php?p=668804 is the earlier request asking for an event registered per recipe list.
- "Please add signal changed event filter" https://forums.factorio.com/99990 is the rejection: firing on every signal change would cost too much even for
  mods that don't listen. That is why nixie-tubes, rec-blue-plus and spoilage-scanner poll.
- "LuaCircuitNetwork.signals_changed" https://forums.factorio.com/viewtopic.php?p=698831 The flag exists internally but is not save-load stable,
  so it can't be exposed to Lua without desyncs.
