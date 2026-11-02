-- Today (Rampant #64): a consumer EEI holding one 800 kJ unit of work, charged
-- at 400 kW, plus one shared 60-tick Lua walk over every cell that deducts the
-- unit, harvests the nearest tree (kept, as in the composed cell) and puts the
-- wood in a chest, which an inserter empties into a sink.
CELL = {w = 7, h = 3, place = function(s, slot)
  local L, y = slot.left, slot.top + 1.5
  BENCH.must(s, {name = "tree-01", position = {L + 0.5, y}, force = "neutral"})
  local eei = BENCH.must(s, {name = "cl-creep-collector-poll-eei", position = {L + 2, slot.top + 1}})
  local chest = BENCH.must(s, {name = "steel-chest", position = {L + 3.5, y}})
  remote.call("component_lab", "creep_poll_add", eei, chest, true)
  BENCH.inserter(s, "fast-inserter", {L + 4.5, y})
  BENCH.infinity_sink(BENCH.must(s, {name = "infinity-chest", position = {L + 5.5, y}}))
end}
