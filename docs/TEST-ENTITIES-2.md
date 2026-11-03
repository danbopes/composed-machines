# Eight more test entities: designs from the forum and GitHub sweeps

> Part of the composed-machine proposal. `SPEC.md`, `WRITEUP.txt` and `V2-PARTS.md` are `SPEC.md`, `WRITEUP.md` and `V2-PARTS.md` in this folder; the research notes are in `../research/`.

Draft, 2026-11-02. Each entity is a thing a mod author asked for or gave up on, written first as it would look in the proposed API
(`SPEC.md` v1; `V2-PARTS.md` where a v2 part is needed), then as `component-lab` has to fake it today, with the
assertions the harness makes and the native entity it is benchmarked against. Builders follow the same
conventions as `ENTITIES.md`: own three files, own workspace, no edits to the library; a limit the
emulation cannot cross is a named `KNOWN-LIMIT` test, not a silent skip. Each builder also writes the two
benchmark cells (`bench/builds/<name>.lua` and `bench/builds/native-<name>.lua`) in the `CELL = {w, h, place}`
form of the existing files, and the integrator registers them in `make_save.py`.

What these eight add over the first eight: three shapes the earlier set did not touch (an always-burning S3, a
rotatable S0, a signal-bound setting), two v2 parts emulated so the status quo can be measured (generation,
heat output), a trigger, and the two events most asked for on the forums (power/fuel state, cycle finished
with a script-chosen job).

## 1. `cl-hearth`: a crafter that burns whether or not it works (S3, burner, `activity = "always"`)

**Asked for.** t=61277 (2018, Won't implement: "Entities that don't consume power constantly ... are asleep
to save CPU time ... that's not going to happen"), t=108882 (2023, "housing" overhaul: "I see now the usual
invisible entity contraption is the only solution"): a hidden reactor under each assembler, nth-tick
temperature polling, `crafting_progress` zeroed when cold.

**Proposed API.**
```lua
{ type = "composed-machine", name = "hearth",
  energy_source = { type = "burner", fuel_categories = {"chemical"}, effectivity = 1, fuel_inventory_size = 1 },
  energy_usage = "90kW", activity = "always",
  inventories = { {name = "in", role = "input", size = 1, filters = {"iron-ore"}},
                  {name = "out", role = "output", size = 1} },
  process = { cycle_time = 3.2, ingredients = {{type="item", name="iron-ore", amount=1}},
              products = {{type="item", name="iron-plate", amount=1}} },
  events = { power_state_changed = true } }
```
Shape S3 by the modder's explicit choice: `activity = "always"` is a tick-watch, the loader logs "S3
(machine: burner, always)", and the instance never sleeps while fuelled; it still sleeps when the burner is
empty (nothing to burn, nothing to do). The cost is a boiler's, declared on one prototype.

**Emulation.** Core `assembling-machine` shell (`emulation.like = "stone-furnace"` graphics, `energy_source =
void`, fixed recipe `iron-ore -> iron-plate`, `raise_on_crafted`) + hidden `reactor` (burner, the library's
burner part) + a scheduled pass every 20 ticks: if the reactor's `temperature` is at ambient and
`burner.remaining_burning_fuel == 0` the core is `disabled_by_script` and the status `no_fuel`; else enabled.
The `power_state_changed` event is raised on that transition by the pass.

**Assert.** Fuel in, ore in: plates come out and fuel burns while idle (no ore): the reactor's fuel inventory
drops over 3600 ticks with the input empty; fuel out: status `no_fuel` red within one pass, the event raised
once; fuel back: `working`, event raised once; mining returns fuel, ore and plates; blueprint has one entity;
clone works. KNOWN-LIMIT: the shell crafts even when the reactor just went cold until the next pass (up to
20 ticks).

**Native comparison.** `stone-furnace` working (the S3 burner shape, which sleeps between crafts) and
`reactor` alone (the always-burning part on its own); the composed native would cost about their sum minus one
entity, and the emulation adds the pass.

## 2. `cl-brazier`: a burner light that announces when its fuel runs out (S1, burner, `power_state_changed`)

**Asked for.** t=4841 (2014, "powered up / powered down" events: "build list of entities an iterate over
this list every tick"), t=64769 (LTN's author, 2019, `on_entity_no_fuel`: "forcing mods to do bad performing
polling in tick handlers").

**Proposed API.**
```lua
{ type = "composed-machine", name = "brazier",
  energy_source = { type = "burner", fuel_categories = {"chemical"}, fuel_inventory_size = 1,
                    light_flicker = { color = {1, 0.6, 0.2} } },
  energy_usage = "30kW", activity = "always",
  events = { power_state_changed = true },
  graphics_set = { working_visualisations = {{ light = { intensity = 0.8, size = 12 }, draw_in_states = {"working"} }} } }
```
S1: a burner with `activity = "always"` and no process. No inventories beyond the fuel slot.

**Emulation.** Core `container`? No: the fuel slot must be the burner's. Core = hidden-part pattern inverted:
the visible core is a `simple-entity-with-owner` (selectable, with the brazier graphics borrowed from
`small-lamp`) and the burner is the library's hidden `reactor` part whose fuel inventory a proxy-container
exposes; a scheduled pass every 30 ticks compares `remaining_burning_fuel + fuel inventory` against zero and
raises `power_state_changed` on transition, and toggles a `rendering.draw_light`.

**Assert.** Fuel in: light on, event raised with `powered = true`; fuel exhausted (use 1 wood, 2 MJ, at 30 kW
= 4000 ticks: shorten by inserting a fuel item with a small `fuel_value` if base has none, else assert via
`burner.remaining_burning_fuel` set through the remote interface): event raised once with `powered = false`
within one pass; refuel: raised once again; no event while steady; mine returns the remaining fuel.
KNOWN-LIMIT: detection latency up to 30 ticks.

**Native comparison.** `reactor` alone (burner, no polling) and `small-lamp` (the engine's own light at
zero update cost).

## 3. `cl-creep-collector`: energy per unit of work, work chosen by script (S3, electric, `start = "script"`)

**Asked for.** Rampant #64 (2021, abandoned): "Factorio API doesn't allow to manage energy consumption
directly - I was planning to consume energy per tile purged"; the 2024 forum request p=687544 for a machine
shell with inventories, energy and progress whose logic lives in Lua.

**Proposed API.**
```lua
{ type = "composed-machine", name = "creep-collector",
  energy_source = { type = "electric", usage_priority = "secondary-input", drain = "5kW" },
  energy_usage = "400kW",
  inventories = { {name = "spoils", role = "output", size = 4} },
  process = { cycle_time = 2, start = "script", consume_at = "script" },
  events = { cycle_finished = true },
  conditions = { {type = "inventory_below", inventory = "spoils", max_count = 200, status = "full_output", diode = "yellow"} } }
```
The mod calls `start_cycle()` when it has found a target (a tree or rock within 8 tiles); each finished cycle
costs 800 kJ of real power at the real rate, and `on_composed_cycle_finished` removes the target and puts its
yield into `spoils`. Energy per unit of work with no Lua energy arithmetic.

**Emulation.** Core `assembling-machine` (electric 400 kW, drain 5 kW, fixed recipe with no ingredients and no
products, `raise_on_crafted`, permanently `disabled_by_script` except while a cycle is wanted) + hidden
`container` + proxy for `spoils`. Handler: on the library's `cycle_finished` (from `on_crafted`) remove the
nearest tree/rock, insert wood/stone, search for the next target and re-enable; disable when none.

**Assert.** Plant three trees within range: after three cycles all three are gone, `spoils` holds wood, and the
EEI feeding the cell shows 3 x 800 kJ consumed (+ drain) within 2 %; no target: status `waiting_for_script`
(custom status), the core `disabled_by_script` and `is_updatable` false... (assert what the shell reports);
`spoils` at 200 items: status `full_output`, no cycle starts; mine returns spoils; blueprint/clone round-trip.

**Native comparison.** `electric-furnace` working (the S3 electric shape) and Rampant's own pattern as a second
"today" cell: `electric-energy-interface` consumer + the same handler driven by a 60-tick scheduled poll
(`native-creep-collector` is the furnace; `poll-creep-collector` is the EEI + poll cell, both built by this
builder so the three columns sit side by side).

## 4. `cl-rotating-chest`: a storehouse that rotates (S0, `direction_count = 4`)

**Asked for.** Warehousing #14 (2017, declined: "the chest in the game is not a rotatable entity, which means
i'd have to add a specific item as a 6x3 or a 3x6 warehouse"), WideChests #9 (2022, abandoned: "Game doesn't
know that when trying to rotate this 5x1 entity, replace it with this 1x5 entity").

**Proposed API.**
```lua
{ type = "composed-machine", name = "storehouse",
  collision_box = {{-2.9, -1.4}, {2.9, 1.4}}, selection_box = {{-3, -1.5}, {3, 1.5}},
  direction_count = 4, use_mirroring = false,
  inventories = { {name = "main", role = "storage", size = 240, with_bar = true} },
  circuit_connector = {...4 entries...}, circuit_outputs = "contents" }
```
S0, never on any list, rotates with R and in blueprints like any 4-way machine, one prototype.

**Emulation.** Core `assembling-machine` used as a rotatable shell (`emulation.core = "assembling-machine"`,
no recipe category, `energy_source = void`, 6x3 collision box, the `steel-chest` graphics stretched, no
module slots) + hidden `container` (240 slots) + proxy exposing it as the shell's "inventory" to inserters on
all sides (one proxy per side if the library needs it; builders decide). Rotation: the shell rotates
natively; the hidden container is re-placed to the rotated footprint by the `on_player_rotated_entity`
handler.

**Assert.** Build, insert 100 iron plates, rotate with `entity.rotate{by_player}` -> direction changed, the
inventory still holds 100 plates, inserters on the new long sides can insert/extract (place one on each side,
run 120 ticks); blueprint of a rotated storehouse pastes rotated and carries the bar; clone; mine returns the
plates; `core.is_updatable == false` (a recipe-less assembler is not updatable: verify, and if it is, record
the per-tick cost it carries as the emulation's tax).

**Native comparison.** `steel-chest` x 2 (the passive floor for the same slots) and `assembling-machine-2`
idle with no recipe (the shell on its own).

## 5. `cl-slag-generator`: power from a fluid, with a solid byproduct (S3, burner + v2 generation)

**Asked for.** t=120072 (2024): "I haven't been able to find a way to do this with the API except through
complex compound entity solutions".

**Proposed API (v2 generation, V2-PARTS 1.1).**
```lua
{ type = "composed-machine", name = "slag-generator",
  energy_source = { type = "burner", fuel_categories = {"chemical"}, fuel_inventory_size = 1 },
  energy_usage = "1MW",
  energy_output = { usage_priority = "secondary-output", output_flow_limit = "2MW", buffer_capacity = "20MJ" },
  fluid_boxes = { {volume = 200, pipe_connections = {{flow_direction="input", direction=defines.direction.north, position={0,-1}}}, filter = "water", production_type = "input"} },
  inventories = { {name = "slag", role = "output", size = 2} },
  process = { cycle_time = 4, ingredients = {{type="fluid", name="water", amount=40}},
              products = {{type="energy", amount="6MJ"}, {type="item", name="stone", amount=1}} } }
```

**Emulation.** Core `assembling-machine` (burner 1 MW, fixed recipe water -> stone with `raise_on_crafted`,
fluid box) + hidden `electric-energy-interface` producer: on each `cycle_finished` the handler adds 6 MJ to the
EEI's buffer (`eei.energy = eei.energy + 6e6`, buffer 20 MJ, `energy_production = 0`, so the network drains
the buffer at up to 2 MW); the slag inventory is the shell's output.

**Assert.** With water and coal, after 10 cycles the cell's sink EEI (a consumer on the same network) has
received about 60 MJ minus losses, and `stone` is in the output; no water: status `fluid_ingredient_shortage`
and no energy produced; buffer full and no consumer: the shell keeps crafting (KNOWN-LIMIT: the native type
would block on `full_output` for the energy product; the emulation cannot); mine returns coal and stone;
blueprint/clone.

**Native comparison.** `stone-furnace` working + `burner-generator`? No: `steam-engine` fed by an infinity
pipe of steam, the engine's own continuous generator (the generation part's cost in its own column), and
`stone-furnace` working (the S3 burner shape).

## 6. `cl-waste-heat-smelter`: a crafter that heats a heat-pipe network while it works (S3, electric + v2 heat)

**Asked for.** t=130444 (2025, Modding help: "What people do in such cases is fake it by having multiple
entites"), planet-muluna's heat assembling machines (assembler + hidden reactor + 30-tick wire retry, n-z P-rows).

**Proposed API (v2 heat output, V2-PARTS 1.2).**
```lua
{ type = "composed-machine", name = "waste-heat-smelter",
  energy_source = { type = "electric", usage_priority = "secondary-input" }, energy_usage = "180kW",
  heat_buffer = { max_temperature = 500, specific_heat = "1MJ", max_transfer = "1GW", minimum_glow_temperature = 200,
                  connections = {{position = {0, 1}, direction = defines.direction.south}} },
  inventories = { {name="in", role="input", size=1, filters={"copper-ore"}}, {name="out", role="output", size=1} },
  process = { cycle_time = 3.2, ingredients = {{type="item", name="copper-ore", amount=1}},
              products = {{type="item", name="copper-plate", amount=1}, {type="heat", amount="400kJ"}} } }
```

**Emulation.** Core `assembling-machine` (electric, fixed recipe copper-ore -> copper-plate, `raise_on_crafted`)
+ hidden `heat-interface` (1x1, south of the core, `heat_buffer` 1 MJ/degree, `mode = "at-least"`? no:
mode `"add"` with `temperature` 0 and the handler adding 0.4 degrees-worth per cycle through
`interface.temperature = interface.temperature + 400e3 / specific_heat`). A heat pipe placed south of the
interface conducts.

**Assert.** Craft 50 plates: the heat pipe's temperature rose (read `pipe.temperature` before/after, > 15
degrees); idle: temperature stops rising; no copper ore: status `item_ingredient_shortage`; mine returns ore
and plates and the heat interface is gone; blueprint has one entity; clone; heat pipe connectivity survives a
rotation (KNOWN-LIMIT candidate: the hidden interface's connection side).

**Native comparison.** `electric-furnace` working + `heat-interface` static (the heat part at rest), and
`reactor` (the engine's own heat pusher) for the per-tick cost of a native heat buffer owner.

## 7. `cl-mass-driver`: charges, then fires a stack along its facing (S3, electric buffer + v1.1 trigger)

**Asked for.** Renai Transportation's item cannon (ext #1: EEI + hidden chest + `on_nth_tick(1)` dispatcher
checking `energy == buffer` and a full stack every 15 ticks), SE's delivery cannon, t=124752 (railgun energy
per shot: "invisible accumulator or assembling machine with some hack-code to track firing events").

**Proposed API (v1 + V2-PARTS 1.4 trigger).**
```lua
{ type = "composed-machine", name = "mass-driver",
  energy_source = { type = "electric", usage_priority = "secondary-input", buffer_capacity = "40MJ", input_flow_limit = "4MW" },
  energy_usage = "0W",
  inventories = { {name = "shell", role = "input", size = 1, filters = {"iron-plate"}, automated_insertion_limit = 1} },
  process = { cycle_time = 10, ingredients = {{type="item", name="iron-plate", amount=1}}, consume_at = "finish" },
  settings = { {name = "range", type = "uint32", default = 20, min = 5, max = 60} },
  cycle_finished_trigger = { type = "direct", action_delivery = { type = "projectile", projectile = "cannon-projectile",
                             starting_speed = 1, range_setting = "range" } } }
```
Energy per shot is the cycle's draw (the 10 s cycle at the buffer's rate = 40 MJ per shot, no Lua arithmetic);
the shot itself is the trigger, no handler at all.

**Emulation.** Core `assembling-machine` (electric 4 MW, buffer 40 MJ, fixed recipe consuming 1 iron plate
with no product, `raise_on_crafted`) + handler on `cycle_finished`: `surface.create_entity{name =
"cannon-projectile", position, target = position + range * facing, speed = 1}`; the `range` setting through
the library's settings (blueprint tags). A second "today" cell reproduces Renai's dispatcher: EEI buffer + hidden
chest + a 15-tick scheduled check of `energy == buffer` and a plate present (`poll-mass-driver`).

**Assert.** Plate in, power on: one projectile created after one cycle (count `cannon-projectile` entities on
the surface right after; or use a harmless projectile), the plate consumed, the buffer drained by about 40 MJ;
no plate: no projectile, status `item_ingredient_shortage`; `range` setting survives blueprint paste; mine
returns the plate; clone.

**Native comparison.** `assembling-machine-2` working (the shell), and the `poll-mass-driver` cell.

## 8. `cl-tuned-furnace`: a machine whose speed is a circuit-bound setting (S3, electric + v2 circuit input)

**Asked for.** t=113922 (2024: "A mod can poll infrequently, but will miss pulsed signals. Or, A mod can
poll every tick, but that would introduce a massive UPS penalty"), RealisticReactors (t=113731, 250
prototypes to change a number), gap 7.

**Proposed API (v1 settings + V2-PARTS 1.3).**
```lua
{ type = "composed-machine", name = "tuned-furnace",
  energy_source = { type = "electric", usage_priority = "secondary-input" }, energy_usage = "200kW",
  inventories = { {name="in", role="input", size=1, filters={"iron-ore"}}, {name="out", role="output", size=1} },
  process = { cycle_time = 3.2, ingredients = {{type="item", name="iron-ore", amount=1}}, products = {{type="item", name="iron-plate", amount=1}} },
  effect_receiver = { base_effect = {speed = 0}, speed_limits = {low = -0.8, high = 3} },
  settings = { {name = "rate", type = "uint32", default = 10, min = 1, max = 40} },
  circuit_connector = {...}, circuit_inputs = { enable_disable = true, settings = {{setting = "rate", signal = "signal-R"}} } }
```
`rate` maps to `local_effect.speed = rate / 10 - 1` at cycle start (the entity-side pull of V2-PARTS 1.3);
the enable condition is the standard one.

**Emulation.** Core `assembling-machine` (electric, fixed recipe, circuit connector) + a scheduled pass every
30 ticks reading `get_signal({type="virtual", name="signal-R"}, red/green)` and writing
`core.local_effect = {speed = clamp(rate)/10 - 1}` (2.1.13 field, native effect, no hidden beacon) and the
enable condition through the shell's own `circuit_enable_disable`? (the assembler's control behaviour supports
`circuit_enable_disable` in 2.0: verify, else emulate with `active`).

**Assert.** With `signal-R = 30` on a wire from a constant combinator: within one pass `local_effect.speed ==
2` and plates per minute about 3x the default (count products over 1200 ticks); `signal-R = 5`: speed -0.5;
enable condition false: status `disabled_by_control_behavior`, no crafting; the `rate` setting default
survives blueprint paste; mine; clone. KNOWN-LIMIT: a pulsed signal shorter than 30 ticks is missed.

**Native comparison.** `assembling-machine-2` working (the shell) and the same shell with a hidden
`beacon` per machine (the pre-2.1.13 way of changing speed: `beacon-tuned-furnace`, so the report can show
three columns: polling + local_effect, polling + hidden beacon, native).

## Order and what each step proves

1. `cl-rotating-chest` (S0): a passive shape that rotates; proves lifecycle, nothing to tick.
2. `cl-brazier` (S1): the event the forums asked for in 2014 and 2019.
3. `cl-hearth` (S3 always): the shape Wube said would never sleep, on one prototype by choice.
4. `cl-creep-collector` (S3 script): energy per unit of script-chosen work; three columns (composed, furnace,
   Rampant-style poll).
5. `cl-tuned-furnace` (S3 + circuit input): a runtime number without a prototype per value; three columns.
6. `cl-mass-driver` (S3 + trigger): two columns of "today" (event vs dispatcher).
7. `cl-slag-generator` (S3 + generation): the v2 part with the most rows, status quo measured.
8. `cl-waste-heat-smelter` (S3 + heat): the second v2 part, status quo measured.

Benchmark cells: every entity gets `cl-<name>.lua` (the emulation) and `native-<name>.lua` (its comparison);
3, 6 and 8 also get the `poll-` / `beacon-` third cell named above. Cells are placed as in `_cells.lua`
(`CELL = {w, h, place}`), fed by infinity chests / pipes where a process needs input, with a sink chest for
outputs, and settled 3600 ticks before the save is taken. N = 2000 cells, 3600 ticks, 5 runs, pinned to CPUs
8-11, as in `bench/README.md`.
