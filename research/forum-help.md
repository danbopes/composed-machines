# Forum research: modders blocked by fixed entity types

Angle: Modding help / Modding discussion / Modding interface requests on forums.factorio.com,
plus mod-portal discussions, Alt-F4, Steam. Method: WebSearch only (forum pages return 403 to
WebFetch; reddit.com is blocked to the search agent, so r/factorio and Discord contributed
nothing directly). Everything below is reconstructed from search-result excerpts. Threads
marked **[read]** in the last section need a full read before they are quoted in the writeup.

Dates: where the excerpt gave no date, the year is estimated from the phpBB post id
(p≈150k → 2016, p≈220k → late 2016, p≈275k → 2017, p≈368k → 2018, p≈510k → 2020,
p≈580k → 2023, p≈655k → early 2025, p≈690k → 2025/26). These estimates are marked "~".

---

## 1. Wube's stated position (context for everything else)

| Thread | URL | Date | Gist |
|---|---|---|---|
| Divorcing behavior from entities | https://forums.factorio.com/viewtopic.php?p=367885 (also p=368117, 368897, 373679, 386083, 386247, 387174, 387791, 387802) | 2018 | Modder proposes splitting entities into components (dimensions, selection, behaviour, optional Lua hook). Rseding91 first asks what kind of writeup is wanted ("detailed C++ performance analysis or a modder's view of what would I do with it?"), then says after four years in the codebase he is convinced a runtime component system "will never perform the same or better than the static model", but he is "not against the concept" and has "yet to see anyone write up how such an entity would work". |
| Entity/component model in prototypes | https://forums.factorio.com/viewtopic.php?p=154019 (154064, 154297, 154824, 155391) | ~2016 | Same idea, prototype-level. Filed under "Things that we aren't going to implement". Example given: a boiler decomposes into inventory + fluid box + fluid connectors. A reply: "suggested many times, devs keep saying it's not gonna happen". |
| Entity Prototype Composition | https://forums.factorio.com/viewtopic.php?p=151612 | ~2016 | Staff reply: "I've never seen any game implement such a system that did anything close to what Factorio does today." |
| [lua][feature] User defined data attached to lua entity | https://forums.factorio.com/viewtopic.php?p=578072 | ~2023 | In "Won't implement". boskid: extend entities with a mod table keyed by unit_number; generic tags rejected because every entity (trees, resources) would grow in memory. Relevant: Wube's objection is per-entity memory/CPU for entities that do not use the feature, which is exactly what prototype-time composition avoids. |

Take-away for the writeup: the objection is (a) runtime composition costs every entity,
(b) nobody wrote the concrete design. A prototype-time, pay-only-for-what-you-pick design
answers (a) directly and the writeup itself answers (b).

---

## 2. "How do I make an entity that ..." threads (the asks)

Each entry: ask → workaround given → cost of the workaround.

### 2.1 Combo entity: accum + chest. How?
- URL: https://forums.factorio.com/viewtopic.php?p=220800 — ~late 2016, Modding help
- Ask: a chest that inserters/loaders can use, which also draws power while "charging".
- Workaround: "script-placing another hidden entity is the only workable solution"; chest +
  hidden accumulator, or a hidden electric-energy-interface if the draw changes at runtime;
  make the hidden part non-destructible and non-minable.
- Cost: two entities per building, build/remove bookkeeping, Lua to vary the draw.
- Component mapping: `inventory` + `energy_source{electric}`.

### 2.2 Making "fake single" entity from multi entities?
- URL: https://forums.factorio.com/viewtopic.php?t=104996 (posts p=580478, 580480) — ~2023
- Ask: one item that places a "substation facility" which both transfers and stores power;
  worried about item duplication if two entities are placed/removed separately.
- Workaround (Pi-C): one item places a placeholder; listen to *all* build events; create
  the real hidden entities; keep a table of which hidden entities belong to which visible
  one; destroy them on mined/died.
- Cost: every build/remove event path, duplication risk if any path is missed.

### 2.3 Adding automatic belt loaders into a furnace entity
- URL: https://forums.factorio.com/viewtopic.php?p=510612 — Sep 2020
- Ask: a furnace with built-in loaders.
- Workaround (DaveMcW): a second, invisible (blank sprite) loader entity placed by a
  build handler; others point to Loader-Furnace and miniloader (hidden inserters).
- Cost: N extra entities per furnace, each ticking on its own.

### 2.4 Event for machine crafting complete
- URL: https://forums.factorio.com/viewtopic.php?p=632310 (632716, 633369) — ~2024 (2.0)
- Ask: a Lua event when a custom assembler finishes a craft.
- Workaround: poll `crafting_progress` / `products_finished` every tick; or micromario's
  hack: add a dummy result item with a 1-tick `spoil_to_trigger_result` and catch the trigger.
- Cost: per-tick polling over all machines, or polluting recipes with fake items.
- Older siblings: "Entity On_crafting_complete event" https://forums.factorio.com/viewtopic.php?p=255754
  (2016; Nexela doubts it will ever be added because it would fire too often across all
  machines) and "Recipe Finished Trigger or Event" https://forums.factorio.com/viewtopic.php?p=668733
  (~2025; proposes per-recipe opt-in registration precisely to avoid that).
- Component mapping: **per-prototype opt-in event** is exactly what both requests ask for.

### 2.5 Smart assembling machines [solved]
- URL: https://forums.factorio.com/viewtopic.php?p=137681 — ~2016
- Ask: assembler on the circuit network (pre-0.17).
- Workaround: a dummy entity that connects to the network plus control.lua "magic" to
  link the two.
- Cost: hidden entity + polling. (Vanilla later gained this, but only for that one type.)
- Component mapping: `circuit_connector` as a pickable part.

### 2.6 circuit network connector for hidden loader entity
- URL: https://forums.factorio.com/viewtopic.php?p=380443 (380520) — ~2018
- Ask: circuit control of loaders.
- Answer: loaders do not support circuit/logistic connections. Related staff note
  (Direct circuit output and imput, https://forums.factorio.com/viewtopic.php?p=242757):
  a signal must be owned by an entity, so mods use hidden combinators / disabled lamps as pins.
- Cost: hidden combinator per entity, Lua copying signals.

### 2.7 Liquid science input / Help with lab and water
- URLs: https://forums.factorio.com/viewtopic.php?p=267976 (268308);
  https://forums.factorio.com/viewtopic.php?p=245813 (245824) — ~2017
- Ask: a lab that consumes a fluid.
- Answer: lab inputs only accept items ("is not an item"). Workarounds: a pseudo-pack item
  crafted from the fluid, or a hidden pipe under the lab plus a script that drains it and
  toggles `lab.active`.
- Cost: hidden pipe + per-entity script; Steamed mod notes a lab with fluid energy source
  crashed 0.16/0.17 and abandoned it (https://mods.factorio.com/mod/Steamed/discussion/5f4ac08c00178311ffd36147).
- Component mapping: `fluid_box` on a lab-like core.

### 2.8 [0.13.10] Burner energy_source doesn't work in certain entity types
- URL: https://forums.factorio.com/viewtopic.php?p=187844 — 2016
- Answer (Rseding91): not all entities support burner; "specific code has to be put in the
  entity for that to function"; it is a modding interface request.
- Later requests of the same shape: "[2.0.10] Allow the beacon prototype to accept the
  Burner energy_source" https://forums.factorio.com/viewtopic.php?p=624508 (~2024; reply adds
  fluid and heat); turret energy_source only on ammo-turret, artillery excluded
  ("How to stop turrets from firing without electricity?" https://forums.factorio.com/viewtopic.php?p=654671).
- Cost: either impossible or hidden EEI + scripted `active` toggle.
- Component mapping: the energy-source part being generic, not per-type code, is the
  core argument.

### 2.9 Fuel-powered radar
- URL: https://forums.factorio.com/viewtopic.php?p=527757 (also https://forums.factorio.com/93074) — 1.1.6, ~2020
- Ask/report: Fantario adds a burner radar; crash when fuel is inserted with the GUI open.
  Fixed by kovarex. Shows that energy-source combinations outside the tested set hit
  untested code paths in the engine.

### 2.10 Modding mining drills to work without an ore patch / Custom mining drill behavior
- URLs: https://forums.factorio.com/viewtopic.php?p=541351 (~2021),
  https://forums.factorio.com/viewtopic.php?p=225942, https://forums.factorio.com/viewtopic.php?p=450080
- Ask: a drill that produces output without resources (a "dig site").
- Workaround: re-type it as an assembling-machine with a fixed recipe and copy the drill's
  animation. Omega Drill page: drills pick a random ore tile each cycle, "nothing mods can
  do about that, scripts won't help either".
- Component mapping: `progress_timer` + `output inventory` without the recipe machinery;
  this is the pY dino-dig-site pattern.

### 2.11 Invisible/visible but still selectable entity?
- URL: https://forums.factorio.com/viewtopic.php?p=153202 — ~2016
- Ask: 1x1 container that can toggle visibility.
- Answer: visibility is in the prototype; swap between two entity prototypes and copy the
  inventory each time.
- Cost: destroy/create + inventory copy on every state change.

### 2.12 Api Request: assembling_machine_trash + write into assembler inventories
- URL: https://forums.factorio.com/viewtopic.php?p=660581 (660791) — ~2025
- Ask: insert arbitrary items into an assembler (works for chests/bots/belts, not
  assemblers). Partially addressed in 2.0.36 via trash inventory, still fixed size.
- Component mapping: additional generic `inventory` slot groups on a crafting core.

### 2.13 Packed Entity Prototype, for using multi entity to do custom function
- URL: https://forums.factorio.com/viewtopic.php?p=688799 (697708) — ~2025/26, interface request
- Ask: a new prototype that bundles several linked sub-entities into one stackable,
  script-friendly unit with build/remove handled by the engine. Argues per-tick loops over a
  data list are bad for UPS.
- Reply: suggests generic build/destroy events with native name filters instead.
- Closest existing request to the author's proposal. Must read.

### 2.14 Data-driven tooltip forwarding from script-linked hidden/composite entities
- URL: https://forums.factorio.com/134073 (p=694914, 694919, 695002) — 2026 (2.1.7)
- Ask: show a hidden accumulator's charge etc. in the parent roboport's tooltip
  (`register_dependent_tooltips`). Notes 2.1.7 `set_tooltip_field` works but fast-changing
  data means heavy Lua. Reply points at Tooltip Library mod. Author discloses AI drafting.
- Shows a 2026-era cost of compound entities: the UI lies, and fixing it costs Lua per tick.

### 2.15 Linked Energy Sources / Script-Controlled Electric Networks
- URL: https://forums.factorio.com/viewtopic.php?p=657216 (657207, 657226, 657238, 677324) — Jan 2025
- Ask: an energy source that connects only by script (linked belts/containers/fluid boxes
  exist; energy does not). Workarounds are paired EEIs with Lua transfers.
- Related: "Request: Simplification of custom power sources" https://forums.factorio.com/viewtopic.php?p=587705
  (~2023): custom generators require an infinity pipe feeding steam into a turbine hidden
  under the custom entity; Rseding91 replied (text not in excerpt).

### 2.16 Need advice for first mod / Adding a Hidden-Electric-Energy-Interface to an entity
- URLs: https://forums.factorio.com/viewtopic.php?p=239905 (~2017), https://forums.factorio.com/viewtopic.php?p=408100 (~2019)
- The canonical "attach a hidden EEI to give X a power draw" answers.

### 2.17 Spoilage helpers (2.0, Space Age)
- Spoilage Combinator https://mods.factorio.com/mod/spoilage-combinator : hidden timer
  combinators; author says inventory scans cause UPS spikes the API does not let it avoid;
  changelog spreads scans across ticks; hidden circuit helpers froze on cold surfaces (a
  hidden part inherited a mechanic the parent did not want).
- Cryo-container https://mods.factorio.com/mod/cryo-container/changelog : "slowed down
  refresh to stay UPS friendly". No Spoilage in Space: 300-tick scan, configurable.
- Same pattern as corrundum's ice-box. Component mapping: an inventory with a
  `spoil_rate_multiplier` part, no Lua.

---

## 3. Recurring advice threads and the failure modes of compound entities

### 3.1 Blueprints
- **Blue-prints and Hidden Entities** https://forums.factorio.com/viewtopic.php?p=274182 (~2017):
  bio farm's hidden parts missing when placed by blueprint; fix is to handle robot builds
  and ghost revives too. Excerpted code has an impossible condition
  (`name == "entity-ghost" and name == "bi_bio_farm"`), i.e. this is easy to get wrong.
- **blueprint scrip created entity** https://forums.factorio.com/viewtopic.php?p=370376 (~2018, many posts):
  Klonan: putting hidden entities in blueprints means they appear in the component list and
  players can remove them; make the entity that carries the wires the main one.
- **[1.0.0] Entity flag "hidden" also makes it "not-blueprintable"** https://forums.factorio.com/viewtopic.php?t=89383
  and **[Solved] Incomplete description of entity flag "hidden"** https://forums.factorio.com/viewtopic.php?t=89398 (2020).
- Hidden item for hidden part makes blueprints reference an item that cannot be built
  (Burner Fuel Bonus uses 2 items for N entities): https://forums.factorio.com/viewtopic.php?p=535757 (~2021).
- **Storing Custom Metadata on Entities** https://forums.factorio.com/viewtopic.php?p=613616 (615133) (~2023):
  unit_number tables fail on blueprint paste over existing entities; DaveMcW: limitation of
  the API, workaround is to disable copy/paste for the entity. Repost "Metadata on Entities"
  https://forums.factorio.com/viewtopic.php?p=615628.

### 3.2 Undo / redo / cut-paste
- Composite entity undo thread https://forums.factorio.com/viewtopic.php?p=655527 (~early 2025):
  main entity constructible + sub-entity deconstructible breaks undo and cut/paste. Fix: a
  third, blueprint-only entity with a script swapping names at creation; works for the
  blueprint tool but not cut/copy because the handler cannot read
  `player.blueprint_to_setup`; ghosts require injecting the sub-entity removal into the
  latest undo item via LuaUndoRedoStack.
- https://forums.factorio.com/viewtopic.php?p=688381 (~2025): scripted entities with wires vanish
  on undo; no answer.
- **Allow mod to track entities across undo** https://forums.factorio.com/viewtopic.php?p=584507 (~2023, GlassBricks):
  no stable id across undo/revive; dummy-combinator workaround does not work for vanilla
  entities; asks for `old_unit_number` in undo events.
- **item_index doesn't seem to fully work for surface.create_entity** https://forums.factorio.com/viewtopic.php?p=677355 (~2025):
  multi-tick undo actions; dev says the parameter is `undo_index` (docs wrong).
- Crafting Combinator Xeraph's Fork deprecated because the composite design "creates more
  problems ... just to make it restorable from undo":
  https://mods.factorio.com/mod/crafting_combinator_xeraph/discussion/638e5af5d7899393f855150d
- The whole library **Things** (https://mods.factorio.com/mod/0-things) exists to give
  parent/child compound entities identity that survives blueprint and undo; its changelog
  warns disabling it breaks saves. A library-sized workaround is itself evidence of the gap.

### 3.3 Cloning
- Moon Logic / Bottleneck / Construction Drones all needed `on_entity_cloned` handlers for
  their helper entities when Space Exploration clones ship surfaces; helpers clone as
  separate entities and must be destroyed/re-linked on the destination:
  https://mods.factorio.com/mod/Moon_Logic/discussion/5fc618f0a5bbf2dbb181872f ,
  https://mods.factorio.com/mod/Bottleneck/discussion/5d6a3d585c14aa000b3fac9b ,
  https://mods.factorio.com/mod/Construction_Drones/discussion/5edb35e234a5c4000ce3bdeb
- **Make on_marked_for_deconstruction not fire before cloning events** https://forums.factorio.com/viewtopic.php?p=576712 (~2023):
  event ordering surprises during clone.

### 3.4 Mining returns / minability / upgrade planner
- **Unable to deconstruct entity that lacks a paired item** https://forums.factorio.com/viewtopic.php?p=277134 (~2017).
- **[0.18.22] Improve error message about wrong next_upgrade** https://forums.factorio.com/viewtopic.php?p=493092 (2020):
  mining result must be exactly one non-hidden item; hidden helper parts collide with this.
- **[2.0.73] Hidden minable entities are impossible?** https://forums.factorio.com/viewtopic.php?p=688255 (Jan 2026).
- **[2.0.23] LuaEntity minable always reads back as false** https://forums.factorio.com/123921.
- **Help with removing hidden entities when mining a tile** https://forums.factorio.com/viewtopic.php?p=286940 (~2017).
- Upgrade planner ignores hidden prototypes (needs an interface request):
  https://gitlab.com/jfletcher94/factorio-mods/-/work_items/26 ;
  "Add EntityPrototype properties for more control of upgrade planner"
  https://forums.factorio.com/viewtopic.php?p=698067 (2026).
- Contents of hidden parts (fuel, items in a hidden chest) are lost or duplicated unless
  the mod forwards them in `on_pre_player_mined_item`/`on_player_mined_entity`.

### 3.5 Picker Dollies / moving
- Picker Dollies and Even Pickier Dollies move one entity and raise an event; compound
  mods must listen and move children, or blacklist themselves via `add_blacklist_name`.
  https://mods.factorio.com/mod/PickerDollies , https://mods.factorio.com/mod/even-pickier-dollies
  No thread found that documents a specific breakage; treat as plausible-not-proven.

### 3.6 UPS / tick cost
- **N-lane Tick Balancer (Lua library)** https://forums.factorio.com/viewtopic.php?p=152105 (~2016):
  per-entity on_tick work is the bottleneck; staggering 1-in-N; Klonan says simple
  staggering is fine for 95% of mods.
- **Distributing Workload of Mod to Multiple Ticks** https://forums.factorio.com/viewtopic.php?t=53405 (~2017).
- EEI shadow entities updated every 15/30 ticks to avoid UPS cost:
  https://forums.factorio.com/viewtopic.php?p=306708 (~2017).
- Bio Industries Bio Farm hidden poles: separate "electric network UPS issues with Bio
  Farm poles" thread, fixed in engine 1.1.105:
  https://mods.factorio.com/mod/Bio_Industries/discussion/652c7c674499e24c39eff96a .
  Bio Cannon only fires if its hidden radar is powered (hidden part leaks a requirement).
- Rseding91: many small electric networks perform worse than one large one
  (https://forums.factorio.com/viewtopic.php?p=431446) — relevant because hidden poles/EEIs
  fragment networks.

### 3.7 UI honesty
- Tooltip forwarding request (2.14), "[2.1.8] Hidden miner prototypes show up in mined-by
  tooltip... Again?" https://forums.factorio.com/134533 (2026), "[2.0.13] hidden_in_factoriopedia
  works in unexpected ways" https://forums.factorio.com/viewtopic.php?p=629879 (alt-click still
  opens the hidden part), power graph shows hidden EEIs as 0 W producers
  (https://forums.factorio.com/viewtopic.php?p=550041).

### 3.8 Modder confessions
- **Alt-F4 #55 "The Dark Alleys of Modding"** https://alt-f4.blog/ALTF4-55/ (2021-12-17):
  MagmaMcFry, raiguard, Deadlock989, Anachrony, PFQNiet, Earendel list invisible mining
  drills for alt-mode arrows, invisible chests, one-way energy connections, hidden entities
  placed while dragging a tape line. Notes some hacks were later made unnecessary by API
  additions, which is the precedent for asking.
- "Modding Hackes" thread https://forums.factorio.com/viewtopic.php?p=369162 (372666) (~2018):
  "I use a lot of hidden entities ... because the primary entity doesn't have all the
  attributes I need"; reply: "you can't give an entity the properties of another entity, an
  entity is what it is and modders are stuck with the palette of existing entities".

---

## 4. Cost summary of the compound-entity pattern (as reported)

| Cost | Evidence |
|---|---|
| Every build path must be handled (player, robot, platform, revive, script_raised) or parts go missing | 2.2, 3.1 Blue-prints and Hidden Entities |
| Blueprints leak hidden parts, or reference unbuildable items | 3.1 Klonan, Burner Fuel Bonus |
| Undo / cut-paste break; needs LuaUndoRedoStack surgery or a whole library | 3.2, Things, Xeraph deprecation |
| Clone (SE ships) needs per-mod handlers | 3.3 |
| Mining returns / upgrade planner constraints on hidden items | 3.4 |
| Moving tools must be handled or blacklisted | 3.5 |
| Per-tick Lua loops, staggered for UPS, so behaviour is coarse | 3.6, 2.17 |
| UI shows the wrong thing (tooltips, power graph, factoriopedia) | 3.7 |
| Engine paths outside tested combinations crash | 2.9, 2.7 Steamed |

---

## 5. Threads that deserve a full read (priority order)

1. **Divorcing behavior from entities** — https://forums.factorio.com/viewtopic.php?p=367885 — the exact Rseding91 wording and what "write up how it works" was asking for.
2. **Packed Entity Prototype** — https://forums.factorio.com/viewtopic.php?p=688799 — the closest live request; check for staff replies and the objections raised.
3. **Composite entity undo/cut-paste** — https://forums.factorio.com/viewtopic.php?p=655527 — the most detailed 2.0 description of the failure modes and the LuaUndoRedoStack workaround.
4. **Event for machine crafting complete** + **Recipe Finished Trigger or Event** — https://forums.factorio.com/viewtopic.php?p=632310 , https://forums.factorio.com/viewtopic.php?p=668733 — precedent for per-prototype opt-in events vs firehose events.
5. **Entity/component model in prototypes** — https://forums.factorio.com/viewtopic.php?p=154019 — prototype-time (not runtime) composition, and why it landed in "won't implement".
6. **Allow mod to track entities across undo** — https://forums.factorio.com/viewtopic.php?p=584507 — identity across undo/revive, needed by any compound entity.

## 6. Candidate entities for the test mod (from the asks above)

- Powered chest: container inventory + electric energy source (2.1).
- Fluid lab / fluid-fed "research" core: lab-like core + fluid_box (2.7).
- Burner beacon / burner radar: energy_source variety on cores that hard-code it (2.8, 2.9).
- Dig site: progress timer + output inventory, no recipe, no resource patch (2.10; pY dino-dig-site).
- Cold box: inventory + spoil-rate part, no Lua (2.17; corrundum ice-box).
- Loader-furnace: furnace core + built-in item I/O (2.3).
- Circuit-enabled anything: circuit_connector part on a type that lacks it (2.5, 2.6).
- Crafting-complete notifier: opt-in on_progress_complete event for one prototype (2.4).
- Battery chest / substation-storage: inventory + accumulator-style buffer (2.1, 2.2).
- Toggle-visible container: render state part instead of prototype swap (2.11).
