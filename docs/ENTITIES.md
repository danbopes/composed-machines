# The emulated entities (public summary)

> Part of the composed-machine proposal. `SPEC.md`, `WRITEUP.txt` and `V2-PARTS.md` are `SPEC.md`, `WRITEUP.md` and `V2-PARTS.md` in this folder; the research notes are in `../research/`.

Sixteen test entities built by the `component-lab` reference mod as today's compound-entity fakes (a native shell plus hidden entities plus a Lua control script), each benchmarked next to a native comparison in `bench/`. The first eight are listed here with their proposed-API parts, what shipped mod or request they stand in for, and the native comparison; the second eight are specified in full in `TEST-ENTITIES-2.md`. The proposal text (the prototype specification) is not part of this repository.

## 1. `cl-fluid-chest`: a chest with a fluid box (S0)

**Parts.** `inventories = {{name = "main", role = "storage", size = 16, with_bar = true}}`;
`fluid_boxes = {{production_type = "input-output", volume = 200, pipe_connections = {north, south}}}`;
`fluid_thresholds = {{fluid_box = 1, amount = 150, hysteresis = 10}}`; `events = {fluid_threshold = true}`.
Shape: S0 for the inventory alone; the threshold with its event makes it **S1** in the spec (section 2), so the
test has two prototypes: `cl-fluid-chest` without the event (S0) and `cl-fluid-chest-watch` with it (S1).

**Stands in for.** pY biofluid provider / requester tanks (a `furnace` used for its fluid box, nth(143) scan;
RESEARCH section 2) and the tailings pond (`storage-tank` + nth(153)); aai-loaders' hidden storage tank
(solved in 2.1 by `LoaderPrototype::energy_source`); the fluid lab request p=267976 (gap 8).

**Native comparison.** `wooden-chest` (the existing `chests` variant) for `entityUpdate`, plus a new `tanks`
variant (N storage tanks on one pipe) so `fluidFlowUpdate` is seen separately. Expected: `entityUpdate` at the
chest floor for both the native and the emulation; the emulation adds the `on_nth_tick(60)` poll to
`scriptUpdate` (that is the saving) and one entity per chest to memory.


## 2. `cl-signal-chest`: a chest with script-written signals (S0)

**Parts.** `inventories = {{name = "main", role = "storage", size = 16}}`; `circuit_connector` (one, the chest
definition); `circuit_outputs = "script"`; `max_output_signals = 20`; `events = {inventory_changed = {"main"}}`.
Shape **S0**: nothing ticks; the control behaviour registers only while a read mode is enabled.

**Stands in for.** The hidden-constant-combinator pattern: Cybersyn, rec-blue-plus (x2), Verbose-Engineering,
Muluna telescope, Nanobots2, PowerPlusPowerMeter, spoilage-scanner; LTN's lamp + 2 combinators per stop;
the refused request p=682756 (gap 3).

**Native comparison.** `wooden-chest` + `constant-combinator` (new variant `signal-chests`: N chests each
wired to one constant combinator). Expected: `entityUpdate` at the chest floor; `controlBehaviorUpdate`
grows with N for both; the emulation's poll is the `scriptUpdate` saving.


## 3. `cl-fuelled-chest`: a chest that burns fuel (S1, burner)

**Parts.** `inventories = {{name = "main", role = "storage", size = 16}}`; `energy_source = {type = "burner",
fuel_categories = {"chemical"}, fuel_inventory_size = 1, burnt_inventory_size = 0}`; `energy_usage = "20kW"`;
`activity = "inventory_not_empty"`, `activity_inventories = {"main"}`; `events = {power_state_changed = true}`.
Shape **S1**: a burner has to burn per tick, so a shape with one is updatable by construction; it sleeps when the
main inventory is empty or the fuel runs out.

**Stands in for.** The chest-plus-hidden-accumulator request p=220800 and burner-on-non-burner requests
p=187844, p=624508 (gap 5); aai-signal-transmission's roboport-for-its-buffer plus nth(30) energy poll
(RESEARCH section 4, rank 2). It is the smallest entity with one ticking part.

**Native comparison.** `stone-furnace` working (the existing variant: burner tick plus crafting) is the upper
native reference, and a new `burner-reactors` variant (N 1x1 burner reactors fed coal by inserters) is the
exact native cost of the emulation's ticking part. Expected: the native S1 at or below the `Furnace` column
(31 ns per machine-tick on the busy box at N = 2000, no crafting work); the emulation at the `Reactor` column
plus the poll in `scriptUpdate`.


## 4. `cl-cold-box`: a powered chest that slows spoilage (S1, electric watcher)

**Parts.** `inventories = {{name = "cold", role = "storage", size = 16, with_bar = true, spoil_modifier =
{multiplier = 8, requires_power = true}}}`; `energy_source = {type = "electric", usage_priority =
"secondary-input", buffer_capacity = "60kJ", drain = "0W"}`; `energy_usage = "10kW"`; `activity =
"inventory_not_empty"`, `activity_inventories = {"cold"}`; `tick_interval = 60`; `conditions = {{type =
"powered", status = "no_power", diode = "red"}}`; `events = {power_state_changed = true}`. Shape **S1**: a
power-dependent spoil modifier and a `powered` condition are tick-watches; the watcher updates once a second on
the engine's every-N-ticks schedule, draws 10 kW in one lump per interval (the loader sizes the buffer for 60
ticks), and sleeps when the box is empty. With `drain = "0W"` a sleeping box costs the network nothing either; a
non-zero drain would still be charged by the electric network while asleep.

**Stands in for.** corrundum `ice-box` (`on_nth_tick(53)`, per-stack `spoil_percent` rewrite, cache rebuilt
by `find_entities_filtered`; `git-mods/corrundum/corrundum/control.lua`), cryo-container, freezer, No
Spoilage in Space, spoilage-combinator; the surface-multiplier request boskid refused p=678356 (gap 9); the
"cannot detect low power cheaply" complaint p=690374 (gap 10).

**Native comparison.** `wooden-chest` (`chests`) for the passive floor and an `eei-watchers` variant (N
`electric-energy-interface` at 10 kW, nothing else) for the cost of one always-on electric updatable, which is
the ceiling of what the native S1 at `tick_interval = 1` would cost and about 60x the projected cost at
`tick_interval = 60`. The emulation's spoil pass is reported as its own `scriptUpdate` line and the native part
is projected at zero per tick, since a native spoil modifier re-stamps a stack once per transfer rather than
scanning: this is the one entity where the emulation over-counts the native part, and the calibration says so.

## 5. `cl-timed-converter`: a machine shell whose logic is in Lua (S3, script start)

**Parts.** `inventories = {{name = "input", role = "input", size = 4, filters = {"iron-ore", "copper-ore",
"stone", "cl-tagged-sample"}, automated_insertion_limit = 20}, {name = "output", role = "output", size = 2}}`;
`energy_source = {type = "burner", fuel_categories = {"chemical"}, fuel_inventory_size = 1,
burnt_inventory_size = 1}`; `energy_usage = "90kW"`; `module_slots = 2`, `allowed_effects = {"speed",
"consumption"}`; `process = {cycle_time = 5, start = "script", consume_at = "script"}`; `events =
{inventory_changed = {"input"}, cycle_started = true, cycle_finished = true}`. Shape **S3**; `activity =
"cycle"` by default, so fuel burns only while a cycle runs.

**Stands in for.** The April 2024 request "Non-machine with possible input, output, module and fuel
inventories" p=687544 (full read; gap 4), the craft-complete requests p=632310 / t=47728 (gap 2),
equipment-gantry (assembler shell + 3 containers), Cerys wrecks (polls `products_finished` every 15 ticks),
Moshine stages (already on `on_crafted_event`).

**Native comparison.** `assembling-machine-2` (the existing `assembler` variant) and `stone-furnace` for the
burner. Expected: the shell's `AssemblingMachine` column at ~30 ns per working machine-tick (busy-box
figure), the emulation adding two `Container` entities, two `ProxyContainer` entities and the poll; the
native S3 projected at the `Furnace` figure (no recipe work) x D/A.


## 6. `cl-seep-derrick`: a fluid process with engine-side ingredients and products (S3)

**Parts.** `fluid_boxes = {{production_type = "input", volume = 1000, filter = "water", pipe_connections =
{north}}, {production_type = "output", volume = 1000, filter = "crude-oil", pipe_connections = {south}}}`;
`energy_source = {type = "electric", usage_priority = "secondary-input", drain = "20kW"}`; `energy_usage =
"300kW"`; `process = {cycle_time = 2, start = "automatic", ingredients = {{type = "fluid", name = "water",
amount = 10}}, products = {{type = "fluid", name = "crude-oil", amount = 100}}, output_full_blocks = true}`;
`conditions = {{type = "fluid_at_least", fluid_box = 1, amount = 10, status = "low_input_fluid", diode =
"yellow"}}`; `settings = {{name = "depletion", type = "uint32", default = 0, show_in_gui = false}}`;
`events = {cycle_finished = true}`. Shape **S3**. Water stands in for pY's drilling fluid so the test needs no
pY items.

**Stands in for.** pY oil / tar / gas derricks on seeps (`mining-drill` + hidden `<name>-base` assembler
with a void source and `disabled_by_script`, a new `draw_text` per derrick per run, nth(67);
`pypetroleumhandling/scripts/bitumen.lua`; RESEARCH section 5 rank 5); the multiple-fluidbox request
p=680453 (gap 8); aai-loaders' lubricant (gap 8).

**Native comparison.** The same `assembling-machine-2` with the same recipe set by script and no
`raise_on_crafted` (new variant `fluid-assembler`). Expected: identical `AssemblingMachine` column; the
difference between native and emulation is the crafted handler in `scriptUpdate` and the tags handlers,
which is what pY pays per derrick today minus the hidden assembler and the render object (those are counted
by running the real pY save, not this cell).


## 7. `cl-dig-site`: a dig-site-shaped machine with modules, conditions and a blocked status (S3)

**Parts.** `inventories = {{name = "food", role = "input", size = 2, filters = {"raw-fish", "cl-ration"},
automated_insertion_limit = 10}, {name = "ore", role = "output", size = 4}, {name = "trash", role = "trash",
size = 1}}`; `module_slots = 4`, `allowed_module_categories = {"cl-creature"}` (two test modules in that
category: `cl-creature-slow` speed +0, `cl-creature-fast` speed +1), `allowed_effects = {"speed"}`;
`energy_source = {type = "electric", usage_priority = "primary-input", buffer_capacity = "400kJ", drain =
"400kW"}`; `energy_usage = "1W"`; `process = {cycle_time = 20, start = "automatic", consume_at = "script"}`;
`conditions = {{type = "module_slot_filled", count = 1, status = "no_modules", diode = "red"}, {type =
"inventory_not_empty", inventory = "food", status = "no_ingredients", diode = "yellow"}, {type =
"inventory_below", inventory = "ore", max_count = 1000, status = "full_output", diode = "yellow"}}`; `events
= {cycle_started = true, cycle_finished = true}`; `gui_title_key = "cl-dig-site.title"`. Shape **S3**.

**Stands in for.** pY `dino-dig-site` (`pyalienlife/scripts/digosaurus/digosaurus.lua`: assembler shell
`fixed_recipe` + `disabled_by_script`, food `container`, a `unit` and a `simple-entity` per trip, nth(61) plus
`on_ai_command_completed`; RESEARCH section 4 rank 8, section 5 rank 2); the drill-without-ore-patch request
p=541351 (gap 4); the required-module status of pY farms (gap 10) in the `no_modules` condition.

**Native comparison.** `electric-furnace` (the existing variant: electric crafter with module slots) and the
`assembler` variant; the emulation adds `Container` x2, `ProxyContainer` x2 and the nth(61) pass. The real
pY save gives the field ratio for dig sites (`bench_save.py "pY 134"`), where the per-trip `unit` and
`simple-entity` and the AI callbacks are the part this cell does not reproduce.


## 8. `cl-signal-endpoint`: a powered signal source with a status event (S1, electric, script output)

**Parts.** `energy_source = {type = "electric", usage_priority = "secondary-input", buffer_capacity = "1MJ"}`;
`energy_usage = "50kW"`; `activity = "always"`; `tick_interval = 60`; `circuit_connector` (four, the
constant-combinator definitions, `direction_count = 4`); `circuit_outputs = "script"`; `max_output_signals =
20`; `events = {status_changed = true, power_state_changed = true}`. Shape **S1**: an always-on electric draw
with nothing to sleep on; the one shape that ticks forever, at 1/60 of a per-tick entity because of
`tick_interval` (the loader sizes the buffer to 60 ticks of draw; the instance is
updated every 60 ticks).

**Stands in for.** aai-signal-transmission sender / receiver (roboport with 0 radius for the buffer, two
decider combinators and a pole on a hidden surface, nth(30) polling `energy`; RESEARCH section 2), pY aerial
base (constant combinator + EEI + container; section 5 rank 4), Factorio-Tiberium emitters (EEI energy
poll); gaps 3 and 5.

**Native comparison.** `constant-combinator` + `electric-energy-interface` (new variant `endpoints`: N EEIs at
50 kW next to N combinators with one section each). Expected: the `ElectricEnergyInterface` column is what the
native S1 costs at `tick_interval = 1` and ~60x the projection at `tick_interval = 60` (which, updated every 60 ticks,
would show in no per-class column); `electricNetworkUpdate` carries the per-source drain and refill for both;
`controlBehaviorUpdate` for the sections is the same in both; the poll is the `scriptUpdate` saving.
