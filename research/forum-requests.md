# Forum requests: entity parts and behaviours modders could not get (2019-2026)

Read-only research for the composable-entity writeup. Sources are forums.factorio.com threads found through
WebSearch excerpts; the forum itself returns 403 to direct fetches, so nothing here comes from a full thread
read. Where a date is marked "~", it is estimated from the phpBB post id (p=450k is about 2019, p=520k about
Nov 2020, p=580k about Jan 2023, p=632k about Nov 2024, p=655k Dec 2024, p=677k about mid 2025, p=687k about
Oct 2025, p=695k about early 2026). "Implemented?" is checked against `data/changelog.txt` (Factorio 2.1.24)
and the API reference at lua-api.factorio.com.

Subforums: "Modding interface requests" (f=28), its children "Implemented mod requests" and "Won't implement",
and "Ideas and Requests For Mods".

## The anchor thread

**Divorcing behavior from entities** (2018), https://forums.factorio.com/viewtopic.php?p=367885
- Ask: split entities into components (physics, UI, energy, logic).
- Rseding91: a runtime component system "will never exist and perform the same or better than the static model";
  no game he knows does it with acceptable performance. But on a *general-purpose, highly customizable modding
  entity* (p=373679, p=386083): "I'm not against that concept but I've yet to see anyone write up how such an
  entity would work". The open question he named: how deep the writeup should go and "whether parts of it can
  just be shut off". bobingabout agreed a runtime ECS would collapse on performance.
- This is the door the proposal walks through: parts chosen at prototype load, not at runtime, and parts that
  are absent cost nothing.

## Catalogue

Legend: [W] won't implement / declined, [I] implemented later, [P] partially covered, [O] open / no answer.

### A. Compound entities themselves (the pattern the proposal replaces)

1. **A new prototype type to describe compound entities?** (~2020), https://forums.factorio.com/viewtopic.php?p=512078 [W]
   - Ask: `type = "compound-entity"` listing a proxy entity, components and a control-script tag, so mods
     (e.g. a battery-powered cargo ship) could compose entities from other mods.
   - Limitation: no engine notion of a parent owning child entities; every mod hand-rolls on_built/on_mined
     bookkeeping.
   - Rseding91: "this along with the other request seem too much like a hack than a proper or even partial
     solution for compound entities." eradicator: children should not be independently reachable from the API.
   - Takeaway: Wube rejects *glue* for compound entities. A single entity with built-in parts is the "proper
     solution" this reply implies is missing.

2. **Making "fake single" entity from multi entities?** (Jan 2023), https://forums.factorio.com/viewtopic.php?p=580478 [O]
   - Ask (modding help): one item places two linked entities. Answer (Pi-C): placeholder + hidden entities,
     track ownership yourself, clean up on mine/die (Bio Industries as the example).
   - Shows the cost of the status quo; related bug p=553277: fast-replace removes extra entities at the same
     position and staff had no clean fix.

3. **Packed Entity Prototype, for using multi entity to do custom function** (~Oct 2025), https://forums.factorio.com/viewtopic.php?p=688799 (also p=697708) [O]
   - Ask: a "PackedEntity" prototype stacking sub-entities, managed by the engine.
   - Argument in the post: hand-written linking is tedious and error prone, and "looping over long lists every
     tick is really worse for UPS, especially for large factories".
   - Replies recall Rseding91 rejecting an ECS; another reply suggests generic build/destroy events with native
     filters. No staff acceptance visible.

4. **Data-driven tooltip forwarding from script-linked hidden/composite entities** (2026, after 2.1.7), https://forums.factorio.com/134073 [O]
   - Ask: hidden helpers (accumulators, electric-energy-interfaces, fluid boxes) stacked under the visible
     entity should forward live values into the parent's tooltip.
   - Limitation: 2.1.7 added `LuaEntity::set_tooltip_field()` [I-partial], but live data then needs Lua on
     ticks. Klonan has warned elsewhere that hidden entities leak into blueprints/component lists.
   - Very current evidence that compound entities are still the norm in 2.1.

5. **Generic entity** (2016, older than the window but the canonical ask), https://forums.factorio.com/viewtopic.php?t=33010 [W]
   - Ask: an entity type with no predefined behaviour. Dev reply: engine design makes it hard; ask for specific
     entity features via modding requests instead.

### B. Inventories: extra, script-controlled, linked, proxied

6. **Non-machine with possible input, output, module and fuel inventories** (~Oct 2025), https://forums.factorio.com/viewtopic.php?p=687544 [O]
   - Ask: an entity with furnace-like inventories (input, output, modules, fuel) and the crafting presentation
     (progress bar, animation, sound, power/fuel draw) that does NOT start recipes on its own; the mod decides
     when crafts start and how inventories change.
   - This is almost exactly the proposed entity. Strongest single piece of evidence. No staff reply in excerpts.

7. **More than one input slot on furnace prototypes** (~2025), https://forums.factorio.com/viewtopic.php?p=667877 [O]
   - Ask: `source_inventory_size > 1` on furnaces. Docs still cap it at 1; a 0.13-era post says Rseding91 hard
     coded the limit for performance. Workaround: storage entity + control script, "can cause desyncs if done
     incorrectly".

8. **Allow Quality Crafting To Use Multiple Output Slots** (~early 2026), https://forums.factorio.com/viewtopic.php?p=694804 [O]
   - Ask: furnace `result_inventory_size` extra slots are not used for different qualities of the same item;
     proposes `additional_result_inventory_size` for assemblers. "Any machine without direct belt output ...
     is badly limited by this" in modded play.

9. **Api Request: Add defines.inventory.assembling_machine_trash & a way to write in assembling machine inv** (~2025), https://forums.factorio.com/viewtopic.php?p=660581 [P]
   - Ask: write to crafter trash/dump inventories, resize trash. 2.0.48 added `crafter_trash`; trash size is
     still fixed (2.0.36). Size not moddable.

10. **Extending usefulness of linked inventory (and script inventory)** (~2023), https://forums.factorio.com/viewtopic.php?p=580752 [W-ish]
    - Ask (Honktown): persistent handle on a linked-container inventory independent of any chest;
      `game.get_linked_inventory(force, prototype, link_id)`.
    - boskid: "inventories are not targetable", a LuaInventory must bind to a targetable owner that has
      inventories. Engine limitation: inventory identity is owner-bound. Relevant to the design: inventories
      as parts of an entity are naturally targetable through that entity.

11. **Add LuaEntity.drop_inventory [RW] and LuaEntity.pickup_inventory [RW]** (~Feb 2025), https://forums.factorio.com/viewtopic.php?p=664814 [W]
    - Ask: choose which inventory inserters drop into/pick from, instead of hidden proxy containers.
    - boskid: won't implement. Reason (curiosity): inserter input is not "insert into inventory X"; the entity
      decides, and machines advertise up to four output inventories. Workaround: proxy-container (2.0.38) with
      `proxy_target_entity/inventory` [I]. Design takeaway: inserter routing must be a per-part prototype rule.

12. **Inserters ignoring ProxyContainers** (Jul 2025), https://forums.factorio.com/viewtopic.php?p=676926 [resolved]
    - Not a limitation (force mismatch), but shows modders now build multi-inventory machines out of
      proxy-container + script inventory, i.e. a fourth hidden entity per machine.

13. **Gui element that shows script inventory** (~2025), https://forums.factorio.com/131526 [I in 2.1.7]
    - Ask: a GUI element that renders a `game.create_inventory()` inventory inside a custom GUI (instead of
      an invisible container whose GUI is force-opened).
    - Implemented: 2.1.7 "Added LuaGuiElement type 'inventory' ... Added on_gui_inventory_action event."
      Related open asks: **Add LuaGuiElement type for InventorySlot?** https://forums.factorio.com/135618 and
      **LuaGuiElement Inventory filter slots** https://forums.factorio.com/135616 (2026).

14. **Limit inventory stack size in a container** (~2025), https://forums.factorio.com/viewtopic.php?p=673694 [I in 2.0.56]
    - Implemented as `inventory_type = "with_custom_stack_size"` + `stack_size_max` (changelog 2.0.56, also
      `with_filters`, `with_weight_limit`). Precedent: Wube does accept container inventory options when they
      are prototype-time flags. Also 2.0.50 `LuaEntity::set_inventory_size_override` (container, cargo wagon).

15. **Container Entities: More inventory control** (older, pre-2019), https://forums.factorio.com/viewtopic.php?p=111820 [P]
    - Rseding91: "more of a suggestion ... feasible for the most part", GUIs would need updating for filtering.
      Mostly covered by 14 years later.

### C. Energy sources on entities that do not have them

16. **Add the field "energy_source" to transport-belt, underground-belt, splitter, loader** (Dec 2024), https://forums.factorio.com/viewtopic.php?p=654992 [W]
    - Rseding91 (23 Dec 2024): "This is never happening." Energy source support requires the entity to be
      *updatable*, which belts will not be. Loaders already are updatable (2.0).
    - Key quote for the design: Wube's cost model is "updatable or not". The proposal's rule "only updatable if
      a part needs ticking" speaks directly to this.

17. **Allow fluid energy source for lamps?** (Nov 2020), https://forums.factorio.com/viewtopic.php?p=520549 [W]
    - Rseding91: lamps are batched in the electric network and not updatable; "I personally don't want to
      implement and maintain a new variant of lamp just for energy source support." Left in requests "on the
      off chance another developer wants to sign up for maintaining a new entity type."
    - Suggested workaround: fixed-recipe assembling machine with a burner/fluid energy source and a null recipe.
      That workaround is the "assembler as generic core" pattern this proposal formalises.

18. **standardized energy sources for improved possibilities** (2017, context), https://forums.factorio.com/viewtopic.php?p=315055 [W]
    - Staff: entities that lack an energy source type lack it "for performance reasons". Same 0.13 thread
      (p=187844): burner energy sources need per-entity code; radars, lamps, pumps fail with burner.

19. **Linked Energy Sources/Script-Controlled Electric Networks** (~Jan 2025), https://forums.factorio.com/viewtopic.php?p=657207 [O]
    - Ask: an electric energy source that connects only via script (linked, like linked fluidboxes/containers).
      Reply: today "integrate a power pole into your compound entity". boskid elsewhere: electric networks are
      not targetable.

20. **To have "assembling-machine" entity type generate electricity** (~mid 2025), https://forums.factorio.com/viewtopic.php?p=677298 [O]
    and **Allow Generator to produce byproducts, or allow AssemblingMachinePrototype to have negative
    energy_usage** (~Nov 2024), https://forums.factorio.com/viewtopic.php?p=633859 [P]
    - Ask: a crafter that also outputs electricity, or a generator with a solid/fluid byproduct.
    - Staff on the similar heat request: power output is outside the scope of assembling-machine; use a
      scripted composite entity. 2.1.7 added `GeneratorPrototype::output_fluid_box, spent_fluid` and
      `FluidEnergySource::output_fluid_box` (fluid byproduct only) [P].

21. **Assemblers could implement `heat_buffer` to output Heat via Heat Pipe?** (~Feb 2021), https://forums.factorio.com/viewtopic.php?p=536323 [W]
    - Moved to "Things we aren't going to implement". Workaround: hidden heat-interface per assembler (UPS cost,
      "quite common in modding").

### D. Script-controlled crafting, timers, completion events

22. **Event for machine crafting complete** (Nov 2024), https://forums.factorio.com/viewtopic.php?p=632310&t=119719 [I in 2.1.12, opt-in]
    - Ask: react when a custom assembler finishes a craft without polling `crafting_progress` /
      `products_finished` every tick. Replies: needs a filter, 2.0 can do multiple crafts per tick; workaround
      a dummy product with a 1-tick spoil trigger.
    - Implemented: 2.1.12 "Added RecipePrototype::raise_on_crafted" (event `RecipeCraftedEvent` with entity,
      recipe, quality data; only raised for crafting machines) and "Added ScriptTriggerEffectItem::custom_event".
    - IMPORTANT precedent: Wube shipped exactly the "per-prototype opt-in event instead of a per-tick hook"
      shape the proposal asks for. Older ancestor: **Entity On_crafting_complete event** (2016)
      https://forums.factorio.com/viewtopic.php?p=255754 (rejected then as "fires too often").

23. **Add crafting_progress and bonus_progress R/W to science labs** (~2026), https://forums.factorio.com/viewtopic.php?p=692025 [O]
    - Staff questioned the purpose. Shows the desire for script-driven progress on non-crafter entities.

24. **[2.0.77] Calling set_recipe() and writing to crafting_progress ... ignores quality** (2026), https://forums.factorio.com/viewtopic.php?p=692818 [fixed 2.1]
    - Evidence that mods drive assemblers from script (set_recipe + crafting_progress) as a timer/progress bar,
      i.e. the "assembler as a timer" pattern used by pY dig sites.

25. **Event for on_pre_recipe_changed / on_recipe_changed** (~2019), https://forums.factorio.com/viewtopic.php?p=461088 [W]

### E. Status, tooltips, per-entity events, update hooks

26. **defines.entity_status.broken cannot be set through LuaEntity::status** (~2025), https://forums.factorio.com/viewtopic.php?p=672970 [I]
    - `LuaEntity::custom_status` exists since 2.0.7, but it is only shown when a player hovers/opens; the
      ElectricEnergyInterface thread (https://forums.factorio.com/viewtopic.php?p=690374, 2.0.76) notes
      script has no cheap way to detect the conditions (low power) to set it, so it again needs polling.

27. **LuaEntity::register_on_signal_changed proposal** (~2025), https://forums.factorio.com/viewtopic.php?p=683267 [P in 2.1.21]
    - Ask: register specific entities to get an event when their circuit input changes, like
      `register_on_object_destroyed`; "only ever fire for that small handful of entities that are registered".
    - 2.1.21 added `LuaEntity::get_signals_changed()` (a poll, not an event). Related:
      **LuaCircuitNetwork.signals_changed** https://forums.factorio.com/98542.

28. **on_module_changed (assembler, furnace)** (eradicator, re-bumped 2024-2026), https://forums.factorio.com/viewtopic.php?p=607687 [W]
    - Moved to won't implement; Rseding91 floated a narrower "on_post_module_configuration_changed".
    - Inventory-changed events in general: Rseding91 "performance for something like that would be a problem"
      (https://forums.factorio.com/viewtopic.php?p=180836). Per-prototype opt-in is the answer to that objection.

29. **on_combinator_recieve_circuit_update** (context), https://forums.factorio.com/75678 [W]
    - Staff: an every-input-change event would effectively run like on_tick; mods should round robin instead.

30. **Promote Circuit Connections to Base Entity Type** (~2025), https://forums.factorio.com/viewtopic.php?p=682756 [W]
    - Ask: let any entity carry wires. Reply: "No." Circuit connectors exist only on entities with control
      behaviour (poles excepted); connector count varies per type. A circuit connector as a selectable part,
      with its control behaviour, matches that rule.

### F. Spoilage, beacons, misc parts

31. **Add custom spoilage categories** (~2026), https://forums.factorio.com/viewtopic.php?p=697061 [O]
    - Rseding91: spoil result is "simply a trigger that runs"; most of the work is Factoriopedia integration.
    - No container spoil-rate modifier exists in 2.1 (changelog shows only item/quality spoil fields:
      `QualityPrototype::spoil_ticks_multiplier` 2.1.7, `ItemPrototype::quality_affects_spoil_ticks`). Fridge /
      freezer / cryo-container / corrundum ice-box mods all do it in Lua loops. **Increase spoilage timer**
      https://forums.factorio.com/120079 and **Technology request: Conservation**
      https://forums.factorio.com/viewtopic.php?t=116097 ask for freezing.

32. **Fixed effect for beacons as prototype** (~mid 2025), https://forums.factorio.com/viewtopic.php?p=676269 [O]
    - Ask: a beacon that projects an effect with no module slots. Rseding91 suggested negative-pollution entity
      instead. Older **fixed-module beacon** thread (~2019, https://forums.factorio.com/viewtopic.php?p=455855):
      workaround is a hidden non-operable beacon under a visible entity; "doubled the entity count". 2.1.7 added
      `EffectReceiver::*_limits` (partial).

33. **Add flow to Fluid box API** / **insert_fluid fluidbox index support** (~2020), https://forums.factorio.com/viewtopic.php?p=490560 [I in 2.1.7]
    - 2.1.7 added per-index `LuaEntity::add_fluid/remove_fluid/get_fluid_box_*`. Linked fluidbox connections
      (**Linked pipes** https://forums.factorio.com/viewtopic.php?p=533108) shipped in 2.0.7.

## What Wube has said, distilled

- No runtime component system (Rseding91 2018, repeated 2025 in the Packed Entity thread).
- Open to a general-purpose moddable entity *if written up* with how parts can be shut off (2018).
- Won't add energy sources to non-updatable entities (belts 2024, lamps 2020): the cost unit is updatability.
- Won't maintain a new entity variant just for one feature (lamps 2020), "unless another developer signs up
  for maintaining a new entity type".
- Rejects compound-entity glue as "a hack" (2020); rejects arbitrary inserter inventory routing (boskid 2025).
- Inventories must belong to a targetable owner (boskid 2023).
- Generic events are refused on performance grounds; per-prototype opt-in events are accepted
  (`RecipePrototype::raise_on_crafted`, 2.1.12; `ScriptTriggerEffectItem::custom_event`, 2.1.12).
- Prototype-time inventory options are accepted (2.0.56 container `inventory_type` variants).

## Implemented since the asks (changelog evidence)

| Feature | Version | Covers |
|---|---|---|
| linked-container | 1.1.0 | shared inventories |
| `LuaEntity::custom_status` | 2.0.7 | scripted status (display only) |
| linked fluidbox connections | 2.0.7 | script-linked fluids |
| `is_updatable`, `disabled_by_script` | 2.0.26 | updatability visible to Lua |
| proxy-container | 2.0.38 | inserter access to arbitrary inventories |
| `set_inventory_size_override` | 2.0.50 | container/wagon resize |
| container `inventory_type` with_filters/weight/custom_stack | 2.0.56 | container inventory options |
| `Prototype::custom_tooltip_fields` | 2.0.59 | static tooltip lines |
| GUI element "inventory", `set_tooltip_field`, per-index fluid API, generator spent_fluid | 2.1.7 | script inventory UI, live tooltips, fluid parts |
| `RecipePrototype::raise_on_crafted`, `ScriptTriggerEffectItem::custom_event` | 2.1.12 | opt-in craft-complete event |
| `LuaEntity::get_signals_changed()` | 2.1.21 | cheaper circuit polling |

Still missing: an entity that picks its inventories/energy/fluid/timer/modules/circuit parts freely; fuel or
module slots on non-crafters; multi-input furnaces; container spoil modifiers; inventory/module change events;
per-entity update hooks; status that updates without polling; script-only electric links.

## Threads worth a full read

1. https://forums.factorio.com/viewtopic.php?p=367885 (Divorcing behavior from entities; Rseding91's terms)
2. https://forums.factorio.com/viewtopic.php?p=687544 (Non-machine with input/output/module/fuel inventories)
3. https://forums.factorio.com/viewtopic.php?p=512078 (compound-entity prototype; "too much like a hack")
4. https://forums.factorio.com/viewtopic.php?p=688799 (Packed Entity Prototype; 2025 ECS refusal restated)
5. https://forums.factorio.com/viewtopic.php?p=654992 (belts energy source; updatability cost model)
6. https://forums.factorio.com/viewtopic.php?p=632310 (crafting complete event; now raise_on_crafted)

## Candidate test entities suggested by these threads

- Fuel-burning chest/heater: container + burner energy source, no recipe (16, 18).
- Multi-input "furnace" with script-driven craft start and progress bar (6, 7).
- Freezer chest: container whose part sets a spoil-rate multiplier, no Lua loop (31).
- Fixed-effect beacon: effect emitter with no module inventory (32).
- Assembler-plus-generator: crafter + electric output part (20).
- Heat-emitting crafter: crafter + heat buffer output (21).
- Fluid-powered lamp / fluid-boxed container (17).
- Dig site timer: progress-timer part + output inventory + opt-in on_cycle event, replacing assembler + hidden
  container + unit AI (22, 24).
- Status-reporting entity: custom status derived from part state without polling (26).
- Circuit-reading container with inventory-changed opt-in event (28, 30).
