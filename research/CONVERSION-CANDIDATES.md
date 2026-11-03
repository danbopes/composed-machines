# Conversion candidates: every building that could become a `composed-machine`

Consolidates four sweep notes, local-a-m (a-m), local-n-z (n-z), base-game (base) and external-mods (ext) (sweep
notes, not included in the public repository), plus [RESEARCH.md](RESEARCH.md) section 2 (RES §2) and
[pyanodons.md](pyanodons.md), with the verdicts SPEC Appendix A (AppA, [../docs/SPEC.md](../docs/SPEC.md)) gives the
RESEARCH §2 entries. Instance counts come from [../bench/RESULTS.md](../bench/RESULTS.md)
section (d) (census of `pY_134`, `pY_Season_3_A2_Fixed`, `pY_Fixed`). Portal download counts for local-library and
pY mods were fetched from `https://mods.factorio.com/api/mods/<name>` on 2026-11-02. External-mod counts are the ones
`ext` recorded the same day. Nothing else is new. Every row cites the sweep row it came from and that row's source
file.

**Fidelity** (as in the sweeps): **FULL** means the composed machine replaces every hidden part and every tick loop.
Lua that does the mod's own job in an event handler may stay. **PARTIAL** means some parts or loops go, and the row
names what stays. **NO** means the core needs a capability the v1 type does not have, and the row names it. Shapes:
S0 passive, S1 watcher, S2 timer, S3 machine (SPEC section 2).

**How duplicates were resolved.**
- Where a sweep re-rules on an AppA entry, the sweep's row is used. That happens for every pY entity (from n-z) and
  for the Muluna, Nanobots2, rec-blue-plus, spoilage-scanner, Verbose, PowerPlus, SpidertronPatrols and cybersyn rows.
- Two verdicts change against AppA, both from n-z:
  - The pY LRF panel and stirling concentrator go from no to **FULL**. The boiler's energy source is `void`, so this
    is a daylight-gated fluid conversion, not generation.
  - The Muluna telescope goes from no to **PARTIAL**. Its hidden combinator is exactly `circuit_outputs = "script"`.
- [pyanodons.md](pyanodons.md) adds no row that n-z lacks.
- aai-loaders is **already solved** (2.1 `LoaderPrototype::energy_source` accepts `fluid`, AppA). It is left out of
  every count.
- The data-only pY shells in n-z §2 are not rows: cooling towers, electric/oil boiler, coal powerplant, solar
  concentrator, retorter, clay pit, micro-mine, `py-sinkhole`. Each is a `fixed_recipe` assembler that would convert
  FULL but buy nothing (SPEC 11).
- Closed-source external rows (SE, AAI Programmable Structures, IR3) are marked **inferred** in ext. They come from
  portal and wiki text, not code.

**Sort order.** Rows are sorted by fidelity first. Within each fidelity they are sorted by weight:
1. pY families with a census count above 0, largest first.
2. Vanilla entity types (present in every save).
3. Mods by portal downloads.
4. Wube scenario and campaign scripts.
5. Unknown.
6. Families the census found at 0 in all three saves.

The census figure is the largest of the three saves.

**Blocker codes** (column "Blocks"):

| Code | Meaning |
|---|---|
| GEN | power generation or storage, including script-scaled output curves (gap 11) |
| HEAT | heat output, heat buffer behaviour, ambient heat loss (gap 12) |
| RECIPE | recipe selection on a crafter, including recipe-by-input and wildcard "void anything" sinks |
| CIRC | circuit input read or circuit-driven behaviour (the type writes signals and never reads them) |
| UNIT | moving core: unit, vehicle, character (gap 13) |
| NET | robot, logistic, train-stop, rail or electric-network role (roboport, logistic chest, power switch) |
| MINE | resource search and depletion (mining drill) |
| WORLD | interaction with world entities: plants, asteroids, lightning |
| CORE | some other fixed core: inserter, loader, combinator logic, silo or rocket, platform, lab research, turret, valve or pump flow, market, infinity entities |
| BCAST | effect broadcast (beacon) |
| XENT | cross-entity or cross-surface inventory or fluid link (forbidden, SPEC 0) |
| AREA | a world or network query that stays Lua (area search, charting, data from another mod or a platform) |
| ITEMSET | item-, fluid- or signal-typed `settings` (v2 in SPEC 1.6) |
| VCRAFT | needs a change on vanilla crafters, not this type (`require_module`, base effect, status event) |
| TILE | product or prototype depends on the surface or tile |
| PLACE | placement on resource entities |
| FREEZE | freeze/thaw event or status on S0 |
| CONT | continuous, demand-throttled conversion instead of a discrete cycle |
| PERCYC | per-entity cycle time or energy per cycle |
| LIGHT | light part |
| LIFE | self-destroy on empty or expiry, timed alert |
| FLUIDREAD | fluid amounts in the `contents` circuit read |
| CCEDIT | player-edited constant-combinator sections |
| ENRULE | custom energy rule (drain when under-supplied) |
| NOTHING | nothing polled or hidden, so there is nothing to simplify |

---

**Correction (2026-11-02, session 2):** `LuaEntity::local_effect` (R/W `Effect`, "additional effect applied to this
entity with effect receiver", present in the 2.1.24 runtime API) is the runtime base effect on vanilla
crafters that rows 60 (TURD hidden beacons, census 2,176) and the VCRAFT note below asked for. TURD is therefore
**ALREADY-SOLVED** in 2.1 without this type: one `local_effect` write per upgraded machine replaces its hidden beacon.
The vat brain (row 61) still needs broadcast, because its effect is tiered by recipe and applied *while working* to
one machine; `local_effect` could carry it too if the mod rewrites the value on `status_changed`-like polling, which
is the same 41-tick loop it runs today. pY farms (row 59, `require_module`) remain a one-field ask.

---

## 1. Master table (189 rows)

| # | Fid. | Source | Mod | Weight | Entity | What it is | Today (core / hidden parts / ticking) | Composed shape + parts | Reason / what stays | Blocks | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | **FULL** | pY | pyalienlife | census 18 | `provider-tank`, `requester-tank` | Endpoints of the biofluid network | `furnace`, void ES, 100k + 1-unit fluid boxes, `disabled_by_script`, chosen for fluid box + `custom_status`; scanned by nth(143) | S0 (provider) / S1 (requester): FB 1, `fluid_thresholds` + `fluid_threshold`, settings `request_amount` (uint32), `min_temperature` (int32) | Courier dispatch answering the event is the bioport's (row: bioport) | - | n-z F2; AppA; `pyal/scripts/biofluid/biofluid.lua:167-170,981`; census 9+9 in A2_Fixed |
| 2 | **FULL** | pY | pyalienlife | census 14 | `dino-dig-site` (+ food `container`, digosaur `unit`, `digosaurus-mineable-proxy`) | Creature miner: eats food, sends digosaurs to random ore in range | `assembling-machine` + `digosaurus-hidden-recipe`, permanently `disabled_by_script`; hidden food container; 1 unit + 1 simple-entity per trip; nth(61) batch + `on_ai_command_completed` | S3: INV food/creatures/ore/trash, electric ES, process 20-30 s `consume_at=script`, `cycle_started/finished`, conditions `inventory_not_empty`/`module_slot_filled`/`inventory_below` | Ore choice and depletion move into the `cycle_finished` handler; units become optional visuals | - | n-z F1; AppA; `pyal/scripts/digosaurus/digosaurus.lua:285`; bench (b) cl-dig-site 60 ns vs 47 ns e-furnace |
| 3 | **FULL** | pY | pycoalprocessing | census 1 | `tailings-pond` | Fluid sink that vents gas and spills onto polluted tiles | `storage-tank`; nth(153): `get_fluid`, capacity reads, `pollute`, `set_fluid`, fill sprite re-render; nth(154) tiles + `ninja-tree` | S1: FB 1, `fluid_thresholds` 99 % (+hysteresis), `fluid_threshold` event | Venting and tile spill run in the handler; fill-level sprite stays a render object (no level window in the graphics set) | - | n-z F3; AppA; `pycp/scripts/tailings-pond.lua` |
| 4 | **FULL** | base | base / space-age | vanilla | `assembling-machine` with `fixed_recipe` (captive spawner, silo part crafting) | Converter with one recipe | crafting machine, `fixed_recipe`, sleep/wake, `raise_on_crafted` | S3: process with the recipe's ingredients/products | Already the native shell; spawner alone is PARTIAL (`production_health_effect`) | - | base 1a#1; `data/space-age/prototypes/entity/entities.lua:1563-1650` |
| 5 | **FULL** | base | base | vanilla | `container` | Chest | `container`, not updatable (assumed) | S0 | SPEC 12: emulation exact | - | base 1b; [ContainerPrototype](https://lua-api.factorio.com/latest/prototypes/ContainerPrototype.html) |
| 6 | **FULL** | local | aai-signal-transmission | 590,476 dl | sender / receiver | Powered cross-surface circuit link | `roboport` (0 radius, for its buffer + CC) + 2 decider combinators + pole on a hidden surface; nth(30) polls `energy` | S1 electric + CC script output + `status_changed` | Hidden-surface wiring is unrelated and stays | - | AppA; RESEARCH §2 |
| 7 | **FULL** | local | equipment-gantry | 298,377 dl | gantry / remover | Inserts/removes equipment into grids | `assembling-machine` fixed recipe, `disabled_by_script` + 3 containers at rotated offsets + prototype per rotation; nth(60) | S3: grid-item/equipment/output inventories by filters, `start=script`, `inventory_changed` + `cycle_finished` | - | - | AppA; RESEARCH §2 |
| 8 | **FULL** | external | AAI Programmable Structures | 145,192 dl | tile / zone / unit-data scanners (**inferred**) | Circuit scanners reading the world | shell + script-written CC, 10 structs per tick round robin (portal text) | S2 timer + CC script output; scan in `cycle_finished` | Scan logic stays Lua; controllers acting on units PARTIAL; closed source | - | ext #5; portal page |
| 9 | **FULL** | pY | pyalternativeenergy | 93,170 dl | `lrf-panel-mk01..`, `stirling-concentrator` | Concentrated-solar molten-salt heaters | `boiler`, `energy_source = void`, salt-filtered boxes; nth(55) writes `disabled_by_script` + `custom_status` for every panel every run from **nauvis** daylight | S2 (void): FB in/out, process cold salt -> hot salt, `daylight` condition 0.5 | Semantics change: loses the boiler's throughput-from-temperature rule; gains per-surface daylight. **Disagrees with AppA** (filed as generation); the boiler source is void, so nothing is generated | - | n-z F4; `pyae/control.lua:79-93`, `pyae/prototypes/buildings/lrf-panel-mk01.lua:99-127` |
| 10 | **FULL** | local | Cerys-Moon-of-Fulgora | 79,117 dl | fulgoran wrecks | Repair by feeding kits | `assembling-machine` with repair recipe; polls `products_finished` every 15 ticks; fast-replaced when done | S3 `ingredients` = repair kits, `cycle_finished` does the swap | - | - | AppA; RESEARCH §2 |
| 11 | **FULL** | local | Cerys-Moon-of-Fulgora | 79,117 dl | `cerys-fulgoran-radiative-tower-contracted-container` | Sealed ruin that opens when emptied of iron sticks | `container`; `tick_20` calls `get_item_count("iron-stick") == 0` on every contracted tower while a player is on Cerys | S0: INV sticks (filter iron-stick), `inventory_changed={"sticks"}` | Opening animation chain stays one-shot Lua | - | a-m #1; `scripts/radiative-tower.lua:390-470` |
| 12 | **FULL** | local | Moshine | 66,165 dl | cosmic scanner stages | Multi-stage build | assembler per stage, `on_crafted_event` (2.1.12); already event-driven | One prototype whose `products` are the next stage's parts | Little to gain: already no polling | - | AppA; RESEARCH §2 |
| 13 | **FULL** | local | corrundum | 61,554 dl | `ice-box` | Fridge: dry ice slows/undoes spoilage | `container` + nth(53) rewriting every stack, cache rebuilt with `find_entities_filtered` | S1 burner, `activity=inventory_not_empty`, `spoil_modifier` m = 8 `requires_power` | Semantics change: loses pause-below-50 %/rewind, per-stack dry-ice draw, Aquilo/Frozeta exemption. Rests on the spoil re-stamp boskid has not permitted (SPEC 1.3) | - | AppA; RESEARCH §2 |
| 14 | **FULL** | external | Renai Transportation | 58,623 dl | `RTItemCannon` | Fires a stack once the buffer is charged | EEI buffer + hidden chest; global `on_nth_tick(1)` dispatcher, cannon branch every 15 ticks checks `energy == buffer` and a full stack | S3: electric buffer, ammo INV 1 slot, `start=script` from `inventory_changed`, `cycle_finished` spawns projectile | Projectile stays Lua in the handler | - | ext #1; `script/event/on_tick_ItemCannons.lua` |
| 15 | **FULL** | external | Nullius | 47,384 dl | `nullius-align-concordance-transmitter` | Powered mission transmitter | `radar` copy as a 100 MJ buffered shell; on_tick dispatcher reads `energy/buffer > 0.6` | S0/S1 electric with `buffer_capacity`, `power_state_changed` | - | - | ext #4; `nullius/scripts/alignment.lua` L528-560 |
| 16 | **FULL** | local | Age-of-Production | 16,008 dl | `aop-core-miner` | Planet-core miner, ore from nothing, 10 module slots | `assembling-machine` `fixed_recipe=aop-core-mining`; one-per-surface build rule | S3: INV output, electric, process with products, `allow_productivity`, MOD 10 | Like-for-like, no gain: a fixed-recipe assembler already is this | - | a-m #2; `Age-of-Production_2.3.5/control.lua:1-80` |
| 17 | **FULL** | external | Quantum Fabricator | 6,227 dl | `digitizer-chest` | Pushes contents into virtual storage | `container` + hidden `storage-tank`; round-robin nth reads signals and transfers | S2: storage INV + FB + CC; `cycle_finished` (or S0 `inventory_changed`) | - | - | ext #2; `scripts/tracking_utils.lua` |
| 18 | **FULL** | external | Quantum Fabricator | 6,227 dl | `qf-storage-reader` | Combinator showing network storage | `constant-combinator`; nth(84) round robin | S2 + `circuit_outputs=script` | Gain is only the per-entity schedule | - | ext #3 |
| 19 | **FULL** | base (script) | base scenario `supply` | scenario | `red-chest` quota chests | Deliver N of each item before the timer | story update every 60 ticks walks every chest's `get_contents()` | S0 + `inventory_changed` | Quota rule stays Lua, run on insert | - | base §2#4; `data/base/script/supply/control.lua:273-290` |
| 20 | **FULL** | base (script) | base scenario `team-production` | scenario | team delivery chests | Teams race to produce items | nth(29) `check_chests` over every chest | S0 + `inventory_changed` | Input refill (nth 997) stays | - | base §2#5; `team_production.lua:486-552` |
| 21 | **FULL** | base (script) | campaign `transport-belt-madness` | scenario | `red-chest` output chests | Fill each chest with 21 of the right item | `on_tick` `get_item_count()` per chest | S0 + `inventory_changed` | - | - | base §2#6; `transportbeltmadness.lua:119-125` |
| 22 | **FULL** | base (script) | campaign `tight-spot` | scenario | result chest | Sell what lands in the chest | `on_tick` story reads `get_contents()` | S0 + `inventory_changed` | - | - | base §2#7; `tightspot.lua:327,363-370` |
| 23 | **PARTIAL** | pY | pypetroleumhandling | census 29 | `oil-derrick`, `tar-extractor`, `natural-gas-derrick` mk01-04 (+ `<name>-base`) | Drills on bitumen seeps that need drilling fluid; patch on depletion | `mining-drill` + hidden `assembling-machine` (`fixed_recipe=drilling-fluids`, void, `disabled_by_script` forever) for a 2nd fluid input; nth(67): `extract_fluid`, stats, 2 property writes, a new `draw_text` per derrick per run | S3: FB drilling fluid in + product out, `ingredients`/`products`, `fluid_at_least 50`, `cycle_finished` bonus, setting uint32 | Mining (seep search/depletion) stays; FULL only if pY accepts Lua-managed depletion. Census found **0** `-base` assemblers in all 3 saves next to 29 drills (UNVERIFIED why) | MINE | n-z P4; AppA; `pyph/scripts/bitumen.lua:43-69,125-146,265-291`; RESULTS (d) |
| 24 | **PARTIAL** | pY | pyalienlife | census 1 | `bioport` | Courier hub of the biofluid network | `assembling-machine` (hidden recipe, void, 1 module slot, `disabled_by_script`); courier `unit`s; nth(143) with O(P log P) `get_fluid` sorts per request; O(N) network rebuild per biofluid build | S3/S1: INV creatures/food/guano, `consume_at=script`, module slots, no-food / no-creature conditions | Courier units and the network graph/dispatch stay | UNIT, NET | n-z P1; AppA; `pyal/scripts/biofluid/biofluid.lua:230-260,977` |
| 25 | **PARTIAL** | base | base | vanilla | `furnace` | Recipe chosen by input item | `source/result_inventory_size`, recipe from input | S3 with the one recipe | FULL only for one-recipe categories; recycler rules it out | RECIPE | base 1a#3; [FurnacePrototype](https://lua-api.factorio.com/latest/prototypes/FurnacePrototype.html) |
| 26 | **PARTIAL** | base | base | vanilla | `boiler` (boiler, heat-exchanger) | Water to steam | `target_temperature`, two boxes, `mode` | S3 burner/heat, two FBs, short-cycle process | Continuous energy-proportional conversion; heat-in-place mode | CONT | base 1a#10; [BoilerPrototype](https://lua-api.factorio.com/latest/prototypes/BoilerPrototype.html) |
| 27 | **PARTIAL** | base | base | vanilla | `electric-energy-interface` | Script/editor source or sink | runtime `energy_production/usage` | Consumer half: S1 electric `activity=always` | Production half is generation | GEN | base 1a#12; [ElectricEnergyInterfacePrototype](https://lua-api.factorio.com/latest/prototypes/ElectricEnergyInterfacePrototype.html) |
| 28 | **PARTIAL** | base | space-age | vanilla | `temporary-container` (cargo pod) | Landed pod; goes when empty; alert after time | `time_to_live`, `destroy_on_empty`, `alert_after_time` | S0 + `inventory_changed` handler; S2 timer for expiry | Self-destruction and timed alert need Lua handlers | LIFE | base 1a#18; [TemporaryContainerPrototype](https://lua-api.factorio.com/latest/prototypes/TemporaryContainerPrototype.html) |
| 29 | **PARTIAL** | base | base | vanilla | `offshore-pump` | Pumps the tile's fluid | output box, `pumping_speed`, circuit enable | S2 void timer with a fixed fluid product | Fluid comes from the tile (one prototype per fluid); circuit enable | TILE, CIRC | base 1a#23; [OffshorePumpPrototype](https://lua-api.factorio.com/latest/prototypes/OffshorePumpPrototype.html) |
| 30 | **PARTIAL** | base | base | vanilla | `radar` | Charts sectors; radar-to-radar circuit link | `energy_per_sector`, ranges | S3 electric cycle + handler calling `force.chart` | Charting, nearby reveal, radar circuit network | AREA | base 1a#25; [RadarPrototype](https://lua-api.factorio.com/latest/prototypes/RadarPrototype.html) |
| 31 | **PARTIAL** | base | base | vanilla | `lamp` | Light in darkness; circuit colour | darkness thresholds, RGB signals | S3 1/60 s cycle + `daylight` + light in `working_visualisations` | Circuit enable/colour; costs more than the lamp (anti-pattern) | CIRC | base 1a#29; [LampPrototype](https://lua-api.factorio.com/latest/prototypes/LampPrototype.html) |
| 32 | **PARTIAL** | base | space-age | vanilla | `fusion-reactor` | Power + cells + coolant -> plasma | two energy sources, neighbour bonus, demand-scaled usage | S3 electric, fuel as an ingredient | Second energy source, neighbour pass-through, demand scaling | CONT | base 1a#33a; `data/space-age/prototypes/entity/entities.lua:2558` |
| 33 | **PARTIAL** | base | base | vanilla | `storage-tank` | Fluid tank | one box, circuit fluid read | S0 + FB | `circuit_outputs=contents` has no fluid read | FLUIDREAD | base 1b; [StorageTankPrototype](https://lua-api.factorio.com/latest/prototypes/StorageTankPrototype.html) |
| 34 | **PARTIAL** | base | base | vanilla | `constant-combinator` | Player-set signals | sections edited in GUI | S0 + CC `script` | Player-edited sections not in SPEC 8 | CCEDIT | base 1b |
| 35 | **PARTIAL** | external | Space Exploration | 532,206 dl | delivery cannon (**inferred**) | Fires a capsule to another surface | loaded shell + charging power, distance-dependent recharge, custom GUI | S3: electric, filtered input, settings target surface/x/y (3 x int32), `cycle_finished` | Distance-dependent recharge is per-entity cycle cost; closed source | PERCYC | ext #14; wiki `Delivery_cannon` |
| 36 | **PARTIAL** | external | Space Exploration | 532,206 dl | meteor point defence / installation (**inferred**) | Charges power and ammo, fires at meteors | turret-looking shell, disabled until a meteor is in range | S3/S1: electric buffer + ammo input | Turret rotation/visual, per-shot charge | CORE | ext #15; wiki `Meteor_Defence` |
| 37 | **PARTIAL** | external | Krastorio 2 | 394,869 dl | `kr-intergalactic-transceiver` | Victory building: charge 30 TJ, then activate | `accumulator` + per-tick `on_tick` energy delta, 50 GJ/tick drain, `entity.energy` writes, **random jitter so status does not flip**; swaps to EEI and an inactive simple-entity | S1: electric large buffer + `powered` condition + `status_changed` | Drain-when-under-supplied rule, activated form is generation, one-per-surface rule stay | GEN, ENRULE | ext #6; `scripts/intergalactic-transceiver.lua` L438-533 |
| 38 | **PARTIAL** | external | AAI Programmable Structures | 145,192 dl | vehicle deployer (**inferred**) | Deploys vehicles on circuit command | container shell + script | S3 `start=script`, `cycle_finished` spawns | Vehicles stay vehicles | UNIT | ext #16 |
| 39 | **PARTIAL** | local | Mining_Drones | 118,259 dl | mining depot | Walking miners | assembler as config selector + units + proxy units/chest; bucket | S3 `start=script` | Drones stay units; selected item wants an item-typed setting | UNIT, ITEMSET | AppA; RESEARCH §2; ext notes |
| 40 | **PARTIAL** | pY | pyalienlife | 106,253 dl | `ipod` | Personal-logistics pad for ocula couriers | `container` filtered to ocula; status sprites drawn per ipod in the nth(221) player pass | S0: one filtered inventory | Ocula units and per-player request scan stay; status sprite needs conditions evaluated on transfer for S0 (open in SPEC 1.5) | UNIT | n-z P2; `pyal/scripts/ocula/ocula.lua:358-411` |
| 41 | **PARTIAL** | external | Maraxsis | 86,615 dl | `maraxsis-regulator` | Dome regulator that is also a roboport | `roboport` copy + hidden per-quality `assembling-machine` consuming atmosphere; nth(73) checks `is_crafting()` and floods/unfloods the dome | Hidden assembler becomes an S3 part with `status_changed` | Roboport core and dome flooding stay; a composed machine inside a compound | NET, AREA | ext #7; `scripts/pressure-dome.lua` L663-718 |
| 42 | **PARTIAL** | local | Cerys-Moon-of-Fulgora | 79,117 dl | module inserter | Inserter that loads modules | `inserter` + proxy-container into module inventory; every 25 ticks | Composed module inventory with `inserter_access=insert` | Vanilla crafters still need the proxy | CORE | AppA; RESEARCH §2 |
| 43 | **PARTIAL** | local | Cerys-Moon-of-Fulgora | 79,117 dl | `cerys-fulgoran-teleporter` (+ `-frozen`) | Ancient teleporter with a mod GUI | `assembling-machine` with no-recipe category; 15-tick loop writes `custom_status` from `frozen`; frozen variant polled and swapped | S0, electric drain-only, `default_status`, `gui_title_key` | Freeze/thaw poll and variant swap stay (S0 has no `status_changed`) | FREEZE | a-m #3; `scripts/teleporter.lua:250-330` |
| 44 | **PARTIAL** | external | Transport Drones | 78,606 dl | request/supply/buffer/fuel/fluid depots | Road-network depots | `assembling-machine` as item selector + hidden chest; drone units; on_tick | S0/S3 with declared inventories + FB | Drones stay units; selected item needs item-typed setting | UNIT, ITEMSET | ext #11; `script/depots/*.lua` |
| 45 | **PARTIAL** | local | planet-muluna | 63,938 dl | `muluna-telescope` family + hidden `constant-combinator` | Observatory crafting per-planet data, outputs platform signals | `assembling-machine` with per-surface locked recipe + script-wired combinator; **nth(6) by default** rewriting `section.filters` | S3: process + `cycle_finished`, `circuit_outputs=script` | Platform data refresh stays Lua; per-surface products need Lua or a prototype per planet. **Disagrees with AppA (no)** | AREA, TILE | n-z P5; `mul/scripts/telescopes.lua:298,655-700`; `mul/settings.lua:304-306` |
| 46 | **PARTIAL** | local | planet-muluna | 63,938 dl | `muluna-satellite-radar` | Platform radar charting around remote-view players | `radar` chosen for its buffer only (`energy_per_sector=1TJ`); nth(60) per player subtracts energy, `force.chart` | S0: electric drain-only buffer, setting bool `enabled` | Per-player charting loop is the feature | AREA | n-z P6; `mul/scripts/nav-beacon.lua:297,377-450` |
| 47 | **PARTIAL** | external | Renai Transportation | 58,623 dl | `RTVacuumHatch` | Sucks ground items into a chest | EEI + per-tick dispatcher every 3 ticks: `find_entities_filtered{type=item-entity}` | S3: electric, output INV, `cycle_finished` area search | Area scan stays Lua | AREA | ext #8; `script/event/on_tick_VacuumHatches.lua` |
| 48 | **PARTIAL** | external | Bio Industries | 55,109 dl | `bi-arboretum` (1.1) | Plants trees / terraforms per recipe | `assembling-machine` + hidden `radar` (timer) + pole + lamp | S3 + mode setting, cycle replaces radar timer | Terraforming, recipe-as-mode, light stay | AREA, RECIPE, LIGHT | ext #13; `prototypes/compound_entities/main_list.lua` L160-180 |
| 49 | **PARTIAL** | external | Castra / Castra Prime | 50,274 dl | `jammed-data-collector` | Captured collector accumulating interference | insert 1 item every 60 ticks from on_tick when a powered jammer radar is near | S2 timer, products 1 item per 60 ticks | Cross-entity jammer gate stays | AREA | ext #12; `control.lua` L856-895 |
| 50 | **PARTIAL** | local | Factorio-Tiberium | 45,770 dl | sonic / SRF emitters | Charged weapon, force field | EEI + target dummy (`fish`), wall segments, pipe connectors; staggered tick | S1 electric with buffer + `status_changed` replaces the energy poll | Walls and weapon stay | CORE | AppA; RESEARCH §2 |
| 51 | **PARTIAL** | local | Factorio-Tiberium | 45,770 dl | `tiberium-growth-accelerator` | Credits add ore to the node's next growth burst | `furnace` as a cycle counter (result probability 0), `products_finished` read by the growth loop; drill placeholder swapped on build | S2: INV credits, void, `cycle_time=15`, `products={}` | Drill placeholder stays: cannot place on a resource | PLACE | a-m #4; `control.lua:698-717,1640-1653` |
| 52 | **PARTIAL** | local | Factorio-Tiberium | 45,770 dl | `tiberium-monoculture-green/-blue` | Powered node structure that biases growth; 4 blue -> 1 green | `assembling-machine`, recipe set on build; growth loop reads `energy`; drill placeholder | S3: INV in/out, electric, process | Placement shim stays | PLACE | a-m #5; `control.lua:683-690,1654-1690` |
| 53 | **PARTIAL** | local | Nanobots2 | 45,340 dl | `roboport-interface-main` (+ cc, scanner) | Circuit-controlled roboport actions | `roboport` + hidden constant combinator + **radar used as a timer** | S2/S3 timer + `cycle_finished` replaces the radar | Roboport core stays | NET | n-z P7; AppA |
| 54 | **PARTIAL** | local | rec-blue-plus | 40,526 dl | `blueprint-deployer`, `-deployer2`, scanner | Circuit-driven blueprint placement | `container` + hidden constant combinator; on_tick | S0 + `circuit_outputs=script` | Reading circuit input stays Lua | CIRC | n-z P8; AppA |
| 55 | **PARTIAL** | external | Exotic Industries (+ESI) | 34,971 dl | `ei_neutron-collector` | Rate set by distance to nearest fusion reactor | assembler; script picks one of N recipes and locks it | S3 + setting `efficiency`, `start=script` | Proximity search; per-entity rate | AREA, PERCYC | ext #9; `scripts/control/neutron_collector.lua` L177-215 |
| 56 | **PARTIAL** | external | Quantum Fabricator | 6,227 dl | `dedigitizer-reactor` | Pulls items/fluid out of virtual storage on reactor heat | `reactor` + hidden container + hidden storage-tank; nth(60) | S3 burner, output INV + FB, `cycle_finished` pulls | Item/quality filter is item-typed (v2); heat gating becomes energy per cycle | ITEMSET | ext #10; `scripts/tracking_utils.lua` L309-339 |
| 57 | **PARTIAL** | local | spoilage-scanner | 4,074 dl | `spoilage-scanner` | Spoil % of facing inventory | `constant-combinator`; on_tick walks every scanner with modulo | S2 cycle as sample period + `circuit_outputs=script` | Neighbour-inventory read stays | AREA | n-z P9; AppA |
| 58 | **PARTIAL** | pY | pyalternativeenergy | census 0 | `aerial-base` (+ `-animation` EEI, `-chest`) | Hangar for aerial turbines | `constant-combinator` + EEI + container; nth(117) reads signals, stores/releases turbines, writes 10 slots; nth(301) refresh | S1: INV blimps, electric `activity=script`, `circuit_outputs=script` | Turbine units, distance-flown generation, reading input signals stay | UNIT, GEN, CIRC | n-z P3; AppA; `pyae/scripts/aerial.lua:393,433,1154-1162` |
| 59 | **NO** | pY | pyalienlife | census 5,100 | every farm (~45 names x mk01-04 + TURD variants) | Animal/plant/fungus farms that need a module | Vanilla `assembling-machine` with recipes; Farming121 1/8 batch: `get_module_inventory().is_empty()`, `custom_status`, alert walked every tick by alerts lib | - | Crafter with recipes. One-field fix outside this type: `require_module` on `CraftingMachinePrototype` (SPEC 11) | RECIPE, VCRAFT | n-z N4; AppA; `pyal/scripts/farming/farming.lua:26-41` |
| 60 | **NO** | pY | pyalienlife | census 2,176 | `hidden-beacon-turd`; TURD machine swaps | Tech-tree bonus per upgraded machine | One hidden `beacon` per machine (research/build events); `create_entity{fast_replace}` swaps | - | **Already solved in 2.1.13**: `LuaEntity::local_effect` (R/W `Effect` on every effect receiver) is the runtime base effect on vanilla crafters; one write per upgraded machine replaces its hidden beacon | ALREADY-SOLVED | n-z N5; AppA; `pyal/scripts/turd/turd.lua:374,425-494` |
| 61 | **NO** | pY | pyalienlife | census 1,178 | `vat-brain` + `hidden-beacon-vatbrain` | Recipe-tiered beacon effect while working | `assembling-machine` + hidden `beacon`; nth(41) toggles beacon and swaps modules | - | Effect broadcast; crafter with recipes | BCAST, RECIPE | n-z N3; AppA; `pyal/scripts/vatbrain/vatbrain.lua:19-30`; census 1178 + 1178 beacons in A2_Fixed |
| 62 | **NO** | pY | pyalienlife | census 13 | `caravan`, `caravan-turd`, `flyavan`, `fluidavan`, `nukavan` | Scheduled food-powered haulers | `unit` + `game.create_inventory` cargo/fuel + Lua `fuel_bar`; nth(60) + AI callbacks | - | Moving core; schedule part | UNIT | n-z N1; AppA; `pyal/scripts/caravan/**` |
| 63 | **NO** | base | base / space-age | vanilla | `assembling-machine` (general) | Player-picked recipe | engine type | - | See the base-game sweep row | RECIPE | base 1a#2; `data/base/prototypes/entity/entities.lua:3163` |
| 64 | **NO** | base | base / space-age | vanilla | `agricultural-tower` | Plants and harvests world plants | engine type | - | See the base-game sweep row | WORLD | base 1a#4 |
| 65 | **NO** | base | base / space-age | vanilla | `asteroid-collector` | Arms grab asteroid chunks | engine type | - | See the base-game sweep row | WORLD, CIRC | base 1a#5 |
| 66 | **NO** | base | base / space-age | vanilla | `lab` | Research from packs | engine type | - | See the base-game sweep row | CORE | base 1a#6 |
| 67 | **NO** | base | base / space-age | vanilla | `beacon` | Projects module effects | engine type | - | See the base-game sweep row | BCAST | base 1a#7 |
| 68 | **NO** | base | base / space-age | vanilla | `accumulator` | Electric buffer | engine type | - | See the base-game sweep row | GEN | base 1a#8 |
| 69 | **NO** | base | base / space-age | vanilla | `reactor` | Fuel to heat; neighbour bonus | engine type | - | See the base-game sweep row | HEAT | base 1a#9 |
| 70 | **NO** | base | base / space-age | vanilla | `burner-generator` | Fuel to electricity | engine type | - | See the base-game sweep row | GEN | base 1a#11 |
| 71 | **NO** | base | base / space-age | vanilla | `heat-interface` | Editor heat source/sink | engine type | - | See the base-game sweep row | HEAT | base 1a#13 |
| 72 | **NO** | base | base / space-age | vanilla | `infinity-container` | Editor item source/sink | engine type | - | See the base-game sweep row | ITEMSET, NET | base 1a#14 |
| 73 | **NO** | base | base / space-age | vanilla | `infinity-pipe` | Editor fluid source | engine type | - | See the base-game sweep row | ITEMSET | base 1a#15 |
| 74 | **NO** | base | base / space-age | vanilla | `proxy-container` | Another entity's inventory | engine type | - | See the base-game sweep row | XENT | base 1a#16 |
| 75 | **NO** | base | base / space-age | vanilla | `linked-container` | Shared inventory by link id | engine type | - | See the base-game sweep row | XENT | base 1a#17 |
| 76 | **NO** | base | base / space-age | vanilla | `cargo-landing-pad` | Receives pods from orbit | engine type | - | See the base-game sweep row | CORE | base 1a#19 |
| 77 | **NO** | base | base / space-age | vanilla | `space-platform-hub` | Platform core | engine type | - | See the base-game sweep row | CORE | base 1a#20 |
| 78 | **NO** | base | base / space-age | vanilla | `rocket-silo` | Rocket launch | engine type | - | See the base-game sweep row | CORE | base 1a#21 |
| 79 | **NO** | base | base / space-age | vanilla | `mining-drill` (+ pumpjack) | Mines resources | engine type | - | See the base-game sweep row | MINE | base 1a#22 |
| 80 | **NO** | base | base / space-age | vanilla | `pump` | Moves fluid between segments | engine type | - | See the base-game sweep row | CORE, CIRC | base 1a#24 |
| 81 | **NO** | base | base / space-age | vanilla | `roboport` | Robot network | engine type | - | See the base-game sweep row | NET | base 1a#26 |
| 82 | **NO** | base | base / space-age | vanilla | `programmable-speaker` | Circuit-driven sound | engine type | - | See the base-game sweep row | CIRC | base 1a#27 |
| 83 | **NO** | base | base / space-age | vanilla | `display-panel` | Circuit-driven text | engine type | - | See the base-game sweep row | CIRC | base 1a#28 |
| 84 | **NO** | base | base / space-age | vanilla | `power-switch` | Joins electric networks | engine type | - | See the base-game sweep row | NET, CIRC | base 1a#30 |
| 85 | **NO** | base | base / space-age | vanilla | `valve` | Threshold flow between segments | engine type | - | See the base-game sweep row | CORE | base 1a#31 |
| 86 | **NO** | base | base / space-age | vanilla | `thruster` | Pushes a platform | engine type | - | See the base-game sweep row | CORE | base 1a#32 |
| 87 | **NO** | base | base / space-age | vanilla | `fusion-generator` | Plasma to electricity | engine type | - | See the base-game sweep row | GEN | base 1a#33b |
| 88 | **NO** | base | base / space-age | vanilla | `lightning-attractor` | Lightning to power | engine type | - | See the base-game sweep row | WORLD, GEN | base 1a#33c |
| 89 | **NO** | base | base / space-age | vanilla | `logistic-container` | Logistic chests | engine type | - | See the base-game sweep row | NET | base 1b |
| 90 | **NO** | base | base / space-age | vanilla | `cargo-bay` | Extends hub/pad inventory | engine type | - | See the base-game sweep row | XENT | base 1b |
| 91 | **NO** | base | base / space-age | vanilla | `generator`, `solar-panel` | Generation | engine type | - | See the base-game sweep row | GEN | base 1b |
| 92 | **NO** | base | base / space-age | vanilla | `market` | Trade offers | engine type | - | See the base-game sweep row | CORE | base 1b |
| 93 | **NO** | external | Space Exploration | 532,206 dl | core miner (inferred) | Infinite mixed-resource drill | see ext row | - | See the external-mods sweep row | MINE | ext #43 |
| 94 | **NO** | external | Space Exploration | 532,206 dl | cargo rocket silo, capsule, console, elevator | Interplanetary transport | see ext row | - | See the external-mods sweep row | CORE, UNIT, XENT | ext #44 |
| 95 | **NO** | external | Space Exploration | 532,206 dl | energy beam emitter/injector/receiver, condenser turbine | Power beaming | see ext row | - | See the external-mods sweep row | GEN | ext #45 |
| 96 | **NO** | external | Krastorio 2 | 394,869 dl | `kr-planetary-teleporter` | Player teleport; turret as character sensor | see ext row | - | See the external-mods sweep row | AREA, UNIT | ext #17; `scripts/planetary-teleporter.lua` L27-232 |
| 97 | **NO** | external | Krastorio 2 | 394,869 dl | `kr-tesla-coil` | Charges grid absorbers nearby | see ext row | - | See the external-mods sweep row | CORE, XENT | ext #18 |
| 98 | **NO** | external | Krastorio 2 | 394,869 dl | `kr-shelter`, `-plus` | Spawn point making 120 kW and light | see ext row | - | See the external-mods sweep row | GEN, LIGHT | ext #19 |
| 99 | **NO** | external | Krastorio 2 | 394,869 dl | roboport modes, wind turbine collision | Mode swap; footprint | see ext row | - | See the external-mods sweep row | NET, GEN | ext #20 |
| 100 | **NO** | local | DiscoScience | 335,541 dl | `lab` (vanilla and modded); also disco-science-lite | Labs flash research colours | vanilla labs + render objects; on_tick/nth over labs | - | Lab core; render only | CORE | a-m #27 |
| 101 | **NO** | local | bobplates | 293,209 dl | `bob-void-pump` | Deletes any piped fluid | `furnace` with one void recipe per fluid | - | Wildcard sink / recipe auto-select | RECIPE | a-m #14; `bobplates/prototypes/entity/entities.lua:1169-1200` |
| 102 | **NO** | local | LogisticTrainNetwork | 288,413 dl | LTN stop | Stop with circuit in/out + status light | `train-stop` + lamp + 2 constant combinators; tick state machine | - | Train-stop core; one-field fix: script CC on `TrainStopPrototype` (SPEC 11) | NET | AppA; RESEARCH §2 |
| 103 | **NO** | local | bobenemies | 284,697 dl | `bob-artifact-radar` | Radar scans spawn artifacts at enemy bases | `radar`; `on_sector_scanned` drives a queued chunk scan | - | Charting is the job | AREA | a-m #13; `bobenemies/control.lua:907-945` |
| 104 | **NO** | external | Cargo Ships | 283,934 dl | `oil_rig` | Offshore oil drill | see ext row | - | See the external-mods sweep row | MINE | ext #40 |
| 105 | **NO** | local | angelsrefining | 224,470 dl | sea pump | Fluid extractor anywhere | placeholder swapped to `mining-drill` on an infinite resource | - | Mining | MINE | AppA; RESEARCH §2 |
| 106 | **NO** | local | angelspetrochem | 220,240 dl | `angels-flare-stack`, `angels-clarifier` (angelsrefining) | Fluid voiding | `furnace` + per-fluid void recipes | - | Wildcard sink | RECIPE | a-m #15; `angelspetrochem/prototypes/buildings/flare-stack.lua:14` |
| 107 | **NO** | local | Flare Stack | 177,861 dl | flare stack, incinerators | Void any fluid or item | `furnace`, generated void recipe per fluid/item | - | Wildcard sink | RECIPE | a-m #16; `Flare Stack_4.3.1/data-final-fixes.lua` |
| 108 | **NO** | local | SpidertronEnhancements | 155,199 dl | dummy spidertron | Spider inside a vehicle | `spider-vehicle`; on_tick | - | Vehicle | UNIT | n-z N29 |
| 109 | **NO** | local | EditorExtensions | 142,590 dl | infinity fluid wagon / infinity accumulator | Infinity fluid on rails; configurable source/sink | fluid wagon + infinity pipe teleported every tick; EEI prototype per priority x mode | - | Vehicle; generation/EEI priority | UNIT, GEN | AppA; RESEARCH §2 |
| 110 | **NO** | local | EditorExtensions | 142,590 dl | `ee-infinity-loader`, aggregate chest, super pump | Editor test tools | `loader-1x1` + `infinity-container`; script filters; `offshore-pump`; nth(15) filter sync | - | Loader/infinity/pump cores | CORE | a-m #25; `scripts/infinity-loader.lua:240-265` |
| 111 | **NO** | local | EditorExtensions | 142,590 dl | infinity pipe settings | Infinity pipe settings that survive blueprints | `infinity-pipe`, settings mirrored into a constant combinator | - | Infinity-pipe core; settings are fluid + temperature + mode | CORE, ITEMSET | a-m #26; `scripts/infinity-pipe.lua:1-60` |
| 112 | **NO** | external | Factorissimo 3 | 133,830 dl | factory buildings | Enterable building | see ext row | - | See the external-mods sweep row | XENT | ext #28 |
| 113 | **NO** | external | Factorissimo 3 | 133,830 dl | `borehole-pump` | Surface-native fluid pump | see ext row | - | See the external-mods sweep row | TILE | ext #29 |
| 114 | **NO** | local | SpidertronPatrols | 129,970 dl | `sp-spidertron-dock` | Dock exposing a parked spider's trunk | `proxy-container`; round robin + area search | - | Cross-entity link | XENT | n-z N28; AppA |
| 115 | **NO** | local | KS_Power | 125,584 dl | `wind-turbine-2` | Constant generator | EEI, data only | - | Generation | GEN | a-m #24; `KS_Power_2.1.0/prototypes/turbine.lua:29` |
| 116 | **NO** | local | PlanetsLib | 124,850 dl | `*-ground-digger` | Drill-like digger off-resource | assembler with per-planet recipe, placed from a drill item; events | - | Per-surface recipe; no loop to remove | TILE | n-z N23; `scripts/ground-diggers.lua:380` |
| 117 | **NO** | local | PlanetsLib | 124,850 dl | per-planet entity replacements | Place X on planet Y, get X' | `create_entity` swap copying ~15 fields | - | Surface-dependent prototype variant | TILE | n-z N24; `scripts/entity-replacement.lua:20-35,503-533` |
| 118 | **NO** | pY | pycoalprocessing | 118,170 dl | `beacon-AMx-FMy`, `diet-beacon-*` | Frequency-tuned beacons | 50 beacon prototypes, frequency in the name, fast-replace swap | - | Beacon core; settings on a beacon | BCAST | n-z N18; `pycp/scripts/beacons.lua:160-180` |
| 119 | **NO** | pY | pycoalprocessing | 118,170 dl | programmable inserter + `py-dynamic-inserter-target` | Inserter aimed at a chosen inventory | `inserter` + `proxy-container`; events | - | Inserter core (proxy-container already native) | CORE | n-z N19; `pycp/scripts/programmable-inserter.lua:333-483` |
| 120 | **NO** | external | Kux Orbital Ion Cannon / Teleporters | 107,160 dl | ion cannon targeter; teleporter | Orbital strike; player teleport | see ext row | - | See the external-mods sweep row | UNIT | ext #48; `src/control.lua` L247; `script/teleporters.lua` |
| 121 | **NO** | pY | pyalienlife | 106,253 dl | `ocula` (+ beam, map tag) | Personal-logistics courier | `unit` + script inventory; nth(43) chart-tag churn, nth(221) player pass | - | Moving core | UNIT | n-z N2; `pyal/scripts/ocula/ocula.lua:47-50,378` |
| 122 | **NO** | pY | pyalienlife | 106,253 dl | bhoddos culture | Random atomic-rocket side effect | `assembling-machine`; nth(423) reads `crafting_progress` + RNG; one-shot `on_nth_tick(future)` | - | Crafter with recipes (2.1.12 `raise_on_crafted` already removes the poll) | RECIPE | n-z N6; `pyal/scripts/turd/bhoddos.lua:20` |
| 123 | **NO** | pY | pyalienlife | 106,253 dl | `crawdad`, `dingrido`, `phadaisus`, spidertron mount | Burner-fed mounts with a grid | `car`/`spider-vehicle`; nth(239) moves burner fuel into equipment energy | - | Moving core; vehicle burner-to-grid link | UNIT | n-z N7; `pyal/scripts/mounts/mounts.lua:75-101` |
| 124 | **NO** | pY | pyalienlife | 106,253 dl | `wyrmhole` + `wyrmhole-skin` | Paired teleport chest | `linked-container` + `lamp` as a visual layer; events only | - | Shared inventory across entities (forbidden indirection) | XENT | n-z N8; `pyal/scripts/worm/worm.lua:14-24` |
| 125 | **NO** | pY | pyalienlife | 106,253 dl | `mega-farm` | Launch seeds to grow a 23x23 crop patch | `rocket-silo` as timed harvest; events only (fences, landfill, resource creation) | - | Recipe selection + resource creation; nothing polled | RECIPE | n-z N9; `pyal/scripts/smart-farm/smart-farm.lua:71-200` |
| 126 | **NO** | pY | pyalienlife | 106,253 dl | slaughterhouse and other recipe-viewer machines | Custom recipe picker GUI | `assembling-machine`; raw `on_tick` per player polling `get_recipe()` | - | Recipe selection; wants `on_recipe_changed` | RECIPE | n-z N10; `pyal/scripts/slaughterhouse/slaughterhouse.lua` |
| 127 | **NO** | pY | pyalienlife | 106,253 dl | `ulric-man` | Transformed player | `character` swap, nth(397) | - | Player character, not a building | UNIT | n-z N11; `pyal/scripts/ulric/ulric.lua:39-90` |
| 128 | **NO** | local | nixie-tubes | 101,530 dl | nixie tubes | Digit display of a signal | `lamp` + render sprites; on_tick round robin `get_signal` | - | Circuit input + text display | CIRC | n-z N25 |
| 129 | **NO** | pY | pyalternativeenergy | 93,170 dl | `hawt-*`, `vawt-*`, multiblade turbines | Wind power | `solar-panel` + `solar_coefficient_property`; collision entity; nth(61) animation | - | Generation, already engine-driven (the success case) | GEN | n-z N13; `pyae/scripts/wind/wind.lua:53,124` |
| 130 | **NO** | pY | pyalternativeenergy | 93,170 dl | `tidal-mk01..04` (+ `-solar`) | Tidal power | placer -> `simple-entity-with-owner` + hidden `solar-panel`; nth(83) global | - | Generation | GEN | n-z N14; `pyae/control.lua:47-67`, `pyae/scripts/tidal.lua:46` |
| 131 | **NO** | pY | pyalternativeenergy | 93,170 dl | `solar-tower-building` + 33 heliostat variants | Heliostat tower | `boiler` whose fuel fluid Lua writes (`set_fluid`, nth(60)); heliostats recreated to rotate | - | Script-scaled output temperature (generation, gap 11) | GEN | n-z N15; `pyae/scripts/thermosolar/heliostat.lua:50,78,200-208` |
| 132 | **NO** | pY | pyalternativeenergy | 93,170 dl | `sut` (+ panels, placement entity, smoke) | Solar updraft tower | EEI; nth(60) writes `power_production` from daylight | - | Generation | GEN | n-z N16; `pyae/scripts/thermosolar/solar-updraft-tower.lua:129-183` |
| 133 | **NO** | pY | pyalternativeenergy | 93,170 dl | `microwave-receiver` | Power from satellites | EEI, `power_production` set on launch/build; event-only | - | Generation | GEN | n-z N17; `pyae/scripts/microwave-receiver.lua:109-135` |
| 134 | **NO** | external | Maraxsis | 86,615 dl | `maraxsis-pressure-dome` | Dry buildable dome | see ext row | - | See the external-mods sweep row | AREA | ext #21 |
| 135 | **NO** | external | Maraxsis | 86,615 dl | `maraxsis-fishing-tower` | Agri tower harvesting fish | see ext row | - | See the external-mods sweep row | WORLD, UNIT | ext #22 |
| 136 | **NO** | external | Maraxsis | 86,615 dl | duct exhaust, trench duct, hydro-plant module variant | Pipe rules; cross-surface duct | see ext row | - | See the external-mods sweep row | XENT, RECIPE | ext #23 |
| 137 | **NO** | local | Cerys-Moon-of-Fulgora | 79,117 dl | radiative tower | Radius grows with temperature | `reactor` + hidden reactor + lamp, prototype per radius; tick + 20-tick loops | - | Heat emitter with runtime radius | HEAT | AppA; RESEARCH §2 |
| 138 | **NO** | local | Cerys-Moon-of-Fulgora | 79,117 dl | frozen placeholders (`*-wreck-frozen`, tower/reactor frozen) | Ruins that thaw | various cores; checked every 15 ticks for `not frozen`, then fast-replaced | - | Freeze/thaw event | FREEZE | a-m #6; `scripts/cryogenic-plant.lua:7-30` |
| 139 | **NO** | local | Cerys-Moon-of-Fulgora | 79,117 dl | `cerys-fulgoran-cryogenic-plant`, `-crusher` quality upgrade | Upgrade recipe swaps the machine to next quality | crafters; `tick_20` scan + every-tick watch, then swap | - | Crafter with recipes (`raise_on_crafted` already fixes the watch) | RECIPE | a-m #7; `scripts/cryogenic-plant.lua:198-325` |
| 140 | **NO** | local | Cerys-Moon-of-Fulgora | 79,117 dl | `cerys-fulgoran-reactor` (active) | Repaired reactor with radiation particles | `reactor`; interval tick | - | Heat output | HEAT | a-m #8; `scripts/nuclear-reactor.lua:26-220` |
| 141 | **NO** | local | Cerys-Moon-of-Fulgora | 79,117 dl | `cerys-radiative-heater` | Player-built heater | burner `reactor`; temperature drop every 16 ticks | - | Heat output / ambient loss | HEAT | a-m #9 |
| 142 | **NO** | local | Cerys-Moon-of-Fulgora | 79,117 dl | `cerys-charging-rod` | Lightning rod, circuit polarity | `accumulator` + glow/lamp children; 12-tick loop | - | Power storage | GEN | a-m #10; `scripts/charging-rod.lua:88-300` |
| 143 | **NO** | local | Cerys-Moon-of-Fulgora | 79,117 dl | heat pipes, boilers (cooling) | Cold-planet heat loss | vanilla heat entities; tick_30/60 writes `temperature` | - | Ambient heat loss | HEAT | a-m #11; `scripts/cooling.lua` |
| 144 | **NO** | local | minimalist-rails | 68,484 dl | `hidden-rail-pole` | Rails carrying power and signals | `electric-pole` per rail piece, wired on build | - | Rail core, power distribution | NET | a-m #17; `control.lua:45-95` |
| 145 | **NO** | external | IR3 | 65,774 dl | teleporters, fissures, forestry (inferred, 1.1) | Teleport; ebbing resources; trees | see ext row | - | See the external-mods sweep row | UNIT, MINE | ext #46 |
| 146 | **NO** | local | planet-muluna | 63,938 dl | heat assembling machines (+ `-reactor`) | Crafter that also emits heat | assembler + hidden `reactor`, linked fluid box; nth(30) wire retry | - | Heat output; crafter with recipes | HEAT, RECIPE | n-z N21; AppA; `mul/scripts/heat-assembling-machine.lua` |
| 147 | **NO** | local | planet-muluna | 63,938 dl | burner roboports + refueler | Roboport on propellant | `roboport` + fluid-fuelled assembler with `raise_on_crafted` | - | Roboport core | NET | n-z N22; AppA |
| 148 | **NO** | local | corrundum | 61,554 dl | `pressure-lab` | Lab accepting only non-normal quality | `lab` + nth(45) | - | Lab core; one-field fix: quality filter on lab input (SPEC 11) | CORE | AppA; RESEARCH §2 |
| 149 | **NO** | local | cybersyn | 60,371 dl | `cybersyn-combinator` + `-output` (project-cybersyn) | Station controller | `arithmetic-combinator` + hidden constant combinator, settings bit-packed | - | Combinator / train-stop core | CORE, NET | n-z N33; AppA |
| 150 | **NO** | external | Renai Transportation | 58,623 dl | thrower inserters, bounce plates, ziplines, ramps | Transport gimmicks | see ext row | - | See the external-mods sweep row | CORE | ext #30 |
| 151 | **NO** | external | Bio Industries | 55,109 dl | bio farm, solar boiler, bio cannon, rail power | Crafter with own solar; artillery | see ext row | - | See the external-mods sweep row | GEN, CORE | ext #41 |
| 152 | **NO** | local | Updated_Construction_Drones | 51,945 dl | construction drones | Drones carrying items | `unit` + off-map proxy chest per drone | - | Moving core | UNIT | n-z N30 |
| 153 | **NO** | external | Castra / Castra Prime | 50,274 dl | data collector, combat roboport | Item spawner; robot spawns | see ext row | - | See the external-mods sweep row | UNIT, NET | ext #36 |
| 154 | **NO** | external | Nullius | 47,384 dl | wind, geothermal, solar collectors, thermal tanks, turbines | Power and heat | see ext row | - | See the external-mods sweep row | GEN, HEAT | ext #31 |
| 155 | **NO** | external | Nullius | 47,384 dl | large beacons | Beacons with interference | see ext row | - | See the external-mods sweep row | BCAST | ext #32 |
| 156 | **NO** | local | LTN_Content_Reader | 46,946 dl | content readers (also Cybersyn-Content-Reader) | Combinator showing network state | `constant-combinator` written from another mod's state; stride | - | Data source is another mod; CC already native | NOTHING | a-m #22 |
| 157 | **NO** | local | Factorio-Tiberium | 45,770 dl | control node | Scaling area bonus | `beacon` + hidden beacon with N script-computed modules | - | Effect broadcast | BCAST | AppA; RESEARCH §2 |
| 158 | **NO** | local | Factorio-Tiberium | 45,770 dl | node harvesters, spike, detonation charge, network node | Extractors on Tiberium nodes | `mining-drill` cores; build swaps | - | Mining | MINE | a-m #12 |
| 159 | **NO** | external | Paracelsin | 45,263 dl | `pressure-turbine` | Generator on vents | see ext row | - | See the external-mods sweep row | GEN | ext #37 |
| 160 | **NO** | external | Rubia | 44,975 dl | trashsteroid collectors | Catch asteroid projectiles | see ext row | - | See the external-mods sweep row | CORE | ext #38 |
| 161 | **NO** | external | Exotic Industries (+ESI) | 34,971 dl | black hole, fusion reactor, induction matrix | Late-game power | see ext row | - | See the external-mods sweep row | GEN | ext #33 |
| 162 | **NO** | external | Exotic Industries (+ESI) | 34,971 dl | matter stabilizer, beacon fluid rules, drone port, gate | Range gate; pipes; character; teleport | see ext row | - | See the external-mods sweep row | AREA, CORE, UNIT | ext #34 |
| 163 | **NO** | external | Ultracube | 28,129 dl | `cube-beacon` | Beacon gated by hidden assembler | see ext row | - | See the external-mods sweep row | BCAST | ext #24; `scripts/linked_entities.lua` L114-129 |
| 164 | **NO** | external | Ultracube | 28,129 dl | `cube-cyclotron` | Crafter with hidden 240 MJ EEI | see ext row | - | See the external-mods sweep row | RECIPE | ext #25 |
| 165 | **NO** | external | Ultracube | 28,129 dl | antimatter/nuclear reactors, local turbine, bulkframe | Power plants | see ext row | - | See the external-mods sweep row | GEN, HEAT | ext #26 |
| 166 | **NO** | external | Ultracube | 28,129 dl | experimental teleporter; beacon overload | Silo; beacon-count gate | see ext row | - | See the external-mods sweep row | CORE, VCRAFT | ext #27 |
| 167 | **NO** | external | Lignumis | 26,796 dl | `provisional-rocket-silo` | Wooden silo | see ext row | - | See the external-mods sweep row | CORE | ext #35 |
| 168 | **NO** | local | rigor-module | 24,733 dl | crafters with rigor module | Module that changes the machine | prototype explosion + fast-replace; nth(15) | - | Crafter with recipes; module-change event on crafters | RECIPE, VCRAFT | n-z N27 |
| 169 | **NO** | external | Warptorio Space Age | 14,328 dl | warp platform, teleporters, linked belts, combinator | Moving base | see ext row | - | See the external-mods sweep row | XENT | ext #39 |
| 170 | **NO** | local | sun_heat_and_cooling | 12,207 dl | `sun_heat_cooler_1/2` | Lightning absorber turned into power | `lightning-attractor` + cosmetic children | - | Generation (lightning) | GEN | n-z N32 |
| 171 | **NO** | local | Inter-Platform-Logistics | 9,703 dl | antennas | Circuit-driven platform request endpoint | `display-panel` copy; on_tick load spreader, nth(60) | - | Circuit input; remote inventories | CIRC, XENT | a-m #23; `scripts/logistic_system.lua:8-110` |
| 172 | **NO** | pY | pyhardmode | 7,884 dl | `py-coal-powerplant-mk01..04` (+ picture/animation) | Coal heat plant | assembler re-typed to `reactor` in data-final; `simple-entity-with-owner` picture swapped on nth(87) when `energy ~= 0` | - | Heat output; the swap exists because a reactor has no working animation | HEAT | n-z N20; `pyhm/control.lua:51-73`, `pyhm/prototypes/heat.lua:179-265` |
| 173 | **NO** | local | 0-things | 6,568 dl | invisible combinators, invisible land mine | Child helpers for compound Things | combinator / land-mine cores, event-driven | - | Combinator logic, circuit input; arbitrary tags exceed 4 scalar settings | CIRC, CORE | a-m #18; `0-things_0.6.7/data/combinators.lua:1-60` |
| 174 | **NO** | local | GhostScanner4 | 4,597 dl | `ghost-scanner` | Lists ghosts in its logistic network | `constant-combinator`; stride | - | Network query | AREA | a-m #21 |
| 175 | **NO** | local | PowerPlusPowerMeter | 3,172 dl | `power-meter-usage-combinator` (+3 interfaces) | Network load per priority | `constant-combinator` + 3 EEIs refilled each update | - | Electric network statistics | NET | n-z N26; AppA |
| 176 | **NO** | external | Biter Power | 2,508 dl | treadmill, incubator, escapables | Caged biters make power | see ext row | - | See the external-mods sweep row | GEN, RECIPE | ext #42 |
| 177 | **NO** | local | cybersyn2 | 2,103 dl | wagon-contents reader | Read wagon at stop | combinator + proxy-container (via 0-things) | - | Combinator core; cross-entity proxy | CORE, XENT | AppA; RESEARCH §2 |
| 178 | **NO** | local | cybersyn2 | 2,103 dl | `cybersyn2-combinator` | Station/depot controller | combinator Thing with tags, graph edges, hidden constant combinators | - | Combinator core, circuit input, structured tags | CIRC, NET | a-m #19; `prototypes/entity.lua:100-225` |
| 179 | **NO** | local | bottleneck-analyzer | 1,661 dl | every crafter | Status light overlay | vanilla crafters + renders; nth polling `status` | - | Watches vanilla types; needs a general `on_entity_status_changed` | VCRAFT | a-m #28 |
| 180 | **NO** | local | AlertScanner | 1,570 dl | `alert-scanner` | Outputs logistic alert counts | `constant-combinator` + lamp + decoy ghosts; on_tick | - | Logistic membership; alert query | NET, AREA | a-m #20 |
| 181 | **NO** | local | Verbose-Engineering | 1,331 dl | rocket silos | Silo with assembler circuit modes | `rocket-silo` + circuit helper combinator; tick | - | Silo core | CORE | n-z N31; AppA |
| 182 | **NO** | base (script) | core/lualib `silo-script` | scenario | core/lualib `silo-script` | Victory on launch | no entity polling | - | Nothing to simplify / out of scope | NOTHING | base §2#1 |
| 183 | **NO** | base (script) | core/lualib `space-finish-script` | scenario | core/lualib `space-finish-script` | Victory at solar-system edge | no entity polling | - | Nothing to simplify / out of scope | NOTHING | base §2#2 |
| 184 | **NO** | base (script) | core/lualib `crash-site` | scenario | core/lualib `crash-site` | Opening wrecks | no entity polling | - | Nothing to simplify / out of scope | NOTHING | base §2#3 |
| 185 | **NO** | base (script) | scenario `rocket-rush` market/trash | scenario | scenario `rocket-rush` market/trash | Buy with coins | no entity polling | - | Nothing to simplify / out of scope | CORE | base §2#8 |
| 186 | **NO** | base (script) | scenarios `wave-defense`, `pvp` | scenario | scenarios `wave-defense`, `pvp` | Setup | no entity polling | - | Nothing to simplify / out of scope | NOTHING | base §2#9 |
| 187 | **NO** | base (script) | core/lualib `production-score` | scenario | core/lualib `production-score` | Price computation | no entity polling | - | Nothing to simplify / out of scope | NOTHING | base §2#10 |
| 188 | **NO** | external | AAI Vehicles | n/a | miners, haulers | Mobile mining vehicles | see ext row | - | See the external-mods sweep row | UNIT | ext #47 |
| 189 | **NO** | pY | pyalternativeenergy | census 0 | `aerial-blimp-mk01..04` (+ `<name>-accumulator`) | Flying turbines | `unit` + one accumulator per network x tier credited by distance | - | Moving core + generation | UNIT, GEN | n-z N12; `pyae/scripts/aerial.lua:393-433,778` |

---

## 2. Totals

| Source | FULL | PARTIAL | NO | Rows |
|---|---:|---:|---:|---:|
| Local library, excluding pY (a-m, n-z, AppA) | 7 | 11 | 43 | 61 |
| pY (pyalienlife, pyalternativeenergy, pycoalprocessing, pypetroleumhandling, pyhardmode) | 4 | 4 | 20 | 28 |
| Base game: entity types | 2 | 10 | 30 | 42 |
| Base game: scenario / campaign scripts | 4 | 0 | 6 | 10 |
| External (popular mods not in the library) | 5 | 11 | 32 | 48 |
| **All** | **22** | **36** | **131** | **189** |
| Mods only (local + pY + external) | 16 | 26 | 95 | 137 |

The local, pY and external rows match the sweeps' own counts: n-z 4/9/33, a-m 2/3/23, AppA 8/9/23 less the
overlaps, ext 5/11/32. The base rows match base's "FULL 6, PARTIAL 10, NO 36".

**Distinct mods touched: 71.** That is 66 mod labels in the table. Five secondary mods share a row with a sibling:
Castra Prime, Exotic Space Industries, Teleporters, disco-science-lite and Cybersyn-Content-Reader. By source:
- Local library excluding pY: 41 mods (42 with aai-loaders, already solved).
- pY: 5 mods. pyindustry, pyrawores, pyhightech and pyfusionenergy have no scripted building (n-z §3.6).
- External: 25 mods.

The sweeps also read about 240 mods and found nothing to convert. Those are listed under "skipped" or "checked with
nothing to convert" in a-m, n-z and ext.

---

## 3. Wube's own types that are shapes of this one

Of 42 vanilla entity types, 2 are FULL instances and 10 are PARTIAL (base 1a, 1b). Only the PARTIAL rows have
anything missing, so the third column below names the gap for those.

| Type | Verdict | What is missing |
|---|---|---|
| `assembling-machine` with `fixed_recipe` | FULL (S3) | Nothing. It already is the no-Lua converter (SPEC 11). The captive spawner alone is PARTIAL because of `production_health_effect`. |
| `container` | FULL (S0) | Nothing (SPEC 12: "exact") |
| `furnace` | PARTIAL | Recipe-by-input. FULL only for a one-recipe category. |
| `boiler` / heat-exchanger | PARTIAL | Continuous energy-proportional conversion; heat-in-place mode |
| `fusion-reactor` | PARTIAL | A second energy source; neighbour plasma pass-through; demand-scaled usage |
| `electric-energy-interface` | PARTIAL | The production half is generation (the consumer half is S1) |
| `offshore-pump` | PARTIAL | The fluid comes from the tile; circuit enable |
| `radar` | PARTIAL | Charting itself (the cycle + energy half fits, with a handler) |
| `lamp` | PARTIAL | Circuit colour/enable. A 1/60 s cycle used only for darkness gating costs more than the lamp. |
| `temporary-container` | PARTIAL | `destroy_on_empty` / `time_to_live` / timed alert without Lua |
| `storage-tank` | PARTIAL | A fluid read in `circuit_outputs = "contents"` |
| `constant-combinator` | PARTIAL | Player-edited sections in the GUI |

The other 30 types are NO, and base's headline groups why:
- recipe selection: the general assembling machine
- generation: accumulator, burner-generator, generator / solar-panel, fusion-generator
- world interaction: mining drill, agricultural tower, asteroid collector, lightning attractor
- network role: roboport, logistic container, power switch
- rockets and platforms: silo, landing pad, hub, cargo bay, thruster
- broadcast: beacon
- cross-entity links: proxy, linked
- circuit-driven: speaker, display panel, pump
- other: valve, lab, market, infinity chest and pipe, heat-interface, reactor

Base's own conclusion: the special types since 0.17 each add a world interaction or a network role, not a set of
parts. In vanilla, the composed axis (inventories + energy + fluid boxes + timer) is already covered by the
fixed-recipe assembler plus `raise_on_crafted` (2.1.12).

---

## 4. What most often blocks FULL

Counted over the 167 PARTIAL and NO rows. "Rows" counts every row that names the capability. "Sole" counts the rows
where it is the only blocker, so adding it alone would lift those rows. "Kind" says whether it could be a part of
this type at all:
- **part**: a v2 candidate.
- **core**: a different entity type, not a part.
- **excluded**: forbidden by SPEC 0.

| Rank | Capability | Kind | Rows | Sole | Examples |
|---:|---|---|---:|---:|---|
| 1 | CORE: other fixed cores | core | 29 | 19 | programmable inserter (pY), Lignumis silo, SE meteor defence |
| 2 | **GEN: power generation / storage** | part | 27 | 16 | pY SUT / heliostat tower / tidal; K2 shelter and intergalactic transceiver (activated form); Nullius power line |
| 3 | UNIT: moving core | core | 22 | 10 | pY caravans and ocula; Transport Drones; Updated_Construction_Drones |
| 4 | **RECIPE: recipe selection** | part (wildcard sink only) | 17 | 10 | pY farms and vat brain; bob void pump, Angels flare stack, Flare Stack (wildcard sinks, 3 rows sole); slaughterhouse picker |
| 5 | NET: robot / logistic / train / electric network role | core | 16 | 7 | LTN stop; Maraxsis regulator; Nanobots2 roboport interface |
| 6 | AREA: world or network query stays Lua | core (the timer goes, the search stays) | 15 | 8 | Renai vacuum hatch; Muluna satellite radar; spoilage-scanner |
| 7 | **CIRC: circuit input read** | part | 13 | 5 | rec-blue-plus deployer; nixie tubes; pY aerial base; vanilla lamp |
| 8 | XENT: cross-entity link | excluded | 12 | 7 | pY wyrmhole; SpidertronPatrols dock; Factorissimo buildings |
| 9 | **HEAT: heat output** | part | 10 | 7 | Cerys reactor / heater / radiative tower; pyhardmode coal powerplant; Muluna heat assembler |
| 10 | MINE: resource search | core | 7 | 6 | pY seep derricks; Cargo Ships oil rig; SE core miner |
| 11 | **BCAST: effect broadcast** | part | 6 | 5 | pY vat brain, AM/FM beacons; Tiberium control node; Ultracube cube-beacon |
| 12 | **ITEMSET: typed settings** | part (SPEC 1.6 v2) | 6 | 2 | QF dedigitizer filter; Transport Drones and Mining_Drones selected item; infinity pipe |
| 13 | **VCRAFT: field on vanilla crafters** | one-field elsewhere | 5 | 2 | pY farms (`require_module`, census 5,100); TURD beacons (base effect on vanilla, census 2,176); bottleneck-analyzer (status event) |
| 14 | **TILE: surface / tile-derived product** | part | 5 | 3 | offshore pump; PlanetsLib ground digger; Factorissimo borehole pump; Muluna telescope |
| 15 | WORLD: plants / asteroids / lightning | core | 4 | 1 | agricultural tower; asteroid collector; Maraxsis fishing tower |
| 16 | **FREEZE** | part | 2 | 2 | Cerys teleporter; Cerys frozen placeholders |
| 16 | **PLACE: placement on resources** | part (placement rule) | 2 | 2 | Tiberium growth accelerator, monoculture |
| 16 | **CONT: continuous process** | part | 2 | 2 | boiler; fusion reactor |
| 16 | **PERCYC: per-entity cycle cost** | part | 2 | 1 | SE delivery cannon; EI neutron collector |
| 16 | LIGHT | part | 2 | 0 | Bio Industries arboretum; K2 shelter |
| 21 | LIFE, FLUIDREAD, CCEDIT, ENRULE | part | 1 each | 1, 1, 1, 0 | temporary-container; storage-tank; constant-combinator; K2 transceiver |

**Ranked v2 candidates** (part-level only, by rows unlocked when added alone):
1. **Generation part** (16 sole, 27 named). Ext calls it "the strongest argument for the v2 generator part"; the
   pY solar family alone is five rows. Precedent: `solar_coefficient_property` already moved pY wind/tidal power into
   the engine (pyanodons §4).
2. **Heat output** (7 sole, 10 named). Five of the ten are Cerys entities.
3. **Effect broadcast** (5 sole, 6 named). The highest-count single entity behind it is the pY vat brain, census
   1,178 plus 1,178 hidden beacons in A2_Fixed.
4. **Circuit input read / circuit-driven start** (5 sole, 13 named). SPEC 6 already rules out a signal-changed event
   (the changed flag is assumed not to be save/load stable), so any read part would still poll.
5. **Wildcard ingredient** (3 sole), the only recipe-selection case small enough to be a part. a-m notes it is cheap
   engine-side but "recipe selection under another name".
6. **Surface/tile-derived products** (3 sole, 5 named).
7. **Typed settings** (2 sole, 6 named; already v2 in SPEC 1.6).
8. **Freeze status on S0, placement on resources, continuous process** (2 sole each).

**The largest-count families are blocked by changes to vanilla crafters, not by anything in this type.** pY farms
(census 5,100), TURD hidden beacons (2,176) and vat brains (1,178) are NO under v1. The first two flip with
`require_module` on `CraftingMachinePrototype` and with a runtime base effect on vanilla crafters (SPEC 11, AppA). The
vat brain needs broadcast.

---

## 5. Spec gaps: what the sweeps found that SPEC's part list cannot express but should

New gaps (no SPEC section covers them):

| # | Gap | Found in | One-line proposal |
|---|---|---|---|
| G1 | A composed machine cannot sit on a resource entity, so Tiberium keeps a `mining-drill` placeholder swapped on build | a-m #4, #5 (2 rows, sole blocker) | Add `placeable_on_resources = {resource categories}` to the prototype (a placement rule, no runtime cost) |
| G2 | S0 has no `status_changed` (SPEC 1.7 requires S1-S3), so the engine's own transitions on a passive instance (`frozen`, SPEC 5 order 4) go unreported | a-m #3, #6 (Cerys, 5 entity kinds polled every 15 ticks) | Allow `events.status_changed` on S0 for engine-originated transitions only (frozen, disabled, deconstruction); no tick-watch needed |
| G3 | No wildcard ingredient: four mods build "void anything" from furnaces with one generated recipe per fluid/item | a-m #14-16 (bobplates, angelspetrochem/angelsrefining, Flare Stack) | `ingredients = {{type = "fluid", any = true, amount = n, fluidbox_index = k}}`: consume whatever the box holds, no product |
| G4 | Conditions are evaluated only for cycle start (SPEC 1.5), so an S0 cannot show "empty" or "missing filter" status | n-z P2 (pY ipod status sprites) | Evaluate `inventory_*` conditions on transfer for S0 and let the first failing one set status (they are already "evaluated on transfer") |
| G5 | Conditions gate cycle start, not `activity`, so darkness gating needs a fake 1/60 s cycle | base 1a#29 and Notes (lamp anti-pattern) | Let `powered` / `daylight` conditions gate `activity` on S1, not only cycle start |
| G6 | `circuit_outputs = "contents"` sums inventories only, with no fluid | base 1b (storage-tank) | Add fluid boxes to the `contents` read (amount per fluid; temperature signal optional) |
| G7 | No self-destroy on empty or expiry | base 1a#18 (temporary-container) | Carry `destroy_on_empty`, `time_to_live`, `alert_after_time` from `TemporaryContainerPrototype` as optional S0 fields |
| G8 | The process is always discrete with fixed amounts, so it matches boiler/fusion rates only at full load | base 1a#10, #33a, Notes | `process.mode = "continuous"`: consume and produce per tick in proportion to energy received and output space |
| G9 | Products are fixed per prototype, but some depend on the surface or tile | base 1a#23, n-z P5/N23/N24, ext #29 (5 rows) | `products_by_surface` (or `products_from_tile` for fluids) keyed by surface property / tile fluid, resolved at build time |
| G10 | No "a stack is full" / "at least n of one item" gate. Renai's cannon needs `start = "script"` from `inventory_changed` | ext #1 | Condition `inventory_at_least {inventory, count, per_item = true}` |
| G11 | No fluid-level window in the graphics set, so pY keeps a fill sprite render object | n-z F3 (tailings pond) | Accept `StorageTankPrototype`'s window / `fluid_level` visualisation keyed to a fluid box |
| G12 | `production_health_effect` is not in SPEC 1.1 | base 1a#1 (captive biter spawner) | Add the crafter field, applied per cycle state |
| G13 | SPEC does not say whether a composed machine may be a hidden part of a compound, which is where Maraxsis would use it | ext #7 and Notes (regulator: per-quality hidden assembler under a roboport) | State that hidden composed prototypes are valid and get the same lifecycle as any hidden entity; list it as a test entity |
| G14 | The sweeps disagree on light: ext records "no light part" (K2 shelter, Bio Industries lamps), while base uses `light` in `working_visualisations` for the lamp row | ext Notes; base 1a#29 | Name `working_visualisations[].light` in SPEC 1.1 as the light part and say whether it follows `draw_in_states` |
| G15 | Per-entity energy per cycle: SPEC 11 offers `local_effect.speed` for cycle time, but distance-dependent recharge also scales energy | ext #9, #14 (EI neutron collector, SE delivery cannon) | Document `local_effect.consumption` as the per-entity energy lever next to `speed` (both rows already have a process) |

Known gaps the sweeps confirm (already in SPEC 11 / 1.6), with the rows they block: generation (27), recipe selection
(17), circuit input (13), heat output (10), broadcast (6), typed settings (6), moving cores (22, gap 13), and the
one-field changes on vanilla types: `require_module`, script CC on `TrainStopPrototype`, quality filter on lab input.

---

## 6. The ten most persuasive conversions

Chosen for the hack replaced, instance counts in the author's saves, and mod popularity.

1. **pY dino dig site** (FULL; census 14; n-z F1, AppA). Today it is an assembling machine kept permanently
   `disabled_by_script` and used only for its inventories, power and GUI. Around it sit a hidden food container, a
   unit plus a proxy entity per trip, and a 61-tick batch over every site; all of it becomes one S3 with four named
   inventories and cycle events. The lab emulation already runs it at 60 ns per instance against 47 for an electric
   furnace, with 1.4 ns of script ([RESULTS](../bench/RESULTS.md) (b)).
2. **pY biofluid provider/requester tanks** (FULL; census 9 + 9 in A2_Fixed; n-z F2). These are furnaces used only
   for a fluid box and a status. They are scanned every 143 ticks, with `get_fluid` calls inside sort comparators,
   and they become S0/S1 with a `fluid_threshold` push. The biofluid loop is rank 1 in pyanodons §3 because it
   scales superlinearly.
3. **aai-signal-transmission sender/receiver** (FULL; 590,476 downloads, the most-downloaded FULL; AppA). A roboport
   with zero radius was picked only for its electric buffer and circuit connector. With two decider combinators on a
   hidden surface and a 30-tick energy poll, it collapses to S1 electric + `circuit_outputs = "script"` +
   `status_changed`.
4. **equipment-gantry** (FULL; 298,377 downloads; AppA). An assembler shell with three hidden containers at rotated
   offsets and a prototype per rotation becomes one S3. Its filtered named inventories do the routing the hidden
   chests fake.
5. **pY LRF panel / stirling concentrator** (FULL, semantics change; pyalternativeenergy 93,170 downloads; n-z F4).
   Every 55 ticks pY writes `disabled_by_script` and `custom_status` on every panel from **nauvis** daylight, which
   is wrong off-planet. As S2 + a `daylight` condition, both the loop and the multi-surface bug go.
6. **Cerys fulgoran wrecks and the contracted radiative-tower container** (FULL; 79,117 downloads; AppA, a-m #1).
   One polls `products_finished` every 15 ticks and the other `get_item_count` every 20 ticks, only to learn that
   something finished or emptied. `cycle_finished` and `inventory_changed` replace the polls with no shell at all.
7. **Renai item cannon** (FULL; 58,623 downloads; ext #1). An EEI plus a hidden chest sits under a global
   `on_nth_tick(1)` dispatcher that checks `energy == buffer` and a full slot. It becomes an S3 with an electric
   buffer, a one-slot inventory and `cycle_finished`, the cleanest external case of the shell-plus-poll pattern.
8. **Krastorio 2 intergalactic transceiver** (PARTIAL; 394,869 downloads; ext #6). Today a per-tick `on_tick`
   computes energy deltas, writes `entity.energy`, and adds **random jitter so the status does not flip to
   "normal"**. A `powered` condition with `status_changed` removes that hack; the activated generator form stays.
9. **Muluna telescope** (PARTIAL; 63,938 downloads; n-z P5). A script-wired hidden constant combinator, restored
   through bplib, is rewritten by default every 6 ticks for every telescope; it is the costliest loop in n-z outside
   pY. `circuit_outputs = "script"` on the machine removes the combinator and its lifecycle glue; only the platform
   data refresh stays.
10. **Wube's own quota chests** (FULL; base §2 #4-7). `supply` (every 60 ticks), `team-production` (nth 29),
    `transport-belt-madness` and `tight-spot` (on_tick) all poll chest contents, and each becomes S0 +
    `inventory_changed`. The milliseconds are small at their scale, but the pattern is in Wube's own scripts.

Left off despite large numbers:
- pY seep derricks (PARTIAL, census 29). The census found 0 hidden `-base` assemblers in all three saves, so the
  hidden-entity half of the case is UNVERIFIED in the author's saves.
- corrundum `ice-box` (FULL with semantics change). It rests on the spoil re-stamp, which boskid has not agreed to
  (SPEC 1.3).
- The three largest-count families: farms 5,100, TURD 2,176, vat brain 1,178. All are NO under v1 (section 4).
