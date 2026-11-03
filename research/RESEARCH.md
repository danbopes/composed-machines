# Composable entity: consolidated research

Consolidates the seven notes in this folder ([forum-requests.md](forum-requests.md), [forum-help.md](forum-help.md),
[forum-threads-full.md](forum-threads-full.md), [mod-library-a.md](mod-library-a.md), [mod-library-b.md](mod-library-b.md),
[pyanodons.md](pyanodons.md), [wube-direction.md](wube-direction.md)). Nothing new was fetched; every claim
below comes from one of those notes, which in turn cite the forum thread, changelog line or mod file. Forum
material marked (full read) was read in full in Chrome ([forum-threads-full.md](forum-threads-full.md)); everything else comes from
search excerpts, and "~" dates are estimated from phpBB post ids. API and changelog facts are from the
2.1.24 changelog (`data/changelog.txt` in the game install) and the API reference JSON published at lua-api.factorio.com.

Part vocabulary used throughout: **INV** inventories (named, sized, filtered, inserter-reachable) ·
**ES** energy source (electric / burner / fluid / heat / void) · **FB** fluid boxes · **PROG** progress
timer / work cycle with no recipe · **MOD** module slots / intrinsic effect · **CC** circuit connector with
Lua-writable output · **EV** per-prototype opt-in events · **COND** engine-evaluated enable condition
feeding status.

---

## 1. Capability gaps, ranked by frequency

Counted across forum requests, help threads and shipped mods (local library a–z plus pY). "Hits" is the
number of distinct threads + mods in the notes that show the gap; it is a floor, not a census.

| # | Gap | Hits | Citations |
|---|---|---|---|
| 1 | **Compound-entity lifecycle glue** (build paths, blueprint, undo, cut/paste, clone, mine returns, orphaned children) | ~20 | https://forums.factorio.com/viewtopic.php?p=512078 (full read; Rseding91 2020-09-13 "At their core compound entities don't work"); https://forums.factorio.com/viewtopic.php?p=655527 (full read; undo needs `LuaUndoRedoStack` surgery, "mostly" works); https://forums.factorio.com/viewtopic.php?p=688799 (full read; Feb 2026, orphaned dummies, three build events); 0-things (23k LOC library for this alone), planet-muluna `scripts/compound-entities.lua` (623 lines restoring wires/orientation) |
| 2 | **Polling because the event is missing** (craft/cycle done, circuit changed, module changed, power state, fluid threshold) | ~18 | https://forums.factorio.com/viewtopic.php?f=28&t=47728 (full read; 2017 "massive drain"); https://forums.factorio.com/viewtopic.php?p=668733 (full read; per-recipe opt-in asked); https://forums.factorio.com/99990 and https://forums.factorio.com/75678 (circuit-change events refused); Cerys polls `products_finished` every 15 ticks, spoilage-scanner walks every entity every tick, pY derricks/tailings pond/slaughterhouse GUI poll |
| 3 | **Circuit connector / script-written signal output on a type that lacks one** | ~13 | https://forums.factorio.com/viewtopic.php?p=682756 ("No"); https://forums.factorio.com/viewtopic.php?p=380443 (loaders); hidden constant combinators in Cybersyn, rec-blue-plus (x2), Verbose-Engineering, Muluna telescope, Nanobots2, PowerPlusPowerMeter; LTN uses lamp + 2 combinators per stop |
| 4 | **A machine shell with no recipe: inventories + energy + progress, logic in Lua** ("assembler used only as a shell", permanently `disabled_by_script`) | ~12 | https://forums.factorio.com/viewtopic.php?p=687544 (full read; Apr 2024, unanswered, closest existing request); https://forums.factorio.com/viewtopic.php?p=541351 (drill without ore patch → fixed-recipe assembler); pY dino-dig-site, bioport, derrick `-base`; equipment-gantry, Cerys wrecks, Age-of-Production core miner |
| 5 | **Energy source on a type without one, or a different kind** | ~12 | https://forums.factorio.com/viewtopic.php?p=654992 (full read; belts "never happening", 2024-12-23); https://forums.factorio.com/viewtopic.php?p=520549 (fluid lamps, 2020); https://forums.factorio.com/viewtopic.php?p=618737 / https://forums.factorio.com/viewtopic.php?p=703127 (burner roboports); Muluna burner roboport (fluid assembler + `raise_on_crafted`), aai-signal-transmission (roboport picked for its buffer), pY aerial base (EEI), https://forums.factorio.com/viewtopic.php?p=220800 (chest + hidden accumulator) |
| 6 | **More / differently-shaped inventories, and control over which one inserters reach** | ~11 | https://forums.factorio.com/viewtopic.php?p=667877 (furnace input >1); https://forums.factorio.com/viewtopic.php?p=664814 (drop/pickup inventory, boskid won't implement); https://forums.factorio.com/viewtopic.php?p=694804 (quality outputs); equipment-gantry (3 hidden chests), Cerys module inserter (proxy into module inventory), pY dig-site food container, pY caravans (`game.create_inventory`) |
| 7 | **Runtime-settable parameters / intrinsic effects** (today: prototype per value, or a hidden beacon per machine) | ~10 | https://forums.factorio.com/viewtopic.php?p=676269 and https://forums.factorio.com/viewtopic.php?p=455855 (fixed-effect beacon; hidden beacon "doubled the entity count"); pY TURD hidden beacon per upgraded machine, pY vat brain; Tiberium beacon filled with N fake modules; Cerys reactor/lamp prototype per radius; EditorExtensions accumulator per priority x mode; rigor-module prototype explosion |
| 8 | **Fluid box on a type without one, or a second input box** | ~8 | https://forums.factorio.com/viewtopic.php?p=267976 (fluid lab); https://forums.factorio.com/viewtopic.php?p=680453 (multiple fluidboxes, later 2.1.7 `optional_fluidbox_indexes`); aai-loaders (hidden storage-tank, lubricant); pY derrick hidden assembler for drilling fluid; pY biofluid tanks are furnaces used for a fluid box; EditorExtensions infinity wagon pipe |
| 9 | **Inventory spoil-rate modifier** (no container spoil field exists in 2.1) | ~8 | https://forums.factorio.com/viewtopic.php?p=678356 (full read; boskid 2025-08-13 "unlikely to be ever implemented" for surfaces); https://forums.factorio.com/viewtopic.php?p=697061; https://forums.factorio.com/120079; corrundum `ice-box` (`on_nth_tick(53)`), cryo-container, freezer, No Spoilage in Space, spoilage-combinator |
| 10 | **Status / tooltip honesty without polling** | ~8 | https://forums.factorio.com/134073 (tooltip forwarding from hidden parts, 2026); https://forums.factorio.com/viewtopic.php?p=690374 (cannot detect low power cheaply to set `custom_status`); https://forums.factorio.com/134533 (hidden prototypes in tooltips); pY LRF panels write `custom_status` every 55 ticks unconditionally, pY derricks create a render text per run, dig site draws error sprites |
| 11 | **Script-scaled energy/fluid output curves** | ~7 | https://forums.factorio.com/viewtopic.php?p=587705 (custom generators need hidden turbine + infinity pipe); https://forums.factorio.com/viewtopic.php?p=633859 / https://forums.factorio.com/viewtopic.php?p=677298 (crafter that also generates); pY solar updraft tower, heliostat tower (`set_fluid` from Lua), aerial accumulators. Counter-example that worked: pY wind/tidal via `solar_coefficient_property` |
| 12 | **Heat output from a crafter** | ~3 | https://forums.factorio.com/viewtopic.php?p=536323 (won't implement); Muluna heat assembling machine (data-final-fixes builds assembler + hidden reactor); Cerys radiative tower |
| 13 | **Inventory / energy on moving units** | ~4 | pY caravans, ocula, biofluid couriers (script inventories, Lua fuel counter); Updated_Construction_Drones (proxy chest per drone) |

Cost of the status quo, as reported by modders ([forum-help.md](forum-help.md) §4): every build path must be handled or
parts go missing; blueprints leak hidden parts or reference unbuildable items
(https://forums.factorio.com/viewtopic.php?p=370376, Klonan); undo/cut-paste break
(https://forums.factorio.com/viewtopic.php?p=655527); identity is lost across undo
(https://forums.factorio.com/viewtopic.php?p=584507, full read); SE ship clones need per-mod handlers
(Moon Logic, Bottleneck, Construction Drones discussions); per-tick Lua loops are staggered so behaviour is
coarse; UI shows the wrong thing; untested energy-source combinations crash
(https://forums.factorio.com/viewtopic.php?p=527757 burner radar).

---

## 2. Catalogue of shipped compound entities

Tick strategy key: **E** events only · **nth(N)** `on_nth_tick(N)` over every instance · **bucket** `on_tick`
with stride/buckets · **tick** every tick over every instance.

| Mod | Entity | Core type | Hidden parts | Emulated behaviour | Tick strategy |
|---|---|---|---|---|---|
| corrundum 1.0.51 | `ice-box` | container | none | fridge: dry ice slows/undoes spoilage | nth(53), cache rebuilt with `find_entities_filtered` |
| corrundum | `pressure-lab` | lab | none | lab that only accepts non-normal quality | nth(45) |
| pyalienlife 3.1.8 | `dino-dig-site` | assembling-machine, `fixed_recipe`, permanently `disabled_by_script` | food `container`; per trip a `unit` + `simple-entity` target | creature miner, ore without a drill | nth(61) + `on_ai_command_completed` |
| pyalienlife | bioport / provider / requester tanks | assembling-machine (bioport); **furnace** used only for a fluid box (tanks) | `unit` couriers, fluid carried in Lua | fluid logistics network | nth(143); full network rebuild on any biofluid build |
| pyalienlife | caravans | unit | script inventories for cargo and fuel; Lua `fuel_bar` | train-like schedule, food as fuel | nth(60) + AI callbacks |
| pyalienlife | vat brain | assembling-machine | `hidden-beacon-vatbrain` | recipe-dependent beacon effect while working | nth(41) |
| pyalienlife | all farms (~45 names x mk01-04) | assembling-machine | none | "requires module" status + alert | nth(121), 1/8 per call; alerts lib walks every alert every tick |
| pyalienlife | TURD upgraded machines | any | `hidden-beacon-turd` per machine | tech-tree bonus as module effect | E (research, build) |
| pyalternativeenergy 3.2.11 | aerial base + blimps | constant-combinator (+ blimps are `unit`) | EEI (`aerial-base-animation`), `container`, one `accumulator` per network x tier | machine with inventory + energy + circuit I/O; distance-flown generation | nth(117), nth(301), AI callbacks |
| pyalternativeenergy | solar updraft tower | electric-energy-interface | placement-distance entity, panel entity per glass tile | daylight power curve | nth(60) |
| pyalternativeenergy | solar tower + heliostats | boiler | 33-rotation `simple-entity-with-owner` heliostats, recreated to rotate | script as fluid source | nth(60) |
| pyalternativeenergy | LRF panel / stirling | boiler | none | daylight gating | nth(55), unconditional writes |
| pyalternativeenergy | tidal | simple-entity-with-owner | hidden `solar-panel` with `solar_coefficient_property` | tide power | nth(83), global only |
| pycoalprocessing 3.1.8 | tailings pond | storage-tank | none | gas venting, overflow to polluted tiles | nth(153/154) |
| pycoalprocessing | AM/FM beacons | beacon | none; 25+25 prototypes, frequency in the name | per-instance setting | E |
| pypetroleumhandling 3.1.5 | oil/tar/gas derricks on seeps | mining-drill | `<name>-base` assembling-machine (fixed recipe, void energy, `disabled_by_script`) for a second fluid input | drill runs only with drilling fluid, bonus on depletion | nth(67), new `draw_text` per derrick per run |
| planet-muluna 2.9.8 | heat assembling machines | assembling-machine | `reactor` (fluid ES via linked fluid box, heat buffer) | crafter whose output is heat | E + nth(30) wire retry |
| planet-muluna | burner roboports | roboport (`input_flow_limit` 0) | fluid-fuelled assembler "refueler", `raise_on_crafted` recipe | fluid-powered roboport | long nth (~1200-2400) + `on_crafted_event` |
| planet-muluna | telescopes | assembling-machine | constant-combinator | day/night condition + signal output | periodic loop |
| aai-loaders 0.3.0 | `aai-*-loader` | loader-1x1 | storage-tank pipe | lubricant-consuming loader | bucket (per-loader schedule) |
| aai-signal-transmission 0.6.0 | sender / receiver | roboport (0 radius, for buffer + CC) | 2 decider combinators + pole on a hidden surface | powered cross-surface circuit link | nth(30) polling `energy` |
| equipment-gantry 0.3.0 | gantry / remover | assembling-machine, fixed recipe, `disabled_by_script` | 3 containers at rotated offsets; extra prototype per rotation | insert/remove equipment into grids | nth(60) |
| Cerys 4.25.0 | fulgoran wrecks | assembling-machine, fixed repair recipe | none; fast-replaced when done | repair by feeding kits | polls `products_finished` every 15 ticks |
| Cerys | radiative tower | reactor | hidden reactor + lamp, one prototype per radius | radius grows with temperature | tick + 20-tick loops |
| Cerys | module inserter | inserter | proxy-container into module inventory | inserter that loads modules | every 25 ticks |
| Moshine 1.2.13 | cosmic scanner stages | assembling-machine per stage | none | multi-stage build | **E via `on_crafted_event`** (2.1.12) |
| LogisticTrainNetwork 3.5.0 | LTN stop | train-stop | lamp (input), 2 constant combinators (output, lamp colour) | stop with circuit in/out + status light | tick state machine |
| cybersyn2 0.5.2 | combinator, wagon-contents mode | combinator | proxy-container | read wagon at stop | E (via 0-things) |
| project-cybersyn | `cybersyn-combinator` | arithmetic-combinator | constant combinator output; settings bit-packed into `second_constant` | station controller | nth at configured rate |
| Factorio-Tiberium 2.1.17 | control node | beacon | hidden beacon with N script-computed modules | scaling area bonus | E + area searches |
| Factorio-Tiberium | sonic / SRF emitters | EEI | target dummy (`fish`), wall segments, pipe connectors | charged weapon, force field | tick, staggered |
| EditorExtensions 2.6.1 | infinity fluid wagon | fluid-wagon | infinity-pipe that follows the wagon | infinity fluid on rails | **tick**, every wagon, fluid copy + teleport |
| EditorExtensions | infinity accumulator | EEI | none; prototype per priority x mode | configurable source/sink | E |
| Nanobots2 3.3.2 | roboport interface | roboport | constant combinator + **radar used as a timer** | circuit-commanded roboport actions | `on_sector_scanned` |
| rec-blue-plus 1.5.2 | deployer, scanner | container / combinator-like | hidden constant combinator | circuit-driven blueprint deploy | tick |
| Verbose-Engineering 1.3.2 | rocket silos | rocket-silo | constant combinator | re-implemented assembler circuit modes | tick |
| PowerPlusPowerMeter 1.1.0 | usage combinator | constant-combinator | 3 generator/interface entities, one per priority | network load as signals | tick (default) |
| spoilage-scanner 1.1.0 | scanner | constant-combinator | none | spoil % of facing inventory | **tick over all**, modulo filter |
| Mining_Drones | mining depot | assembling-machine, recipe as config selector | units, proxy units whose health = work, proxy chest | walking miners | bucket |
| SpidertronPatrols 2.7 | dock | proxy-container | none | expose parked spider's trunk | bucket, 20/tick + area search |
| angelsrefining | sea pump | placeholder swapped to mining-drill | infinite resource, item-request-proxy for modules | fluid extractor anywhere | E |

Frameworks that exist only to make this bearable: **0-things** (compound lifecycle, 23k LOC), **load-spreader**
(spread ticks), **item-request-proxy-events** (polling to fake an event), pypostprocessing
`lib/compound-entities.lua` (exists, used by none of the nine pY mods) and its nth-tick dispatcher (6
cross-mod `remote.call` per tick, capped at about 2 batch functions per tick).

---

## 3. What Wube has shipped toward this, and what they have said

### 3a. Shipped (changelog, 2.1.24)

| Version | Addition | Bearing |
|---|---|---|
| 1.1 | linked-container, `script` trigger effect, EEI, heat-interface, infinity-pipe, simple-entity-with-owner | the parts compound entities are built from |
| 2.0.7 (2024-10-20) | `custom-event` prototype; `LuaEntity::custom_status`; `register_on_object_destroyed`; linked fluidbox connections; energy_source on offshore-pump and ammo-turret; effect_receiver/module categories on more types | data-stage events; status display; part creep begins |
| 2.0.26 (2024-12-16) | `LuaEntity::is_updatable`, `disabled_by_script` | the engine's updatability concept exposed to Lua |
| 2.0.38 (2025-03-04) | `proxy-container` | inserter access to another entity's inventory (mitigation, not a fix) |
| 2.0.48 | `valve`; `crafter_trash` and unified crafter inventory defines | |
| 2.0.50 | `set_inventory_size_override` (container, wagon) | |
| 2.0.56 | container `inventory_type` with_filters / with_weight_limit / with_custom_stack_size | Wube accepts prototype-time inventory options |
| 2.0.58 / 2.0.59 | `mod-data` prototype; `custom_tooltip_fields` | |
| 2.1.7 (2026-06-23) | `set_tooltip_field`; GUI element `inventory`; per-index fluid API on LuaEntity (`LuaFluidBox` removed); circuit_connector on boiler, heat-pipe, lab, land-mine, pipe, pipe-to-ground; module_slots on agricultural-tower; `output_fluid_box` on FluidEnergySource and generator; `optional_fluidbox_indexes`; `EffectReceiver::*_limits` | the largest single round of part creep |
| 2.1.12 (2026-07-21) | **`RecipePrototype::raise_on_crafted`**, `ScriptTriggerEffectItem::custom_event` | **per-prototype opt-in event**; Moshine and Muluna deleted polling loops for it |
| 2.1.21 (2026-10-06) | `LuaEntity::get_signals_changed()`; proxy-container `direction_count`, circuit_connector array | cheaper polling, still polling |
| 2.1.22 (2026-10-15) | `SelectionToolPrototype::send_pre_selection_events`; min/max input temperature added to six types one at a time | another opt-in flag; more part creep |

Load-time composition already exists ([wube-direction.md](wube-direction.md) §2): 12 types take the full `EnergySource` union
chosen by `type` at load (agricultural-tower, assembling-machine, boiler, furnace, inserter, lab, mining-drill,
offshore-pump, pump, radar, reactor, rocket-silo); `circuit_connector` is optional on about 45 types;
`module_slots` + `effect_receiver` on 6. The combinations modders cannot get are cross-type.

Pattern: Wube adds narrow types (20+ since 2.0.7) and copies the same parts onto fixed types one at a time;
events move toward "declared on the prototype, raised only for prototypes that opt in".

### 3b. Developer positions (verbatim where a full read exists)

| Date | Who | Where | Position |
|---|---|---|---|
| 2016-04-27/29 | Rseding91 | https://forums.factorio.com/viewtopic.php?p=154019 (full read, Won't implement) | "I've got nothing against the concept in general I just don't believe it actually works when applied to something that runs at the scale that Factorio does." Describes `UpdatableEntity { virtual void update() = 0; ... }` as a side interface with boost intrusive active/inactive lists. Batched by-type updates tested: "zero difference in performance". "We're making a *game*. We're not making a game engine." |
| ~2016 | Rseding91 | https://forums.factorio.com/viewtopic.php?p=151612 (excerpt) | ECS "not happening"; "never seen any game implement such a system that did anything close to what Factorio does". The powered ammo turret asked for there shipped as a part in 2.0.7. |
| 2017-05-16 | Rseding91 | https://forums.factorio.com/viewtopic.php?f=28&t=47728 (full read) | "We specifically don't have such an event because it would be a massive drain on game performance." Reversed as an opt-in in 2.1.12 (`raise_on_crafted`). |
| 2018-06-18 | Rseding91 | https://forums.factorio.com/viewtopic.php?p=367885 (full read) | "such a system will never exist and perform the same or better than the static model ... it's never going to happen in Factorio." (about runtime ECS) |
| **2018-06-23** | Rseding91 | same thread | On a general-purpose modding entity: "I'm not against that concept but I've yet to see anyone write up how such an entity would work ... If someone did that it would go a long way towards me thinking about adding it to the game." |
| **2018-06-24** | Rseding91 | same thread | On what level of writeup: "That's what I don't know. All of that has to be figured out and then see if it can actually work to make such an entity where parts of it can just be shut off." |
| 2018-11-10 | posila | same thread | Believes in data-oriented design, but "any significant change to the entity system simply won't happen any time soon." |
| 2018-11-12 | Rseding91 | same thread | Pluggable energy sources "still don't divorce the behavior from the entity. Each entity that supports these dynamic energy sources has special logic in them to handle each type." |
| 2018-11-24 | Rseding91 | same thread | ECS is "smoke and mirrors"; in Factorio "everything touches everything else", logic is per entity. |
| 2020-09-13 | Rseding91 | https://forums.factorio.com/viewtopic.php?p=512078 (full read, Won't implement) | "This along with the other request seem too much like a hack than a proper or even partial solution for compound entities. At their core compound entities don't work." |
| 2020-11 (~) | Rseding91 | https://forums.factorio.com/viewtopic.php?p=520549 (excerpt) | Won't maintain a lamp variant for energy-source support; left open "on the off chance another developer wants to sign up for maintaining a new entity type". |
| ~2023 | boskid | https://forums.factorio.com/viewtopic.php?p=580752 (excerpt) | "inventories are not targetable"; a LuaInventory must bind to a targetable owner. |
| ~2023 | boskid | https://forums.factorio.com/viewtopic.php?p=578072 (excerpt) | Generic per-entity user data rejected because every entity would grow in memory. |
| 2024-12-23 | Rseding91 | https://forums.factorio.com/viewtopic.php?p=654992 (full read) | "This is never happening. To add energy source support means making a given entity updatable which isn't happening for belts." |
| ~2025-02 | boskid | https://forums.factorio.com/viewtopic.php?p=664814 (excerpt) | Inserter drop/pickup inventory selection: won't implement; entity decides routing. |
| 2025 (2.0.72) | boskid | https://forums.factorio.com/viewtopic.php?p=685891 (excerpt) | Ghost item requests through proxy-container intentionally disabled; cross-entity indirection was never verified in GUI/blueprint code. |
| 2025-08-13 | boskid / Rseding91 | https://forums.factorio.com/viewtopic.php?p=678356 (full read) | boskid: surface spoil multiplier "unlikely to be ever implemented" (items don't know their surface; spoil tick would need adjusting on every move). Rseding91: a creation-time modifier "*might* be possible". |
| 2023-05 | Rseding91 (dev flair) | https://www.reddit.com/r/factorio/comments/13bsf3s/technical_questions/ (excerpt) | "Most of Factorio does not use any kind of entity component system"; performance comes from O(1) sleep/wake on an intrusive list. |

Two separate positions: runtime ECS is a flat no (2016, 2018 x3); a single general-purpose moddable entity
is "not against", conditional on a writeup that shows parts can be shut off (2018-06-23/24). The 2026
"Packed Entity Prototype" thread has **no** staff reply (full read; earlier notes misattributed an ECS
refusal to it). The "electric train-wagon assembler" sample came from the modder kumpu in the 2018 thread,
not from Rseding91 (full read; [wube-direction.md](wube-direction.md)'s excerpt-based attribution is superseded).

Design constraints that follow: fix the part set at prototype load; join the update list only when a part
ticks (matches Rseding91's 2016 description: an `UpdatableEntity` side interface + intrusive lists); keep per-entity `update()` rather than promising SoA
wins (Wube measured none); events opt-in per prototype; spoil modifiers act on the spoil tick at insert and
remove, never per tick, and must define inserter-hand / cursor / script-inventory behaviour.

---

## 4. Test-mod entities, ranked simple to complex

Updatable column: whether the entity should enter the active list under the proposal's rule.

| Rank | Entity | INV | ES | FB | PROG | Other parts | EV (opt-in) | Updatable | Stands in for |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Fluid-holding chest** | main (e.g. 16 slots) | none | 1 storage box, connectable | none | — | `on_fluid_threshold` | **no** (passive parts only; must cost what a container costs) | pY biofluid provider/requester tanks (furnace used for a fluid box); aai-loaders hidden storage-tank; https://forums.factorio.com/viewtopic.php?p=267976 |
| 2 | **Fuelled chest** | main + fuel (1-2, burner) | burner, constant drain while powered | none | none | status from ES | `on_power_state_changed` | yes, only via ES | https://forums.factorio.com/viewtopic.php?p=220800 (chest + hidden accumulator); burner on non-burner types https://forums.factorio.com/viewtopic.php?p=187844, https://forums.factorio.com/viewtopic.php?p=624508; aai-signal-transmission energy polling |
| 3 | **Timed converter** | input (n slots, Lua-declared accept list) + output | electric | none | fixed duration, starts when Lua says | progress bar, working animation | `on_cycle_finished` (Lua produces output), `on_inventory_changed` (input) | yes while cycling, asleep when idle | https://forums.factorio.com/viewtopic.php?p=687544 (full read); equipment-gantry; Cerys wrecks; https://forums.factorio.com/viewtopic.php?p=632310 |
| 4 | **Cold box** | main with spoil-rate multiplier applied on insert/remove | electric (multiplier only while powered) | none | none | — | `on_power_state_changed` (rescale on change) | ES only; no per-item ticking | corrundum `ice-box`; cryo-container, freezer; constraint from https://forums.factorio.com/viewtopic.php?p=678356 |
| 5 | **Signal chest** | main | none | none | none | CC with Lua-writable output + read-contents | `on_inventory_changed` | no | hidden constant-combinator pattern (Cybersyn, rec-blue-plus, PowerPlusPowerMeter, spoilage-scanner); https://forums.factorio.com/viewtopic.php?p=682756 |
| 6 | **Required-module machine** | module slots (required) | electric | none | inherits crafter-like cycle | COND "module slot not empty" → engine status | `on_status_changed` | yes | pY farms (Farming121 + alerts lib), `scripts/farming/farming.lua` |
| 7 | **Seep derrick** | output | electric | input box consumed per cycle (COND fluid >= x) | fixed cycle | — | `on_cycle_finished` (accumulate bonus) | yes | pY derrick + hidden assembler base, `pypetroleumhandling/scripts/bitumen.lua`; aai-loaders lubricant |
| 8 | **Dig site** | food (filtered) + creature slots + output + trash | electric | none | trip timer | COND no food / no creature / no ore | `on_cycle_finished` (Lua yields ore) | yes | pY `dino-dig-site`, `pyalienlife/scripts/digosaurus/digosaurus.lua`; https://forums.factorio.com/viewtopic.php?p=541351 |
| 9 | **Intrinsic-effect machine** | crafter-like | electric | none | crafter-like | MOD with runtime-settable base effect, no hidden beacon | `on_status_changed` | yes | pY TURD hidden beacons and vat brain; Tiberium control node; https://forums.factorio.com/viewtopic.php?p=676269 |

Rationale for order: 1 and 5 prove that passive-only part sets never tick; 2 and 4 add one ticking part
(ES); 3 adds PROG + events; 6-9 are pY-shaped and pair directly with the benchmarks in §5.

---

## 5. pY entities worth benchmarking, ranked by expected cost

Ranking is from code reading ([pyanodons.md](pyanodons.md) §3): per-run work divided by period N, plus engine work the
emulation forces (units, hidden entities, render objects). Must be confirmed against the three pY saves;
instance counts per save are not yet known.

| Rank | Entity | Script file (in the mod's zip) | Period | Why it costs | Native replacement |
|---|---|---|---|---|---|
| 1 | Biofluid bioport / provider / requester | `pyalienlife/scripts/biofluid/biofluid.lua` | 143 | per unfulfilled request: provider sort calling `get_fluid` in the comparator (O(P log P) API calls) + bioport distance sort; courier unit pathing; O(all) network rebuild on any biofluid build | FB + `on_fluid_threshold` |
| 2 | Dino dig site | `pyalienlife/scripts/digosaurus/digosaurus.lua` | 61 | ~10 API calls + `get_contents` per site; O(#ores) scan per dispatch; 2 entity creations + 2 AI callbacks per trip; up to 4 units per site | dig site (§4 #8) |
| 3 | Caravans | `pyalienlife/scripts/caravan/impl/control.lua` (+ `caravan.lua`, `impl/actions.lua`) | 60 | schedule evaluation, script-inventory transfers, unit pathing | INV + burner ES on a unit core (out of scope for the first test mod) |
| 4 | Aerial turbines + bases | `pyalternativeenergy/scripts/aerial.lua` | 117, 301 + per flight leg | Lua callback per leg; base reads signals and writes 10 combinator slots; pole tracking on every pole build | INV + ES + CC on one core |
| 5 | Oil / tar / gas derricks on seeps | `pypetroleumhandling/scripts/bitumen.lua` | 67 | fluid read/extract, stats `on_flow`, 2 property writes, **1 new render object per derrick per run**, 1 hidden assembler each | seep derrick (§4 #7) |
| 6 | Tailings pond | `pycoalprocessing/scripts/tailings-pond.lua` | 153 / 154 | 3-4 fluid API calls + occasional tile work | FB + `on_fluid_threshold` |
| 7 | Vat brain | `pyalienlife/scripts/vatbrain/vatbrain.lua` | 41 | 3-4 calls per instance + hidden beacon | intrinsic effect (§4 #9) |
| 8 | LRF panel / stirling concentrator | `pyalternativeenergy/control.lua` (`register_on_nth_tick(55, "thermosolar")`, `storage.lrf_panels`) | 55 | 2 unconditional writes per instance; numerous | COND daylight |
| 9 | Solar tower / SUT | `pyalternativeenergy/scripts/thermosolar/heliostat.lua`, `.../solar-updraft-tower.lua` | 60 | 1-3 writes per instance, smoke spawn; few instances | ES with daylight curve |
| 10 | Farms | `pyalienlife/scripts/farming/farming.lua` + `pypostprocessing/lib/alerts.lua` | 121 (1/8 per call) + alerts walk every tick | tiny per instance but the largest count; every module-less farm sits in the per-tick alerts walk | required-module machine (§4 #6) |
| 11 | TURD hidden beacons | `pyalienlife/scripts/turd/turd.lua` | none (events) | engine-side: one beacon entity per upgraded machine, effect links, research sweeps | intrinsic effect (§4 #9) |
| 12 | Wind / tidal (control) | `pyalternativeenergy/scripts/wind/wind.lua`, `scripts/tidal.lua` | 61 / 83 | near zero per instance: `solar_coefficient_property` already moved the power into the engine | baseline: the success case for a declarative part |

Fixed pY overhead to measure separately (independent of entity counts): the dispatcher in
`pypostprocessing/control.lua` + `lib/events.lua` (6 `remote.call` per tick, at most ~2 batch functions per
tick) and about 8 lib `on_tick` handlers each walking `storage.alerts` and `ignored_players`.

Suggested first targets: farms (highest count, cheapest to emulate natively), derricks (hidden entity +
render churn), dig sites (assembler-as-shell, closest to the proposed entity), biofluid (superlinear).

---

## 6. Threads still worth a full read

- Page 2 of "Divorcing behavior from entities" (2 posts; needs the t= id, p= links render page 1).
- https://forums.factorio.com/viewtopic.php?t=44269 (older crafting-complete request).
- https://forums.factorio.com/viewtopic.php?p=602029 and https://forums.factorio.com/viewtopic.php?p=427782 (undo impossible for custom entities).
- https://forums.factorio.com/viewtopic.php?p=680453 (who wrote "stay that way forever" before the 2.1.7 reversal).
- https://forums.factorio.com/viewtopic.php?p=685891 (boskid's indirection-cost reasoning, verbatim).
- https://forums.factorio.com/viewtopic.php?p=151612 (exact date and "not happening" wording).
- https://forums.factorio.com/viewtopic.php?p=520549 (lamp energy-source refusal, verbatim).

---

## 7. Second pass (2026-11-02): dropped features, Wube's on-record objections, GitHub

- [forum-dropped-features.md](forum-dropped-features.md): 53 more threads read in full through the browser (none overlapping sections 1-6),
  29 of them in the "Won't implement" subforum (f=221, pages 1-7). 25 describe a hidden-entity workaround in use,
  13 say per-tick polling is the only option, 4 are features actually dropped (Better Belt Balancer's compiled
  belts, a heat-beacon mechanic, a Gleba roboport, a plant-only tower). Staff reasons across the 29: performance
  12, "doesn't work that way" 11, maintenance 3, none 5. Two reversals: offshore-pump `energy_source` (refused
  2020, shipped 2.0) and the runtime per-entity effect (`LuaEntity::local_effect`, 2.1.13), which retires pY's
  TURD hidden beacons today. The six objections the proposal must answer (t=15257, t=69180, t=88647, t=61277,
  t=113632/t=132603, t=134525) and the answers are in [../docs/WRITEUP.md](../docs/WRITEUP.md) section 3.
- [github-issues.md](github-issues.md): the mods' own issue trackers, swept read-only with the GitHub CLI (five search angles,
  every finding re-opened and verified, classified against SPEC). 176 findings verified in 100 repositories (78 portal mods, 5.79 M downloads): 30 abandoned features, 78 hidden-entity workarounds, 32 polling loops, 13 prototype-per-value patterns. 35 fixed by v1, 60 by a v2 part (54 % inside the design), 65 other cores, 11 cross-entity, 5 VCRAFT. 87 rejected, 49 of them because 2.0/2.1 already shipped the piece (`local_effect`, `on_blueprint_settings_pasted`, infinity cargo wagon, valve, `raise_on_crafted`). Two findings are from the author's own account (planet-muluna #376, Corrundum #78) and are flagged, not cited. New gaps: rotatable storage, multi-item filters, blueprint-carried settings, placement rules.
- Gap 7 (runtime-settable parameters) is partly closed by 2.1.13's `local_effect` for effect receivers; the
  prototype-per-value pattern for everything else (RealisticReactors' 250 reactors, t=113731) stands.
- Gap 9 (spoil modifier): refused a second time for containers (t=134525, boskid, 2026-06-28). Kept in v1 as the
  isolated, contested part (SPEC 1.3).
