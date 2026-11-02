-- Composed: cl-creep-collector (electric 400 kW assembler shell, script-started
-- 2 s cycles, hidden spoils container + proxy east of the shell) harvesting a
-- tree beside it. The tree is marked renewable so the cell works at steady
-- state: every cycle still pays the search, the yield and the insert. Spoils go
-- out through the proxy to a sink.
CELL = {w = 7, h = 3, place = function(s, slot)
  local L, y = slot.left, slot.top + 1.5
  BENCH.must(s, {name = "tree-01", position = {L + 0.5, y}, force = "neutral"})
  local c = BENCH.must(s, {name = "cl-creep-collector", position = {L + 2.5, y}, raise_built = true})
  remote.call("component_lab", "creep_collector_renewable", c, true)
  BENCH.inserter(s, "fast-inserter", {L + 5.5, y})
  BENCH.infinity_sink(BENCH.must(s, {name = "infinity-chest", position = {L + 6.5, y}}))
end}
