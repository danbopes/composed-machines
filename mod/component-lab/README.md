# component-lab: builder notes

Reference test mod. It emulates the `composed-machine` type from
`../../docs/SPEC.md` with native shells plus hidden parts (SPEC section 12),
so each test entity in `../../docs/ENTITIES.md` can be asserted and
benchmarked against native entities.

## Layout and ownership

```
lib/component.lua            data stage: component.define(spec)            (library, do not edit)
lib/hidden.lua               hidden-part prototype boilerplate             (library)
lib/validate.lua             SPEC 1.9 checks as data-stage errors          (library)
scripts/runtime.lua          control stage entry: register / install / get (library)
scripts/{defs,scheduler,record,status,lifecycle,gui}.lua                   (library)
prototypes/_libtest.lua      the library's own test entities               (library)
prototypes/entities/<name>.lua   YOUR prototype file
scripts/entities/<name>.lua      YOUR handler table
data.lua, control.lua        already require every entity file             (shared, do not edit)
~/factorio/ai-harness/suites/component-lab/<name>.lua   YOUR tests
mod/ws/<name>/                     YOUR harness workspace
```

Edit only your three files. If the library is missing something, report it rather
than patching `lib/` or `scripts/*.lua`; parallel builders share them.

## Running tests

```bash
cd mod/ws/<name>
~/factorio-harness/.venv/bin/fh test component-lab --fresh      # _lib.lua + your suite
~/factorio-harness/.venv/bin/fh test component-lab --keep       # leave the server up
~/factorio-harness/.venv/bin/fh rcon --project component-lab expr "game.tick"
~/factorio-harness/.venv/bin/fh stop component-lab
```

Each workspace has its own Factorio root (`ws/<name>/factorio`: a hardlink of the
real binary, `read-data` pointing at `~/factorio/data`, its own write directory),
its own run directory and its own RCON/game port range, so all eight can run at
once. Factorio locks its write directory, which is why a shared root would not do.
If the Factorio binary in `~/factorio` is replaced, re-link it:
`ln -f ~/factorio/bin/x64/factorio ws/<name>/factorio/bin/x64/factorio`.

Pass `--fresh` after any prototype change, and whenever you rely on `on_init`
(the library's scheduler and orphan probes are armed there). The full suite
(`cd ~/factorio/ai-harness && fh test component-lab`) runs every builder's
file; use it only at the end.

## component.define(spec)

A spec is the SPEC.md section 1 prototype, as a Lua table. Fields the emulation
reads today: `name`, `inventories` (`name`, `size`, `role`, `inserter_access`,
`filters`, `filters_editable`, `with_bar`, `quality_affects_size`,
`spoil_modifier`, `show_in_gui`), `energy_source`, `energy_usage`, `activity`,
`activity_inventories`, `fluid_boxes`, `fluid_thresholds`, `process`
(`cycle_time`, `base_speed`, `start`, `consume_at`, `ingredients`, `products`,
`allow_productivity`), `module_slots`, `allowed_effects`,
`allowed_module_categories`, `effect_receiver`, `circuit_connector` (`true`
borrows the `like` entity's), `circuit_outputs`, `max_output_signals`,
`conditions`, `settings`, `events`, `tick_interval`, `default_status`,
`gui_title_key`, `vector_to_place_result`. Everything is copied into the
mod-data record, so fields the library does not act on (thresholds, spoil
modifiers, conditions, `tick_interval`) are still readable from your script via
`rec:spec()`.

Emulation-only fields, never part of the SPEC type:

| Field | Meaning |
|---|---|
| `emulation.like` | base entity whose graphics, boxes and icon are borrowed (deep-copied whole when it has the core's type) |
| `emulation.core` | force the core type instead of deriving it |
| `emulation.prototype` | fields merged into the core prototype last (graphics, sounds, anything); a value of `component.CLEAR` unsets an inherited field (also in `emulation.item`) |
| `emulation.item`, `emulation.recipe` | fields merged into the generated item / recipe |
| `inventories[i].proxy_offset` | where that inventory's proxy-container sits, relative to the core facing north |

What gets generated (SPEC section 12 mapping):

| Spec | Core / part |
|---|---|
| `process` present | core `assembling-machine` with `fixed_recipe = "<name>-cycle"` (own recipe category, `energy_required = cycle_time`, engine ingredients/products unless `consume_at = "script"`, `raise_on_crafted = true`); the shell carries the energy source, fluid boxes, module slots and circuit connector natively |
| inventories, no process | core `container` holding the first inventory natively |
| only `circuit_outputs = "script"` | core `constant-combinator` |
| each other inventory | hidden `container` `<name>-inv-<inv>` + `proxy-container` `<name>-proxy-<inv>` (unless `inserter_access = "none"`) |
| electric source on a non-shell core | hidden `electric-energy-interface` `<name>-eei` |
| burner source on a non-shell core | hidden `reactor` `<name>-burner` (burns continuously while fuelled) |
| fluid box on a non-shell core | hidden `storage-tank` `<name>-tank-<i>` (1x1, rotated with the core) |
| `circuit_outputs = "script"` on a container/shell | hidden `constant-combinator` `<name>-cc`, red and green wired to the core |
| always | item `<name>`, recipe `<name>` (5 iron plates), `mod-data` `component-lab--<name>` |

The derived shape (S0-S3, SPEC section 2) is logged at load and stored in the
mod-data record. Fluid and heat energy sources on a non-shell core, module slots
on a non-shell core, and static multi-item `filters` on hidden containers are
not emulated as such: the library pins slot i of the hidden container to
`filters[i]`, so each listed item can use exactly one slot.

An electric source with `tick_interval > 1` and a draw gets a buffer of one
interval of draw when `buffer_capacity` is omitted (SPEC rule 12); an explicit
one below that fails at load.

### Example

```lua
local component = require("lib.component")

component.define{
  name = "cl-example",
  emulation = {like = "assembling-machine-2"},
  inventories = {
    {name = "food", role = "input", size = 2, proxy_offset = {-1, 0}},
    {name = "ore", role = "output", size = 4, proxy_offset = {1, 0}},
  },
  energy_source = {type = "electric", usage_priority = "secondary-input", drain = "20kW"},
  energy_usage = "100kW",
  module_slots = 2,
  allowed_effects = {"speed"},
  process = {cycle_time = 10, start = "script", consume_at = "script"},
  conditions = {
    {type = "inventory_not_empty", inventory = "food", status = "no_ingredients", diode = "yellow"},
    {type = "module_slot_filled", count = 1, status = "no_modules", diode = "red"},
  },
  settings = {{name = "depth", type = "uint32", default = 0}},
  events = {cycle_started = true, cycle_finished = true, status_changed = true},
}
```

## Runtime

`control.lua` already calls `runtime.register(name, require("scripts.entities.<name>"))`
for every entity, then `runtime.install()`. Your script returns a handler table;
every field is optional:

| Handler | Called |
|---|---|
| `on_created(rec, ctx)` | after the parts exist, on every build path (player, robot, platform, `script_raised_built`, `script_raised_revive`) and on clone. `ctx.cause` is the event id (or `"clone"`), `ctx.tags` the applied blueprint tags, `ctx.source` the record cloned from |
| `before_mine(rec)` | the core is about to be mined (player, robot, platform, or `runtime.mine`) while its native inventory still holds its contents; adjust what is mined here, because by `on_removed` they have moved |
| `on_pasted(to, from)` | settings were pasted between two cores of this prototype; the library has already copied SPEC settings and the hidden combinator's sections |
| `on_removed(rec, mode, buffer)` | before the parts go. `mode`: `mined` (hidden contents then go to `buffer`), `died` (spilled), `destroyed` (`script_raised_destroy`: lost, as for a chest), `orphaned` (core vanished with no event: spilled) |
| `on_tick(rec, tick)` | a tick you scheduled |
| `on_cycle_finished(rec, event)` | the shell's recipe finished (`RecipeCraftedEvent`). Before this runs the library has already re-disabled a `start = "script"` shell and raised `cycle_finished` if declared |
| `blueprint_tags(rec) -> table` / `apply_tags(rec, extra)` | extra state carried through blueprints; settings and hidden inventory bars are carried for you |
| `on_gui(rec, player, frame)` | fill the relative frame anchored to the core's GUI; without it the frame lists every hidden inventory and a hidden reactor's fuel slot |
| `on_rotated(rec, previous_direction)` | the core turned (`on_player_rotated_entity`, or the `rotate` remote below); every part is already at its offset for the new facing |

Record API (`rec`, also `runtime.get(entity)` for a core or any of its parts):

| Member | Does |
|---|---|
| `rec.entity`, `rec.unit_number`, `rec.name` | the core |
| `rec.parts[kind .. ":" .. key]` | hidden part entities: `inventory:<inv>`, `proxy:<inv>`, `energy:energy`, `tank:fluid<i>`, `combinator:signals` |
| `rec.data` | your per-entity scratch table (saved, copied on clone) |
| `rec.settings` | SPEC settings, defaults applied, carried by blueprints and clones |
| `rec:spec()`, `rec:def()` | the spec / the whole mod-data record |
| `rec:inventory(name)` | the named `LuaInventory`, native or hidden |
| `rec:energy_entity()`, `rec:fuel_inventory()` | the entity holding the energy source (hidden EEI/reactor or the shell) |
| `rec:fluid_box(i)` | `entity, index` for the per-index fluid API (`get_fluid(index)` etc.) |
| `rec:combinator()`, `rec:set_signals{{name=, type=, quality=, count=}, ...}` | script output (quality defaults to `"normal"`) |
| `rec:schedule(delay)`, `rec:schedule_at(tick)`, `rec:unschedule()` | run `on_tick` later; one pending tick per record, the latest call wins |
| `rec:schedule_phase(interval, after)` | run `on_tick` at the next tick after `after` (default now) with `tick % interval == unit_number % interval` (SPEC 3.4); `interval` defaults to the spec's `tick_interval` |
| `rec:contents_changed(inv)` | true when the inventory's contents differ from the previous call; the first call only records. The `inventory_changed` poll |
| `rec:raise(flag, payload)` | raise the opt-in event (errors if the prototype did not declare it) |
| `rec:event_id(flag)` | the generated event id |
| `rec:set_status(name, {diode=, label=, force=})` | `custom_status` from a `defines.entity_status` key or `no_modules` / `waiting_for_script`; writes on change only; raises `status_changed` if declared; `nil` clears |
| `rec:check_conditions()` | first failing SPEC 1.5 condition (table) or nil |
| `rec:get_setting(n)`, `rec:set_setting(n, v, player_index)` | clamped to min/max; raises `settings_changed` if declared |
| `rec:start_cycle()` | `start = "script"` shells: enable, raise `cycle_started`, status `working` |

Module-level: `runtime.schedule(unit_number, tick)`, `runtime.raise(entity, flag, payload)`,
`runtime.set_status(entity, name, opts)`, `runtime.mine(entity, inventory)`
(script mining with hidden contents), `runtime.tag_blueprint(bp, mapping)`.

## Library parts added for the later entities

Added for the `TEST-ENTITIES-2.md` entities; each is exercised by a `lib:` test
in `_lib.lua` against the `cl-libtest-rotor`, `cl-libtest-rotor-long`,
`cl-libtest-hearth` and `cl-libtest-brazier` prototypes in `prototypes/_libtest.lua`.

Data stage (`component.define`):

| Spec field | What it generates |
|---|---|
| `emulation.core = "assembling-machine"` with no `process` | a **passive shell**: an assembler with an empty recipe category of its own (`<name>-none`), void energy, no modules, flags `no-automated-item-removal` / `-insertion`. Every inventory (the first too) becomes a hidden container + proxy. For a rotatable storehouse (`cl-rotating-chest`) |
| `direction_count = 4` on a passive or process shell | a connectionless fluid box (added only when the shell declares no fluid box of its own) that never switches off, because the engine only lets a crafting machine rotate if it has one. Square shells then rotate 90 degrees after placement. **A non-square shell only flips 180 degrees after placement** (east <-> west, box unchanged; `lib: KNOWN-LIMIT` test); placement and blueprints take all four directions |
| `direction_count = 4` on a container core | the container's own `direction_count` (containers rotate since 2.1.7), its picture as a four-way sprite and its circuit connector repeated per direction. Hidden tanks follow the core's direction on build, rotate and clone. For `cl-fluid-chest` |
| `inventories[i].proxy_offsets = {{x, y}, ...}` | one proxy per offset, all doors to the same hidden container. Part keys `proxy:<inv>`, `proxy:<inv>@2`, `proxy:<inv>@3`... (one shared prototype `<name>-proxy-<inv>`). Use it when inserters must reach the inventory from several tiles |
| burner `energy_source` + `activity = "always"` + `process` | the burner moves off the shell onto a hidden `reactor` (`energy:energy`, `<name>-burner`), which burns while fuelled whether or not the shell crafts; the shell runs on void. `rec:energy_entity()` / `rec:fuel_inventory()` return the reactor. For `cl-hearth` |
| no process, no inventories, burner + `activity` | already worked: a `simple-entity-with-owner` core + hidden reactor (shape S1). Give the core graphics with `emulation.prototype = {picture = ...}` (a lamp is not a simple-entity, so `like = "small-lamp"` only lends icon and boxes). For `cl-brazier` |
| `emulation.fuel_proxy_offset = {x, y}` (or `true` for the centre) | a proxy-container `proxy:fuel` (`<name>-proxy-fuel`) whose target is the hidden reactor's fuel slot (`defines.inventory.fuel`), so inserters can refuel it. Errors unless the burner is on a hidden reactor |
| `energy_output = {usage_priority, output_flow_limit, buffer_capacity}` (V2-PARTS 1.1) | a hidden producer `electric-energy-interface` `generator:output` (`<name>-generator`) with `energy_production = 0`: the handler adds energy to its buffer and the network drains it at up to `output_flow_limit`. For `cl-slag-generator` |
| `process.products` entries of type `energy` or `heat` | kept in the spec (mod-data) for the entity script and left out of the engine cycle recipe, which only takes item and fluid results. For `cl-slag-generator` |
| `heat_buffer = {max_temperature, specific_heat, max_transfer, connections, ...}` (V2-PARTS 1.2) | a hidden `heat-interface` `heat:heat` (`<name>-heat`) with the core's collision box, so `connections` are written relative to the core's centre exactly as in the spec. For `cl-waste-heat-smelter`. Its connections do not turn when the core rotates (KNOWN-LIMIT candidate) |

Runtime:

| Member | Does |
|---|---|
| `rec:has_fuel()` | the burner (hidden reactor or burner shell) is mid-burn or has fuel waiting. The brazier/hearth power-state test |
| `rec:read_signal(name, type, quality)` | red + green value of a signal on the core's wires; `type` defaults to `"virtual"`, `quality` to `"normal"`; 0 when absent. The core needs `circuit_connector`. Wires carry nothing on the tick they are made |
| `rec:add_output_energy(joules)` | add to the generator part's buffer; returns what fit (the rest is lost, as the spec's KNOWN-LIMIT says) |
| `rec:add_heat(joules)` | raise the heat part's temperature by `joules / specific_heat`, capped at `max_temperature`; returns the joules that fit |
| `rec:part(kind, key)` | (existed) the live part entity or nil, e.g. `rec:part("generator", "output")`, `rec:part("heat", "heat")`, `rec:part("proxy", "fuel")` |
| remote `rotate(entity, reverse)` | `LuaEntity.rotate` raises nothing without a player, so suites rotate through this: rotates, repositions the parts, calls `on_rotated`. Returns what `rotate` returned |
| `on_player_rotated_entity` | handled by the library for every core (parts follow the facing); entity scripts get `on_rotated` instead of subscribing |

Facts measured while adding these (2.1.24):

- An inserter picking up from a tile inside an assembler shell targets the
  shell, not the proxy on that tile. The passive shell's
  `no-automated-item-removal` flag makes it fall through to the proxy (probed
  both ways with a burner inserter: 20 plates in, 20 out). A **process** shell
  carries no such flag, and on the same evidence an inserter picking from a
  tile inside it will take from the shell's own result slot, not an output
  proxy there (unverified for process shells: test it if your outputs live in
  a hidden container behind a proxy inside the shell).
- Settings already ride blueprints (`lifecycle.blueprint_tags`): `rec.settings`
  and hidden inventory bars are carried for you; `blueprint_tags` /
  `apply_tags` are only for extra state. The `mass-driver` `range` and the
  `tuned-furnace` `rate` need nothing more.
- Directions are 16-way: `defines.direction.east == 4`, `west == 12`.

Not added (do it locally in your script and report it): a fluid-to-heat or
fluid-to-power shell, a hidden `beacon` part (the `beacon-tuned-furnace`
native cell builds a plain beacon), mirroring (`on_player_flipped_entity` is
not handled; parts ignore `mirroring`).

## Bench cell cookbook

Each builder writes `component/bench/builds/<name>.lua` (the emulation) and
`component/bench/builds/native-<name>.lua` (its comparison), plus the third
cell where TEST-ENTITIES-2 names one (`poll-creep-collector`,
`poll-mass-driver`, `beacon-tuned-furnace`). **The integrator registers them in
`make_save.py` (`COMPOSED`, `PAIRS`); do not edit `make_save.py`.**

A cell file only sets `CELL`. `make_save.py` prepends `ARGS` and
`builds/_common.lua` and appends `builds/_grid.lua` (the composed grid driver;
`_cells.lua` is the older `{machine=, size=, inserter=}` matrix form, not
yours):

```lua
-- Composed: cl-hearth (void assembler shell + hidden reactor, 20-tick pass),
-- fed ore through the input proxy, plates out, coal in the reactor.
CELL = {w = 7, h = 3, place = function(s, slot, i)
  local L, y = slot.left, slot.top + 1.5
  BENCH.infinity_source(BENCH.must(s, {name = "infinity-chest", position = {L + 0.5, y}}), {"iron-ore"})
  BENCH.inserter(s, "fast-inserter", {L + 1.5, y})
  local c = BENCH.must(s, {name = "cl-hearth", position = {L + 3.5, y}, raise_built = true})
  remote.call("component_lab", "parts", c.unit_number)["energy:energy"].get_fuel_inventory().insert{name = "coal", count = 50}
  BENCH.inserter(s, "fast-inserter", {L + 5.5, y})
  BENCH.infinity_sink(BENCH.must(s, {name = "infinity-chest", position = {L + 6.5, y}}))
end}
```

Layout rules (`BENCH.plan(n, w, h)`): cells are packed into 18x18 substation
blocks, in two 7-tile bands either side of the substation, so **w <= 7 and
h <= 18**. A cell owns `[left, left + w) x [top, top + h)`; every cell is
inside one substation's supply area, so anything electric is powered (4 big
infinity EEIs feed the network). Leave a gap row (as `native-seep-derrick`
does with `h = 6`) when pipes of neighbouring cells could touch. The first
line comment says what the cell is and why it is the fair comparison.

Helpers (`builds/_common.lua`, global `BENCH`):

| Helper | Does |
|---|---|
| `BENCH.must(s, spec)` | `create_entity` with `force = "player"`, errors if it fails. **Composed cores need `raise_built = true`** or they get no parts |
| `BENCH.inserter(s, name, pos, eastward)` | an inserter moving items west to east (pass `false` for east to west). `BENCH.EAST_FLOW` is the direction for west-to-east |
| `BENCH.infinity_source(chest, {items})` | infinity chest that keeps one full stack of each item |
| `BENCH.infinity_sink(chest)` | infinity chest that deletes whatever arrives |
| `BENCH.infinity_pipe(s, pos, fluid, fill)` | infinity pipe held at `fill` (0..1) of `fluid`; `fluid = nil` for none, `fill = 0` drains. For steam pass the temperature yourself: `p.set_infinity_pipe_filter{name = "steam", temperature = 165, percentage = 1, mode = "exactly"}` |
| `BENCH.eei_consumer(s, pos, watts)` | a native EEI that draws `watts` continuously: the stand-in for an always-on electric part, and the `poll-` cells' energy buffer (set `electric_buffer_size` yourself for a 40 MJ driver) |
| `remote.call("component_lab", "parts", u)` | a composed cell's hidden parts, to put fuel in a reactor (`["energy:energy"]`) or fluid in a tank |

Native comparisons that need no mod code: `steel-chest`, `assembling-machine-2`
(no recipe, or `set_recipe`), `stone-furnace` / `electric-furnace` fed by
`BENCH.cell`-style inserters, `reactor` with `uranium-fuel-cell`, `heat-interface`
(base, hidden, `heat_setting` R/W), `small-lamp`, `steam-engine` on a steam
infinity pipe, `beacon` with `speed-module` (for `beacon-tuned-furnace`). Use
the emulation's own hidden part prototype where the comparison is "the part on
its own" (`native-fuelled-chest` places `cl-fuelled-chest-burner` with no
script attached).

**`poll-` cells need mod code.** A build file runs once through `/sc`; it
cannot leave a handler in the save. Put the poll in your own script file:
register a named scheduler callback at load and expose a function the build
file calls with the cells, e.g.

```lua
local scheduler = require("scripts.scheduler")
scheduler.on_named("cl-mass-driver-poll", function(tick)
  for _, cell in pairs(storage.cl.mass_driver_poll or {}) do --[[ Renai's 15-tick check ]] end
  scheduler.schedule("cl-mass-driver-poll", tick + 15)
end)
runtime.expose("mass_driver_poll_add", function(eei, chest)
  storage.cl.mass_driver_poll = storage.cl.mass_driver_poll or {}
  table.insert(storage.cl.mass_driver_poll, {eei = eei, chest = chest})
  if #storage.cl.mass_driver_poll == 1 then scheduler.schedule("cl-mass-driver-poll", game.tick + 15) end
end)
```

One shared walk over every polled cell is the real "today" pattern (Renai,
Rampant): one `on_nth_tick` over a list. Keep it that way rather than one
schedule per cell, or the column measures the library's scheduler instead.

Smoke-test a cell from your own workspace (small `n`, never from
`~/factorio/ai-harness`, never `make_save.py`: it boots the shared server):

```bash
cd mod/ws/<name>
FH=~/factorio-harness/.venv/bin/fh; B=~/factorio/component/bench/builds
$FH test component-lab --keep
for v in cl-<x> native-<x>; do
  { echo "ARGS = {name = \"smoke\", variant = \"$v\", n = 48}"; cat $B/_common.lua $B/$v.lua $B/_grid.lua; } > smoke-$v.lua
  $FH rcon --project component-lab file "$PWD/smoke-$v.lua"      # prints the build report JSON
  # let it tick (poll game.tick), then the same health check make_save runs:
  { echo "ARGS = {}"; cat $B/_check.lua; } > check.lua; $FH rcon --project component-lab file "$PWD/check.lua"
done
$FH stop component-lab
```

The check prints status histograms, `products_finished`, reactors burning and
the composed census: a cell that is starved, unpowered or not crafting shows
there and must be fixed before the integrator benchmarks it. Each build
deletes and recreates the `bench` surface, so run variants one after another.
The integrator then builds N = 2000 cells, settles 3600 ticks and runs 3600
ticks x 5 runs pinned to CPUs 8-11 (`bench/README.md`).

## Conventions and traps

- **Never call `script.on_event` in an entity script.** Factorio keeps one handler
  per event per mod, so it would replace the runtime's. Use
  `runtime.subscribe(defines.events.x, fn, filters)` at file load; filtered events
  deliver the union of all listeners' filters, so check the entity name yourself.
  Filters passed for an event that takes none (e.g. `on_entity_settings_pasted`)
  are dropped with a log line instead of failing the load.
  Never subscribe `on_tick`: the scheduler owns it and only registers it while
  something is due.
- Poll with `rec:schedule(n)` from `on_created` and again from `on_tick`, not with
  `on_nth_tick` over all instances.
- `runtime.expose(name, fn)` adds a function to the `component_lab` remote
  interface; `runtime.init_hooks` / `runtime.load_hooks` take functions for
  `on_init`/`on_configuration_changed` and `on_load`. All three only at file load.
- Suites run inside the aitest mod and reach this mod only through
  `remote.call("component_lab", ...)`: `parts`, `record`, `call(unit_number, method, ...)`
  (any record method), `count`, `census` (records per prototype), `owner_of`,
  `shape`, `event_ids`, `mine`, `rotate(entity, reverse)`, `paste(source, destination)` (copy_settings plus
  the library paste path, since headless copy_settings raises no event),
  `tag_blueprint`, `schedule`, `bucket`, `dispatch`, and
  `set_event_log(true)` / `event_log(clear)` to see raised events with their scalar payload.
- A whole suite runs inside one tick, so nothing can wait. To observe something
  over ticks, arm it in an init hook (as `_libtest.lua` does), use `--keep` and
  poll `game.tick` over RCON, or drive `dispatch(tick)` synthetically. A fixture
  that needs more than ~30 ticks calls `runtime.fixtures.hold_until(last_tick)`:
  game.speed stays at 1000 until the latest such tick across all fixtures, then
  drops to 1. Never write `game.speed` yourself; fixtures cut each other short.
- Suites build on their own row through `_site.lua` (`row{x=, y=, half=, tile=}`,
  `row:next(width)`, `temp_surface(name)`): the site is cleared and paved first,
  and everything in the row is removed after each test. `zz-leftovers.lua` fails
  the run if any composed machine outlives the test that built it.
- Events raised during `on_init` are not delivered: call
  `runtime.lifecycle.materialise(entity)` directly there.
- Headless servers have no players: `on_player_mined_entity`,
  `on_player_setup_blueprint` and GUI events cannot fire. Use `runtime.mine` /
  `remote.call("component_lab", "mine", entity, inv)` and
  `create_blueprint` + `tag_blueprint`. A player-less character's `mine_entity`
  raises no mined event; the core is then cleaned up by the orphan path.
- `build_blueprint` skips fogged chunks by default; pass `skip_fog_of_war = false`.
- 2.1: `hidden` is a top-level field; no `LuaEntity.fluidbox`; recipes use
  `categories`; mod-data names allow only `[A-Za-z0-9_-]`; set
  `quality = "normal"` on every `SignalFilter`; wires carry nothing on the tick
  they are created.
