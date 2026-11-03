# Beyond v1: the parts that would let the composed machine extend the game

> Public copy. Engine-internal references from the private working notes have been removed; where a claim rested on them it is marked as an assumption for Wube to confirm.

Revision 2, 2026-11-02 (revision 1 was taken apart by a hostile review from a "Wube engineer" persona, which
checked each mechanism against the engine's public behaviour and documentation; the review is not included in
the public repository; every correction it made is applied here). Companion to `docs/SPEC.md` (v1) and
`docs/WRITEUP.md`. Evidence columns cite `research/CONVERSION-CANDIDATES.md` (189 buildings with blocker
codes; "sole" = rows where that capability is the only thing stopping a FULL conversion; the per-part row lists
are in section 5), `research/RESEARCH.md` section 1 (13 ranked gaps), `research/forum-dropped-features.md`
(53 threads, 2026-11-02) and the public 2.1 Lua API and prototype reference. "UNVERIFIED" marks a claim that
public evidence cannot settle.

## 0. The rule every v2 part has to obey

v1 earns its performance from four properties, and a part that breaks any of them is not a part of this
type, however useful: (1) the part is fixed when the prototype loads and never changes at runtime; (2) an
instance whose parts need no ticking is not on any update list, and one that does tick can sleep; (3) no
Lua runs inside the entity update, only opt-in events flushed after it; (4) the part wraps an existing engine
mechanism, or is small enough to be read in one sitting. Every part below names the mechanism and what it
does to the shape (S0 passive, S1 watcher, S2 timer, S3 machine).

**Coverage.** v1 converts 22 of 189 buildings fully. The parts kept below lift the sole-blocker rows they
own: FULL rises to at least 64 after v2 and 73 after v3 (34 % to 39 %), counting the four two-blocker rows
both of whose blockers ship (Nullius and Ultracube power, K2 shelter, the offshore pump). Counting mods only
(leaving out the vanilla types that are themselves a generator, a reactor, a beacon or a lamp), v2 lifts 29
mod buildings and v3 four more. What stays out is what needs a different core (inserter, roboport, train
stop, silo, moving unit, mining drill: 29 + 16 + 22 + 7 rows), recipe selection (17), or a cross-entity link
(12).

## 1. The parts, ranked

| # | Part | Sole rows (mods / all) | Mechanism wrapped | Shape effect | Size (C++, no GUI) | Stage |
|---|---|---|---|---|---|---|
| 1 | Generation (electric out) | 12 / 16 | the electric energy interface's production side; the burner generator, which already pairs a burner with an electric output on one entity (the two-source precedent) | S3 push per cycle, or S1 while working | 300-500 | v2 |
| 2 | Heat output | 5 / 7 | the reactor's heat buffer and the heat-pipe conduction pass; the owner fills its buffer in its own update, as a reactor does | S3 push per cycle, or S1 while working | 300-400 | v2 |
| 3 | Circuit input: enable condition, signal-bound settings | 2 / 5 | the enable/disable circuit condition every pump and inserter has, with its state-change handling and its place in the control-behaviour pass | none for the condition; settings are pulled by the entity at cycle start | 300-500 | v2 |
| 4 | Trigger on cycle | 1 / 1 (+ every "fires something" building) | the projectile, smoke and area-effect machinery weapons use (trigger items, deliveries and effects) | none | 100-200 | v1.1 |
| 5 | Typed settings and blueprint parameters | 1 / 2 | the constant combinator's signal storage and blueprint parameters | none | 200-300 | v1.1 |
| 6 | Wildcard ingredient | 3 / 3 | fluid half: an unfiltered fluid box; item half: about 100 lines of new consume logic (rule 4's one exception, said plainly) | none | 100-200 | v1.1 |
| 7 | Tile and surface products; placement on resources | 3 + 2 / 3 + 2 | the offshore pump's tile fluid and the mining drill's placement rule (`require_resources_to_place`); the surface-property check behind `surface_conditions` | none (resolved at build) | 200-300 | v2 |
| 8 | Small fields: emissions per cycle, light, destroy on empty, fluid in the contents read, editable sections | 0 / 3 | the pollution emission machines already use, the working-visualisation light, the temporary container's (cargo pod's) fields, the constant combinator's logistic-section GUI | none, except `time_to_live` (S1, updated every N ticks) | 150-250 | v1.1 |
| 9 | Logistic role per inventory | 0 / 0 (NET rows are cores) | the logistic-member behaviour ten types, eight of them not chests, already have (the character, vehicles, the roboport, the rocket silo, the space platform hub, the cargo landing pad among them); the logistic-section GUI; the logistic chest's blueprint storage | none; a logistic chest has no update | 400-700 | v3 |
| 10 | Effect broadcast | 4 / 5 | the beacon's receiver linking; receivers find the beacons around them, so a non-beacon broadcaster is a change in receiver code the effect receiver types share (assumed) | none per tick (beacons do not update every tick, Rseding91, 2024, t=113632) | 500-800 | v3 |

Dropped from revision 1: the solar-curve generation form (`usage_priority = "solar"` is `SolarPanelPrototype`-only,
"ignored otherwise"; the vanilla `solar-panel` with `solar_coefficient_property` already is a tide mill or wind
turbine); electric-in plus electric-out on one entity (one electric source per entity is assumed, and there is
no vanilla precedent for two); heat in plus heat out (one heat buffer per entity, assumed; a thermal battery is
a `heat-pipe` with a large `specific_heat`); the
continuous process mode (the vanilla `boiler` already takes the full energy-source union and converts through
`output_fluid_box`, which 2.1.7 also put on `FluidEnergySource` and `generator`; two rows for 200-400 lines);
`status_changed` on S0 (a container cannot be frozen and has no update, and deconstruction has its own event;
SPEC 1.7 stands); a `surface` setting type (a runtime index, not a prototype id, so it cannot live in a
blueprint); the `resource_present` runtime condition (nothing re-evaluates it once Lua drains the resource).

Total kept: about 2.6 to 4.2 thousand lines before GUI. GUI is not in that figure and is not small: a power
and a temperature readout, a circuit-condition panel, signal and offset choosers, the logistic section panel.
SPEC 11 puts v1's GUI at 1200-2000 lines; v2's is of the same order.

### 1.1 Generation: a machine that makes power

```lua
energy_output = { usage_priority = "secondary-output", output_flow_limit = "5MW", buffer_capacity = "50MJ" },
process = { cycle_time = 10, ingredients = {{type="fluid", name="slag-oil", amount=20}},
            products = {{type = "energy", amount = "20MJ"}, {type="item", name="slag", amount=1}} }   -- S3
-- or: output_power = "2MW" while working, with a burner / fluid / heat source as the fuel side   -- S1/S3
```

One electric source per entity (assumed), so the fuel side is burner, fluid, heat or the process itself; the output
buffer is the electric energy interface's production side filled on cycle finish (or per update while working,
as the burner generator does) and drained by the electric network like any generator. Runtime lever:
`local_effect.productivity` scales energy per cycle through the existing receiver (SPEC 7.2). What it lifts
(section 5): the pY solar family (SUT, heliostat tower, microwave receiver), KS Power's turbine, Cerys's
charging rod, Paracelsin's pressure turbine, Exotic Industries' black hole, the thread t=120072 ("power from
a fluid with a solid byproduct": no way "except through complex compound entity solutions"), and K2's
transceiver activated form. A fully charged **capacitor bank** is not buildable: electric in and electric out
is the dropped case.

### 1.2 Heat output: a machine that heats a heat-pipe network

```lua
heat_buffer = { max_temperature = 600, specific_heat = "10MJ", max_transfer = "2GW", connections = {...} },
products = { {type = "heat", amount = "40MJ"} }      -- or heat_output = "10MW" while working
```

The buffer is `ReactorPrototype`'s `heat_buffer`; conduction is the existing heat-pipe pass, assumed to run
outside the owner's update and charge it nothing (for Wube to confirm). The owner keeps its connections current
on build, in ghost setup and when moved, as a reactor does, and pushes heat in its own update.
Conditions gain `temperature_at_least` / `temperature_below` on the owner's buffer. One buffer per entity:
a heat *input* (`energy_source.type = "heat"`, v1) and a heat *output* are exclusive, so a heat pump
(t=129521) stays out. Lifts Cerys's reactor, heater, radiative tower and cooling boilers, pyhardmode's coal
powerplant, and with 1.1 Nullius's and Ultracube's power buildings; t=130444 (an assembler that emits waste
heat while crafting, today "fake it by having multiple entities") is the blast furnace in section 3. The
2021 request for a crafter with heat output (p=536323) was moved to Won't implement without a stated reason.

### 1.3 Circuit input: an enable condition and signal-bound settings

```lua
circuit_inputs = { enable_disable = true, connect_to_logistic_network = true,
                   settings = { {setting = "rate", signal = "signal-R"} } }
```

The enable condition is the enable/disable circuit condition every pump and inserter has, with its own
state-change handling setting `disabled_by_control_behavior` (SPEC 5, order 3) and putting
the instance to sleep. Control behaviours are assumed to run in their own pass, possibly threaded (for Wube to
confirm), so nothing in it may touch the entity or raise Lua; signal-bound settings therefore
work the way the inserter's stack-size override is assumed to (the entity reads the signal; the behaviour only
holds the flag): the entity reads the bound signal at cycle start and on wake,
writes the setting, and `settings_changed` fires from the entity's own update. Whether a behaviour is
registered only while wired is UNVERIFIED. No
signal-changed event (SPEC 6). Lifts rec-blue-plus's deployer and nixie tubes, and makes every setting
remotely drivable; the darkness gating of a lamp is v1's `daylight` and needs none of this.

### 1.4 Trigger on cycle: a machine that fires, smokes or explodes

```lua
cycle_finished_trigger = { type = "direct", action_delivery = { type = "projectile",
    projectile = "cannon-shell", starting_speed = 1, range_setting = "range" } },
cycle_started_trigger  = { type = "direct", action_delivery = { type = "instant",
    source_effects = { type = "create-trivial-smoke", smoke_name = "kiln-smoke" } } }
```

The trigger machinery weapons use, applied with the entity as source and a target position `range` tiles along its
facing (whether a projectile delivery accepts a position with no target entity is UNVERIFIED). `type = "script"`
effects are **forbidden** inside cycle triggers: a script trigger effect is assumed to raise its Lua event in place
(for Wube to confirm), and the composed events already cover the case.
Lifts Renai's item cannon and SE's delivery cannon without Lua, pY's SUT smoke, kilns that belch, flares,
and any machine that shoots. `created_effect` on `EntityPrototype` is the lifecycle precedent (how it is
applied is UNVERIFIED).

### 1.5 Typed settings and blueprint parameters

v1 settings are `uint32 / int32 / bool`. v2 adds `item`, `fluid`, `signal`, `quality` (stored as the
constant combinator stores a signal, a `SignalID`; its size was not measured) and `offset` (an entity-relative
`MapPosition` that rotates and flips with the blueprint, so a paste never leaves an absolute coordinate
behind). Still at most four, still inline. A signal-typed setting becomes a blueprint parameter through the
same blueprint-parameter path the constant combinator's signals use; not
free, about a day (estimate). Lifts Quantum Fabricator's filter and the depots' "selected item" (Mining Drones,
Transport Drones: today an assembler recipe used as a dropdown), and retires the prototype-per-value
pattern (RealisticReactors' 250 reactor prototypes, t=113731; a Cerys lamp per radius; EditorExtensions'
accumulator per priority times mode).

### 1.6 Wildcard ingredient: sinks without a recipe per fluid

```lua
ingredients = { {type = "fluid", any = true, amount = 100, fluidbox_index = 1} }           -- void anything
ingredients = { {type = "item", any = true, amount = 1, filter = {spoilable = true}} }     -- composter
```

The fluid half is an unfiltered box; the item half is new code: consume the first stack that passes the
filter, and an insertion check that refuses what the filter refuses, so an incinerator does not jam on
what it cannot burn. Three mods generate one recipe per fluid to fake this (bob's void pump, Angel's flare
stack and clarifier, Flare Stack); vanilla's any-fluid void is the `infinity-pipe` in remove mode, which is
assumed to update every tick, so the argument is cost and prototype count, not possibility.

### 1.7 Tile and surface products; placement on resources

`products_from_tile = true` takes the tile's fluid the way the offshore pump does at setup (`LuaTilePrototype.fluid`; so an item from a
tile, a plankton net, is not covered); `products_by_surface = { {property, min, max, products}, ... }` resolves
the product list once at build from the surface properties that `surface_conditions` already read;
`placeable_on_resources = {"hot-rock"}` is the mining drill's `require_resources_to_place` placement rule,
evaluated at placement only. Depletion stays Lua. Lifts Factorissimo's borehole pump, PlanetsLib's ground
digger and per-planet replacements, Muluna's telescope products per planet, Tiberium's node structures
(today a mining-drill placeholder swapped on build).

### 1.8 Small fields

`emissions_per_cycle = {pollution = 5}` through the pollution emission machines already use; `working_visualisations[].light`
named as the light part (a `WorkingVisualisation` already carries a `light`); `destroy_on_empty` from `TemporaryContainerPrototype`;
`time_to_live` / `alert_after_time`, which make the prototype S1, updated every N ticks (the temporary container is
assumed to update every tick, so this is cheaper than the cargo pod, not free); fluid boxes in the
`circuit_outputs = "contents"` read (the storage-tank row); player-editable sections for `circuit_outputs =
"script"` through the logistic-section GUI the constant combinator uses (the constant-combinator row).

### 1.9 Logistic role per inventory (v3)

`inventories[].logistic_mode = "requester" | "buffer" | "passive-provider" | "active-provider" | "storage"`
makes the inventory a logistic member, the behaviour ten types, eight of them not chests, already have. No per-entity
tick; robots and the logistic manager pay as for a chest. The estimate must include ghost setup, the
robot door offsets and a harness matrix for ghost, blueprint, undo and upgrade,
which is where boskid's objection to borrowed inventories lives (t=136024: a proxy "does not own the
inventory it borrows, which means it is not instantly notified of content changes"; a composed machine
owns every inventory it declares, so the objection does not apply). Few conversions; this is the part that
makes new buildings: a requester that cooks, an output slot that provides, a cold store that orders its own
coolant.

### 1.10 Effect broadcast (v3)

```lua
effect_broadcast = { supply_area_distance = 3, distribution_effectivity = 0.5, profile = {1, 0.7, 0.5},
                     while = "always" }    -- or "powered"
```

A non-beacon broadcaster is a change in how receivers find the beacons around them, code the effect receiver types share (assumed; for Wube to confirm);
that is why it is v3. `while = "working"` is gone: every status flip would refresh every receiver in range,
and working-gated broadcasters in each other's range chain. Most of revision 1's unlocks are already
served by `LuaEntity::local_effect` (2.1.13, R/W on every effect receiver): the vat brain writes its own
machine's effect on the same loop it runs today with no hidden beacon, and TURD's 2,176 hidden beacons go
the same way. What is left for a broadcast part: Tiberium's control node, Ultracube's cube beacon, Nullius's
large beacons, pY's AM/FM beacons with a typed `frequency` setting instead of fifty prototypes.

## 2. Considered and not proposed

- **A second process per prototype** (charge plus cooldown, grow plus harvest). Doubles the GUI and the
  validation table. The showcase below avoids buildings that need it; `restart_delay`, `start = "script"`
  and a typed setting cover the cases seen in the sweeps.
- **An equipment grid on a building.** A grid with active equipment is assumed to cost an update every tick,
  which breaks rule (2) for the common case.
- **Two energy sources on one entity** (PennyJim, t=125679: "I'm making a compound entity so I can pretend an
  entity has multiple energy sources"). One energy source per entity is assumed; the burner generator, which
  pairs a burner with an electric output, is the single precedent and is exactly the generation part's
  continuous form. Beyond that, no.
- **Attached child entities** (the engine owning hidden parts the way a spidertron owns its legs). The
  number-one forum gap (about 20 threads, the 23,000-line `0-things` library), but
  Rseding91's 2020 position is "at their core compound entities don't work" (p=512078), and a child is
  still a second entity with its own update, so it buys lifecycle, not performance. v1 removes the need for
  children in every FULL row; keep this as the escape hatch to argue separately, not as a part.
- **Moving cores, mining, network roles beyond logistic points, cross-entity links.** Different types.

## 3. What becomes possible: buildings no mod can ship today

Each is one prototype and at most one event handler. Rows that turned out to be vanilla-buildable in 2.1
(tide mill, thermal battery, biomass boiler, geothermal tap, quality tumbler, composter) were removed by
the review; what is left is not expressible today, and the forum thread is cited where a modder asked.

| Building | Parts | Why it does not exist today |
|---|---|---|
| Aging cellar | v1: storage inventory with `spoil_modifier = 0.25` (faster), filters, `inventory_changed` | No per-container spoil rate; "spoil into" is the aging product. Contested: boskid refused a container spoil multiplier (t=134525, 2026) |
| Smokehouse | v1: burner, storage inventory with `spoil_modifier = 4`, `activity = inventory_not_empty` | A chest cannot burn fuel; the hidden-reactor rig is the only way (t=108882) |
| Housing / always-burning hearth | v1: burner, `activity = "always"`, process with products | "Entities that don't consume power constantly ... are asleep" (t=61277); today a hidden reactor plus nth-tick polling |
| Greenhouse | v1: heat energy source, `daylight` condition, process with products | Heat-powered crafters exist, but not with a daylight gate and no recipe |
| Radio mast | v1: electric watcher, `circuit_outputs = "script"`, `status_changed` | aai-signal-transmission fakes it with a roboport and a hidden surface |
| Powered-state alarm block | v1: electric S1, `power_state_changed` | Asked since 2014 (t=4841), LTN asked for no-fuel (t=64769): "forcing mods to do bad performing polling" |
| Slag generator | v2: fluid energy source, generation per cycle, solid byproduct product | t=120072: no way "except through complex compound entity solutions" |
| Blast furnace with heat recovery | v2: burner, process with products, heat output while working | t=130444: an assembler that emits heat while crafting is faked with "multiple entities" |
| Adjustable reactor | v2: burner, heat output, `int32` output setting bound to a signal | RealisticReactors swaps between 250 reactor prototypes (t=113731) |
| Kiln / incinerator | v1.1: wildcard item ingredient, emissions per cycle, smoke trigger per cycle | Needs a recipe per input today (Flare Stack, Angel's) |
| Mass driver | v1.1: ammo inventory, electric buffer, projectile trigger along facing with a `range` setting | Renai's cannon: EEI, hidden chest and an every-tick dispatcher |
| Solar still | v2: `daylight` condition, timer shape, products by surface property | Needs surface-derived products |
| Hot-rock vent | v2: placement on a resource, timer shape, steam product per cycle | Needs placement on resources without a drill |
| Signal-tuned furnace | v2: process, `rate` setting bound to a signal, enable condition | Needs circuit input on a non-vanilla type |
| Requester that cooks | v3: input inventory as requester, burner, process | Needs a logistic role on a non-chest |
| Tuned broadcast node | v3: effect broadcast while powered, typed `frequency` setting | pY ships fifty AM/FM beacon prototypes |

## 4. Staging

- **v1**: `SPEC.md` as written. 22 FULL, 36 PARTIAL of 189; every "chest plus one thing" and every
  "machine whose rules live in Lua".
- **v1.1, same release**: triggers (1.4), typed settings (1.5), wildcard ingredient (1.6), the small fields
  (1.8). None copies another type's update; each is one call or about a hundred new lines. 550-950 lines.
- **v2**: generation (1.1), heat output (1.2), circuit input (1.3), tile products and placement (1.7).
  1.1-1.7 thousand lines. FULL rises to at least 64 (68 with the two-blocker rows).
- **v3, debated**: logistic roles (1.9) and effect broadcast (1.10), each 400-800 lines and each touching a
  manager other types own; and the attached-children escape hatch, which is a different argument.

## 5. What a Wube engineer would ask for next, and the per-part row lists

The review's list, kept here as the work order before v2 is argued in earnest:

1. **Behaviour confirmed, not assumed**: how effect receivers enumerate the beacons around them; whether one
   entity can carry two electric sources; whether a projectile delivery accepts a position with no target
   entity; how `created_effect` is applied; how the inserter reads its stack-size signal; what activates a
   control behaviour.
2. **The shape model re-measured with the v2 axes: DONE** (`model/RESULTS-v2.md`). With an electric or heat
   output pushed on cycle finish, a circuit enable that sleeps the machine and a trigger on finish, keeping the
   four v1 shapes and testing the energy-output pointer only at the push (variant D1) runs at 0.95-1.02 of the
   static baseline with shuffled update lists; multiplying shapes (D2: six machine shapes, one bucket each)
   runs at 0.96-1.01 and buys nothing measurable, at about 100 bytes of code and one type-order slot per extra
   shape. Variant B's cost returns only if the parts become runtime slots in a class shared with passive
   entities (B2: 1.08-1.12 at 1M, where a 112-byte chest costs cache lines). One trap found: if each shape
   instantiation gets its own copy of the functions inserters call (inventory and recipe accessors), the
   inserters' indirect calls go polymorphic and the tick is 12-35 % slower at 10k-100k; those functions must
   live in a core class every variant of a shape shares. Recommendation: the step-confined null check, four
   shapes. Caveat: pushes happen on 2-3 % of updates in the workload; a part acting every tick needs its own
   measurement.
3. **A thread-safety statement** for anything touched from the control-behaviour pass or the heat pass.
4. **GUI line counts per part**, and migration rules when a part is added to or removed from a prototype in
4. **GUI line counts per part**, and migration rules when a part is added to or removed from a prototype in
   an existing save (a heat buffer appears; the logistic member index shifts with `inventories[]` order;
   energy-source kind changes are assumed to be covered already by the engine's save-load path).
6. **Measured numbers** from the bench harness for the two parts with a cost story: broadcast transition
   storms and the count of wired control behaviours.

Per-part sole-blocker rows (row numbers from `CONVERSION-CANDIDATES.md`; "vanilla" rows are base-game
types that are themselves instances of the part):

- **GEN (16)**: 27 EEI (vanilla), 68 accumulator, 70 burner-generator, 87 fusion-generator, 91 generator and
  solar panel (vanilla); 95 SE energy beam and condenser turbine; 115 KS Power wind turbine; 129 pY wind
  turbines; 130 pY tidal; 131 pY solar tower and heliostats; 132 pY SUT; 133 pY microwave receiver; 142 Cerys
  charging rod; 159 Paracelsin pressure turbine; 161 Exotic Industries black hole, fusion reactor, induction
  matrix; 170 sun_heat_and_cooling. Two-blocker rows that also need HEAT: 154 Nullius, 165 Ultracube; LIGHT:
  98 K2 shelter.
- **HEAT (7)**: 69 reactor, 71 heat-interface (vanilla); 137 Cerys radiative tower; 140 Cerys reactor; 141
  Cerys radiative heater; 143 Cerys heat pipes and cooling boilers; 172 pyhardmode coal powerplant.
- **CIRC (5)**: 31 lamp, 82 programmable speaker, 83 display panel (vanilla); 54 rec-blue-plus deployer; 128
  nixie tubes. Two-blocker with TILE: 29 offshore pump.
- **Wildcard (3 of RECIPE's 10)**: 101 bob void pump; 106 Angel's flare stack and clarifier; 107 Flare Stack.
- **TILE (3)**: 113 Factorissimo borehole pump; 116 PlanetsLib ground digger; 117 PlanetsLib per-planet
  replacements. **PLACE (2)**: 51, 52 Tiberium growth accelerator and monoculture.
- **ITEMSET (2)**: 56 Quantum Fabricator dedigitizer; 73 infinity-pipe (vanilla). **PERCYC (1)**: 35 SE
  delivery cannon, covered by `local_effect.consumption` in v1. **LIFE (1)**: 28 temporary-container.
  **FLUIDREAD (1)**: 33 storage-tank. **CCEDIT (1)**: 34 constant-combinator.
- **BCAST (5, v3)**: 67 beacon (vanilla); 118 pY AM/FM beacons; 155 Nullius large beacons; 157 Tiberium
  control node; 163 Ultracube cube beacon.
- Rows the review moved out of reach: FREEZE 43, 138 (an S0 cannot be frozen; the teleporter stays a crafter
  shell), CONT 26, 32 (the vanilla boiler and fusion reactor are their own answer).
