# `composed-machine`: prototype and runtime specification (v1)

> Public copy. Engine-internal references from the private working notes have been removed; where a design
> decision rested on them it is marked as an assumption for Wube to confirm.

Synthesised 2026-11-02 from the author's design drafts and their reviews (not included in the public
repository). Factual base: `research/RESEARCH.md`, the public Lua API and prototype documentation for 2.1.24
(`defines` values from the 2.1.24 runtime API JSON), public statements by Wube developers, the measurements in
`bench/RESULTS.md` (rules in `bench/README.md`) and the cost model in `model/RESULTS.md` (with variant D).
Anything not backed by one of those is marked **UNVERIFIED** or as an assumption for Wube to confirm, and gets
a stated fallback; section 13 lists what each engine fact rests on. Section 12 says how the Lua reference mod
(`mod/component-lab/`) fakes every part today and what it cannot fake.

## 0. The design in one paragraph

One new static C++ entity type whose optional parts are fixed when the prototype loads: named
inventories, one energy source, fluid boxes, a recipe-less process, module slots with an effect
receiver, a circuit connector, a spoil-rate modifier per inventory, engine-evaluated conditions, and a
few blueprintable settings. The loader reduces the part set to one of four shapes, each a separate
`final` class with its own bucket in the type-ordered active list (the model's variant D). An instance
is updatable iff its shape has a process or something to watch per tick; it sleeps through the wake
lists crafting machines use, and can be scheduled every N ticks. Lua sees the entity through accessors
and per-prototype opt-in events that the engine coalesces and dispatches after the entity update
phase. No per-tick Lua, no runtime part change, no unbounded shape set, no cross-entity indirection,
no generic per-entity data.

---

## 1. Prototype: `ComposedMachinePrototype`, `type = "composed-machine"`

Inherits `EntityWithOwnerPrototype`; everything from `EntityPrototype`, `EntityWithHealthPrototype` and
`EntityWithOwnerPrototype` applies unchanged (collision, selection, health, `minable`, `corpse`,
`fast_replaceable_group`, `next_upgrade`, `heating_energy`, `surface_conditions`,
`custom_tooltip_fields`, quality indicator). Validation errors are data-stage errors, so the harness
load test (`harness/component-lab.json`, step "creating map") catches them exactly as it catches a bad
`energy_source`.

### 1.1 Top-level fields

| Field | Type | Default | Rule |
|---|---|---|---|
| `inventories` | array[`ComposedInventory`] | `{}` | 0-8 entries. Names unique, 1-32 chars `[a-z0-9_-]`, never `fuel`, `burnt_result`, `modules` (those come from the energy source and module slots). Total declared slots <= 1024. |
| `energy_source` | `EnergySource` | nil | Any of electric / burner / fluid / heat / void: the union the existing full-union prototype types accept, loaded by the existing energy-source loader. `void` is allowed only with `process` (a free-running timer). |
| `energy_usage` | `Energy` | `"0W"` | Drawn per tick while *working* (section 1.9 `activity`). Requires `energy_source`. Burner / fluid / heat: must be > 0. Electric: may be 0 (drain only). Void: must be absent. |
| `activity` | `"cycle"` / `"inventory_not_empty"` / `"always"` / `"script"` | `"cycle"` if `process`, else `"always"` | What "working" means: draws `energy_usage`, burns fuel, plays the working animation, reports `working`. `"cycle"` requires `process`; `"inventory_not_empty"` requires `activity_inventories`. |
| `activity_inventories` | array[string] | nil | Names from `inventories`; the entity works while any of them holds a stack. |
| `fluid_boxes` | array[`FluidBox`] | `{}` | 0-8 standard `FluidBox` tables (`volume`, `pipe_connections`, `production_type`, `filter`, temperature limits). Loaded by the existing fluid-box loader; the layout never changes at runtime (no recipe to relayout for). A `FluidEnergySource` adds its own box as today. |
| `fluid_thresholds` | array[`ComposedFluidThreshold`] | `{}` | Section 1.8. Only meaningful with `events.fluid_threshold`. |
| `process` | `ComposedProcess` | nil | Section 1.4. |
| `module_slots` | `ItemStackIndex` | 0 | As crafters. |
| `allowed_effects` | `EffectTypeLimitation` | none | As crafters. `"quality"` only when `process.products` is non-empty (there is nothing else to roll). `"productivity"` only with `process.allow_productivity`. |
| `allowed_module_categories` | array[`ModuleCategoryID`] | all | As crafters. |
| `effect_receiver` | `EffectReceiver` | nil | As crafters, including `base_effect` and the `*_limits` ranges (2.1.7). `base_effect` is runtime-writable (section 7). Requires `process` or `module_slots > 0`. |
| `quality_affects_module_slots`, `quality_affects_energy_usage` | boolean | false | As crafters. |
| `circuit_connector` | array[`CircuitConnectorDefinition`] | nil | Exactly `direction_count` entries (1-4), the `ContainerPrototype` array form since 2.1.7. Required for every circuit feature. |
| `circuit_wire_max_distance` | double | 0 | |
| `draw_circuit_wires`, `draw_copper_wires` | boolean | true | |
| `circuit_outputs` | `"none"` / `"contents"` / `"script"` | `"none"` | `contents`: sum of inventories with `show_in_gui`, read like a chest. `script`: the control behaviour owns logistic sections written from Lua (the constant-combinator data model, `LuaLogisticSection`). |
| `max_output_signals` | uint8 | 20 | 1-100. `script` only; bounds the total filter count across sections. |
| `default_working_signal`, `default_cycle_finished_signal` | `SignalIDConnector` | nil | As the `AssemblingMachinePrototype` pair (`default_working_signal` / `default_recipe_finished_signal`). |
| `conditions` | array[`ComposedCondition`] | `{}` | 0-4, section 1.5. Evaluated in order; all must hold for a cycle to start; the first failing one sets the status. |
| `settings` | array[`ComposedSetting`] | `{}` | 0-4, section 1.6. |
| `events` | `ComposedEvents` | all off | Section 1.7. |
| `tick_interval` | uint8 | 1 | 1-195. S1-S3 instances update every `tick_interval` ticks and integrate that many ticks of energy and progress per update (section 3.4). The cap assumes the engine's existing every-N-ticks schedule (section 3.4) has a bounded period that fits a `uint8`; the exact limit is assumed from the engine's behaviour, for Wube to confirm (UNVERIFIED), and v1 refuses larger values. |
| `default_status` | `EntityStatus` | `"normal"` | Status of an S0 instance and of an idle S1 with nothing failing, as `default_status` on `ContainerPrototype`. |
| `vector_to_place_result` | `Vector` | nil | Items in the first `output`-role inventory are ejected to the drop target (the furnace / drill output path). Requires an `output` inventory. |
| `graphics_set`, `graphics_set_flipped` | `CraftingMachineGraphicsSet` | nil | Reused whole: 4-way animation, idle animation, `working_visualisations` with `draw_in_states` keyed by the statuses of section 5, `status_colors`. |
| `use_mirroring` | boolean | false | Crafter mirroring rules. |
| `match_animation_speed_to_activity`, `animation_random_start_frame`, `perceived_performance` | | as crafters | |
| `working_sound` | `WorkingSound` | nil | Played while `working`. |
| `show_contents_in_description` | boolean | true | Hover tooltip lists inventory and fluid contents (as crafters do). |
| `gui_title_key` | string | `""` | As `gui_title_key` on `AssemblingMachinePrototype`. |
| `next_upgrade` | `EntityID` | nil | Must be a `composed-machine` of the same shape whose inventories are a superset by name; validated at data stage. |

### 1.2 `ComposedInventory`

| Field | Type | Default | Rule |
|---|---|---|---|
| `name` | string | required | Key for Lua, GUI locale (`composed-inventory-name.<name>`), fast replace, migration, `conditions`, `events.inventory_changed`, `activity_inventories`. |
| `size` | `ItemStackIndex` | required | 1-1024. |
| `role` | `"input"` / `"output"` / `"storage"` / `"trash"` | required | At most one `trash`. Decides inserter defaults, ingredient / product routing and GUI placement. |
| `inserter_access` | `"none"` / `"insert"` / `"extract"` / `"both"` | by role: input `insert`, output `extract`, storage `both`, trash `extract` | Implemented in the per-entity-type checks inserters already consult for drop and pickup targets (assumed from the engine's behaviour; for Wube to confirm). Loaders follow inserters. `trash` may not be `insert` or `both`. Answers gap 6 per inventory instead of per inserter (boskid refused per-inserter routing, p=664814). |
| `filters` | array[`ItemID`] | nil | Static accept list, created as the engine's filtered inventory (the 2.0.56 container `inventory_type = "with_filters"` machinery). |
| `filters_editable` | boolean | false | Per-slot filter buttons in the GUI and `LuaInventory::set_filter`; blueprinted and pasted. |
| `automated_insertion_limit` | `ItemCountType` | 0 | 0 = the container default (bar and stack size only). n > 0: inserters and robots stop at n of each item, through the same per-slot automated insertion limit inserters already respect on crafters, replacing the "2x recipe" rule crafters derive from the recipe. |
| `with_bar` | boolean | `role == "storage"` | The chest bar; bar blueprinted. |
| `quality_affects_size` | boolean | false | As `quality_affects_inventory_size` on `ContainerPrototype`. |
| `spoil_modifier` | `ComposedSpoilModifier` | nil | Section 1.3. Not on `trash`. |
| `show_in_gui` | boolean | true | Also whether it counts in `circuit_outputs = "contents"` and in the tooltip. |

### 1.3 `ComposedSpoilModifier`

| Field | Type | Default | Rule |
|---|---|---|---|
| `multiplier` | double | required | 0.01-100. **m > 1 slows spoilage.** On insert into the inventory: `remaining = spoil_tick - now; spoil_tick = now + remaining * m`. On removal (inserter hand, cursor, script `remove`/`transfer`, mining, death spill, fast replace): `spoil_tick = now + remaining / m`. Integer `MapTick` arithmetic, truncating; at most one tick lost per transfer. |
| `requires_power` | boolean | false | The modifier applies only while the energy source is *powered*: it can currently supply energy (fuel, electricity, fluid or temperature available). On a transition every spoilable stack in the inventory is re-stamped once by `m_new / m_old` (O(slots) per transition, never per tick). Requires `energy_source`; makes the prototype at least S1. |
| `items` | array[`ItemID`] | all spoilable | Only these items are re-stamped. |

`multiplier = 0` (pause) is **reserved, not in v1**. A stack carries one absolute spoil tick
(`LuaItemStack::spoil_tick`, public API; 0 when it does not spoil), and nothing in the public API returns a
stack that has started spoiling to a not-started or paused state. Pause is therefore assumed to need a new
engine state (a frozen remaining time plus removal from the spoil schedule) or a periodic re-stamp that drifts
by up to one period, for Wube to confirm; multiply is a one-shot re-key per transfer.

What this part assumes about the engine, inferred from its observable behaviour and the public API, for Wube
to confirm: spoilage is driven by a tick-keyed schedule, not by scanning inventories, so a re-stamp is one
reschedule of the stack with no search, no per-inventory structure and no scan; a machine holding spoilables
is revisited by the engine when a stack inside it spoils, so a sleeping composed machine holding spoilables
needs no polling to notice a spoil result; and a move of an already-spoiling stack between inventories does
not touch its spoil tick, so the re-key must be added on every transfer path into and out of the declared
inventory (inserter hand, loader, cursor, script, crafting moves, mining, death spill). The hook points, not
the re-key, are the real cost. One cap to carry: v1 caps the native re-stamp at `now + full duration` (a fresh
stack entering an `m > 1` inventory is clamped at full duration), the same limit a script write of
`spoil_tick` is assumed to have. Still open: how a partial move's split stack is scheduled, and how a merge of
two stacks weighs their ticks; the fallback for the merge case is to restrict `spoil_modifier` to inventories
with `filters` so stacks never merge across modifiers. boskid's position (p=678356, full read) is that
per-move spoil-tick adjustment is what the spoilage optimisations rule out; this part is exactly that cost,
confined to transfers into and out of one declared inventory of one opt-in prototype, and the inventory knows
its owner, so the "items don't know their surface" objection does not apply. He did not permit it; it has to
be argued against the cost of one re-key per transfer and the per-path hook.

### 1.4 `ComposedProcess`

| Field | Type | Default | Rule |
|---|---|---|---|
| `cycle_time` | double | required | Seconds per cycle at speed 1; >= 1/60. Plays `energy_required`. |
| `base_speed` | double | 1 | Plays `crafting_speed`; multiplied by the effect receiver's speed. |
| `speed_quality_multiplier` | dictionary[`QualityID` -> double] | nil | As `crafting_speed_quality_multiplier`. |
| `start` | `"automatic"` / `"script"` | `"automatic"` | automatic: a cycle starts whenever the gates hold. script: only after `LuaEntity::start_cycle()`; idle otherwise with status `waiting_for_script`. |
| `ingredients` | array[`IngredientPrototype`] | `{}` | The recipe struct, so quality, `fluidbox_index`, temperature limits, Factoriopedia and statistics come for free. Each item ingredient is satisfied from one inventory: the first `input`/`storage`-role inventory, in declared order, holding the whole amount (as a crafter checks its ingredients); fluids from the box named by `fluidbox_index`, else the first input box whose filter matches. |
| `consume_at` | `"start"` / `"finish"` / `"script"` | `"start"` | `script`: the engine consumes nothing; `ingredients` must be `{}` and `events.cycle_started` must be set. The handler of `on_composed_cycle_started` reads and removes what it wants, which is how a mod gets the real consumed stack with its tags and nested inventories (the 2024 request, p=687544) without the engine copying anything. |
| `products` | array[`ProductPrototype`] | `{}` | The recipe struct (probability, `amount_min`/`max`, temperature, `ignored_by_productivity`). Each item product goes to the first `output`/`storage`-role inventory, in declared order, that takes all of it; fluids to the box named by `fluidbox_index`, else the first output box whose filter matches. Empty means Lua produces in `on_composed_cycle_finished`. |
| `allow_productivity` | boolean | false | Requires `products`. `bonus_progress` accumulates as it does on crafters; a bonus cycle gives `products` without consuming. |
| `output_full_blocks` | boolean | true | With `products`: hold at 100 % with status `full_output` and sleep on the output wake list when nothing takes them (crafter behaviour; no product is ever lost). |
| `max_cycles_per_tick` | uint8 | 1 | 1-16. Cap on cycles finished in one update and the coalescing unit of `on_composed_cycle_finished`. |
| `return_consumed_on_cancel` | boolean | true | `consume_at = "start"` only; the crafter refund path on cancel and on mine. |
| `restart_delay` | uint16 (ticks) | 0 | automatic only. The next start decision happens at least this many ticks after a finish. With `events.cycle_finished` set the effective minimum is 1, so the handler always sees the finished state before the next consumption (the "no tick between crafts" complaint). |
| `progress_resets_when_blocked` | boolean | false | If a gate stops holding mid-cycle (an input was removed), progress is kept (false) or dropped (true). Evaluated only on a transfer out of a declared inventory, never per tick. |

### 1.5 `ComposedCondition`

`{type, ..., status = EntityStatus, diode = "red" | "yellow"}`. Types:

| `type` | Extra fields | Evaluated | Meaning |
|---|---|---|---|
| `inventory_not_empty` | `inventory` | on transfer | the named inventory holds a stack |
| `inventory_empty` | `inventory` | on transfer | |
| `inventory_below` | `inventory`, `max_count` | on transfer | total item count < `max_count` (the dig site's "stop at 1000") |
| `module_slot_filled` | `count` | on module change | at least `count` module slots filled |
| `fluid_at_least` | `fluid_box`, `amount` | on wake / at start | 1-based index into `fluid_boxes` |
| `powered` | | per tick (S1+) | the energy source is powered (section 1.3) |
| `daylight` | `threshold` | per tick (S1+) | surface darkness < `threshold` |

`status` must be an existing `defines.entity_status` value (2.1.24 has, among others, `no_ingredients`,
`item_ingredient_shortage`, `fluid_ingredient_shortage`, `no_input_fluid`, `low_input_fluid`,
`missing_required_fluid`, `full_output`, `not_enough_space_in_output`, `waiting_for_source_items`,
`waiting_for_more_items`, `no_minable_resources`, `no_filter`, `turned_off_during_daytime`, `disabled`,
`paused`, `no_fuel`, `low_temperature`, `input_fluid_too_cold`) **or one of the two values this type adds:
`no_modules` and `waiting_for_script`.** `no_food` and `no_minimum_temperature` do not exist in 2.1.24 and
are not used anywhere in this spec; a condition that needs other wording keeps the enum value and the mod
uses `custom_status` for the label. `powered` and `daylight` make the prototype at least S1.

### 1.6 `ComposedSetting`

`{name, type = "uint32" | "int32" | "bool", default, min?, max?, show_in_gui = true}`. v1: scalar types only,
0-4 entries, 4 bytes each, stored inline in the entity (at most 16 bytes per instance). Carried by blueprints,
copy-paste, undo, fast replace and `additional_pastable_entities`. `item` / `fluid` / `signal` types and
blueprint parameters are v2. This is the one item most likely to draw boskid's "every entity would grow"
objection (p=578072); the answer is that it is fixed-size, declared per prototype, and exists only on this
type (section 10).

### 1.7 `ComposedEvents`

| Flag | Type | Needs |
|---|---|---|
| `cycle_started` | boolean | `process` |
| `cycle_finished` | boolean | `process` |
| `status_changed` | boolean | S1-S3 (S0 changes status only through script or deconstruction orders, which already have events) |
| `inventory_changed` | array[string] | names from `inventories` |
| `power_state_changed` | boolean | `energy_source`; makes the prototype at least S1 |
| `fluid_threshold` | boolean | `fluid_thresholds`; makes the prototype at least S1 |
| `settings_changed` | boolean | `settings` |

### 1.8 `ComposedFluidThreshold`

`{fluid_box = uint8 (1-based), amount = FluidAmount, hysteresis = FluidAmount (0)}`. `below` fires when the
box crosses from >= `amount` to < `amount`; `above` on the reverse crossing at `amount + hysteresis`.
Evaluated in the entity's update (S1+). A hook where the fluid system writes a segment's contents would keep
threshold-only prototypes off the active list; whether such a hook exists is UNVERIFIED, and only the cost
differs (one compare per update in the fallback).

### 1.9 Validation (data-stage errors, in the order the loader checks them)

1. At least one part (`inventories`, `energy_source`, `fluid_boxes`, `process`, `module_slots`,
   `circuit_connector`) must be present; an empty composed machine is an error ("use simple-entity-with-owner").
2. `energy_usage` requires `energy_source`; burner / fluid / heat require `energy_usage > 0`; void forbids it.
   `energy_source.type = "void"` requires `process`.
3. `energy_usage > 0` without `process` requires an explicit `activity` (`"inventory_not_empty"`, `"always"` or
   `"script"`): a draw with nothing that says when to draw is the S0-plus-burner hole, and is rejected.
   A burner / fluid / heat source with no `process` and no `activity` is the same error.
4. `activity = "cycle"` requires `process`; `"inventory_not_empty"` requires `activity_inventories`, every name
   declared.
5. `process.ingredients` with an item entry requires an `input` or `storage` inventory; with a fluid entry an
   input fluid box. `products` likewise for `output`/`storage` and output boxes. `consume_at = "script"`
   requires `ingredients = {}` and `events.cycle_started`.
6. `process` with `start = "automatic"`, no `ingredients`, no `conditions` and no `energy_source` is an error
   ("free-running cycle with nothing to wait for") unless `events.cycle_finished` is set: a timer nobody
   observes is a bug, not a part.
7. `allow_productivity` requires `products`; `"quality"` in `allowed_effects` requires `products`;
   `"productivity"` in `allowed_effects` requires `allow_productivity`.
8. `conditions`: every `inventory` declared; every `fluid_box` in range; `status` in the allowed set of 1.5;
   `module_slot_filled` requires `module_slots > 0`.
9. `circuit_outputs ~= "none"`, `default_*_signal` require `circuit_connector`, whose length must equal
   `direction_count`.
10. `events.fluid_threshold` requires `fluid_thresholds`; `cycle_*` require `process`; `inventory_changed`
    names declared; `power_state_changed` requires `energy_source`; `settings_changed` requires `settings`.
11. `spoil_modifier.requires_power` requires `energy_source`; no `spoil_modifier` on `trash`;
    `inserter_access` on `trash` is `none` or `extract`.
12. `tick_interval > 1` with a process requires `tick_interval * (1 + speed_limits.high) <= cycle_time * 60 *
    max_cycles_per_tick`, so one update never finishes more cycles than the cap (with module slots this forces
    an explicit `effect_receiver.speed_limits.high`). `tick_interval > 1` with a fluid or heat source is an
    error in v1 (their buffers are the modder's fluid box / heat buffer and cannot be auto-sized without
    visible change). `tick_interval > 1` with an electric source and `energy_usage > 0`: the loader multiplies
    the computed electric buffer by `tick_interval` (section 3.4); an explicit `buffer_capacity` below that is
    an error.
13. Names: `inventories[].name` unique and not reserved; `settings[].name` unique; at most 8 inventories, 8
    fluid boxes, 4 conditions, 4 settings.
14. `next_upgrade` (if set) same shape, inventories a superset by name, same `role` for shared names.
15. The loader logs the derived shape (`composed-machine "x": shape S1 (watcher: burner)`) so a modder sees
    what they bought; `LuaEntityPrototype.composed_shape` exposes it.

---

## 2. Shapes

| Shape | Derivation | Updatable | Bucket |
|---|---|---|---|
| S0 `passive` | no `process` and no tick-watch | **no**; constructed like a container, and containers are never updated (measured: chests cost ~0 ns per instance per tick at N = 2000 and N = 20 000, `bench/RESULTS.md` section (a)) | none |
| S1 `watcher` | no `process`; at least one tick-watch | yes | +1 |
| S2 `timer` | `process`; no energy source or `void` | yes | +1 |
| S3 `machine` | `process`; electric / burner / fluid / heat source | yes | +1 |

A **tick-watch** is any of: a burner / fluid / heat energy source (assumed from the engine's behaviour, for
Wube to confirm: a burner refills its buffer from fuel and takes new fuel only in its owner's update, so an
un-updated burner runs dry after one buffer; fluid likewise; a heat draw happens only in the owner's update);
`energy_usage > 0` with `activity ~= "cycle"` (a draw that depends on activity); a `powered` or `daylight`
condition; a `spoil_modifier.requires_power`; `events.power_state_changed`; `fluid_thresholds` with
`events.fluid_threshold`. An electric source with `energy_usage = 0` and drain only is **not** a tick-watch:
the electric network is assumed to subtract drain from and refill every connected buffer by network
membership alone, without the owner's update, for Wube to confirm. It fits what can be observed: idle electric
machines keep drawing drain in the power statistics, and idle furnaces measure at chest cost in
`entityUpdate` (`bench/RESULTS.md` section (a)). A sleeping or S0 electric instance therefore still pays drain
and shows in the power statistics; what it does not pay is an entity update. (Whether a script
`disabled_by_script = true` detaches the source is open.)

Parts that are never shape axes: inventories (touched only by transfers), fluid boxes without thresholds
(moved by the separate fluid-flow update), the circuit connector (control behaviours update separately from
their entity, as the separate `controlBehavior` benchmark column shows; `contents` and `script` outputs need
no ticking, like a chest and a constant combinator), module slots (the effect is recomputed when modules or
beacons change, not per tick; assumed, consistent with Rseding91 2024 that beacons "do not update every tick",
t=113632), settings, static filters, spoil modifiers without `requires_power`.

**Template variant.** Each shape is one instantiation of `ComposedMachine<Shape>`, `final`, with absent parts
as empty bases (zero bytes under the empty-base optimisation) and their steps removed by `if constexpr`
(`model/RESULTS.md` variant D). Each shape adds one entry to the engine's per-type batched update (Rseding91,
2016, p=154019, described updatable entities on intrusive active / inactive lists with per-type batched
updates), so three shapes add three entries; that the per-surface memory cost of those entries is small is
assumed, for Wube to confirm. Instances with `tick_interval > 1` are filed in the every-N-ticks schedule
instead (section 3.4), need no per-type entry, and are assumed to run outside the per-type timing. The model
measures D/A at 1.00 +/- 0.02 (g++ and clang++, 10k-1M entities) against B/A 1.05-1.10 for a single class
with null-checked parts (B), and notes the cost D does have: each shape is another per-type list and another
copy of the update code in the instruction cache. That is why the shape set is four and curated, not one
instantiation per prototype. The v2 re-measure (`model/RESULTS-v2.md` confirms it: with
energy output and a circuit enable added, four shapes plus a null check confined to the push step match six
shapes with no check (0.95-1.02 vs 0.96-1.01 of static), and the inserter-facing accessors must live in a core
class shared by every shape, or the inserters' calls go polymorphic (12-35 % slower). B (one bucket, part
checks) is the fallback if three more entries per surface are unwelcome.

---

## 3. The updatable rule, sleep and wake

### 3.1 Updatable iff

1. **Prototype level.** `LuaEntity::is_updatable` (public API since 2.0.26) is true iff the shape is not S0.
   An S0 instance is never on any update list, under any circumstance; its cost is what a container costs.
2. **Instance level.** An S1-S3 instance is on its update list (its shape's per-type list, or the
   every-N-ticks schedule when `tick_interval > 1`) iff it is not deactivated and not asleep.
   - Deactivated: `disabled_by_script` (public API since 2.0.26), deconstruction ordered, `frozen`, or
     `disabled_by_control_behavior`. Re-entry by the matching activate path (deconstruction cancelled,
     unfrozen, the script write, the control behaviour enabling it).
   - Asleep: section 3.2.
3. Nothing that exists becomes updatable. Only instances of mod prototypes that declared a ticking part ever
   enter the list; belts and vanilla types are untouched (Rseding91, 2024-12-23, p=654992).

### 3.2 Sleep

Sleep mirrors what crafting machines already do; the engine's update performance comes from O(1) sleep and
wake on an intrusive list (Rseding91, Reddit, 2023). The rule below is what this type commits to; it sleeps on
inventory wake lists rather than on its drop target. The instance unlinks from its update list (an O(1)
intrusive unlink) and registers as a sleeper on the wake lists that can change the result:

| Result | Sleeps? | Wakes on |
|---|---|---|
| a transfer-evaluated condition failed | yes | the named inventory's wake list |
| `item_ingredient_shortage` | yes | input / storage inventories named by `ingredients` |
| `fluid_ingredient_shortage`, `fluid_at_least` failed | yes, only while the named boxes are empty | the fluid boxes' wake nodes, if they have any. Crafters are assumed to stay awake while a fluid box holds content, and whether fluid boxes own a wake list is UNVERIFIED, so the fallback is the crafter's: stay awake while a named box is non-empty |
| `full_output` | yes | output inventories / boxes named by `products` |
| `no_modules` | yes | the module inventory (module change) |
| `waiting_for_script` | yes | `start_cycle()`, `composed_active` write |
| `no_fuel` (burner: flame out, fuel inventory empty) | yes | the fuel inventory |
| `activity = "inventory_not_empty"` and all named inventories empty (S1) | yes | those inventories |
| `blocked_status` set by script | yes | `blocked_status = nil` |
| `no_power`, `low_power`, `not_plugged_in_electric_network` | **no** | the electric network is assumed to have no per-consumer wake list (for Wube to confirm); the instance stays active at zero progress, as a crafter in a brownout is assumed to. Drain is charged by the network either way (section 2). `tick_interval` is the lever for prototypes that mostly wait on power. |
| `restart_delay` countdown | no | |
| `powered` / `daylight` condition failed (S1) | no (its job is to watch) | |

Every insertion into or removal from a declared inventory by inserter, robot, loader, player or script is
assumed to pass through the entity's transfer notification, which fires the wake list: the same path that
wakes an inserter sleeping on a chest. That every script path (`LuaInventory::insert` included) reaches it is
assumed, for Wube to confirm. Other wake sources: fuel insertion (the energy source's fuel inventory is a
normal inventory of the entity); fluid arrival in a box named by a gate; `disabled_by_script = false`;
control-behaviour enable; a settings write; `blocked_status = nil`; chunk activation; load (sleepers
re-register on load). None is a poll. Inserters sleeping *on* a composed machine use the machine's input and
output wake lists unchanged; an inserter waiting to insert registers on the first inventory with
`inserter_access` allowing insert, in declared order (this is where the multi-inventory inserter rules need
tests; section 11).

### 3.3 Lua `is_updatable`, `status` and the circuit `working` read all report this state truthfully.

### 3.4 `tick_interval`

The instance updates every `tick_interval` ticks. Mechanism: the engine's existing every-N-ticks schedule,
which some vanilla entities already use (Rseding91, 2024: beacons "do not update every tick", t=113632). A
composed machine with `tick_interval > 1` is filed there with period `tick_interval` and never takes a
per-type list slot; with `tick_interval = 1` it is on its shape's per-type list. An entity is assumed to be on
exactly one of these, so the choice is per prototype and fixed. Assumed from the engine's behaviour, for Wube
to confirm: the schedule's period limit (v1 caps `tick_interval` at 195, section 1.1; a larger value is
assumed to wrap and fire early, UNVERIFIED); the phase is set when the entity is filed on attach, not
`unit_number % tick_interval`, and `next_update_tick` is derived from it; sleep and wake work unchanged
(sleeping removes the entity from the schedule, waking re-files it); an update from that schedule is outside
the per-type batching and its per-type timing, so it shows under no per-class `--benchmark-verbose` column. If
the schedule does not fit, the fallback is an in-entity countdown on the shape's per-type list (one compare
per tick).

Energy over an interval: one update integrates `dt = tick_interval` ticks. A burner's buffer is the burning
stack's remaining energy, so drawing `dt * usage_per_tick` in one update just works (assumed). An electric
buffer is sized for about one tick (crafters derive it from usage, as `LuaEntity::electric_buffer_size` shows;
formula UNVERIFIED), so a 60-tick interval would starve the machine to 1/60 speed. Rule: the loader
multiplies the computed buffer by `tick_interval`; `input_flow_limit` stays at the per-tick rate, so the
buffer refills over the interval (the network is assumed to add up to the flow limit, scaled by satisfaction,
to every connected buffer each tick) and is full at the next update. Visible effect: the power graph shows one
lump per interval. Fluid and heat sources: `tick_interval > 1` is an error in v1 (rule 12).

---

## 4. `update()` for S3, as ordered steps

The obligations of a crafter's update for a furnace or assembler, minus recipe selection, with `activity`,
`consume_at`, `restart_delay` and deferred events added. This is the order the composed machine commits to.
It puts the energy source tick first, so a burner's refill precedes the draw; the crafter is assumed to draw
first and refuel after (for Wube to confirm).

1. **Interval.** `dt = tick_interval` (section 3.4).
2. **Energy source tick.** Burner and fluid sources only; electric, heat and void have nothing to do here.
   Burner: refill the buffer from the burning stack, move the burnt result, pull the next from the fuel
   inventory, smoke; it is assumed to be the only path that burns fuel (section 2). Electric: nothing here;
   the electric network drains and refills the buffer whether or not this step runs (section 2). Heat: nothing
   here (the heat network moves temperature). Fluid: the fluid source's own update.
3. **Gates.** `disabled_by_script`, `disabled_by_control_behavior`, frozen, deconstruction ordered,
   `blocked_status`: result = that status; go to 8.
4. **Conditions and start** (only when no cycle is active). Evaluate `conditions` in order, then `ingredients`
   availability (as a crafter checks ingredients), then `products` space when `output_full_blocks`; with
   `start = "script"` also the pending-start flag; with `restart_delay` the countdown. First failure: result =
   that status; go to 8. Success: `consume_at = "start"` removes `ingredients` (as a crafter consumes them for
   items, fluid box extract for fluids); `cycle_active = true`, `progress = 0`; queue `cycle_started` if
   declared.
5. **Progress.** `need = energy_usage * dt * consumption_multiplier`; `got` is drawn from the source by its
   kind, fixed at construction: burner, electric, heat (limited by temperature above the minimum), void
   (fraction 1), fluid; each clamps to the buffer, writes it back and pollutes. Whether this reuses the
   crafter's own draw code or a generic energy-source call is Wube's choice; the model treats the energy source
   as a part that is already polymorphic and so adds no new overhead (`model/RESULTS.md`). `progress += (got /
   need) * base_speed * speed_multiplier * dt / (cycle_time * 60)`. Low power slows the cycle; `got == 0` with
   a burner is `no_fuel`. The multipliers are the cached effect receiver values.
6. **Finish.** While `progress >= 1` and `cycles_done < max_cycles_per_tick`: with `products` and
   `output_full_blocks`, if the target is full, clamp `progress = 1`, result = `full_output`, break. Else give
   `products` (crafter product semantics, productivity through `bonus_progress`; `vector_to_place_result`
   ejects), `consume_at = "finish"` removes `ingredients`, `products_finished += 1`, production statistics
   `on_flow` for declared items and fluids, `progress -= 1`, `cycles_done += 1`. Then: `start = "script"`:
   `cycle_active = false`, `progress = 0`. Automatic with `restart_delay == 0` and no `cycle_finished` event
   and gates still holding: the next cycle starts in this update (crafter behaviour). Otherwise
   `cycle_active = false` and the countdown starts (minimum 1 tick when `cycle_finished` is declared).
7. **Events (queue only).** `cycles_done > 0` and `events.cycle_finished`: push. Status differs from the
   stored one and `events.status_changed`: push. The powered state (section 1.3) flipped since the last update:
   re-stamp every `requires_power` spoil modifier's inventory (O(slots), at the transition only) and push
   `power_state_changed` if declared. Fluid thresholds crossed: push.
8. **Status and visuals.** Store the status enum (section 5); the crafter's working-visualisation and
   animation-state drawing drive the graphics (assumed reusable for this type because the graphics set is
   reused whole; for Wube to confirm).
9. **Sleep decision.** Section 3.2.

S2 is S3 with steps 2 and 5's energy terms removed by `if constexpr` (`got / need = 1`). S1 is steps 1, 2, 3,
the tick-evaluated conditions and the `activity` evaluation (working iff `activity` says so; `energy_usage` is
drawn only on working updates and burners burn only then), 7, 8, 9. Lua never runs inside any step.

---

## 5. Status

Priority, first match wins. Diode as in `defines.entity_status_diode`.

| Order | Status | Diode | Source |
|---|---|---|---|
| 1 | `marked_for_deconstruction` | red | deconstruction ordered |
| 2 | `disabled_by_script` | red | script |
| 3 | `disabled_by_control_behavior` | red | control behaviour condition |
| 4 | `frozen` | red | freezing (Space Age) |
| 5 | `blocked_status` value | as declared by the script write (red default) | script (`no_minable_resources` for the dig site) |
| 6 | energy source status: `no_power`, `not_plugged_in_electric_network`, `no_fuel`, `low_temperature`, `no_input_fluid` | red | the energy source's own status, as crafters report it for each source kind |
| 7 | `conditions[i].status`, declared order | as declared | first failing condition |
| 8 | `item_ingredient_shortage` / `fluid_ingredient_shortage` | yellow | `ingredients` unavailable |
| 9 | `full_output` | yellow | `output_full_blocks` |
| 10 | `waiting_for_script` (new) | yellow | `start = "script"`, no pending request |
| 11 | `low_power` | yellow | 0 < got < need while working |
| 12 | `working` | green | working this update |
| 13 | `default_status` | none | S0; idle S1 with nothing failing; automatic process in `restart_delay` |

`no_modules` (new) is the status a `module_slot_filled` condition is expected to declare; it is not implied by
a name. `custom_status` (2.0.7, `LuaEntity::custom_status`) overrides the displayed label and diode
only; `LuaEntity.status` keeps the real value for alerts, the circuit `working` read and `draw_in_states`.
`circuit_read_working` is `status == working`; `circuit_read_cycle_finished` is a one-tick pulse per update
with `cycles_done > 0` (the crafter definitions).

---

## 6. Events

All opt-in per prototype (section 1.7), all carrying `{name, tick, entity}`, all with a per-prototype event
id allocated at load the way `custom-event` ids are (`LuaRecipePrototype::on_crafted_event` is the 2.1.12
shape), exposed as `LuaEntityPrototype.composed_events.<flag>` so handlers register with
`script.on_event(id, fn)` and no name filtering runs for prototypes that did not opt in.

| Event | Extra payload | Raised when | Coalescing |
|---|---|---|---|
| `on_composed_cycle_started` | none | step 4 succeeded | one per entity per update |
| `on_composed_cycle_finished` | `cycles` (uint8, 1..`max_cycles_per_tick`), `bonus_cycles` (uint8, of which from productivity) | step 6 finished >= 1 cycle | one per entity per update |
| `on_composed_status_changed` | `old_status`, `new_status` (`defines.entity_status`) | transition only | one per entity per tick |
| `on_composed_inventory_changed` | `inventory` (`defines.inventory`), `inventory_name`, `player_index?`, `robot?` | dirty bit set in the transfer notification for a watched inventory; **not** for the entity's own consume / produce | one per entity per inventory per tick |
| `on_composed_power_state_changed` | `powered` (boolean) | the powered state flipped | one per entity per tick |
| `on_composed_fluid_threshold` | `fluid_box` (uint8), `amount`, `above` (boolean) | crossing, at the entity's update | one per entity per box per tick |
| `on_composed_settings_changed` | `setting`, `player_index?` | GUI edit, paste, blueprint apply, script write | one per entity per setting per tick |

**Dispatch.** Events are **queued** during the entity phase into a per-map vector of `(entity, kind, payload)`
and **dispatched at one flush point: immediately after the entity update phase returns (every surface's
per-type lists and then the every-N-ticks schedule, so both are covered) and before the script phase
(`scriptUpdate`, the last `--benchmark-verbose` column)**, in queue order, which is entity update order
(surface, bucket, list; then the schedule). Dirty bits set outside the entity phase (by Lua in the script phase
of tick T, by input actions, by other phases after the flush) are dispatched at tick T+1's flush with
`tick = T+1`; player input actions are applied before the entity update, so a player's transfer in tick T
lands in tick T's flush. This is **new code with no engine precedent known to the author**: `raise_on_crafted`
handlers (2.1.12) are assumed to run synchronously inside the crafting update, and the engine is not known to
keep a deferred queue for entity events (for Wube to confirm). The update loop is assumed to tolerate removal
of entities during update, so synchronous Lua is *possible*; it is rejected here by choice: a handler could
destroy the entity being updated or its neighbours mid-bucket, and a type built to host Lua logic must not run
Lua inside the entity update phase. The nearest precedent for an end-of-tick flush is `on_object_destroyed`
("fired at the end of the current tick or at the end of the next").

A prototype that declares no events pays one bit test per step; one that declares `inventory_changed` pays
one bit set per transfer, and the flush walks only queued entries. `inventory_changed` on a belt-fed machine
dirties every tick; coalescing bounds it to one event per entity per inventory per tick, and a mod that
declares it on a thousand busy machines gets a thousand events a tick. Documented; no engine-side throttle.

**Not provided.** No per-tick or per-update hook of any kind, no "run Lua when progress reaches x" (each is
`on_nth_tick` wearing a hat; the cost is Lua dispatch, which the engine cannot make cheap: Rseding91 2017
"massive drain", p=47728; ~2016 "hundreds/thousands of times per second", p=180836). No circuit-signal-changed
event (an engine-side changed flag is assumed not to be save/load stable; `get_signals_changed()` from 2.1.21
remains the polling-side tool). No `consumed_items` inventory copy in any payload (payloads are scalars;
`consume_at = "script"` gives the handler the live stacks instead).

---

## 7. Lua surface

### 7.1 `LuaEntityPrototype`

`composed_shape` (`"passive" | "watcher" | "timer" | "machine"`), `composed_inventories` (array of
`{name, index (defines.inventory), size, role, filters}`), `composed_process` (`{cycle_time, base_speed, start,
consume_at, ingredients, products}` or nil), `composed_settings` (array of `{name, type, default, min, max}`),
`composed_events` (`{cycle_started = LuaEventType, ...}` for the declared flags only).

### 7.2 `LuaEntity` on a composed machine

Existing members that keep their meaning (reuse, do not duplicate):
`get_inventory(defines.inventory.composed_1 .. composed_8)` in declaration order, `get_fuel_inventory()`,
`get_burnt_result_inventory()`, `get_module_inventory()`, `get_output_inventory()` (first `output` role),
`burner`, `energy`, `electric_buffer_size`, `temperature`, the per-index fluid API (`get_fluid(i)`,
`set_fluid`, `insert_fluid`, `remove_fluid(index, amount)`, `get_fluid_contents`, `fluids_count`,
`get_fluid_box_prototype`), `status`, `custom_status`, `disabled_by_script`, `disabled_by_control_behavior`,
`is_updatable`, `frozen`, `effects`, `crafting_progress` (read/write; the cycle progress), `bonus_progress`,
`products_finished` (read/write; cycles finished), `is_crafting()` (cycle active), `crafting_speed`
(effective cycle speed after effects and quality), `get_control_behavior()`, `get_circuit_network`,
`get_wire_connectors`, `get_signals_changed`, `set_tooltip_field`, `direction`, `mirroring`, `rotate`,
`copy_settings`, `set_inventory_size_override(index, size)` (public API; allowed on `storage`-role
inventories; items that no longer fit go through the trash inventory first, as crafters do, then spill; size
is not a shape axis).

New (error on other types):

| Member | R/W | Notes |
|---|---|---|
| `get_composed_inventory(name)` | method | `LuaInventory` or nil. |
| `start_cycle()` | method | `start = "script"` only. Returns `true` if the gates hold now and a cycle began (the entity wakes); otherwise `false, blocking_status`. |
| `cancel_cycle(refund)` | method | Ends the active cycle; `refund` returns `consume_at = "start"` consumption to the inventories it came from where it fits, the rest spills as mining does. No event. |
| `composed_active` | R/W boolean | The working flag for `activity = "script"`. A write wakes the entity. |
| `blocked_status` | R/W `EntityStatus` or nil | "I know something the engine does not" (no ore in range). Sets status and diode, sleeps the entity, shown in the GUI and `draw_in_states`; cleared by the script. Saved. Not blueprinted. |
| `local_effect` | R/W `Effect` | The 2.1 field (`LuaEntity::local_effect`, public API: "additional effect applied to this entity with effect receiver"), unchanged: the receiver's intrinsic term, clamped to `effect_receiver` limits, triggers an effect refresh. Saved; not blueprinted. The per-entity cycle duration lever: scale `speed` within the declared limits. Earlier drafts called this `composed_base_effect`; it already exists on every effect receiver, which is why TURD's hidden beacons are replaceable today. |
| `get_setting(name)` / `set_setting(name, value)` | methods | Typed; a script write raises `settings_changed` with `player_index = nil`. |
| `next_update_tick` | R | For `tick_interval > 1`; derived from the entity's phase in the every-N-ticks schedule. |
| `composed_shape` | R | As the prototype's. |

### 7.3 `LuaComposedMachineControlBehavior`

The generic on/off set (`circuit_enable_disable`, `circuit_condition`, `logistic_condition`,
`connect_to_logistic_network`; `LuaGenericOnOffControlBehavior`); `circuit_read_contents` (with
`circuit_outputs = "contents"`), `circuit_read_working`, `circuit_read_cycle_finished`,
`circuit_working_signal`, `circuit_cycle_finished_signal` (the `LuaAssemblingMachineControlBehavior` set); and
with `circuit_outputs = "script"`: `enabled`, `sections`, `sections_count`, `add_section`, `get_section`,
`remove_section`, the `LuaConstantCombinatorControlBehavior` set over the same `LuaLogisticSection` objects, so
script output is serialised, blueprinted and pasted by the code that already does it for constant
combinators. The behaviour updates only while a read mode or a condition is enabled (assumed to match how
other ticking control behaviours register, for Wube to confirm); `script` output alone needs no ticking.

### 7.4 Deliberately not exposed

No per-tick hook (section 6). No runtime add / remove of parts, no change of `energy_source`, `process`,
`tick_interval` or `circuit_outputs` on an instance: a shape change is a bucket move plus a variable layout;
fixed-at-load is the whole safety argument. No writable `energy_usage`, `cycle_time` or `conditions` per
instance (scale through `local_effect` so tooltips, GUI and statistics stay truthful). No access to
wake lists, no `is_sleeping` (observable through `status`). No status write (`custom_status` is the override
channel). No `LuaInventory` without an owning entity ("inventories are not targetable", boskid ~2023,
p=580752). No recipes, mining, energy production, heat output or logistic-network membership in v1 (section 11).

---

## 8. GUI

Assembled from widgets that exist for the parts, in a fixed order; nothing is drawn for an absent part. Every
part already has its own GUI panel and tooltip lines on the entities that carry it today (energy sources,
fluid boxes, effect receivers, crafters, circuit connectors, filtered inventories).

| Order | Part | Shown | Source widget |
|---|---|---|---|
| 1 | Title | `gui_title_key` or entity name; close; entity preview | crafter frame |
| 2 | Status line | icon, label, diode; `custom_status` substitutes label and diode; energy bar (electric) or fuel + burnt-result slots and flame (burner) or fluid / temperature line (fluid / heat) | the existing energy-source panels for each source kind |
| 3 | Inventories | one labelled slot grid per `show_in_gui` inventory in declaration order: `input` and `storage` left of the process bar, `output` and `trash` right; bar handle when `with_bar`; locked filter icons for `filters`; per-slot filter buttons when `filters_editable` | GUI element `inventory` (2.1.7), chest bar, `with_filters` container GUI |
| 4 | Process | progress bar between left and right groups; a row of `ingredients -> products` icons when either is non-empty; with `start = "script"` and no request, a greyed bar reading the status | crafter progress bar |
| 5 | Module slots | slot row, crafter rules | crafter module row |
| 6 | Fluid boxes | one fluid slot per box: fluid, amount, temperature | crafter fluid slots |
| 7 | Settings | one widget per `show_in_gui` setting: checkbox or numeric field with min / max | existing textfield / checkbox |
| 8 | Circuit panel | on wire connection: generic on/off section, read modes, `default_*_signal` pickers; `script` mode shows the sections read-only ("set by script") | chest / constant-combinator circuit panel |
| 9 | Tooltip | status, energy, fluids, per-inventory counts (`show_contents_in_description`), settings, spoil modifier line ("items spoil 8x slower while powered"), runtime `set_tooltip_field` lines | the existing tooltip lines of each part |
| 10 | Factoriopedia | parts: inventories with role and size, energy source, cycle time, ingredients and products, module slots | prototype fields |

Every GUI action is a normal input action (settings edit, filter edit, bar move) and replicates in multiplayer
like a recipe change. `defines.relative_gui_type.composed_machine_gui` anchors mod panels (the pY dig site
keeps its "scanned ores" panel there). Alt-mode draws the first product's icon when `products` is set,
otherwise the module icons, otherwise nothing. The first release may ship a plain vertical stack without drag
between inventories or sorting; this is the long pole of the implementation (`docs/WRITEUP.md`, section 10).

---

## 9. Blueprint, copy-paste, undo, upgrade, fast replace, mine, clone, save/load, migration

One entity on the engine's normal paths; the compound-entity failure list (orphaned children, three build
events, blueprint name swaps, cut/copy through `on_player_cursor_stack_changed`, `LuaUndoRedoStack` surgery,
identity lost across undo) does not arise.

- **Blueprint** (the existing blueprint paths for containers, assemblers, circuit connectors and burners):
  per-inventory bar and editable filters (the existing blueprint-parameter path for parametrised blueprints),
  circuit wires and control-behaviour state including script sections, module requests, fuel requests, item
  requests for any declared inventory (section 11 risk 3), `settings`. Not blueprinted: contents, progress,
  `blocked_status`, `local_effect` (the 2.1 field), `composed_active`.
- **Copy-paste**: same prototype plus `additional_pastable_entities`.
  Between composed machines of different prototypes, settings and filters paste by inventory / setting name;
  unmatched names are ignored. From a `container` into a composed machine: bar and filters into the first
  `storage` inventory. `on_entity_settings_pasted` fires once.
- **Undo / redo**: the engine's own entity undo; one undo-stack item. Lua-side `storage[unit_number]` is still
  lost across undo as for every entity (p=584507); the point of `settings` is that engine-owned per-entity
  values survive.
- **Mining**: every inventory, fuel, burnt result, modules, trash into the collector; an active
  cycle with `consume_at = "start"` refunds (the crafter refund path). Death spills; no refund.
- **Clone**: all parts by value; surface clones need no handler.
- **Fast replace**: within a `fast_replaceable_group`, inventories transfer by `name` (same name, compatible
  role; overflow to the builder as crafters do), fuel when both have a burner, fluids by index when filters are
  compatible, progress and the active cycle when both have a process, settings by name and type, control
  behaviour. From a `container`: contents go to the first `storage` inventory, else the first `input`, else
  spill. Into a `container`: the first `storage`/`output` inventory moves. This is how existing chests get
  upgraded into the type.
- **Upgrade planner**: same shape and superset inventories by name; `next_upgrade` validated at data stage,
  arbitrary pairs at runtime; leftover estimate as containers.
- **Save / load.** A **part mask** (one bit per part present: each inventory slot 0-7, energy source and its
  kind, fluid boxes, process, modules, circuit, settings) followed by each present part's own existing
  serialiser (inventories, the energy source of the declared kind, effect receiver, circuit connector, and the
  updatable state for S1-S3), then process state (`progress` double, `bonus_progress` double, `cycle_active`,
  `pending_start` bits, `products_finished` u32, `restart_countdown` u16, `blocked_status` u8,
  `next_update_tick` u32), then settings. The update list is rebuilt on load from the saved update mode, as
  for any updatable entity; sleepers re-register on load.
  **A shape byte is not enough**: a shape does not say which inventories or which energy kind existed, so the
  mask carries that, and name-matched migration needs the old names. Those are written **once per
  prototype** into the map's prototype-migration data (like the ID mapping tables): a per-prototype inventory
  name table in declaration order. Per-entity strings are wrong.
- **Prototype migration between mod versions** (on load, from the mask and the name table): inventory removed
  or renamed -> contents through the `trash` inventory if any, else spilled on the ground (as when a mod
  shrinks an inventory); added -> empty; resized -> the existing inventory resize; energy kind changed ->
  fuel / burnt spilled, buffer reset (the existing energy-source loader is assumed to read a saved source of
  another kind into a throwaway instance when the prototype's kind differs, so the stream stays consumable;
  for Wube to confirm); process removed -> cycle cancelled with refund; shape changed -> the instance is
  **re-instantiated as the class the current prototype implies**, reading only the parts present in the mask,
  dropping the rest, attaching to the update list if the new shape ticks; `spoil_modifier.multiplier`
  changed -> every affected stack re-stamped once (old out, new in). Entity renames use the normal migrations
  JSON. Removing the mod removes the entities like any type.
- **Migrating a mod off a compound entity** (pY has saves with thousands of dig-site shells and hidden
  containers): a one-time `migrations/<version>.lua` per mod: for each old core entity, `create_entity` the
  composed machine at the same position / direction / force, move contents by inventory
  (`LuaInventory.transfer` is not generic; iterate stacks into `get_composed_inventory(name)`), copy settings
  from `storage`, then destroy the core and every hidden part with `raise_destroy = false`. The reference mod
  ships this recipe for its own emulated entities (section 12).

---

## 10. Memory model

Per instance, by shape (D layout; absent parts are empty bases): the base entity-with-owner object; plus
update-list membership only for S1-S3 (S0 is built like a container and carries none); plus one inventory per
declared inventory; plus the energy source of the declared kind, by pointer; plus fluid boxes only when
`fluid_boxes` is declared (a crafter is assumed to carry fluid-box bookkeeping whether or not it uses it);
plus the sleep plumbing (two wake lists, as a container has, and sleeper links only when the instance itself
sleeps); plus the effect receiver only with module slots or a base effect; plus the control behaviour
(existing, allocated on connect); plus process state 32 bytes and settings <= 16 bytes. The sizes of the
engine's own parts are Wube's to state and are not given here. The design claim is only that an S0 instance
with one inventory costs what a chest costs, and an S1-S3 instance is no larger than a furnace or assembler
with the same parts, because it carries only the parts it declared (assumed, for Wube to confirm). In the
model, a chest-shaped D instance is 16 bytes, the same as the model's container, and a machine-shaped D
instance 64 bytes, the same as the model's furnace / assembler (B was 80 for both; `model/RESULTS.md`). Per
surface, not per chunk: three more entries in the per-type update batching (cost assumed small). The type
gets its own memory-estimate accounting as other entity types are assumed to have, so Wube's own accounting
covers it. Only this type grows, by exactly what the prototype declared.

---

## 11. Out of scope in v1, v2 candidates, and risks

**Out of scope (say so in the docs from day one; the request will come in week one):**
logistic-network membership per inventory (requester / provider / buffer roles: Mining_Drones depots, pY
bioport food supply); recipes and crafting categories (an assembler with `fixed_recipe` is the no-Lua
converter); mining (resource search); energy production and script-scaled output curves (gap 11; EEI stays
the tool); heat output (gap 12); moving cores (gap 13); effect *broadcast* (the type receives effects; vat
brain and the Tiberium node stay beacons); circuit-driven cycle start; trigger effects on cycle start / finish
without Lua (script trigger effects; the pY SUT smoke); item requests for non-module inventories in ghosts
if risk 3 fails; `settings` of item / fluid / signal type; pause spoilage (`multiplier = 0`: no representation
for it is known, section 1.3); per-entity `cycle_time` (use `local_effect.speed`).

**One-field changes on existing types that this type does not replace:** `require_module` on
`CraftingMachinePrototype` (pY farms, the largest-count target in `research/RESEARCH.md` section 5, are vanilla
crafters with recipes and score "no" under every design); `circuit_connector` with script output on
`TrainStopPrototype` (LTN); a quality filter on lab input (corrundum pressure-lab).

**Risks, ranked:**
1. GUI: the largest and least reusable piece (1200-2000 LOC is the honest floor, not 500).
2. Inserter rules across several `input` / `storage` inventories: whether an inserter waiting to insert can
   sleep, the automated insertion limit, drop-target selection, ctrl-click and quick transfer across roles
   (the per-type special cases for crafter input and result slots, restricted slots, sorting and manual
   transfer live here). Test every role combination.
3. Ghost item requests on a non-crafter: the ghost's request setup is assumed to be crafter-specific today;
   whether the generic `item-request-proxy` path covers module, fuel and declared-inventory requests on this
   type is UNVERIFIED.
4. Spoil re-stamp hook points on every transfer path, and the freshness cap (section 1.3); the re-key itself
   is assumed cheap (one reschedule; for Wube to confirm).
5. `tick_interval` on the every-N-ticks schedule: the 195 cap and the schedule's period limit (section 3.4).
6. Event flush placement in the tick and the tick attribution of post-flush changes (section 6).
7. Quality: `quality_affects_size`, `quality_affects_energy_usage`, module quality bonuses; reuse the crafter
   rules verbatim.
8. Maintenance (Rseding91 ~2020: "another developer signs up"): the type's logic is the parts' existing code
   plus about 300 lines of cycle logic; four shapes; the forbidden list; the headless harness suite as the
   regression gate.

---

## 12. Lua emulation mapping (what `component-lab` fakes today, and the gaps)

The reference mod stands in for the type with the nearest native shells, so the benchmark measures "native
shell + Lua glue + hidden entities" (the status quo) against "native shell alone" (the floor), with the model's
D/A = 1.00 (B/A 1.05-1.10 as the pessimistic bound) as the projected overhead of the new class over the
shell. `mod/component-lab/` was a scaffold when this was written (2026-11-02); this is its contract, and its
current state is in `mod/component-lab/STATUS.md`.

| Part / rule | Emulation in 2.1.24 | Fidelity | What the benchmark must attribute |
|---|---|---|---|
| S0: inventories, static filters, bar, `contents` circuit read | `container` with `inventory_type = "with_filters"` and `circuit_connector` | **exact** (the lower bound) | nothing |
| several named inventories on one entity | visible core carries one native inventory; each extra inventory is a hidden `container` (1x1, no collision) plus a `proxy-container` (2.0.38; `direction_count` and `circuit_connector` array since 2.1.21) for inserter access | behaviour yes; one extra entity per inventory plus proxy; lifecycle glue in Lua | the hidden `container` / `proxy-container` entities and the build / mine / clone handlers |
| `role` / `inserter_access` | proxy direction and which inventories get a proxy | approximate | |
| `automated_insertion_limit` | bar on the hidden container; crafters' 2x rule on shells | approximate | |
| ES electric (S1 watcher, S3) | the shell crafter's own electric source, or a hidden `electric-energy-interface` with `power_usage` for a non-crafter core | exact draw and status; the EEI is its own updatable entity | `ElectricEnergyInterface` column |
| ES burner, continuous (fuelled chest, ice box) | hidden burner `reactor` (1x1, no graphics; a reactor burns fuel continuously while fuel is present) with the player reaching its fuel slot through a GUI element `inventory` (2.1.7) in a relative GUI frame | continuous burn exact; wrong bucket (measured in the `Reactor` column) and the fuel slot is a mod GUI, not the entity's | `Reactor` column + the extra entity |
| ES burner with a process | burner `assembling-machine` / `furnace` shell with a `fixed_recipe` | exact | shell column |
| FB on S0 | hidden `storage-tank` (1x1) or a `furnace` used for its box (pY tanks); `add_fluid_box_linked_connection` for linking | behaviour yes, extra entity | `StorageTank` / `Furnace` column + entity |
| FB on a process | the shell's own `fluid_boxes` | exact | |
| process + `cycle_finished` | `assembling-machine` shell with a `fixed_recipe` whose `energy_required = cycle_time`; `raise_on_crafted = true` on the recipe prototype (2.1.12) -> `LuaRecipePrototype.on_crafted_event` | **exact and event-driven**: the shell's own crafting update is the real timer; progress, animation, power draw, status native. The one event the reference mod gets without polling | `AssemblingMachine` column ~ S3 (expect ~ furnace cost: no recipe work) |
| engine `ingredients` / `products` | the shell's real recipe (the derrick: drilling fluid -> crude oil, with real fluid boxes) | exact, including statistics and productivity | |
| `start = "script"` | `disabled_by_script = true` in the crafted handler, `false` on `start_cycle` | one extra tick of latency; otherwise exact | none |
| `consume_at = "script"` | the handler removes from the hidden input container before enabling the shell | exact | |
| `restart_delay` | `disabled_by_script` toggled from `on_nth_tick` | granular to the poll | |
| `conditions`, `blocked_status`, `no_modules` | Lua checks on a poll, `custom_status` written when the loop runs (pY LRF writes it every 55 ticks unconditionally) | status honest only at poll resolution | `scriptUpdate` share of the poll |
| `activity = "inventory_not_empty"` (burner) | poll the inventory; insert / remove fuel from the hidden reactor accordingly | granular to the poll | |
| MOD + `local_effect` | the shell's own module slots; a hidden `beacon` per machine with computed modules for the base effect (the TURD pattern) | exact effect, one entity per machine | `Beacon` column + effect links |
| CC `script` output | hidden `constant-combinator` wired to the core with a hidden wire; `LuaLogisticSection` writes | exact signals, one hidden entity | `ConstantCombinator` control behaviour + entity |
| CC `read_working` / `cycle_finished` | the shell crafter's own control behaviour | exact | |
| `settings` | `storage[unit_number]` + tags written in `on_player_setup_blueprint`, read from ghost tags on build | survives blueprints; **lost across undo** | handler cost separately |
| `spoil_modifier` | an `on_nth_tick(N)` scan re-stamping `spoil_tick` over the inventory (cleaner than corrundum's `spoil_percent` nudge) | wrong cost model: O(slots) per period instead of per transfer; items inserted between scans are stamped late; the unstamp on removal cannot be done at all for inserter hands and cursors (no event) | over-counts the native part; report separately |
| `power_state_changed`, `status_changed`, `inventory_changed`, `fluid_threshold` | **not emulable**; poll `energy` / `status` / `get_contents` (or `get_signals_changed()` on a wire, 2.1.21) / `get_fluid` on `on_nth_tick` | no | the whole poll is the saving |
| `tick_interval` | the poll period | the same idea at Lua cost | |
| updatable iff | each hidden entity is updatable per its own type; a passive shape on a bare container is exact; any powered shape costs one extra updatable entity | partial | hidden entities' columns |
| sleep at crafter cost with wake on transfer | `disabled_by_script` entities do leave the list, but nothing tells Lua when to re-enable them without a poll | no | |
| GUI | relative GUI frames per hidden part; `inventory` GUI element (2.1.7) for hidden inventories | approximate | |
| blueprint / undo / fast replace / clone of the whole | bplib / 0-things style handlers in the mod; blueprint name swapping in `on_player_setup_blueprint`; cut/copy through `on_player_cursor_stack_changed`; undo not handled | the thing being removed | measure handler cost separately |

**Cannot be faithfully emulated (the benchmark marks these "not reproducible in Lua"):** a watcher at ~0 per
tick; coalesced, ordered, engine-raised events; sleeping at crafter cost with wake on transfer; several
inserter-reachable `input` inventories without hidden parts; per-transfer spoil stamping with correct unstamp
on every exit path; blueprint / undo / upgrade / fast replace / clone without lifecycle Lua; `blocked_status`
and status-driven `draw_in_states` without render objects; `tick_interval` scheduling.

**Calibration recipe** (`bench/README.md` rules apply: quiet box, `--cpus` pinned, N >= 2000, compare
`entityUpdate` and per-class columns, report medians beside means). For each test entity report three
columns at the same N: (1) the native engine type doing the most similar work, the floor (`bench/RESULTS.md`
section (a): per instance per tick at N = 2000, whole update including the feeding inserters, electric furnace
46 ns, stone furnace 54 ns, assembler 100 ns; chests ~1 ns); (2) the emulation, the ceiling (`scriptUpdate` +
`luaGarbageIncremental` + the hidden entities' per-class columns); (3) the projected composed cost = (1) x D/A
(1.00; B/A 1.05-1.10 as the pessimistic bound). Passive and sleeping shapes are projected at chest cost, which
the bench shows for idle furnaces within noise (`bench/RESULTS.md` section (a): `entityUpdate` 0.003 ms for
both chests and idle furnaces at N = 2000 and N = 20 000, and -1.4 vs 1.4 ns per instance whole at N = 2000),
consistent with Rseding91's description of sleep as an O(1) removal from an intrusive list (Reddit, 2023); an
electric sleeper is assumed still to pay drain and refill in the electric network update (section 2), which is
not an `entityUpdate` cost. A shape at `tick_interval > 1` is assumed to run from the every-N-ticks schedule
and land in no per-class column, so its attribution needs its own line.

---

## 13. Engine facts relied on, and their verification state

Evidence classes: **measured** = `bench/RESULTS.md` or `model/RESULTS.md`; **public** = the Lua API, the
prototype documentation or the changelog; **Wube statement** = a public post by a Wube developer, cited by
date and thread; **assumed** = inferred from the engine's observable behaviour, for Wube to confirm;
**UNVERIFIED** = open, with a fallback stated where it is used.

| Fact | Evidence | State |
|---|---|---|
| Plain containers are never updated; scripts can tell an updatable entity apart | chests ~0 ns per instance per tick at N = 2000 and N = 20 000 (`bench/RESULTS.md` section (a)); `LuaEntity::is_updatable` and `disabled_by_script` (public API since 2.0.26) | measured / public |
| Updates are batched per entity type on intrusive active lists | Rseding91 2016 (p=154019): an updatable-entity side interface with intrusive active / inactive lists and per-type batched updates | Wube statement; the per-surface layout and the memory cost of three more entries assumed |
| Sleep and wake are O(1); idle machines leave the update list | Rseding91, Reddit 2023 (performance comes from O(1) sleep / wake on an intrusive list); idle furnaces at chest cost (`bench/RESULTS.md` section (a)) | Wube statement + measured; which results a crafter sleeps on assumed; whether fluid boxes own a wake list UNVERIFIED |
| Energy source is a per-prototype component of a fixed kind | `energy_source` prototype field and its five types (public prototype docs) | public; how the draw is dispatched internally is Wube's (the model treats it as already polymorphic, `model/RESULTS.md`) |
| Electric network has no per-consumer wake list | section 3.2 | assumed |
| Drain is charged without an entity update | idle electric machines draw drain in the power statistics (game behaviour) while idle furnaces measure at chest cost in `entityUpdate` (`bench/RESULTS.md` section (a)) | assumed, consistent with measurement; whether `disabled_by_script` detaches the source UNVERIFIED |
| Burner must tick to refuel | section 2 | assumed |
| Every-N-ticks scheduling exists | Rseding91 2024 (t=113632): beacons "do not update every tick" | Wube statement; the period limit, the behaviour above it, and that such updates sit outside per-class timing assumed / UNVERIFIED |
| Spoilage: absolute spoil tick, tick-keyed schedule | `LuaItemStack::spoil_tick` (public API); boskid (p=678356) on what the spoilage optimisations rule out | public / Wube statement; re-key cost, transfer hook points, the freshness cap, split and merge handling assumed / UNVERIFIED |
| Transfer notification on every path wakes sleepers | inserters sleeping on chests wake when contents change (game behaviour) | assumed; coverage of every script path (`LuaInventory::insert`) UNVERIFIED |
| `raise_on_crafted` handlers run synchronously | `raise_on_crafted` / `LuaRecipePrototype::on_crafted_event` (public, 2.1.12) | assumed; deferral is new code |
| Control behaviours are a separate updatable component | separate `controlBehavior` column in `--benchmark-verbose` output (`bench/RESULTS.md`) | measured (the column exists); the registration rule assumed |
| Ghost module / fuel requests are crafter-specific today | risk 3 | UNVERIFIED |
| Per-prototype event ids | the `custom-event` prototype; `LuaRecipePrototype::on_crafted_event` (2.1.12) | public; cost when not opted in (one compare) assumed |
| Reused Lua accessors | `LuaEntity` `crafting_progress`, `bonus_progress`, `products_finished`, `is_crafting`, `crafting_speed`, `set_inventory_size_override`, `is_updatable`, `custom_status`, `local_effect` | public API |
| `EntityStatus` enum and diode | `defines.entity_status` and `defines.entity_status_diode` 2.1.24 (no `no_food`, no `no_minimum_temperature`; `low_temperature` exists) | solid (docs) |
| Per-instance sizes (section 10) | model layouts (`model/RESULTS.md`, object sizes); the engine's own part sizes are not stated in this copy | measured in the model only; engine sizes for Wube |
| Memory accounting hook | section 10 | assumed |
| Inventories are not targetable on their own | boskid ~2023 (p=580752) | Wube statement |

---

## Appendix A: what each shipped hack becomes (`research/RESEARCH.md` section 2, 41 entries)

"full": the hidden parts and the tick loop go; "partial": the loop goes but an engine type the composed machine
does not replace stays; "no": the core is something the type is not (train stop, roboport, beacon, loader,
unit, crafter with recipes, generator).

| Mod / entity | Today | Verdict | As |
|---|---|---|---|
| corrundum `ice-box` | container + nth(53) rewriting every stack | **full** (semantics change) | S1 burner, `activity = "inventory_not_empty"`, `spoil_modifier` m = 8 `requires_power`; loses the pause-below-50 % / rewind, per-stack dry-ice draw and Aquilo / Frozeta exemption |
| corrundum `pressure-lab` | lab + nth(45) | no | lab core; a quality filter on lab input is a one-field request elsewhere |
| pY `dino-dig-site` | assembler shell + hidden food container + 2 entities per trip + nth(61) | **full** | S3: food / ore / trash inventories, creature modules, `no_modules` condition, 20-30 s cycle, `consume_at = "script"`, `cycle_finished`; units optional as visuals |
| pY bioport | assembler shell + unit couriers | partial | the shell collapses to S3; couriers stay units |
| pY provider / requester tanks | furnace used for a fluid box, nth(143) scan | **full** | S0 / S1 with FB + `fluid_threshold` |
| pY caravans | unit + script inventories | no | moving core |
| pY vat brain | assembler + hidden beacon | no | broadcaster |
| pY farms | vanilla assembler + nth(121) + alerts walk | no | crafter with recipes; `require_module` on `CraftingMachinePrototype` is the fix |
| pY TURD beacons | one hidden beacon per machine | already solved in 2.1.13 | `LuaEntity::local_effect` (R/W on every effect receiver) replaces the hidden beacon on vanilla crafters today |
| pY aerial base | constant combinator + EEI + container | partial | base collapses to S1 (INV + electric + CC script); distance-flown generation (gap 11) stays EEI; blimps stay units |
| pY solar updraft tower, solar tower / heliostats, LRF / stirling, tidal | EEI / boiler / solar driven from daylight | no | energy production |
| pY tailings pond | storage tank + nth(153) | **full** | S1 with FB + `fluid_threshold` at 99 %; venting in the handler |
| pY AM/FM beacons | 50 prototypes | no | beacon; `settings` on a beacon is a separate request |
| pY derricks on seeps | mining drill + hidden `-base` assembler + render object per run + nth(67) | partial | S3 with two fluid boxes, engine `ingredients` / `products`, `settings.depletion`, if pY accepts Lua-managed seep depletion (its dig site already does); if it must stay a drill, no |
| planet-muluna heat assembler | assembler + hidden reactor | no | heat output |
| planet-muluna burner roboport | roboport + fluid-fuelled assembler | no | roboport core |
| planet-muluna telescope | assembler + constant combinator | no | crafter with recipes plus CC |
| aai-loaders | loader + hidden storage tank | already solved | in 2.1, `energy_source` on `LoaderPrototype` accepts `fluid` |
| aai-signal-transmission sender / receiver | roboport (for the buffer) + 2 combinators + nth(30) energy poll | **full** (endpoint) | S1 electric + CC script output + `status_changed`; the hidden-surface wiring is unrelated |
| equipment-gantry | assembler shell + 3 containers at offsets + prototype per rotation | **full** | S3: grid-item / equipment / output inventories routed by filters, `start = "script"`, `inventory_changed` + `cycle_finished` |
| Cerys wrecks | assembler with repair recipe, polls `products_finished` every 15 ticks | **full** | S3 with `ingredients` = repair kits, `cycle_finished` doing the swap |
| Cerys radiative tower | reactor + prototype per radius | no | heat emitter with runtime radius |
| Cerys module inserter | inserter + proxy into module inventory | partial | a composed machine's module inventory can be `inserter_access = "insert"`; vanilla crafters still need the proxy |
| Moshine scanner stages | assembler per stage, `on_crafted_event` | **full** | already event-driven; one prototype whose `products` are the next stage's parts |
| LTN stop | train stop + lamp + 2 constant combinators | no | train-stop core |
| cybersyn2 wagon reader, project-cybersyn combinator | combinator + proxy / constant combinator | no | combinator core |
| Factorio-Tiberium control node | beacon + hidden beacon with N modules | no | broadcaster |
| Factorio-Tiberium emitters | EEI + fish target + walls | partial | S1 electric with buffer + `status_changed` replaces the energy poll; walls stay |
| EditorExtensions infinity wagon / accumulator | fluid wagon + infinity pipe / prototype per mode | no | vehicle; EEI priority |
| Nanobots2 roboport interface | roboport + combinator + radar as timer | partial | the timer: an S2 automatic cycle with `cycle_finished`; the roboport stays |
| rec-blue-plus deployer / scanner | container + hidden constant combinator, `on_tick` | partial | S0 with CC read + script output; circuit input still read by the mod, on a cycle event |
| Verbose-Engineering silo | rocket silo + combinator | no | silo core |
| PowerPlusPowerMeter | combinator + 3 interfaces | no | needs network statistics |
| spoilage-scanner | combinator, every entity every tick | partial | CC script output + an S2 cycle as the sample period; the neighbour read stays Lua |
| Mining_Drones depot | assembler as config selector + proxies | partial | S3 with `start = "script"`; drones stay units |
| SpidertronPatrols dock | proxy-container + round robin | no | proximity |
| angelsrefining sea pump | placeholder swapped to drill | no | mining |

Count: 8 full, 9 partial, 1 already solved, 23 no. Gaps closed: 10 of 13 (about 120 of the ~134 counted hits;
gaps 11-13, 14 hits, stay open). The type removes the shell-plus-loop pattern and the hidden container /
combinator on the entities above; it does not remove pY's biggest-count cost (farms), any generator, or any
beacon trick on vanilla machines.

---

## Appendix B: v2 parts

The parts proposed beyond v1 (generation, heat output, circuit input, effect broadcast, triggers on cycle,
typed settings, wildcard ingredients, continuous process, tile and surface products, logistic roles, small
S0 fields), with the engine mechanism each wraps, its shape effect, the rows it unlocks and a staging plan,
are in `docs/V2-PARTS.md`. Nothing in Appendix B changes v1; every v2 part obeys section 0.
