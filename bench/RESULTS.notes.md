## What the numbers say (quick overview)

All figures come from one 5-run pass pinned to CPUs 8-11, with the baloo indexer suspended and kdeconnectd stopped. The pY rows are a later 3-run pass (2026-11-02 04:30-04:50) on the same pinning with the indexer disabled; the first pY 134 pass ran while the indexer was still active (spread +/-23.6 %) and was discarded for the rerun (spread 1.3 %).

- **Passive and sleeping entities cost nothing measurable.** 20000 chests run at the empty-world floor (0.11 ms). So do 20000 idle electric furnaces (0.15 ms vs 0.11).
- **Working native machines cost 47-100 ns per instance per tick at N=2000, and 61-140 ns at N=20000.** Each cell is the machine plus two inserters and two infinity chests. Electric furnace 47 / 64 ns, stone furnace 55 / 61 ns, assembler 100 / 140 ns.
- **The emulation's extra cost is almost all Lua.** For the five non-crafter entities, the hidden part (reactor, EEI, storage tank, combinator) costs what the same native entity costs in its per-class column. Examples: Reactor 0.0516 vs 0.0514 ms for 2000 fuelled chests; EEI 0.025 vs 0.022 ms for 2000 endpoints. The difference is `scriptUpdate` plus extra `luaGarbageIncremental`, which come from the polls that stand in for engine wake-ups.
- **Composed / native, whole-update ns per instance:**
  - fluid chest 83 / 22 (3.8x)
  - signal chest 413 / 93 (4.4x)
  - fuelled chest 152 / 51 (3.0x)
  - cold box 542 / 16 (35x)
  - timed converter 777 / 100 vs assembler (7.8x)
  - seep derrick 149 / 90 (1.7x)
  - dig site 60 / 47 vs electric furnace (1.3x)
  - signal endpoint 81 / 15 (5.6x)
- **The two pY-style crafters with event-only scripts (dig site, seep derrick) pay almost no `scriptUpdate`, about 1-4 ns per instance.** The rest of their gap shows up in the `AssemblingMachine` column: derrick shell 0.153 ms vs a chemical plant on lubricant at 0.045 ms; converter shell 0.219 ms vs a gear assembler at 0.037 ms. These runs do not show which part of the shell causes that. Candidates are the extra fluid box, `raise_on_crafted`, and `disabled_by_script` toggling.
- **Polls without phase spreading make spikes.** The timed converter and signal chest schedule every record on the same tick, so 2000 polls land together every 10 ticks. Their median tick sits near the native one (0.19 / 0.22 ms) while p95 reaches 5-10 ms. The mean, which the per-instance figures use, spreads that cost over all ticks. The cold box and endpoint use `schedule_phase` and show no such spikes.
- **Comparison caveats:**
  - Native seep derrick: base has no one-fluid-to-one-fluid assembler recipe, so its twin is a chemical plant on lubricant (1 s cycle vs the derrick's 2 s).
  - Native fuelled chest: its twin uses the emulation's own hidden reactor prototype with no script attached.
  - Per-instance figures subtract an empty world and include the cell's feeding entities, which are identical between each pair.
- **pY:** the family census for all three saves is below, and the 3600-tick timings are in section (d) and the pY paragraph at the end of these notes (an earlier 300-tick validation of pY 134 on a busy box gave 19.95 ms/update).
- **mulark:** the 1.1-era inserter/assembler maps run at 0.70-3.95 ms/update with stable spreads (1-9%). test-000060 (400x direct-insertion chains) spends 3.9 ms, mostly in the AssemblingMachine and Inserter columns.

- **pY saves (section d).** Three real bases, each run with its own mod set (73-76 mods): pY 134 at 6.12 ms per
  update, pY Fixed at 6.26 ms, the smaller A2 Fixed at 2.22 ms (spreads 1.3-3.8 %). The split is what matters for the
  proposal: `entityUpdate` is 1.81 / 1.69 / 0.60 ms (27-30 % of the tick) and Lua, counted as `scriptUpdate` plus
  `luaGarbageIncremental`, is 1.75 / 1.95 / 0.92 ms, which is **29 %, 31 % and 41 % of the tick**, the same size as
  the whole entity update. Trains are 17-19 % on the two big saves. The Lua share belongs to every mod in the save
  (pY's nth-tick loops, Cybersyn, the rest), not only to compound-entity emulation; the census (above) says how many
  of each Lua-composed family these saves hold (14 dig sites and 29 derricks in pY 134; 9 + 9 biofluid tanks and a
  bioport in A2 Fixed; 5,100 farms and 2,176 TURD beacons, which are vanilla crafters with a Lua loop). The garbage
  collector alone costs 0.63-0.83 ms per tick, which is what per-tick polling tables buy, and why the proposed events
  carry scalars and no inventory copies. Per-mod attribution would need the graphical client's time-usage panel; it
  was not done.

- **Second pass (section b, rows from `cl-hearth` down; 2026-11-02 07:43-07:45).** Eight more entities from `../docs/TEST-ENTITIES-2.md`. Each was built at N = 2000 with a 3600-tick settle, then run 3 x 3600 ticks (first 300 dropped) pinned to CPUs 8-11, loadavg 0.8-1.7. The empty baseline was rerun in the same pass: 0.107 ms best run, the same as the first pass's 0.106, but with a +/-31 % run-to-run spread. Before the run, every build check showed its machines at 100 % `working`. Two exceptions, both intended: the rotating-chest shells are `no_recipe` (a passive shape), and the poll and reactor columns have no crafter. Composed / native, whole-update ns per instance (ratio; composed `scriptUpdate` ns, and its share of the composed delta):
  - hearth 234 / 101 vs stone furnace + bare reactor (2.3x; 125 ns, 53 %)
  - brazier 111 / 53 vs bare reactor + lamp (2.1x; 61 ns, 55 %)
  - creep collector 390 / 49 vs electric furnace (7.9x), and 390 / 194 vs the Rampant-style 60-tick poll (2.0x); 7 ns, 2 %, but see below
  - rotating chest 114 / 94 vs two steel chests on the same flow (1.2x; 2 ns, no Lua after build)
  - slag generator 125 / 158 vs steam engine + stone furnace (0.79x; 3 ns)
  - waste-heat smelter 122 / 113 vs electric furnace + resting heat interface (1.08x), and 122 / 87 vs an always-hot nuclear reactor (1.4x); 3 ns
  - mass driver 40 / 98 vs a gear assembler (0.41x), and 40 / 45 vs the 15-tick dispatcher poll (0.88x); 3 ns
  - tuned furnace 143 / 74 vs the shell with `local_effect` set once (1.9x), and 143 / 98 vs the beacon + module-swap walk (1.5x); 67 ns, 47 %
- **Handlers on `on_crafted_event` run inside the entity update, so their Lua is billed to `AssemblingMachine`, not `scriptUpdate`.** Creep collector shows this most clearly. Every 120 ticks all 2000 shells finish their 2 s cycle together, and that tick costs 78-84 ms. Almost all of it is in `AssemblingMachine` (77.9 ms); `scriptUpdate` on the same tick is 0.01 ms. That is about 39 us per finished cycle: the tree search, the yield and the insert. Averaged over all ticks it is 355 ns per instance in that column, against 0.3 ns for the twin's. The mass driver shows the same thing at 600-tick intervals: 11 ms spikes, about 5.6 us per shot. Slag generator and waste-heat smelter carry 34-40 ns per instance there, against 18-20 ns for a gear assembler's own crafting work. This probably also explains the first pass's unexplained `AssemblingMachine` gap on dig site and seep derrick, whose scripts also run on crafted events. So for event-driven entities, the `scriptUpdate` column understates the Lua cost. Read `AssemblingMachine` together with it.
- **The poll columns are cheaper than the event emulation only where the event handler does more work per call.** poll-creep-collector spends 162 ns per instance in `scriptUpdate`, in 57-60 ms walks every 60 ticks. The composed collector spends about 2.2x that, inline in the crafted handler, where each finished cycle runs the harvest and then a fresh search for the next target. The mass-driver poll walk costs 23 ns per instance and the composed shot about 26 ns, so they are even. The beacon column's 30-tick walk costs 24 ns per instance, and the tuned furnace's own 30-tick `local_effect` pass costs 67 ns. With `local_effect` written once and no pass at all (the native column), the extra is 4 ns.
- **Spikes:** the hearth (20-tick pass) and the brazier (30-tick pass) schedule every record on the same tick. Their median tick stays at the native level (0.26 / 0.20 ms), while the pass ticks reach 4.4 ms (hearth) and 3.2 ms (brazier); 92-95 % of their `scriptUpdate` lands on those ticks. The tuned furnace spreads its pass over five phases (spikes every 6 ticks, at most 1.9 ms). The crafted-event spikes above line up because every cell was built and started on the same tick. A real factory would desynchronise them, but the mean would not change.
- **Rotating chest has no Lua, but its recipe-less shell still costs 18 ns per instance in `AssemblingMachine` (0.037 ms total, the same as 2000 working gear assemblers).** A `no_recipe` assembler does not leave the update list. That accounts for the whole gap to the native chests. The 28,000 proxy doors (14 per cell) cost nothing measurable.
- **Second-pass caveats:**
  - 3 runs, not the first pass's 5.
  - Several twins are not the same work. The mass driver fires one plate per 10 s while its gear-assembler twin crafts continuously. The slag generator's twin is two entities, a steam engine on an infinity steam pipe and a stone furnace, and the steam-engine part costs more than the hidden EEI. The waste-heat smelter crafts at speed 1, the twin's electric furnace at speed 2. The brazier and hearth twins use the emulation's own reactor prototype with no script attached.
  - Ratios under 1.0 (slag generator, mass driver) say the twin does more, not that the emulation is cheap.
  - The native-matrix twins (stone-furnace, electric-furnace, assembler, chests) are the first pass's 5-run results. They were not rerun.
  - The per-instance figures use the new empty baseline, which moves the first-pass rows by 0.5 ns or less.
