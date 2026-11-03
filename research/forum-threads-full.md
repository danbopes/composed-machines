# Forum threads: full reads (2026-11-01)

Read in Chrome (read-only, no interaction). Developer replies are quoted verbatim. Thread order follows the task list; threads 1 and 11 are the same topic and are merged.

---

## 1 + 11. Divorcing behavior from entities

- URL: https://forums.factorio.com/viewtopic.php?p=367885 (p=368117, p=386083, p=387802 are posts in the same topic; Modding discussion)
- First post: Drakomir, Sat Jun 16, 2018
- Size: 22 posts over 2 pages. Page 1 (20 posts, Jun 16 to Nov 24, 2018) read in full. Page 2 (2 posts) could not be reached: the p= permalinks and `&start=20` all render page 1, and the topic id (t=) is not exposed in the page text. Worth one more attempt with the t= id if someone has it.

**The ask.** A full entity-component model: split every entity's baked-in behaviour into components (Physics, Selection, Inserter, Health, Energy, Logic, Sprite, UI, Audio, Container, Script), allow several of a kind per entity, hierarchical, and changeable at runtime (research adding capabilities). Claimed benefits: moddability plus cache-friendly, parallel updates. kumpu narrowed it to "some kind of general purpose/highly customizable entity specifically for modding", accepting lower performance than vanilla. kumpu later sketched a `type = "modding-entity"` prototype composed of "modules" borrowed from existing types (cargo-wagon physics/graphics + assembling-machine UI/container/logic/energy) with `lua_events = { on_production_finished = ... }`. davemcdave sketched registration at load time: a modding-entity with inserter properties is added to the inserter update list, with crafting properties to the crafting list, so no per-tick "has component?" branch.

**Developer replies (verbatim).**

Rseding91, Mon Jun 18, 2018 (reply to "widely adopted by all modern middleware game-engines"):
> I've yet to see any game out there use such a system and perform even moderately well.
>
> From my 4 years experience working with Factorios C++ code base I'm convinced that such a system will never exist and perform the same or better than the static model that Factorio uses now.
>
> The idea sounds nice but if you ever try to implement it you very quickly see how fast it falls apart performance wise due to the dynamic nature of every bit of logic every component has to do.
>
> In summary: it's never going to happen in Factorio.

Rseding91, Sat Jun 23, 2018 (reply to kumpu's general-purpose modding entity):
> I'm not against that concept but I've yet to see anyone write up how such an entity would work and haven't taken the time to try to write that up myself.
>
> If someone did that it would go a long way towards me thinking about adding it to the game.

Rseding91, Sun Jun 24, 2018 (eradicator asked what technical level of writeup: C++ performance analysis, or modder "what would I do with it"):
> That's what I don't know. All of that has to be figured out and then see if it can actually work to make such an entity where parts of it can just be shut off.

Rseding91, Sat Nov 10, 2018 (reply to Lubricus on component arrays / SIMD):
> Show me a game that does what Factorio does as performant as Factorio is with anything you describe here and then I'll start to take these kinds of conversations seriously. ...

posila (now "Former Staff"), Sat Nov 10, 2018:
> That's a little bit harsh response, imho.
> I am big believer in data-oriented design of game engines, and am convinced that there is lot of inefficiency caused by our OOP design. ...
>
> Anyway, any significant change to the entity system simply won't happen any time soon.
>
> CppCon 2014: Mike Acton "Data-Oriented Design and C++"
>
> EDIT: I am not talking about entiy component system specifically here, I have no idea if it would be good fit for Factorio or not, ...

Rseding91, Sat Nov 10, 2018:
> ... I was specifically talking about entity component systems. "Data driven" is not something I see as a concept but more of just "optimize your code". ...
>
> Entity component systems are what I have a problem with and I believe that's what this original post is about ... I don't ever see that working as well as the current system(s) we have in place.

Rseding91, Mon Nov 12, 2018 (bobingabout pointed out `energy_source` is already a pluggable component on boilers, radar etc.):
> Those still don't divorce the behavior from the entity. Each entity that supports these dynamic energy sources has special logic in them to handle each type.

Rseding91, Sat Nov 24, 2018 (after Aidiakapi's long explanation of pure ECS):
> I'm sorry but after reading that you've done nothing but further convince me that entity component systems are nothing but a bunch of smoke and mirrors destined to only appear in internet discussions and demo examples.
>
> What you've described would be *terrible* for any game that has any amount of entity <> entity logic. AKA: your game actually does anything beyond render some cloud of particles.
>
> Especially so in Factorio where virtually everything has some state that it's transforming each time it's updated and that state is effected by other states ... Everything touches everything else.
>
> There's no "update the positions of all biters that are moving" loop in the game that so many ECS examples seem to love showing. There is a *per biter* section of logic ...
>
> I still have not seen one game that uses an ECS do anything near what Factorio is doing. ...

**Other notable points.** bobingabout: furnace = assembling machine with auto-selected recipe, and generalising further stalled on engine rework cost; "small theoretical performance hit" features have been accepted for mod support. H8UL: prefer object composition (like Trigger/projectile nesting) over runtime-swappable hierarchical components.

**Outcome / implications for the proposal.**
- Two separate positions. (a) Runtime ECS / swappable components: a flat no, repeated three times. (b) A single general-purpose moddable entity: "not against", conditional on a writeup, with the specific test "an entity where parts of it can just be shut off". The author's proposal must be framed as (b), never as ECS.
- Rseding91's Nov 12 objection ("special logic in them to handle each type") is satisfied, not contradicted, by a prototype-time composition: the part set is fixed at load, each part is an existing prototype-level part (`EnergySource`, inventories, `FluidBox`), and nothing is swapped at runtime.
- His Nov 24 point (per-entity, interdependent state, "everything touches everything else") argues against SoA system loops; the proposal should keep a normal per-entity update() over the existing parts rather than promise system-wide component loops.
- kumpu's `lua_events = { on_production_finished = ... }` (2018) is an early form of the per-prototype opt-in event idea.

---

## 2. Non-machine with possible input, output, module and fuel inventories

- URL: https://forums.factorio.com/viewtopic.php?p=687544 (Modding interface requests)
- First post: Plop and run, Mon Apr 22, 2024. 2 posts, page 1 of 1, read in full.

**The ask.** An entity that can have every inventory a furnace can have (input, output, modules, fuel), and keeps the crafting *process* (progress bar, animation, sound, power draw, fuel burn) but not the crafting *logic* (when to start, what to consume, what to produce). The mod declares what may be inserted into the input slots instead of recipes and implements the logic itself. A furnace doesn't work because: you cannot delay a craft when ingredients are present (no tick between one craft ending and the next starting); finishing a craft is only detectable by polling the output slot every tick (cited: Space Exploration delivery cannons); you cannot get the item stack the machine consumed, which matters for items with tags or inventories; sometimes there is no craft at all and the machine is just "a fancy chest that outputs items in order they were inserted".

**Developer replies.** None. The only reply is BraveCaperCat (Mon Jan 12, 2026): +1, would help the many mods that use a chest instead of a machine (for example because they need a huge number of recipes); wants more than one input slot.

**Workarounds described.** Furnace + per-tick polling of the output slot; or a plain chest with Lua logic.

**Outcome.** Open, unanswered by staff for about 2.5 years (as of 2026-11-01). It is the closest existing request to the proposed entity: inventories + energy source + progress timer chosen per prototype, with logic left to Lua through events. The proposal's opt-in events (craft finished, input inserted) answer the "no tick between crafts" and "which stack was consumed" complaints directly.

---

## 3. A new prototype type to describe compound entities?

- URL: https://forums.factorio.com/viewtopic.php?p=512078 (filed under Won't implement)
- First post: mrudat, Fri Sep 11, 2020. 5 posts, page 1 of 1, read in full.

**The ask.** A `type = "compound-entity"` prototype listing a proxy entity (what the player places), a `control_script` tag, and a `components` list (entities, optionally items/fluids), readable at runtime via something like `game.find_compound_entities_filtered{control_script=...}`. The driving case: Battery Pack cannot derive a battery-powered Cargo Ship because it doesn't know the ship is a visible wagon plus an invisible locomotive placed by a proxy; each mod has to hard-code knowledge of the other. A second example: a gun turret pre-loaded with ammo (LoadedTurrets). eradicator +1'd, proposed instead a `children = {{name=..., offset=...}}` list on any entity with engine-handled simultaneous build/destroy; mrudat noted that would need blueprint-level detail (sub-tile positions, circuit connections).

**Developer replies (verbatim).**

Rseding91, Sun Sep 13, 2020:
> This along with the other request seem too much like a hack than a proper or even partial solution for compound entities. At their core compound entities don't work; ...

**Modder follow-up.** eradicator (Sep 13, 2020) asked whether that meant Wube *would* think it through (no answer), and named the biggest headache: guaranteeing the parts of a compound are never created, destroyed, teleported or rotated independently. Miniloader had orphaned invisible children left on the map when other mods destroyed the parent. Ideally the children would not be API-accessible as independent entities at all, only through something like `LuaParentEntity.children`.

**Outcome.** Moved to Won't implement. The key line for the proposal is "At their core compound entities don't work": Wube's objection is to the glue (several real entities kept in sync), not to the use cases. A single entity that owns its inventories, energy source and fluid boxes removes the glue entirely, which is exactly the "proper solution" this reply says is missing. eradicator's invariant list (create/destroy/teleport/rotate atomically, no orphaned children) is a ready-made checklist the proposal satisfies by construction.

---

## 4. Packed Entity Prototype. for using multi entity to do custom function

- URL: https://forums.factorio.com/viewtopic.php?p=688799 (Modding interface requests)
- First post: kjrsysy, Mon Feb 09, 2026 (not 2025). 2 posts, page 1 of 1, read in full.

**The ask.** A "packed entity" prototype that stacks several entities into one, with built-in linkage and storage so a modder does not have to hand-write sub-entity lifecycle code. Pain points listed: every compound needs init/link/storage code and teardown when the main entity is removed, and it is easy to miss cases; build has three separate events (`on_built_entity`, `on_robot_built_entity`, `on_space_platform_built_entity`, the last added by Space Age) and more could appear; per-tick Lua loops over a list of entities ("for a in l") are bad for UPS in large factories, and the usual fix (spreading updates over more ticks) makes the mod buggy; dummy sub-entities get left behind in edge cases (the author saw this when the main entity was shot by a cannon).

**Developer replies.** None. The only reply is GN89 (Fri Jul 03, 2026), suggesting generic build/destroy events with native engine filters and guessing that keeping the events separate may be a deliberate design choice.

**Correction to the task brief.** The brief called this a "2025 restatement of the ECS refusal". It is not: there is no staff reply in the thread at all. The UPS argument against per-tick Lua lists is the *requester's* argument, not Wube's. It is still useful as a 2026 modder account of the same pain points (cost of Lua tick loops, orphaned hidden entities, the growing list of build events).

**Outcome.** Open, unanswered by staff.

---

## 5. Add the field "energy_source" to the prototypes: transport-belt, underground-belt, splitter, loader

- URL: https://forums.factorio.com/viewtopic.php?p=654992 (filed under Won't implement)
- First post: Keysivi, Mon Dec 23, 2024. 4 posts, page 1 of 1, read in full.

**The ask.** Add `energy_source` to belt, underground, splitter and loader prototypes so mods can make logistics consume electricity "without big performance problems, as there are now" (today that means hidden electric entities per belt plus Lua).

**Developer replies (verbatim).**

Rseding91, Mon Dec 23, 2024:
> This is never happening. To add energy source support means making a given entity updatable which isn’t happening for belts. Loaders already are updatable and it was added in 2.0.

**Follow-up.** Keysivi asked whether a separate request to make belts updatable would be possible. No answer.

**Outcome.** Won't implement. The cost model in one sentence: an energy source implies the entity is *updatable* (in the per-tick update list), and Wube will not pay that for belts, which are deliberately non-updatable and driven by transport-line logic. Loaders were made updatable in 2.0 and got the field.

**What the proposal has to answer.** (a) Updatability is decided per prototype at load time from the part set: no energy source, no progress timer, no Lua tick request means the entity never enters the update list, exactly like a container today. (b) The proposal must not imply that existing non-updatable types (belts) become updatable; it is a new type, so the base game pays nothing. (c) The benchmark should report the update-list cost of a parts-only entity next to the engine type it replaces (container, assembling-machine), so "updatable only when a part needs ticking" is shown in numbers, not asserted.

---

## 6. Event for machine crafting complete

- URL: https://forums.factorio.com/viewtopic.php?p=632310&t=119719 (Modding interface requests)
- First post: i142857, Mon Nov 04, 2024. 4 posts, page 1 of 1, read in full.

**The ask.** An event when a (custom) assembling machine finishes a craft. The only way today is polling `LuaEntity.crafting_progress` or `products_finished` every tick. The author points out that 2.0 assemblers already emit a 1-tick circuit signal on craft complete, so scripts are less capable than the circuit network. Use case: assemblers abused as "pay gates" with one-time unlock recipes that have no results, chosen because the assembler gives free UI (cost tooltip, partial-fill slots, belt/inserter automation). References an older request, viewtopic.php?t=44269, that never got a definitive answer.

**Developer replies.** None in this thread.

**Modder replies.** ahicks: 2.0 allows multiple crafts per tick, so this implicitly needs a filter or "you're going to get like thousands per second". Silari: a clearer staff "no" exists at viewtopic.php?f=28&t=47728 (not moved to Won't implement). micromario: workaround, add a dummy item to the recipe with a 1-tick spoil trigger and react to the trigger result.

**Outcome.** No staff reply here. Per the brief, this line of requests led to `raise_on_crafted` in 2.1.12 (not verified from this thread; check the 2.1.12 changelog). The framing that matters: the firehose concern (thousands per second) is raised by a modder, and the shipped answer is a per-prototype/per-recipe opt-in rather than a global event, which is the precedent the proposal's opt-in events follow. Worth a separate read: t=47728 (the "clearer no") and t=44269.

**Workarounds.** Per-tick polling of crafting_progress / products_finished; spoil-trigger dummy item (1 tick) to get a trigger callback per craft.

---

## 7. Making a composite entity act like a normal entity (listed in the brief as "Composite entity undo/cut-paste")

- URL: https://forums.factorio.com/viewtopic.php?p=655527 (Modding help). The thread's real title is "Making a composite entity act like a normal entity".
- First post: half a cat, Wed Dec 25, 2024. 8 posts, page 1 of 1, read in full.

**The ask.** A composite entity made of a visible power generator (an assembler the player sees but does not touch) and an invisible crafting machine (an assembler the player uses). They are separate so the generator can animate independently. Every choice of "main" entity breaks something: if the invisible crafter is the built/mined entity there is no build preview and no visible feedback; if the generator is the built/mined entity players cannot deconstruct it because they cannot interact with it; if the generator is built but the crafter is deconstructed, undo and cut-paste break, presumably because the engine expects build and deconstruct to act on the same entity.

**Developer replies.** None (all replies are from modders).

**Workarounds described (the most detailed 2.0 account in this set).**
- DaveMcW: "You need a third entity whose only purpose is to appear in blueprints."
- robot256 ("I've done composite entities every way you can imagine"):
  - A third entity that is a copy of the crafter with the generator's sprites; handle blueprint-creation events and swap the entity name in script.
  - Or make the invisible sub-entities blueprintable too, so their settings survive. They appear as "required materials" but are not craftable; the script revives the remaining sub-entity ghost when the main entity is built. When one sub-entity ghost is deleted the script must delete the other "in such a way that it is appended to the most recent undo queue item".
  - Or split sprites so the interactable, blueprintable assembler carries the building's chassis and the non-interactable generator carries only the animation (tweak the sub-entity's Y so draw order is right), then script create/delete/clone/teleport of the generator whenever the assembler is affected.
- half a cat: editing BlueprintEntities in `on_player_setup_blueprint` works for the blueprint tool but not cut or copy, because the handler cannot read `player.blueprint_to_setup` there. DaveMcW: cut/copy surface through `on_player_cursor_stack_changed`; that got cut-paste working.
- Undo: half a cat concluded it is impossible, citing viewtopic.php?p=602029 and p=427782. DaveMcW: `on_undo_applied`. robot256: see `LuaUndoRedoStack`; "mostly" working in his mods: when the main entity is mined the game opens a new undo stack level, his mining handler deletes the sub-entities and adds them to the same undo entry as the main entity.

**Outcome.** No engine change; the answer is four or five events plus undo-stack surgery, and even an expert reports it only "mostly" works. Failure modes worth listing in the writeup: no build preview for invisible cores; blueprint name-swapping; cut/copy go through a different event than the blueprint tool; undo/redo needs manual LuaUndoRedoStack edits; settings of hidden parts are lost unless the hidden parts are themselves blueprintable, which then leaks them into required materials.

---

## 8. Recipe Finished Trigger or Event

- URL: https://forums.factorio.com/viewtopic.php?p=668733 (Modding interface requests)
- First post: Moterius, Sat Apr 12, 2025. 3 posts, page 1 of 1, read in full.

**The ask.** A way to run script when a specific recipe finishes, tied to the machine that finished it. Today: `spoil_to_trigger` (requires Space Age), or tracking every machine with that recipe set and polling each one every tick. Proposed options: (1) `on_recipe_finished` with the machine in the event data, *registered with a list of recipes to track so it doesn't fire on every craft*; (2) move spoil triggers and spoilage into base, with instant spoilage when the SA spoilage flag is off; (3) an `on_rocket_part_finished` (author later notes he imagined it had existed before).

**Developer replies.** None.

**Modder replies.** curiosity: duplicate of viewtopic.php?t=47728 (among others); one-part rocket silos are another option. Moterius: the point is that Space Age effectively has this event through spoil triggers but base does not, and the non-SA alternative is a "MASSIVE performance hit".

**Outcome.** Open, no staff answer. Read with thread 6: both requesters independently propose per-recipe/per-prototype registration so the event is not a firehose, and both use spoil triggers as the workaround. This is the precedent for the proposal's opt-in events (declared on the prototype, so only entities that asked for them pay). t=47728 is cited by two threads as the canonical earlier request with a staff "no"; read it separately.

---

## 9. Entity/component model in prototypes

- URL: https://forums.factorio.com/viewtopic.php?p=154019 (filed under Won't implement)
- First post: mknejp, Wed Apr 27, 2016. 16 posts, page 1 of 1, read in full.

**The ask.** Replace hard-coded entity types with prototype-time composition: a prototype lists components (inventory, fluid box, fluid connectors, burner, energy buffer, fluid heater, power-grid consumer/supplier...) and the engine instantiates and wires them; each component type is updated by its own system over a packed array. Examples: a boiler is inventory + fluidbox + burner + buffer + heater; an electric boiler swaps burner for grid consumer; a wind turbine is grid coverage + buffer + grid supplier, with only "add energy based on wind" left to Lua. Motivation is the ubiquitous "entity amalgamation" pattern: on_built creates invisible entities, on_tick drives them, removal destroys them (example: a hidden pump drained each tick to fake electricity use; wind turbine via hidden steam engine filled with fake hot fluid, plus four events to keep it invisible, invincible and non-deconstructable, and a nonsense fluidbox in the mouse-over). Sean Mirrsen later asked the narrower question: keep vanilla entities as they are, but let mods compose existing prototypes so a heavily modded game does less Lua.

**Developer replies (verbatim).**

Rseding91, Wed Apr 27, 2016:
> When I see a game implement it at a scale that Factorio runs at then I'll take back my argument about performance.
>
> http://i.imgur.com/sdX9Zcq.jpg
>
> 5,455,472 total entities
> 234,049 active entities (entities updating each tick)
> 60 ticks per second so that means all 234,049 entities have < 16.6~ MS per tick to run all of the logic they implement
> 4.2 GB of RAM used

Rseding91, Thu Apr 28, 2016:
> Everything I look at online is always a concept - some person or group talking about the idea of a component based system. I've never actually seen anyone implement it. ...
>
> Also do remember that we're making a *game*. We're not making a game engine designed to make other games.

Rseding91, Thu Apr 28, 2016 (answering mknejp's guess of `class boiler : entity { fuel_slot; energy_buffer; fluidbox; virtual void update(); }`):
> Factorio's core logic is all single threaded as well
>
> Close, the base entity type isn't updatable but a side type of UpdatableEntity { ... } which updatable types inherit from along side of the base entity type. There is also different boost intrusive lists of active vs. inactive entities ...
>
> It's fine, I've got nothing against the concept in general I just don't believe it actually works when applied to something that runs at the scale that Factorio does as I've never seen anyone do it (probably for good reason).

Rseding91, Fri Apr 29, 2016:
> I already tested storing the entities by type and running updates in series on all entities of a type - it had zero difference in performance. ...
>
> By-type updates aside - they use intrusive lists because entities move between active and not active so frequently that putting them in a container like a vector DESTROYS performance ...

**Other notes.** Adil (2016): "It's been suggested to death actually... Devs keep saying it's not gonna happen", and suggested instead asking for the base components as independent types to glue in Lua. mknejp conceded it is too late for such a change and not worth doing only for modders. Sean Mirrsen's narrower framing (vanilla untouched, mods compose existing parts) got no staff reply.

**Outcome.** Won't implement. Three engine facts from staff that the proposal should build on, not fight:
1. Updatability is a side interface: `Entity` is not updatable; updatable types also inherit `UpdatableEntity { virtual void update() = 0; Entity* getEntity() = 0; }`, and active/inactive entities live in boost intrusive lists. So "register as updatable only when a part needs ticking" maps directly onto existing machinery: the new type inherits UpdatableEntity, and instances whose prototype has no ticking part are simply never linked into the active list (or sleep in the inactive list).
2. Wube measured by-type batched updates and saw "zero difference", so SoA/system loops are not a selling point. The proposal should promise "no Lua per tick" and "no hidden entities", not cache wins.
3. Entities move between active and inactive often, so the cost of sleep/wake must stay O(1) (intrusive list), which a fixed-at-load part set allows.
4. "We're making a *game*... not a game engine": the proposal should be one entity type for mods, not a general framework, and should leave vanilla types untouched (Sean Mirrsen's framing).

---

## 10. Allow mod to track entities across undo

- URL: https://forums.factorio.com/viewtopic.php?p=584507 (Modding interface requests)
- First post: GlassBricks, Wed Apr 26, 2023. 3 posts, page 1 of 1, read in full.

**The ask.** Mods attach data to entities by `unit_number` in `global`/`storage`, but when an entity is deleted and the deletion undone, the new entity has a new unit number and nothing ties it to the old data. Proposals: a persistent `id_number` that survives delete/undo and die/revive; better, per-entity `custom_tags` that live and die with the entity (like ghost tags) and survive undo and revive; best, make those tags copy/paste-able through blueprints, so several mods could store settings in blueprints at once. Follow-ups: an "old unit_number" field in undo events (GlassBricks, Apr 28, 2023); set `ghost_unit_number` of the undo ghost to the removed entity's unit_number, as already happens for ghosts left by killed entities (BlackOverlord, Dec 28, 2023).

**Developer replies.** None.

**Workaround described.** A visible "dummy combinator" that holds the settings (combinator settings survive blueprints and undo) with the functional entities hidden. Does not work for attaching data to vanilla entities.

**Outcome.** Open, unanswered. Bearing on the proposal: every compound entity hits this, because identity lives in Lua tables keyed by unit_number across several real entities. A single entity whose state is in engine-owned parts (inventories, fluid boxes, progress, circuit settings) gets undo/blueprint/revive behaviour from the engine's normal entity paths, and any Lua-side settings only need the one entity's tags rather than a dummy combinator.

---

## 12. Add a surface property for a spoilage time multiplier (brief title: "Surface spoilage multiplier request")

- URL: https://forums.factorio.com/viewtopic.php?p=678356 (Modding interface requests)
- First post: MrSmoothieHuman, Wed Aug 13, 2025. 6 posts, page 1 of 1, read in full.

**The ask.** A surface property `spoilage_time_multiplier` (e.g. 1.5 = items spoil 1.5x slower) for planet mods, for example cold planets like Aquilo where spoilage should be slowed.

**Developer replies (verbatim).**

boskid, Wed Aug 13, 2025:
> ... spoilable items simply do not know on what surface they are and making them know would require adjusting spoil tick every every time spoilable item is moved between inventories. ... It is unlikely for this to be ever implemented.

Rseding91, Wed Aug 13, 2025:
> Something that *might* be possible is a value that modifies the spoil time on item creation. But it would be permanent for that item ...

**Modder replies.** MrSmoothieHuman: merging could just merge timers like stacks of different quality. protocol_1903 (pY developer): would enable preserved items / faster-spoiling items. Cheesestick (Oct 29, 2025): use cases like a toxic planet where everything spoils, or ice melting on Vulcanus only.

**Outcome.** "Unlikely to be ever implemented" for the surface multiplier; a creation-time modifier is floated as *maybe*. Bearing on the cold-box test entity: spoilage is driven by an absolute spoil tick stored on the item, not by a per-tick decrement, so any "slow spoilage while inside this inventory" part has to *rewrite the spoil tick on insert and on remove* (scale remaining time by the factor on entry, unscale on exit), never tick items. That is exactly the "adjust spoil tick every time a spoilable item is moved between inventories" cost boskid names, but confined to one inventory of one opt-in prototype, paid per transfer rather than per tick. The writeup should present it that way: an inventory-level spoil-rate part, evaluated on insert/remove events, which sidesteps the "items don't know their surface" problem because the inventory knows its owner. Edge cases boskid lists that the part must define: items leaving via inserter hand, cursor, script inventories.

---

## Bonus. defines.event.on_entity_crafting_complete (the earlier "clear no" cited by threads 6 and 8)

- URL: https://forums.factorio.com/viewtopic.php?f=28&t=47728 (Modding interface requests, not moved to Won't implement)
- First post: Mylon, Tue May 16, 2017. 8 posts, page 1 of 1, read in full.

**The ask.** `on_entity_crafting_complete` with `{entity, recipe}` for assemblers.

**Developer replies (verbatim).**

Rseding91, Tue May 16, 2017:
> We specifically don't have such an event because it would be a massive drain on game performance.

Rseding91, Tue May 16, 2017 (asked why players already have a craft event):
> Yes, because the player count is not in the 10s of thousands and has a fixed crafting speed.

**Later replies.** IsaacOscar (Dec 25, 2024): could the recipe and/or the crafting machine prototype opt in to the event, to minimise performance problems? SWeini (Dec 10, 2025): mods will do it anyway at higher cost (rocket silos, on_tick polling of products_finished/crafting_progress); it could be enabled per prototype or even per entity, like `register_on_object_destroyed`; built-in is the only way to handle recipes that complete more than once per tick. protocol_1903: writing a script handler for it in the mod "perel", "not cheap to run".

**Outcome and the precedent.** The 2017 objection was the firehose cost of a global event. The opt-in framing was proposed in this thread (Dec 2024, Dec 2025), and the 2.1 changelog confirms the shipped answer: **Version 2.1.12, Modding: "Added RecipePrototype::raise_on_crafted."** (same release also added `ScriptTriggerEffectItem::custom_event`). So Wube moved from "massive drain" to a per-recipe prototype opt-in. This is the strongest precedent for the proposal's per-prototype opt-in events: the cost objection was answered by putting the switch on the prototype.

---

## Cross-thread takeaways for the proposal

1. **Frame it as one general-purpose modding entity, not ECS.** Rseding91 has rejected runtime component systems at least five times (2016, Jun 2018, Nov 2018 x3). The only positive opening is Jun 23-24, 2018: "not against that concept", wants a writeup, and the test is "an entity where parts of it can just be shut off".
2. **Build on the engine's own updatability model.** Staff described it (2016): Entity is not updatable; updatable types also inherit `UpdatableEntity`, with active/inactive boost intrusive lists. Dec 2024: energy source => updatable => refused for belts. The proposal: part set fixed at prototype load; the entity joins the update list only if a part needs ticking (energy source, progress timer); a container-like configuration costs the same as a container.
3. **Don't sell cache/SoA wins.** Wube measured by-type batched updates with "zero difference" (2016). Sell: no hidden entities, no Lua per tick, engine-native blueprint/undo/GUI.
4. **Opt-in events have precedent.** 2017 "massive drain" -> 2024/2025 modders ask for prototype opt-in -> 2.1.12 `RecipePrototype::raise_on_crafted`.
5. **Compound-entity glue is what Wube calls broken** ("At their core compound entities don't work", 2020). Concrete failure list from modders: orphaned hidden children (Miniloader, cannon kills), three-plus build events, blueprint name swaps, cut/copy via `on_player_cursor_stack_changed`, undo via manual `LuaUndoRedoStack` edits, unit_number identity lost across undo, settings stored in dummy combinators, per-tick polling for craft completion.
6. **Spoilage parts must work on the spoil tick at transfer time,** never per tick, and must define behaviour for inserter hands, cursor and script inventories (boskid 2025).

## Corrections to the task brief

- Thread 4 (Packed Entity Prototype) has no staff reply; it is dated Feb 2026, not 2025. The UPS argument there is the requester's.
- Thread 6 has no staff reply; the staff framing is in t=47728 (2017 refusal), read above.
- Thread 7's actual title is "Making a composite entity act like a normal entity".
- Thread 11 (p=368117) is the same topic as thread 1. Its page 2 (2 posts, likely containing p=386083/p=387802) could not be loaded: all p= links and `&start=20` render page 1 and the topic id is not shown. The "nobody has written up how it works" remark is on page 1 (Rseding91, Jun 23, 2018), quoted above.

## Threads worth a further read

- viewtopic.php?t=44269 (older crafting-complete request cited in thread 6).
- viewtopic.php?p=602029 and viewtopic.php?p=427782 (cited in thread 7 as "undo can't be done for custom entities").
- Page 2 of "Divorcing behavior from entities" (needs the t= id).
