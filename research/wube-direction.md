# What Wube has shipped for "custom entity" modding, and what the developers have said

Researched 2026-11-01 against Factorio 2.1.24 (`data/changelog.txt` in the game install, and `prototype-api.json` / `runtime-api.json` published at lua-api.factorio.com, api_version reported by the JSON: 2.1.24) plus web search excerpts. Forum pages could not be fetched directly (HTTP 403), so every forum quote below comes from search-engine excerpts. Treat wording as near-verbatim, and treat dates marked "~" as estimates from post IDs. The threads listed at the end need a full read before anything here is quoted in the writeup.

## TL;DR

1. Wube's actual pattern is **"add a narrow new entity type, or bolt one more part onto an existing type"**. They do not add a generic type. From 2.0.7 to 2.1.24 they shipped: `proxy-container`, `valve`, `infinity-cargo-wagon`, `mod-data`, `custom-event`, `ElectricEnergyInterfaceEquipment`, plus parts added one at a time to fixed types: energy_source on offshore-pump and ammo-turret, module_slots on agricultural-tower, circuit_connector on boiler/heat-pipe/lab/land-mine/pipe/pipe-to-ground, output_fluid_box on FluidEnergySource and generator, and `trash_inventory_size` on lab/car/logistic-container.
2. A lot of load-time composition **already exists** in the engine. 12 entity types accept the full `EnergySource` union (electric / burner / heat / fluid / void), chosen by the `type` key at prototype load time. Module slots, effect receivers, trash inventories, fluid boxes and circuit connectors are all optional per-prototype fields on many types. The proposed type generalises a mechanism the engine already uses: these are the same part types in the prototype API, just with no fixed type wrapped around them.
3. Wube has steadily shipped **opt-in, per-prototype event hooks** instead of per-tick Lua: `custom-event` (2.0.7), `custom_status` (2.0.7), `register_on_object_destroyed` (2.0.7 rename), `RecipePrototype::raise_on_crafted` (2.1.12), `ScriptTriggerEffectItem::custom_event` (2.1.12), `SelectionToolPrototype::send_pre_selection_events` (2.1.22), `LuaEntity::get_signals_changed()` (2.1.21). `raise_on_crafted` is the strongest precedent for the proposal's "per-prototype opt-in event" design: a prototype flag that makes the engine raise an event only for the prototypes that asked for it.
4. Wube's stated position: Rseding91 rejected a runtime ECS in 2016 ("not happening") and in 2018 ("never going to happen in Factorio", based on performance). In the same 2018 thread he said he was not against a general-purpose moddable entity, but had never seen anyone write up how it would work. He asked what level the write-up should be, from C++ performance analysis to a modder's view. A later post invited a concrete design, with a sample prototype (an "electric train-wagon assembler"). **That is the opening this project addresses.**
5. Wube's performance philosophy (FFF-204, the 2023 Reddit technical AMA): the speed comes from the **sleep/wake intrusive active list** (O(1) activate and deactivate, no allocation), not from ECS-style batching. A proposal that keeps static dispatch per prototype and joins the active list only when a part needs ticking matches that philosophy. Wube has not opposed this kind of design; their objection was to dynamic per-instance component logic.
6. Wube reverses "never" answers when a concrete use case shows up. Example: the py developer protocol_1903's "Assigning multiple fluidboxes" request was answered with "not likely to ever happen ... 1-1 link and is likely going to stay that way forever". 2.1.7 then shipped `FluidIngredientPrototype::optional_fluidbox_indexes` / `FluidProductPrototype::optional_fluidbox_indexes`. Who wrote that reply is unverified (see threads to read).

---

## 1. Timeline of modding-oriented entity types and script hooks

Sources: `data/changelog.txt` Modding/Scripting sections, with the changelog line number for each entry. 2.0.7 is the first public 2.0 release and carries the whole 1.1 to 2.0 delta. 2.1.7 does the same for 2.1.

| Version (date) | Addition | Relevance to the proposal |
|---|---|---|
| pre-2.0 (1.1) | `linked-container`, `script` trigger effect + `on_script_trigger_effect`, `electric-energy-interface`, `heat-interface`, `infinity-pipe`, `simple-entity-with-owner` | The 1.x building blocks that every compound entity is made from |
| 2.0.7 (2024-10-20) | **`custom-event` prototype type**: "define custom events in the data stage ... share the same namespace as custom inputs and built-in events" (l.4651); `raise_event`/`on_event` accept event names (Scripting) | Data-stage-declared events: the model the proposal's per-prototype events would reuse |
| 2.0.7 | **`LuaEntity::custom_status` read/write** (l.4859) | Script can already drive the native status line; a component entity needs the same thing natively |
| 2.0.7 | `register_on_entity_destroyed` renamed to **`register_on_object_destroyed`** (l.4817-4818) | Per-object opt-in lifecycle event: the cleanup hook compound entities depend on |
| 2.0.7 | New types: plant, **agricultural-tower**, **asteroid-collector**, thruster, lightning-attractor, temporary-container, lane-splitter, cargo-landing-pad, capture-robot, spider-unit, rail-support, burner-usage, airborne-pollutant, quality, remote-controller | Each Space Age mechanic got its own bespoke type, not a parameterised one |
| 2.0.7 | Parts bolted onto fixed types: `OffshorePumpPrototype::energy_source`, `AmmoTurretPrototype::energy_source/energy_per_shot`, `EntityPrototype::heating_energy`, `trash_inventory_size` on logistic-container/lab/car/rocket-silo, `effect_receiver` on mining-drill/crafting machines/lab, `allowed_module_categories` on beacon/crafting machines/lab/mining-drill, circuit connections on turret/artillery, loader circuit-connectable | **The "part creep" pattern**: the same part types get copied type by type |
| 2.0.7 | "Changed various entity prototypes to only accept `energy_source` ... not `burner`" | Field-name unification across types, a step toward uniform parts |
| 2.0.7 | `delayed-active-trigger`, `active-trigger`, `chain-active-trigger` | More data-driven behaviour without Lua |
| 2.0.23 (2024-11-28) | `LuaCustomEventPrototype::event_id` (l.3324) | |
| 2.0.26 (2024-12-16) | **`LuaEntity::is_updatable`**, `disabled_by_script`, `disabled_by_control_behavior`, `disabled_by_recipe` (l.3172) | First time the API exposes the engine's "updatable entity" concept: the same notion the proposal relies on ("registered as updatable only when a part needs ticking") |
| 2.0.38 (2025-03-04) | **`proxy-container` entity type** + `LuaProxyContainerControlBehavior` (l.2626, 2634); `infinity-cargo-wagon` | A narrow type that forwards inventory access to another entity's inventory. A mitigation for compound entities (an inserter can reach a hidden entity's inventory), not a fix |
| 2.0.48 (2025-05-12) | **`valve` entity type** (l.2142 area); `defines.inventory.crafter_*`, `linked_container_main`, `asteroid_collector_output` | Inventory index unification across crafters |
| 2.0.52 (2025-05-23) | `quality` added to `on_script_trigger_effect` on spoil (l.2005) | |
| 2.0.58 (2025-06-23) | **`mod-data` prototype type** (l.1821); `Prototype::custom_tooltip_fields` (l.1794) | Arbitrary data-stage data readable at runtime: lets a mod attach "component config" to prototypes today |
| 2.0.66 (2025-09-02) | `custom_tooltip_fields` reads on all LuaPrototypes (l.1581) | |
| 2.0.67 (2025-09-22) | `heating_energy` support on fusion-generator and thruster | More per-type part copying |
| 2.1.7 (2026-06-23) | `ElectricEnergyInterfaceEquipmentPrototype` (l.811); **`LuaEntity::set_tooltip_field()` and friends** (l.965); **`LuaEntity::active` write removed in favour of `disabled_by_script`** (l.979) | Runtime per-entity tooltip fields: a compound entity can now show its hidden parts' data on the main entity |
| 2.1.7 | `LuaFluidBox` removed; all fluid access moves onto `LuaEntity` (`get_fluid_box_prototype`, `add_fluid_box_linked_connection`, ...) | Fluid boxes are treated as an indexed part of any entity |
| 2.1.7 | **agricultural-tower gets module_slots/effect_receiver/allowed_effects**; circuit_connector added to boiler, heat-pipe, lab, land-mine, pipe, pipe-to-ground; `FluidEnergySource::output_fluid_box`, `GeneratorPrototype::output_fluid_box`; `BurnerEnergySource::auto_refuel`; `optional_fluidbox_indexes` on fluid ingredients/products; `EffectReceiver::*_limits`; "dynamic" ElectricUsagePriority; new LuaXControlBehavior classes for boiler/lab/land-mine/heat-pipe/single-fluid-box | The largest single round of part creep: six types gain a circuit connector in one release |
| 2.1.12 (2026-07-21) | **`RecipePrototype::raise_on_crafted`** (l.470); **`ScriptTriggerEffectItem::custom_event`** (l.469); `LuaBootstrap::get_event_name()` | **Per-prototype opt-in engine events**: the precedent the proposal's event model copies |
| 2.1.18 (2026-09-16) | **`migrates_from` in info.json**: "take ownership of storage, script inventories, gui elements and render objects of removed mod" (l.258) | |
| 2.1.21 (2026-10-06) | `ProxyContainerPrototype::direction_count`, circuit_connector becomes an array | Proxy-container still gaining parts after shipping |
| 2.1.21 | `LuaEntity::get_signals_changed()` | Lets scripts skip work when circuit input is unchanged: polling made cheaper, but still polling |
| 2.1.22 (2026-10-15) | Selection-tool pre-selection events gated by `SelectionToolPrototype::send_pre_selection_events` | Another per-prototype opt-in event flag |
| 2.1.22 | min/max input temperature added separately to boiler, fusion-generator, fusion-reactor, generator, mining-drill, thruster, `FluidEnergySource` | The same field added to six types one by one |

**The shape of the timeline:** in roughly two years Wube added 20+ entity types. None of them is general. They also added the same handful of parts (energy source, circuit connector, module slots/effect receiver, trash inventory, extra fluid boxes, temperature limits) to fixed types one type at a time, and each addition is its own changelog line, prototype field, docs entry and Lua read. Event hooks, meanwhile, keep moving toward "declared in the data stage, raised only for prototypes that opt in" (`custom-event`, `raise_on_crafted`, `send_pre_selection_events`).

FFF #440 ("2.1 plan", https://factorio.com/blog/post/fff-440) describes 2.1 as mostly quality of life plus "modding improvements", and calls it the last major update, with later work on "support, compatibility, and modding features". 2.1 went stable on 2026-10-23 (FFF #449 per press coverage). From here on, modding features are the main thing still in scope for Wube.

## 2. Load-time composition already in the engine (2.1.24)

Generated from `prototype-api.json` (lua-api.factorio.com, 2.1.24; inherited properties resolved). `EnergySource` = union of Electric | Burner | Heat | Fluid | Void, picked by its `type` key at load time. A `?` means the field is optional.

### 2a. Energy source kind chosen at prototype load

| Accepts | Entity types |
|---|---|
| **Full `EnergySource` union (5 kinds)** | agricultural-tower, assembling-machine, boiler, furnace, inserter, lab, mining-drill, offshore-pump, pump, radar, reactor, rocket-silo (12) |
| Electric \| Heat \| Fluid \| Void (no burner) | loader, loader-1x1 (energy_source optional) |
| Burner \| Void | car, locomotive, spider-vehicle |
| Electric \| Void | arithmetic/decider/selector-combinator, asteroid-collector, beacon, electric-turret, lamp, programmable-speaker, roboport |
| Electric only | accumulator, electric-energy-interface, solar-panel, generator, fusion-generator, ammo-turret (optional), lightning-attractor (optional) |
| Electric + separate `burner` | burner-generator, fusion-reactor |
| `heat_buffer` (no energy source) | heat-interface, heat-pipe (reactor has both) |

### 2b. Other optional parts per type

| Part | Types that take it |
|---|---|
| `fluid_boxes` (array, any count) | assembling-machine, furnace, rocket-silo (the crafting machines) |
| single `fluid_box` | boiler (+output_fluid_box), generator (+output_fluid_box?), offshore-pump, pump, pipe, pipe-to-ground, storage-tank, infinity-pipe, fluid-turret, valve |
| named fluid boxes | mining-drill (input?/output?), fusion-generator/fusion-reactor (input/output), thruster (fuel/oxidizer) |
| plus: any `FluidEnergySource` brings its own fluid_box (and since 2.1.7 an optional output_fluid_box), so any of the 12 full-union types can gain a fluid box through its energy source | |
| `module_slots` + `effect_receiver` | assembling-machine, furnace, rocket-silo, lab, mining-drill, agricultural-tower (since 2.1.7), beacon (slots only) |
| `trash_inventory_size` | assembling-machine, furnace, rocket-silo, lab, car, spider-vehicle, logistic-container, infinity-container, cargo-landing-pad |
| `inventory_size` (single main inventory) | container, logistic-container, infinity-container, linked-container, temporary-container, space-platform-hub, cargo-landing-pad, car, spider-vehicle, cargo-wagon, artillery-wagon, artillery-turret, ammo-turret, asteroid-collector(?), character, cargo-pod |
| `source_inventory_size` / `result_inventory_size` | furnace (assembler sizes come from the recipe) |
| `circuit_connector` | about 45 types, including container, all crafters, lab, inserter, pipes/tanks, boiler, heat-pipe, land-mine, radar, lamp, reactor, proxy-container, display-panel, splitter, wall |
| `heating_energy` | EntityPrototype base (any entity) |

### 2c. What this means for the proposal

- **Energy sources, effect receivers, fluid boxes and circuit connectors are already self-contained part types in the prototype API (`EnergySource`, `EffectReceiver`, `FluidBox`, `CircuitConnectorDefinition`), defined the same way whatever type owns them** (that the engine loads them with the same code is assumed). Choosing the burner versus electric code path happens at load in 12 types today. The proposal's "parts chosen at prototype load" extends that from one part (the energy source) to all parts.
- **The combinations modders cannot get are cross-type**: a container whose inventory spoils at a modified rate, plus an energy source, plus a crafting progress timer; an assembling machine with a second, free inventory; a fluid tank with module slots; a radar-like scanner with a fuel burner and an output inventory. Every one of those needs a compound entity today. The engine has every part; it only lacks a host type that lets them be combined.
- The engine already exposes the gating concept (`LuaEntity::is_updatable`, 2.0.26). An entity that holds only passive parts (inventory plus circuit connector) would never enter the active list, exactly like a container.

## 3. Developer positions, quoted

All quotes come from search-engine excerpts of forum or Reddit pages. Confirm wording in the full read.

### Rseding91 (Wube lead programmer)

- **"Entity Prototype Composition"** (Modding interface requests, then "Won't implement"; ~2016, p=151612): https://forums.factorio.com/viewtopic.php?p=151612
  - The request was composable "behaviours" attachable to any prototype, e.g. a powered ammo turret.
  - Rseding91: it is "essentially an entity component system" and that is **"not happening"**. "I've never seen any game implement such a system that did anything close to what Factorio does today."
  - Adil, in the same thread, points out that modders can combine existing entities (Klonan's burner generator). This is the compound-entity workaround, already standard practice in 2016.
  - Note: the requested powered ammo turret then **shipped as a part in 2.0.7** (`AmmoTurretPrototype::energy_source`).
- **"Entity/component model in prototypes"** (~2016, p=154297 / 154824): https://forums.factorio.com/viewtopic.php?p=154297
  - mknejp argued for batch processing per component type for cache locality. A community reply says the idea "had been suggested many times" and the developers keep saying it will not happen.
- **"Divorcing behavior from entities"** (Modding ideas; ~mid-to-late 2018, p=367885 to 387802): https://forums.factorio.com/viewtopic.php?p=367885 (OP p=368897 per one index)
  - Rseding91 (p=368117 / 386247): his "4 years experience working with Factorio's C++ code base" convinced him such a system "would never exist and perform as well as the static model Factorio uses now". Performance would "fall apart quickly because of the dynamic nature of the logic each component has to handle". **"It's never going to happen in Factorio."**
  - Rseding91, later in the thread (p=387174 / 387791 / 387802): he is **not against the concept**, but has "yet to see anyone write up how such an entity would work". He asked what level of write-up was meant, from detailed C++ performance analysis to a modder's view of what they would build. He also raised whether parts of such an entity could be switched off. One excerpt says a working prototype "would go a long way" toward him considering it. Another says he offered to consider a **general-purpose modding entity** given a concrete design with a sample prototype ("electric train-wagon assembler").
  - bobingabout (modder): "if you want to make your own game engine, go for it", Factorio will not do this. Drakomir: the component approach is standard in modern engines.
- **"Register entity-related events in entity instead of script?"** (p=180836): https://forums.factorio.com/viewtopic.php?p=180836
  - Rseding91: unlikely "due to performance reasons". Such an event would be "fired hundreds/thousands of times per second during normal combat while not adding a lot of value". Takeaway for the proposal: events must be per-prototype opt-in and rare, never a blanket per-instance callback.
- **"on_combinator_recieve_circuit_update"** request: https://forums.factorio.com/75678
  - Rseding91: "what those mod(s) are trying to do is well outside of what the mod API was designed for and as such there's typically performance concerns." (2.1.21 later shipped `get_signals_changed()` as a polling-side mitigation.)
- **Reddit "Technical questions" thread, May 2023** (dev-flair answers attributed to Rseding91): https://www.reddit.com/r/factorio/comments/13bsf3s/technical_questions/ (mirror excerpt)
  - "Most of Factorio does not use any kind of entity component system." ECS "works very well when you need to apply some transformation to a data set independent of any other variables."
  - Performance comes from sleep/wake: entities are removed from the update loop, not early-returned. Sleep and wake are O(1) with no allocation, using "a doubly linked circular intrusive list".
- **FFF-204 "Another day, another optimisation"** (Aug 2017) discussion: https://forums.factorio.com/viewtopic.php?p=303569
  - Staff: the active entity list is an intrusive linked list with next/prev stored in the entity, giving O(1) on/off, so entities can change activity during the update loop. Updatable entities "can be inactive, they still exist, but they do not participate in the update loop".
- Performance advice threads: "Manual: balance load in on_tick" (https://forums.factorio.com/viewtopic.php?p=225100): Rseding91 recommends bucketing by `tick % interval`. This is the officially blessed workaround that every compound-entity mod uses today; it amortises the cost but does not remove it.

### boskid

- **"Can't place item ghosts into proxy inventories"** (2.0.72, p=685891): https://forums.factorio.com/viewtopic.php?p=685891
  - Ghost item requests through a proxy-container were "intentionally disabled, similarly as character and space platform hub". The item-request GUI was never verified for an inventory owned by another entity, and blueprinting could misbehave. He floated a flag on the proxy inventory as a possible future path.
  - Takeaway: every **cross-entity indirection** (proxy to hidden entity) needs separate support work in GUI, blueprint and ghost code. A single entity that owns all its parts needs none of it. This is a strong argument for the proposal and comes from Wube's own words.
- **"Inserters ignoring ProxyContainers"** (p=676926): https://forums.factorio.com/viewtopic.php?p=676926. A force mismatch between the proxy and the inserter blocks extraction. Another compound-entity pitfall.

### kovarex / posila / Klonan / raiguard

- No direct statement on ECS or generic entity types turned up in search. kovarex's FFF-366 "The only way to go fast, is to go well!" (June 2021) covers code-quality philosophy and may contain relevant quotes. FFF-440 (raiguard/kovarex, 2026) commits to "modding improvements" as the remaining scope.

### Community evidence that the compound-entity pain is current (2025-2026)

- "Data-driven tooltip forwarding from script-linked hidden/composite entities" (Modding interface requests, ~2026, https://forums.factorio.com/134073): a hidden accumulator on a roboport, asking for hidden parts to append to the parent's tooltip. No staff reply found. 2.1.7's `set_tooltip_field()` partly covers it.
- "Making 'fake single' entity from multi entities?" (https://forums.factorio.com/viewtopic.php?p=580478): the standard build-event, hidden-entity, track-and-destroy recipe.
- An older `compound-entity` prototype request (proxy_entity + components + control_script; reference in search excerpt near p=369162 "Modding Hackes" / p=512030; needs confirming).
- "Assigning multiple fluidboxes" (protocol_1903, py dev; p=680453 to 688630): https://forums.factorio.com/viewtopic.php?p=680453. Crafting machines "at their core do not support one ingredient/product to/from multiple fluidboxes ... likely going to stay that way forever". 2.1.7 then shipped `optional_fluidbox_indexes`. Wube moves when given a concrete py-scale use case.

## 4. How to frame the writeup against Wube's position

1. **Do not call it ECS, and do not use runtime components.** Rseding's objection is to dynamic per-instance logic. The proposal is a static composition fixed at prototype load: one C++ type, part pointers resolved at load, the same update path for every instance of a prototype, and active-list membership driven by parts. That is the "general-purpose moddable entity" he said he would consider.
2. **Answer his questions directly.** Can parts be turned off? (Yes: passive parts never tick; an entity sleeps when no active part needs updating, using the existing intrusive list.) What would a modder build? (Corrundum ice-box, pY dino-dig-site, his own "electric train-wagon assembler" example.) What is the performance story? (Benchmarks against py saves: compound-entity Lua loops versus native.)
3. **Cite part creep as the cost of the status quo.** Six circuit connectors in one release, temperature limits added type by type, module slots arriving on agricultural-tower two years after it shipped. Each is a separate code path to maintain. A composable host type makes the next such request a data change, not an engine change.
4. **Cite opt-in events as an existing direction.** `custom-event`, `raise_on_crafted`, `send_pre_selection_events`, `register_on_object_destroyed`. The proposal's per-prototype event flags use the same mechanism.
5. **Cite boskid's proxy-container answer** as evidence that cross-entity indirection costs Wube engineering time in GUI, blueprint and ghost code.
6. **Note the timing.** 2.1 is the last major update and modding features are explicitly what remains in scope.

## Threads that deserve a full read

1. Divorcing behavior from entities: https://forums.factorio.com/viewtopic.php?p=367885 (all pages; exact Rseding quotes, dates, the "general-purpose entity" and "write-up" posts p=387174/387791/387802)
2. Entity Prototype Composition: https://forums.factorio.com/viewtopic.php?p=151612 (date, exact "not happening" wording)
3. Entity/component model in prototypes: https://forums.factorio.com/viewtopic.php?p=154297
4. Assigning multiple fluidboxes: https://forums.factorio.com/viewtopic.php?p=680453 (who said "forever", and the reversal in 2.1.7)
5. Can't place item ghosts into proxy inventories: https://forums.factorio.com/viewtopic.php?p=685891 (boskid's indirection-cost reasoning)
6. Data-driven tooltip forwarding from hidden/composite entities: https://forums.factorio.com/134073 (current compound-entity pain, any staff reply)

Secondary: Register entity-related events in entity (p=180836), FFF-204 thread (p=303569), Reddit technical questions 2023 (13bsf3s), FFF-440 blog post, FFF-366.
