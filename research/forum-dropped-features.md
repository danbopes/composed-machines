# Forum sweep: features dropped, crippled or hacked because the engine/API could not express them (2026-11-02)

Read-only sweep of forums.factorio.com through the logged-in Chrome session. Nothing was posted. About 75 page loads.
Quotes are verbatim, 40 words or fewer. "MIR" = Modding interface requests (f=28), "WI" = its "Won't implement"
subforum (f=221, checked from f=28; the brief guessed 47), "Impl" = "Implemented mod requests" (f=65),
"MH" = Modding help (f=25). Dates are the opening post's date unless a reply date is given.

## (a) Summary

53 threads read in full, none on the skip list or in [forum-threads-full.md](forum-threads-full.md) / [forum-requests.md](forum-requests.md). 29 are in Won't implement,
1 is an Implemented reversal, 18 are open MIR threads, and 5 are Modding help threads where the answer was "build a compound entity".
Pages 1 to 7 of Won't implement (175 of its 508 topics, newest first) were listed and every machine-part thread on them was opened.

What the threads say:
- **25 threads** describe a hidden-entity / compound-entity workaround that is in use or recommended. Examples: a hidden reactor under each
  assembler, a hidden assembler on a thruster or offshore pump, hidden heat pipes, hidden beacons, hidden accumulators, a hidden-surface belt network.
- **13 threads** describe per-tick or nth-tick Lua polling as the only workaround, and the author calls it expensive.
- **4 threads** are a feature that was actually dropped or cut back: Better Belt Balancer was reworked for 2.1, the heat-beacon mechanic was
  rolled back, a Gleba roboport never got a reply, and a plant-only tower was rejected. Several more are "it works but probably kills UPS".
- The Wube staff reasons in the 29 Won't-implement threads: **performance 12**, **"doesn't work that way" / design 11**,
  **maintenance or complexity 3**, **no stated reason or no staff reply 5**. Some threads give more than one reason.
- **Two reversals** show that a "no" is not final: offshore pump `energy_source` was refused in 2020 and shipped in 2.0 (t=81770).
  Hidden beacons for global effects were partly replaced by `LuaEntity::local_effect` in 2.1 (t=132032).
- **Hard objections for the proposal.** Rseding91 in t=69180 (2019) and t=15257 (2015) argues against a generic mix-and-match entity:
  "throwing out the entirety of the code around entities", the performance "so poor that you probably couldn't ever leave red science",
  and "un-maintainable" code. In t=88647 he says events cost something "even if zero mods are listening". These are the exact
  objections a composed-machine proposal has to answer: parts fixed at prototype load, events opt-in per prototype.

## (b) New threads

Part keys: inventory, energy, fluid, process, events, circuit-output, circuit-input, spoil, settings, generation, heat, broadcast,
trigger, logistic, lifecycle, unit, other, NONE.

| URL | Date | Forum | Who | Wanted | Blocker / Wube said | Workaround / outcome | Part | Quote |
|---|---|---|---|---|---|---|---|---|
| https://forums.factorio.com/viewtopic.php?t=113731 | 2024-06-03 | MIR | snakeru (RealisticReactors contributor); braxbro | Change reactor power and efficiency at runtime; modules in reactors | No staff reply. Reactor `consumption` and `effectivity` are not writable at runtime. Modules on reactors are ignored | RealisticReactors swaps between 250 reactor prototypes and fakes efficiency with a fuel-cell hack. Alternative proposed: compound assembler + linked fluidbox + fluid-energy reactor | energy, heat, generation, process, settings | "they create 250 reactor prototypes with power output from 1 to 250 MW and then replace the reactor every time its power output has to change." |
| https://forums.factorio.com/viewtopic.php?t=135830 | 2026-08-23 | MIR | Techrocket9 (Better Belt Balancer author); boskid | Let hidden script-only linked belts share a tile. The mod compiles balancers into a hidden-surface belt network so that "the steady state runs no Lua at all" | boskid: belt connections are not saved, so this needs the belt logic rewritten. "I wont reject this interface request but it has no priority for me because of complexity" | **Dropped.** Mod reworked around one connectable per tile for 2.1 | lifecycle, other (compound on hidden surface) | "I have reworked the mod around the one-connectable-per-tile invariant for now ... if this API is ever implemented, I will restore the original functionality." |
| https://forums.factorio.com/viewtopic.php?t=113632 | 2024-05-25 | WI | JamesFire (mod author); Rseding91 | Heat-powered beacons for a "maintain temperature" mechanic | Rseding91: "The reason is performance. Beacons have a huge performance overhead every time the amount of energy they have changes and also they do not update every tick" | **Cut back**, or script it | energy, heat, broadcast | "So now my only real options are to script this in, which will hurt performance for the expected hundreds to thousands of machines, or I severely roll back how this will actually work" |
| https://forums.factorio.com/viewtopic.php?t=132603 | 2026-01-30 | WI | Dr. Dog PhD (planet mod); Rseding91 | Fluid, burner or heat energy for beacons | Rseding91: multiple update modes per energy type; poor performance when not fully powered; "The added complexity to write, test, bug fix and maintain burner beacons has not been deemed worth it" | Mod `zzz-nonstandard-beacons` suggested | energy, broadcast | "We would have to engine level support beacons having multiple update mods depending on the energy source type" |
| https://forums.factorio.com/viewtopic.php?t=88647 | 2020-08-27 | WI | MarcasRealAccount (dustless-miners); Rseding91 | Mining recipes (drill outputs a fluid), then an on-mined event | Overhead on every drill; events cost even with no listener | Script inserts fluid into drills; round-robin 60 drills per tick | process, fluid, events | "Firing events has a performance impact even if zero mods are listening to the event and mining drills, assembling machines, and furnaces exist in thousands" |
| https://forums.factorio.com/viewtopic.php?t=77368 | 2019-10-30 | WI | Rems19; Rseding91 | Mining recipes (clean miner, ore ratio) | "Mining is a completely different system and we aren't going to be merging them together" | Requester: "really nasty hack" | process | "It would break literally every mod out there and add in a lot of overhead to the mining system for things the base game would never use." |
| https://forums.factorio.com/viewtopic.php?t=69180 | 2019-04-07 | WI | alercah; Rseding91 | Custom wire types, connection points on any prototype, mod-defined control behaviours, to replace "additional hidden entities with lots of scripting" (Shortwave, LTN) | Rseding91 lists the 23 files changed for one inserter switch, and says a generic system would be too slow | None | circuit-input, circuit-output | "what you propose simply will never happen. It would mean throwing out the entirety of the code around entities and starting over with the most generic system possible." |
| https://forums.factorio.com/viewtopic.php?t=15257 | 2015-08-26 | WI | ratchetfreak, Afforess, GopherAtl, vzybilly, Divran; Rseding91, Klonan (staff) | "Make the API less rigid": mix-and-match components (inventories, power consumer/producer, fluid connection) | Rseding91: C++ classes per type; generic would be slow and "un-maintainable". Klonan points at KSP part modules | Hidden boilers, invisible constant combinators, per-tick invisible accumulator for electric trains | all parts | "Object oriented C++ doesn't lend its self well to "mix and match any random piece of the code into one entity"" |
| https://forums.factorio.com/viewtopic.php?t=125679 | 2025-01-06 (reply 2026-08-06) | MIR | hgschmie; PennyJim, Kabury, protocol_1903 (pY) | Writable `LuaEntity::loader_container` | No staff reply | PennyJim builds a compound entity with hidden burners fed by loaders, maybe on a hidden surface with linked belts | energy (multiple sources), inventory | "I'm making a compound entity so I can pretend an entity has multiple energy sources. To make the internal burners accessible I'm making specific input ports out of loaders" |
| https://forums.factorio.com/viewtopic.php?t=108882 | 2023-09-23 | MH | LuxArdens (overhaul mod "housing") | Crafter that burns fuel continuously whether crafting or not | Engine: crafters sleep. Reactors burn continuously but cannot run recipes | Hidden reactor under each assembler. nth_tick polls temperature, subtracts heat, zeroes `crafting_progress`. Needs 2 inserters | energy, process, inventory | "I see now the usual invisible entity contraption is the only solution." |
| https://forums.factorio.com/viewtopic.php?t=61277 | 2018-06-29 | WI | Melfish; Rseding91 | Continuous-burn option on the burner energy source | Sleeping entities save CPU | Hidden reactor under every entity + on_tick fuel management | energy, heat | "Entities that don't consume power constantly don't do it because they're asleep to save CPU time. To make them consume constantly would mean they can't sleep and that's not going to happen." |
| https://forums.factorio.com/viewtopic.php?t=132032 | 2025-12-10 | MIR | SWeini (mod author); MeteorSwarm | Better global/per-surface effects so mods stop using hidden beacons | 2.1 added `LuaEntity::local_effect`, but it needs built/destroyed tracking, has no icon and planners cannot see it | Hidden beacons, now local_effect + tracking | broadcast, settings | "Hidden beacons do work, but they are a burden to set up. They also make the compatibility between mods a lot more difficult" |
| https://forums.factorio.com/viewtopic.php?t=81770 | 2020-02-28 | Impl | Linver, DaveMcW; Rseding91, boskid | `energy_source` on offshore pumps | 2020 Rseding91: "We have no interest in making or even supporting modding of offshore pumps requiring power of any kind." boskid 2024: "2.0" | **Reversal**: hidden assembler disguised as offshore pump until 2.0 | energy | "I have two entity, one vanilla, unused, one modded that is a assembler masked like an offshore pump and a lua code that check entities on built events" |
| https://forums.factorio.com/viewtopic.php?t=112913 | 2024-04-09 | WI | Moterius (pneumatic pipes), oobanooba, half a cat; Rseding91 | Several fluid filters per fluidbox | Memory and performance on every fluidbox | `call-plumber` mod destroys pipes holding the wrong fluid. oobanooba doubles every machine's fluidboxes with a special connection category | fluid | "every single fluidbox in the game would need memory allocated to support a dynamic number of filters which is outside of what we want to support" |
| https://forums.factorio.com/viewtopic.php?t=124322 | 2024-12-12 | WI | plexpt; Rseding91 | Plant maturity event/trigger | Growth is computed lazily on interaction | None | events, trigger | "So this is simply not possible to do with the current performance-friendly implementation of plants." |
| https://forums.factorio.com/viewtopic.php?t=120832 | 2024-11-10 | WI | DylanDerEchte (electric-train mod); Rseding91 | Electric `energy_source` for locomotives | Pole reconnect scan each tick while moving | Dropped | energy | "Every tick every time they moved they would need to scan a *huge* area around themselves to disconnect and reconnect to electric poles and that's not acceptable." |
| https://forums.factorio.com/viewtopic.php?t=101666 | 2022-02-22 | WI | fac (resource-automation mod), Amarula, Silari | "Production complete" event | Previously denied for performance (t=47728, t=44269). Amarula suggests an opt-in "mod-assembler" | Poll every machine's inventories | events | "Now I can only record every "machine" and check the input/output inventory, low efficiency." |
| https://forums.factorio.com/viewtopic.php?t=124752 | 2024-12-19 | MIR | ldinc | Electric energy per shot on artillery turret (railgun) | Self-closed | Invisible accumulator or assembler + firing-event tracking | energy | "At the moment it can be aproached with invisible accumulator or assembling machine with some hack-code to track firing events + switch enabled state per hidden building." |
| https://forums.factorio.com/viewtopic.php?t=124537 | 2024-12-16 | MIR | Morgott, Keysivi, ldinc | `energy_source` on fluid and artillery turrets (2.0 added it to ammo turrets) | No staff reply | Hidden entities | energy | "At the moment the only way to create railgun like artillery is hacking with hidden entities for consuming energy (and maybe fluids)" |
| https://forums.factorio.com/viewtopic.php?t=133290 | 2026-04-07 | MIR | Thremtopod, Kryzeth, protocol_1903 | `heating_radius` on HeatEnergySource | No staff reply | Hidden heat pipes (broke in 2.1), hidden heat interfaces, compound | heat | "instead of relying on hidden heat pipes (and soon, hidden heat interfaces, since my previous hidden heat pipe workaround no longer seems to work in 2.1)" |
| https://forums.factorio.com/viewtopic.php?t=130444 | 2025-08-22 | MH | oobanooba; Osmo | Assembler that emits heat while crafting (platform waste heat) | Not supported | Assembler makes a fluid that feeds a hidden reactor through a linked pipe; runtime create/destroy | heat, generation | "What people do in such cases is fake it by having multiple entites" |
| https://forums.factorio.com/viewtopic.php?t=129521 | 2025-06-21 | MH | MrLumme; Osmo | Heat pump: heat in, heat out, circuit enable, read temperatures | Reactor cannot take a heat energy source | heat -> hidden fluid -> reactor compound | heat, circuit-input | "What you could do is something that is reffered to as "compound entities"" |
| https://forums.factorio.com/viewtopic.php?t=120072 | 2024-11-06 | MIR | shiftweave | Power from a fluid with a solid byproduct (generator `burnt_result`, or a negative-energy assembler) | No reply | Compound entity | generation, process, inventory | "I haven't been able to find a way to do this with the API except through complex compound entity solutions" |
| https://forums.factorio.com/viewtopic.php?t=124417 | 2024-12-14 | MIR | shadow0133 (nuclear thermal thruster), petrathekat, braxbro | Thruster with `max_thrust`, other inputs, heat | No staff reply | Invisible thruster fed by script; compound assembler + linked fluidbox | energy, heat, fluid, process | "As-is, there is *no* way to make a custom thruster." |
| https://forums.factorio.com/viewtopic.php?t=130192 | 2025-08-04 | MIR | Chiefjustice (Ultracube port); Bilka | Thruster that consumes one fluid and outputs a byproduct | Bilka: fluidbox filters change inputs only | Fusion Thruster mod's hidden assembler on top of the thruster | fluid, process | "The existing Fusion Thruster mod uses a hidden Assembling Machine entity & recipe to turn "Plasma" into thrust." |
| https://forums.factorio.com/viewtopic.php?t=131709 | 2025-11-09 | MIR | herrkatze0658, protocol_1903; Rseding91 | Runtime-adjustable equipment generator | Rseding91 asks for clarification | Every-30-tick scan of all grids (was every tick) | generation, settings | "Currently in my mod, I use a hacky, performance heavy workaround to have a certain amount of energy generation per locomotive in the equipment grid." |
| https://forums.factorio.com/viewtopic.php?t=133808 | 2026-06-05 | MIR | GN89 | Nutrient-powered Gleba roboport: isolate it from the grid, or give it a linked energy buffer | No reply | Not built | energy, logistic | "Since vanilla roboports are strictly tied to the global electric network, the main challenge is completely isolating this new entity from standard power grids." |
| https://forums.factorio.com/viewtopic.php?t=136701 | 2026-10-25 | MIR | wafflepan (planet mod) | Per-surface `entities_require_heating` | No reply | None feasible | heat, energy | "Also, Entity.frozen is read-only so manually freezing a ship via scripts is not feasible." |
| https://forums.factorio.com/viewtopic.php?t=64576 | 2019-01-25 | WI | Optera, Rainboy (tesseract power mod), bobingabout; Rseding91 | Primary/secondary priority on accumulators/EEI ("transformators") | Same-priority produce/consume drains itself | Multi-entity; EEI lacks accumulator animations | energy, generation | "An entity can't produce power and consume power from the same energy priority or it ends up charging/draining itself." |
| https://forums.factorio.com/viewtopic.php?t=69644 | 2019-04-17 | WI | tux_mark_5; Rseding91 | Join an entity to a circuit/logistic/electric network by id ("without using on_tick") | Networks are defined by wires and areas | None | broadcast, circuit | "This isn't so much a "won't implement" but a "It doesn't work that way, can never work that way, and doesn't make any sense"." |
| https://forums.factorio.com/viewtopic.php?t=73614 | 2019-07-24 | MIR | TheFunnySide, DaveMcW, darkfrei; Rseding91 | Script wires beyond max distance | Players could not reproduce the result | Teleport, connect, teleport back; hidden wires for zero-UPS "radio" | broadcast | "Letting script logic do things which the player normally does - but the player can't reproduce - doesn't seem like a good idea." |
| https://forums.factorio.com/viewtopic.php?t=26458 | 2016-06-09 (to 2023) | MIR | sparr (Belt Overflow), robot256 (Auto Deconstruct); Rseding91 | Read the drill's held output item | Fixed the item-loss bug; inventory still not exposed | Poll drop targets | inventory | "On crowded belts, this will increase overhead as drills are constantly polled until the rest of the patch dries up. This also somewhat defeats the purpose of the mod." |
| https://forums.factorio.com/viewtopic.php?t=4841 | 2014-07-14 | WI | Dark | Powered-up / powered-down events | No reply | Poll a list every tick | events | "the only way to track such thing as "powered" state is to build list of entities an iterate over this list every tick" |
| https://forums.factorio.com/viewtopic.php?t=64769 | 2019-02-06 | MIR | Optera (LTN author) | `on_entity_no_fuel` event | No reply | Tick polling | events, energy | "It just isn't exposed through the api forcing mods to do bad performing polling in tick handlers" |
| https://forums.factorio.com/viewtopic.php?t=85971 | 2020-06-14 | WI | billbo99; Rseding91 | `register_on_entity_inventory_changed` | No reason given | Tick polling | events, inventory | "Sorry but this isn't going to happen." |
| https://forums.factorio.com/viewtopic.php?t=113922 | 2024-06-18 | MIR | scruffyvoltherder | Mod circuit point called when its input changes | No reply | Polling | circuit-input, events | "A mod can poll infrequently, but will miss pulsed signals. Or, A mod can poll every tick, but that would introduce a massive UPS penalty." |
| https://forums.factorio.com/viewtopic.php?t=134525 | 2026-06-28 | WI | snouz (Moshine author), EBhero; boskid | `spoil_time_multiplier` on containers (fridges) | Spoilage design (points to p=678357) | Dropped | spoil | "No. Design decisions around spoilable items make features like this not possible." |
| https://forums.factorio.com/viewtopic.php?t=134641 | 2026-06-30 | MIR | PsyhoBelka | `spoil_result` as an array (return the container) | No reply | None | spoil | "it will add tons of possibilities for moders. especially in dealing with spoilage mechanic." |
| https://forums.factorio.com/viewtopic.php?t=136024 | 2026-09-05 | WI | egladil; boskid | `logistic_mode` on proxy containers (bots serving the platform hub) | A proxy does not own the inventory, so it gets no change notifications | Dropped | logistic, inventory | "proxy container does not own the inventory it borrows, which means it is not instantly notified of content changes" |
| https://forums.factorio.com/viewtopic.php?t=125425 | 2024-12-31 | WI | sh4dow; Rseding91 | Plant-only agricultural tower | Towers only harvest what they planted | Rejected | process | "Agricultural towers do not support "plant only" or "harvest only" modes." |
| https://forums.factorio.com/viewtopic.php?t=123262 | 2024-11-29 | WI | hgschmie (mod author); Rseding91 | Power switch joined to the platform's global electric network | Power switches only connect to poles | Hidden pole | energy | "Power switches can't connect to nothing. They only support connecting to electric poles." |
| https://forums.factorio.com/viewtopic.php?t=129728 | 2025-07-03 | WI | MrSmoothieHuman (mod author); Rseding91 | Change entity quality at runtime (variable beacon range "without entity swapping") | Same as renaming an entity | Entity swap | settings, lifecycle | "The only way to change the quality of an entity runtime is to destroy the entity and create a new one with a different quality." |
| https://forums.factorio.com/viewtopic.php?t=74004 | 2019-08-02 | WI | Adamo; Rseding91 | Per-connection fluidbox index on an assembler | "I don't consider it valid" | Hidden 2nd input via `max_underground_length` | fluid | "After looking at what your use case is I don't consider it valid and I agree you should just make a different recipe." |
| https://forums.factorio.com/viewtopic.php?t=60539 | 2018-05-21 | MIR | shouperman ("modular turret") | Module slots on turrets | No reply | Not built | other (modules on any type) | "It appears that modules can only be added to entities of type "assembling-machine", "mining-drill", "lab", "rocket-silo", "furnace"*, and (obviously) "beacon"." |
| https://forums.factorio.com/viewtopic.php?t=80402 | 2020-01-24 | WI | Pi-C (Autodrive maintainer), Honktown | Prototype-level category filters on car/wagon inventories | No staff text | Item-with-inventory hack | inventory | "I'd like to be able to define in the prototype that a complete inventory may only be filled with items of a certain type/group." |
| https://forums.factorio.com/viewtopic.php?t=47044 | 2017-05-09 | WI | kyranzor | Units with an inventory or equipment grid | No staff text | None | inventory, unit | "a small inventory (of defined size in prototype) accessible only to their own force would be handy." |
| https://forums.factorio.com/viewtopic.php?t=47919 | 2017-05-18 | MH | Theanderblast (powered floor); Klonan | Pole + tile in one entity | Klonan: one type per entity, use compound entities | Compound (Concrete_Lamppost) | lifecycle | "It isn't possible for a single entity to have behaviors of two types of entity," |
| https://forums.factorio.com/viewtopic.php?t=89338 | 2020-09-12 | WI | mrudat, eradicator | "magic-entity" prototype declaring script behaviour for derived entities | No staff text | Hard-coded lists | other | "It would be useful to be able to declare that a given entity is magic (has additional behaviour that is supplied by a control script)" |
| https://forums.factorio.com/viewtopic.php?t=134909 | 2026-07-09 | WI | klobor (stateless car-logistics); boskid | Detect-only collision layers that fire events instead of polling | Collisions are not cheap; idle turrets already do not update | Dropped | trigger, events | "This proposal is completly detached from how collisions work and as such i am not seeing it being applicable." |
| https://forums.factorio.com/viewtopic.php?t=112760 | 2024-03-29 | WI | BlueNova; boskid | Module durability | Base game would pay for item data | Item health suggested | NONE | "For a feature that base game would never use but would have to pay the performance cost i am not accepting that." |
| https://forums.factorio.com/viewtopic.php?t=59065 | 2018-03-26 (to 2024) | WI | sparr (Belt Overflow), ahicks (Factorio Access); boskid | Belt moving/stalled state | Data not present without running the update | Lua heuristics | NONE | "it asks for a piece of data that is simply not present" |
| https://forums.factorio.com/viewtopic.php?t=109644 | 2023-11-10 | WI | sparr; boskid | Manual circuit-network update calls | Breaks internal assumptions | None | NONE | "I am not willing to sign for maintaining this function" |
| https://forums.factorio.com/viewtopic.php?t=102517 | 2022-05-27 | WI | Mylon; Rseding91 | Dummy capsule prototypes in base | Noise in base | Make a mod | NONE | "This would just be spam/noise for base game. Just make a mod if you want it." |

## (c) Won't implement threads by the developer's reason

**Performance (12)**
- t=113632 heat/burner beacons: energy changes are costly and beacons do not update every tick (Rseding91, 2024)
- t=132603 beacon energy sources: multiple update modes and bad underpowered performance; also maintenance (Rseding91, 2026)
- t=112913 multiple fluidbox filters: memory and performance on every fluidbox (Rseding91, 2025)
- t=124322 plant maturity event: growth is computed lazily (Rseding91, 2024)
- t=120832 electric locomotives: pole rescans while moving (Rseding91, 2024)
- t=101666 production-complete event: prior denials t=47728 / t=44269 (2022, closed without a new staff post)
- t=112760 module durability: item data cost the base game would pay (boskid, 2024)
- t=61277 continuous burner: entities must sleep (Rseding91, 2018)
- t=88647 mining recipes / on-mined event: per-drill overhead; events cost even with no listener (Rseding91, 2020)
- t=77368 mining recipes: overhead, and it would break mods (Rseding91, 2019)
- t=134909 detect-only collision layers: collisions are not cheap (boskid, 2026)
- t=69180 generic circuit behaviours: performance plus a rewrite of the entity code (Rseding91, 2019)

**Maintenance / complexity (3)**
- t=109644 manual circuit update: "not willing to sign for maintaining" (boskid, 2023)
- t=15257 component API: "un-maintainable" and slow (Rseding91, 2015)
- t=132603 (also above): "not been deemed worth it"
- Not in WI but the same kind of reason: t=135830 "no priority ... because of complexity" (boskid, 2026)

**Design / "doesn't work that way" (11)**
- t=134525 container spoil multiplier: spoilage design (boskid, 2026)
- t=136024 logistic proxy container: no ownership, so no change notifications (boskid, 2026)
- t=125425 plant-only tower: towers harvest only what they planted (Rseding91, 2026)
- t=123262 power switch to the platform network: switches only connect to poles (Rseding91, 2026)
- t=59065 belt stalled state: the data is not present (boskid, 2024)
- t=102517 dummy capsules: noise in base (Rseding91, 2022)
- t=129728 runtime quality: equivalent to renaming an entity (Rseding91, 2025)
- t=64576 accumulator priorities: an entity would drain itself (Rseding91, 2019)
- t=69644 join a network by id: "can never work that way" (Rseding91, 2019)
- t=74004 fluidbox index: use case "not valid" (Rseding91, 2019)
- t=15257 (also above): C++ classes per type (Rseding91, 2015)

**No stated reason / no staff reply (5)**: t=89338 magic-entity tags, t=4841 power events, t=85971 inventory-changed event
("isn't going to happen", no reason), t=80402 prototype inventory filters, t=47044 unit inventory.

## (d) Queries run, and dead ends

Listing: f=28 to find the subforum ids (Won't implement = f=221, Implemented = f=65, Already exists = f=220). f=221 pages 1 to 7.

Searches (all `search.php?keywords=...`):
- `hidden entity` in f=28 (76 hits, pages 1 to 3 scanned)
- `on_tick performance entities` in f=28 (24)
- `compound entity` in f=28 (27, page 1)
- `"compound entities"` in f=34 + f=25 (7)
- `hidden entities on_tick` in f=25 + f=34 (6)
- `hidden assembling machine` in f=25 (13)
- `"every tick" mod entities` in f=28 + f=221 (14)
- `polling` in f=28 + f=221 + f=65 (23)
- `spoil` titles in f=28/221/65 (4)
- `energy_source` titles in f=28/221/65 (16)
- `fluidbox` in f=221 (7)
- `inventory` titles in f=221 (7)
- `"hidden entities" ups`, all forums (7)
- magic-entities title lookup

Dead ends and gaps:
- `ups expensive workaround` returned 0 hits.
- `"hidden entities" ups performance` with fid=14 returned 0, because the parent forum id does not include its subforums.
- `limitation entity hidden` in f=34/14/94 returned only mod release threads.
- `"had to remove"` in posts returned mostly noise about players removing mods, with no feature-cut stories.
- Mod portal discussion (f=94) and the per-mod subforums gave nothing useful through keyword search. Mod authors seem to explain cuts
  in mod-portal discussion tabs and on GitHub, not on the forum.
- Not read, but worth a look: t=121125 (weighted spoil results, 15 replies), t=46302 (steam engine fluid types array, 25 replies, WI),
  t=55661 (WI fluid filters, has dev responses), the Miniloader thread (hidden inserters and UPS), and t=131947
  (loader with fluid energy source broken).
- Caveat: the skip list identifies threads by post id (`p=`), these by topic id (`t=`). I checked titles against the existing catalogue
  headings. There may still be some overlap with skip-list posts whose topics I could not map. The Won't-implement items already
  catalogued were left unread: on_module_changed, fluid lamps, assembler heat_buffer, belt energy_source, Promote Circuit Connections,
  and the compound-entities prototype thread.
