# Test entities for the `component-lab` reference mod

> Part of the composed-machine benchmarks. References to `SPEC.md`, `WRITEUP.txt`, `V2-PARTS.md` and to research notes point to the proposal text and to the private analysis these numbers were produced alongside; neither is included in this repository.

Eight entities, simplest first, that `mod/component-lab` builds with the hidden-entity
pattern so the harness can assert the behaviour `SPEC.md` promises and `bench/` can measure the status quo
against the native floor. Each entry gives the composed-machine parts and shape, the emulation the mod uses
today (`SPEC.md` section 12), the mod or thread it stands in for, the behaviour to
assert, and the native engine entity to compare against in `bench/`.

Conventions:

- Prototype names are `cl-<entity>`; hidden parts are `cl-<entity>-<part>` with `hidden = true`,
  `collision_mask = {layers = {}}`, no selection box, `flags = {"not-blueprintable", "not-deconstructable",
  "placeable-off-grid", "not-on-map"}` and `create_ghost_on_death = false`.
- Harness: `fh test component-lab` (`ai-harness/suites/component-lab.lua`: load test plus one smoke test per
  entity), `fh unit component-lab` (`ai-harness/unit/component-lab/<entity>.lua`: the behaviour tests below,
  against a `--keep` server). Waiting N ticks is a `game.tick` poll over RCON, not `on_nth_tick` in the test.
- The project needs `space-age` in `base_game_mods` (spoilage is behind `FeatureFlags::Spoiling`; quality is
  needed for the quality assertions). Add `"space-age"`, `"quality"`, `"elevated-rails"` to
  `ai-harness/projects/component-lab.json` rather than keeping two projects.
- Lifecycle tests are the same five for every entity and are written once as a shared helper
  (`unit/component-lab/_lifecycle.lua`): **build** by `surface.create_entity{raise_built = true}`, by a player
  (`player.build_from_cursor`) and by robot (ghost + `revive`), asserting every hidden part exists at the
  expected offset with the expected direction and force; **mine** (`player.mine_entity`) returning the item,
  every inventory's contents and fuel, and leaving no hidden part behind; **blueprint** (`player.cursor_stack`
  blueprint over the area) containing exactly one entity with the expected settings, then placing that
  blueprint and reviving the ghost, asserting the parts are recreated; **destroy** (`entity.die()` and
  `entity.destroy{raise_destroy = true}`) leaving no hidden part and raising `on_object_destroyed` once for
  the core; **clone** (`surface.clone_entities` to a second surface) carrying every part and every inventory.
  Each entity's section lists only what is special on top of these.
- Every entity asserts the **updatable rule** as the engine reports it: `core.is_updatable` (expected per the
  shape, and whether the emulation can match it) and `is_updatable` of each hidden part (the ticking parts the
  native type would not have). `LuaEntity::luaReadIsUpdatable` reports whether the entity has an
  `UpdatableEntity` subobject at all, not whether it is on a list right now: a sleeping or disabled crafter
  still reads `true`, and only the bench shows it left the list.
- Benchmark: a `bench/builds/<variant>.lua` cell per entity, `make_save.py <variant> -n 2000`, run with
  `--cpus 8-11` on a quiet box, comparing `entityUpdate`, the per-class columns, `scriptUpdate` and
  `luaGarbageIncremental` at N = 2000 and 20000 (`bench/README.md`). Three columns per entity: the native
  comparison (floor), the emulation (ceiling), and the projection floor x D/A (1.00; B/A 1.05-1.10 as the
  pessimistic bound). Where the native comparison variant already exists (`chests`, `stone-furnace`,
  `electric-furnace`, `assembler`, `idle-furnace`) it is reused.

---

## 1. `cl-fluid-chest`: a chest with a fluid box (S0)

**Parts.** `inventories = {{name = "main", role = "storage", size = 16, with_bar = true}}`;
`fluid_boxes = {{production_type = "input-output", volume = 200, pipe_connections = {north, south}}}`;
`fluid_thresholds = {{fluid_box = 1, amount = 150, hysteresis = 10}}`; `events = {fluid_threshold = true}`.
Shape: S0 for the inventory alone; the threshold with its event makes it **S1** in the spec (section 2), so the
test has two prototypes: `cl-fluid-chest` without the event (S0) and `cl-fluid-chest-watch` with it (S1).

**Emulation.** `container` (16 slots) + hidden `storage-tank` (1x1, `fluid_box` with the two connections,
`window_bounding_box` nil, no pictures) created at the same position; the threshold by `on_nth_tick(60)`
polling `tank.get_fluid(1)`. Fluid is reachable through `tank` only; `core.fluidbox` does not exist on a
container, which is the first gap the mod has to paper over with a remote interface.

**Stands in for.** pY biofluid provider / requester tanks (a `furnace` used for its fluid box, nth(143) scan;
RESEARCH section 2) and the tailings pond (`storage-tank` + nth(153)); aai-loaders' hidden storage tank
(solved in 2.1 by `LoaderPrototype::energy_source`); the fluid lab request p=267976 (gap 8).

**Assert.** Pipe water in from an infinity pipe and assert `tank.get_fluid(1).amount` rises to 200;
`core.is_updatable == false` and `tank.is_updatable == false` (a storage tank is not in the `EntityOrderList`,
so the emulation matches S0 exactly: nothing ticks); the threshold handler sees one `below` crossing when the
tank is drained from 200 to 100 and one `above` when refilled past 160, and nothing in between (hysteresis);
the emulation's event latency is <= 60 ticks and is recorded, since the native S1 would be <= `tick_interval`;
mining spills the fluid (fluids are lost, as crafters) and returns the items; the blueprint has one entity and
no `storage-tank`; rotating the core rotates the tank's connections (this is where compound mods break).

**Native comparison.** `wooden-chest` (the existing `chests` variant) for `entityUpdate`, plus a new `tanks`
variant (N storage tanks on one pipe) so `fluidFlowUpdate` is seen separately. Expected: `entityUpdate` at the
chest floor for both the native and the emulation; the emulation adds the `on_nth_tick(60)` poll to
`scriptUpdate` (that is the saving) and one entity per chest to memory.

## 2. `cl-signal-chest`: a chest with script-written signals (S0)

**Parts.** `inventories = {{name = "main", role = "storage", size = 16}}`; `circuit_connector` (one, the chest
definition); `circuit_outputs = "script"`; `max_output_signals = 20`; `events = {inventory_changed = {"main"}}`.
Shape **S0**: nothing ticks; the control behaviour registers only while a read mode is enabled.

**Emulation.** `container` with `circuit_connector` (read contents is native) + hidden `constant-combinator`
whose red and green connectors are wired to the chest's connector with
`get_wire_connector(id).connect_to(...)` at build; script output is `cb.get_section(1).filters = ...` on the
combinator (`LuaLogisticSection`); `inventory_changed` by a hidden red wire from the chest to the combinator
and `get_signals_changed()` (2.1.21) on `on_nth_tick(10)`, or `get_contents()` diffing when that returns nil.

**Stands in for.** The hidden-constant-combinator pattern: Cybersyn, rec-blue-plus (x2), Verbose-Engineering,
Muluna telescope, Nanobots2, PowerPlusPowerMeter, spoilage-scanner; LTN's lamp + 2 combinators per stop;
the refused request p=682756 (gap 3).

**Assert.** A wire from the core to a lamp reads the inventory contents (native read mode); `publish{iron-plate
= 5}` through the mod's remote interface appears on the same wire on the next tick and persists across
save/load (`game.auto_save` is not available headless; assert through the server-save-and-reload step the
harness provides); `core.is_updatable == false`, `combinator.is_updatable == false` (a constant combinator is
not in the `EntityOrderList`; its control behaviour is registered only while output is enabled); the
`inventory_changed` emulation raises at most one event per entity per poll and none while untouched; the
blueprint has one entity and the published signals survive blueprint -> ghost -> revive through tags
(the native type blueprints the sections natively); copy-paste between two signal chests carries the sections.

**Native comparison.** `wooden-chest` + `constant-combinator` (new variant `signal-chests`: N chests each
wired to one constant combinator). Expected: `entityUpdate` at the chest floor; `controlBehaviorUpdate`
grows with N for both; the emulation's poll is the `scriptUpdate` saving.

## 3. `cl-fuelled-chest`: a chest that burns fuel (S1, burner)

**Parts.** `inventories = {{name = "main", role = "storage", size = 16}}`; `energy_source = {type = "burner",
fuel_categories = {"chemical"}, fuel_inventory_size = 1, burnt_inventory_size = 0}`; `energy_usage = "20kW"`;
`activity = "inventory_not_empty"`, `activity_inventories = {"main"}`; `events = {power_state_changed = true}`.
Shape **S1**: the burner must burn per tick (`Burner::update`, called only from the owner's update, is the only
path that refills from fuel and takes the next item, so a shape with a burner is updatable by construction);
sleeps when the main inventory is empty or the fuel runs out.

**Emulation.** `container` (16 slots) + hidden burner `reactor` (1x1, `consumption = "20kW"`, `heat_buffer =
{max_temperature = 1, specific_heat = "1kJ"}`, no `heat_lower_layer_picture`, burner source with
`fuel_inventory_size = 1`); the player reaches the reactor's fuel slot through a relative GUI frame anchored to
`container_gui` holding a GUI element `inventory` (2.1.7) bound to `reactor.get_fuel_inventory()`; the
`inventory_not_empty` gate by `on_nth_tick(30)` setting `reactor.active = (not core.get_inventory(1).is_empty())`;
`power_state_changed` by the same poll diffing `reactor.burner.currently_burning ~= nil`; status by
`custom_status` writes (`no_fuel` red / `working` green) on transitions only.

**Stands in for.** The chest-plus-hidden-accumulator request p=220800 and burner-on-non-burner requests
p=187844, p=624508 (gap 5); aai-signal-transmission's roboport-for-its-buffer plus nth(30) energy poll
(RESEARCH section 4, rank 2). It is the smallest entity with one ticking part.

**Assert.** Coal inserted into the fuel slot burns down (`reactor.burner.remaining_burning_fuel` decreases
over 600 ticks while the main inventory holds an item); with the main inventory empty the burn stops
(`reactor.active == false` within one poll; the native S1 sleeps on the inventory wake list instead) and
resumes on insert; the fuel slot rejects a non-fuel item; `core.is_updatable == false` but
`reactor.is_updatable == true` (the emulation's one ticking entity; the native S1 is itself the updatable
one, so the count of updatable entities per fuelled chest is 1 in both, in different classes); status is
`no_fuel` when the fuel runs out and `working` otherwise, within one poll; mining returns the remaining fuel
with the contents; the blueprint has one entity and a fuel item request if the mod writes one (the native type
blueprints fuel requests through `Burner::saveForBlueprint`); clone carries the burning stack.

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
power-dependent spoil modifier and a `powered` condition are tick-watches; the watcher updates once a second
from the engine's N-tick ring (activation mode 5, `SPEC.md` section 3.4), draws 10 kW in one lump per interval
(the loader sizes the buffer for 60 ticks), and sleeps when the box is empty. With `drain = "0W"` a sleeping
box costs the network nothing either; a non-zero drain would still be charged by `ElectricNetwork::update`
while asleep.

**Emulation.** `container` (16 slots, bar) + hidden `electric-energy-interface` (1x1, `energy_usage = "10kW"`,
electric source `buffer_capacity = "10kJ"`); power state by `on_nth_tick(60)` reading `eei.energy > 0` and
`eei.active = not core.get_inventory(1).is_empty()`; the spoil modifier by the same pass re-stamping every
spoilable stack: `remaining = stack.spoil_tick - game.tick`, with the mod remembering per slot the last stamp
so it only multiplies the time that elapsed since the last pass (`spoil_tick += elapsed * (m - 1)` while
powered); on a power transition every stack is re-stamped once; removal by script goes through the mod's
remote interface, which unstamps; removal by inserter hand, cursor or another mod's script is **not caught**
(there is no container transfer event) and is asserted as a known gap.

**Stands in for.** corrundum `ice-box` (`on_nth_tick(53)`, per-stack `spoil_percent` rewrite, cache rebuilt
by `find_entities_filtered`; `git-mods/corrundum/corrundum/control.lua`), cryo-container, freezer, No
Spoilage in Space, spoilage-combinator; the surface-multiplier request boskid refused p=678356 (gap 9); the
"cannot detect low power cheaply" complaint p=690374 (gap 10).

**Assert.** Insert a stack of `raw-fish` with a known `spoil_percent` while powered: after one pass its
`spoil_tick` is later than before by `59 * 7` ticks +/- one pass (the native part stamps on insert: `remaining *
8` at once, clamped at the full duration; the test records both expectations so the bench report can say which
it measured). The Lua write of `spoil_tick` throws above `now + spoil_ticks x modifiers`
(`LuaItemStack::luaWriteSpoilTick`), so the emulation clamps there and the `59 * 7` expectation holds only for
a stack already at least 413 ticks short of fresh: insert the fish at `spoil_percent = 0.5`, and assert
separately that a fresh fish is clamped, not thrown on; cut power
(set the feeding EEI's `power_production` to 0): within one pass the status is `no_power` red and the stacks
are back on the 1x schedule; restore power: `working` and 8x again; remove the fish through the remote
interface: its `spoil_tick` is unscaled (`remaining / 8`), and remove it by inserter: it is **not** unscaled
(the known gap, asserted so it stays visible); `core.is_updatable == false`, `eei.is_updatable == true`;
the box draws 10 kW only while non-empty (`eei.energy` stops refilling when `eei.active == false`); the
blueprint has one entity and the bar; mining returns the fish with real spoil ticks (the mod unstamps in
`on_player_mined_entity` before the items reach the player).

**Native comparison.** `wooden-chest` (`chests`) for the passive floor and a new `eei-watchers` variant (N
`electric-energy-interface` at 10 kW, nothing else) for the cost of one always-on electric updatable, which
is the ceiling of what the native S1 at `tick_interval = 1` would cost and ~60x the projected cost at
`tick_interval = 60` (a mode-5 instance is called from the ring, outside the per-type timing, so the native
figure would land in no per-class column). The emulation's spoil pass is reported as its own `scriptUpdate`
line and the native part is projected at zero per tick, since the engine stamps per transfer (one
`Item::setSpoilTickRaw` per stack entering or leaving): this is the one entity where the emulation
over-counts the native part and the calibration says so.

## 5. `cl-timed-converter`: a machine shell whose logic is in Lua (S3, script start)

**Parts.** `inventories = {{name = "input", role = "input", size = 4, filters = {"iron-ore", "copper-ore",
"stone", "cl-tagged-sample"}, automated_insertion_limit = 20}, {name = "output", role = "output", size = 2}}`;
`energy_source = {type = "burner", fuel_categories = {"chemical"}, fuel_inventory_size = 1,
burnt_inventory_size = 1}`; `energy_usage = "90kW"`; `module_slots = 2`, `allowed_effects = {"speed",
"consumption"}`; `process = {cycle_time = 5, start = "script", consume_at = "script"}`; `events =
{inventory_changed = {"input"}, cycle_started = true, cycle_finished = true}`. Shape **S3**; `activity =
"cycle"` by default, so fuel burns only while a cycle runs.

**Emulation.** `assembling-machine` shell (burner source, 2 module slots, `fixed_recipe = "cl-cycle-5s"`: a
recipe with `energy_required = 5`, `ingredients = {}`, `results = {{type = "item", name = "cl-cycle-token",
amount = 1}}` where the token is a hidden item with `spoil_ticks = 1` and `spoil_result = nil` so it voids
itself, and `raise_on_crafted = true`; if the data stage accepts `results = {}` the token is dropped) +
hidden `container` `input` (4 slots, `inventory_type = "with_filters"`) with a `proxy-container`
(`direction_count = 1`, target inventory `defines.inventory.chest`) at the shell's west edge for inserter
drop, + hidden `container` `output` with a proxy at the east edge for pickup. `start = "script"`: the shell
is `disabled_by_script = true` whenever idle; `start_cycle()` (remote interface) sets it false;
`on_crafted_event` is `cycle_finished`: the handler sets `disabled_by_script = true`, removes the stack it
chose from `input`, inserts the result into `output` (this handler runs synchronously inside
`CraftingMachine::update`, from the inlined `sendOnRecipeCrafted` in `giveProducts`; deactivating the shell
there is tolerated because the type loop keeps the next node in a cursor, and destroying the shell there is
the case the native type's deferred flush rules out); `cycle_started` is raised by the mod at `start_cycle`;
`inventory_changed` by `on_nth_tick(10)` `get_contents()` diff on the input container.

**Stands in for.** The April 2024 request "Non-machine with possible input, output, module and fuel
inventories" p=687544 (full read; gap 4), the craft-complete requests p=632310 / t=47728 (gap 2),
equipment-gantry (assembler shell + 3 containers), Cerys wrecks (polls `products_finished` every 15 ticks),
Moshine stages (already on `on_crafted_event`).

**Assert.** Idle: `shell.is_crafting() == false`, `shell.disabled_by_script == true`, `custom_status` reads
`waiting_for_script`, and the burner's `remaining_burning_fuel` does not change over 300 ticks (fuel burns
only while cycling); inserting iron ore into `input` by inserter (through the proxy) starts a cycle within one
poll (the native type: in the same tick through `inventory_changed` at the flush); `cycle_finished` fires
after 300 ticks at speed 1 (`crafting_progress` observed rising to 1), one iron plate is in `output`, the ore
is gone; a `cl-tagged-sample` item (type `item-with-tags`) inserted with `tags = {seed = 7}` produces a result
whose tag is derived from the input tag, proving the handler saw the real stack; two items in `input` give two
cycles with `products_finished` incrementing at a spacing >= 301 ticks (the forced tick between crafts); a
speed module in the shell shortens the cycle by its effect; `shell.is_updatable == true` and the shell leaves
the active list while disabled (the bench, not Lua, shows this: idle shells cost chest-like, and the decompile
agrees: `deactivate` unlinks); both hidden containers and both proxies report `is_updatable == false`
(`ProxyContainer`, like `ContainerEntity`, inherits the null `Entity::asUpdatableEntity`; it forwards inventory
access to its target with one virtual hop and an inserter feeding it sleeps on the target's lists); the blueprint
has one entity with the module request and no containers or proxies; mining returns input, output, fuel,
burnt result and modules; clone carries a mid-cycle `crafting_progress`.

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

**Emulation.** `assembling-machine` shell with the two fluid boxes, electric source, `fixed_recipe =
"cl-seep-cycle"` (`energy_required = 2`, 10 water -> 100 crude oil, `raise_on_crafted = true`); the
`depletion` setting in `storage[unit_number]`, written into blueprint tags in `on_player_setup_blueprint`
and read back from ghost tags on build; the handler of `on_crafted_event` adds `e.cycles`-equivalent (1 per
event) to `depletion` and `insert_fluid`s the bonus. This is the one entity whose emulation is the native
shell plus a handler and nothing else, so the bench isolates the handler's cost exactly.

**Stands in for.** pY oil / tar / gas derricks on seeps (`mining-drill` + hidden `<name>-base` assembler
with a void source and `disabled_by_script`, a new `draw_text` per derrick per run, nth(67);
`pypetroleumhandling/scripts/bitumen.lua`; RESEARCH section 5 rank 5); the multiple-fluidbox request
p=680453 (gap 8); aai-loaders' lubricant (gap 8).

**Assert.** With water piped in, crude oil appears at 100 per 120 ticks; cut the water: status
`fluid_ingredient_shortage` (the shell's native value; the composed type would report the condition's
`low_input_fluid` first) and `crafting_progress` holds; block the output: status `full_output`, no product
lost, progress clamped at 1 (count products before and after unblocking); each cycle raises exactly one
crafted event; `depletion` increments per cycle, survives blueprint -> ghost -> revive, and is **lost across
undo** (`player.undo_redo_stack`), asserted as the known gap the native `settings` close; `remove_fluid(1,
10)` positional (the 2.1 signature) works on the shell; `shell.is_updatable == true`; the blueprint has one
entity and the recipe is not exposed as a user-settable recipe (`fixed_recipe`); mining refunds nothing
(fluids are lost) and returns modules if any.

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

**Emulation.** `assembling-machine` shell (`fixed_recipe = "cl-dig-cycle"`, `energy_required = 20`, token
result with `raise_on_crafted`; 4 module slots with the creature category; electric source with drain) +
hidden `container` `food` (2 slots, `with_filters`) with a proxy for insert + hidden `container` `ore`
(4 slots) with a proxy for extract (trash is not emulated). Conditions by `on_nth_tick(61)`: modules
present, food present, ore total < 1000; the pass toggles `disabled_by_script` and writes `custom_status`
only on change (`no_modules` -> `{"entity-status.no-modules"}` with a mod locale string, since the enum value
does not exist in 2.1.24); `cycle_started` is raised by the mod when it enables the shell, and its handler
removes one food and records its value; `cycle_finished` is the crafted event: the handler picks an ore from
the scan list made at build (`find_entities_filtered{type = "resource", radius = 12.5}` once) and inserts the
yield into `ore`; `blocked_status` is `custom_status` plus `disabled_by_script` when the scan is empty.

**Stands in for.** pY `dino-dig-site` (`pyalienlife/scripts/digosaurus/digosaurus.lua`: assembler shell
`fixed_recipe` + `disabled_by_script`, food `container`, a `unit` and a `simple-entity` per trip, nth(61) plus
`on_ai_command_completed`; RESEARCH section 4 rank 8, section 5 rank 2); the drill-without-ore-patch request
p=541351 (gap 4); the required-module status of pY farms (gap 10) in the `no_modules` condition.

**Assert.** No module: the shell is disabled and the label reads "No creature" (the composed type: status
`no_modules`, red); module and food but no ore in range: `blocked_status` (`custom_status`
`no_minable_resources`) and disabled; with a test ore patch, module and food: a cycle starts within one pass,
one food is consumed at start, and after 1200 ticks the yield is in `ore` and the ore entity's `amount`
decreased; `cl-creature-fast` halves the cycle (`crafting_speed` 2); ore total >= 1000: disabled with
`full_output`; an inserter can drop fish into `food` through the proxy but cannot drop into `ore`, and can
pick from `ore` but not from `food` (the `inserter_access` semantics); the blueprint carries the module
request for the shell (today's crafter path, `EntityGhost::setupForCrafting`; the native type must match this
and it is risk 3 in `SPEC.md`); a ghost with a food item request is **not** fulfilled (containers behind
proxies do not take ghost requests; the native type's declared-inventory requests are the fix, also risk 3);
mining returns food, ore and the creature modules; `shell.is_updatable == true`; the two containers and two
proxies `false`; the per-trip entity count is 1 core + 4 hidden = 5 against the native 1.

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
`tick_interval` (the loader sizes the buffer to 60 ticks of draw; the instance lives in the mode-5 ring and is
re-filed 60 slots ahead after each virtual `update`).

**Emulation.** Visible `constant-combinator` core (script output is native, `LuaLogisticSection`) + hidden
`electric-energy-interface` (1x1, `energy_usage = "50kW"`, buffer 1 MJ) for the draw; status by
`on_nth_tick(30)` reading `eei.energy` and writing `custom_status` (`no_power` / `low_power` / `working`) and
`cb.enabled` on transitions only; `status_changed` and `power_state_changed` are the same poll's transitions.

**Stands in for.** aai-signal-transmission sender / receiver (roboport with 0 radius for the buffer, two
decider combinators and a pole on a hidden surface, nth(30) polling `energy`; RESEARCH section 2), pY aerial
base (constant combinator + EEI + container; section 5 rank 4), Factorio-Tiberium emitters (EEI energy
poll); gaps 3 and 5.

**Assert.** The endpoint draws 50 kW (`eei.energy` refills each tick; the force's electric statistics show
the EEI); `publish(signals)` appears on a wire from the core; cut the network: within one poll the status is
`no_power`, `cb.enabled == false` and the wire reads nothing; restore: `working` and the signals return;
exactly one transition event per cut and per restore (no event while steady); `core.is_updatable == false`
(constant combinator), `eei.is_updatable == true`; the blueprint has one entity with its sections and no EEI;
copy-paste carries the sections; mining returns the core item only.

**Native comparison.** `constant-combinator` + `electric-energy-interface` (new variant `endpoints`: N EEIs at
50 kW next to N combinators with one section each). Expected: the `ElectricEnergyInterface` column is what the
native S1 costs at `tick_interval = 1` and ~60x the projection at `tick_interval = 60` (which, from the ring,
would show in no per-class column); `electricNetworkUpdate` carries the per-source drain and refill for both;
`controlBehaviorUpdate` for the sections is the same in both; the poll is the `scriptUpdate` saving.

---

## Order and what each step proves

| # | Entity | Shape | New part exercised | Proves |
|---|---|---|---|---|
| 1 | fluid chest | S0 (S1 with the event) | FB on a passive core; `fluid_threshold` hysteresis | passive-only part sets never tick |
| 2 | signal chest | S0 | CC `script` output as `LogisticSection`; `inventory_changed` | CC needs no ticking |
| 3 | fuelled chest | S1 burner | burner ES with `activity = "inventory_not_empty"`; sleep on empty | one ticking part; the S0-plus-burner hole is closed by `activity` |
| 4 | cold box | S1 electric | `spoil_modifier` with `requires_power`; `powered` condition; `tick_interval` | the per-transfer spoil rule and the watcher cost; the electric no-wake-list rule |
| 5 | timed converter | S3 script | `start = "script"`, `consume_at = "script"`, `restart_delay` floor, modules, burner | the 2024 request end to end |
| 6 | seep derrick | S3 fluid | `ingredients` / `products` as recipe structs, `output_full_blocks`, `settings` | engine-side consume / produce; settings survive blueprint |
| 7 | dig site | S3 | three inventories by role, `no_modules`, `inventory_below`, `blocked_status`, ghost requests | the assembler-as-shell pattern with no hidden entities; risk 3 |
| 8 | signal endpoint | S1 electric | `activity = "always"`, `status_changed`, four connectors | the always-on electric shape and its `tick_interval` cost |

A ninth candidate, an intrinsic-effect machine (`local_effect`, which 2.1.13 already ships on every effect receiver, replacing pY's TURD hidden beacons
and the Tiberium node; RESEARCH section 4 rank 9), is left out of the first eight because its emulation (a
hidden `beacon` per machine with computed modules) and its native comparison (`beacon`) are both well
understood and it adds no new engine mechanism beyond `EffectReceiver::refreshEffect`; add it when the
`Beacon` column in the pY saves is attributed.

The pY saves are run as they are (`bench_save.py`, own mod list) for the field ratio; the cells above give
the controlled per-part numbers the saves cannot separate.
