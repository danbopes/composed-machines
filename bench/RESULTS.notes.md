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
- **pY:** the family census for all three saves is below. The 3600-tick pY benchmark was paused before it ran, so the census has no script timings next to it yet. The only pY timing so far is the 300-tick validation of pY 134 on a busy box: 19.95 ms/update, scriptUpdate 2.20 ms.
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
