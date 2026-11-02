-- Native for cl-rotating-chest: the passive floor, two steel chests (96 slots;
-- TEST-ENTITIES-2 section 4), one of them on the same item flow (source -> fast
-- inserter -> chest -> fast inserter -> sink), in the same 7x6 cell so the
-- block layout matches the composed cell.
CELL = {w = 7, h = 6, place = function(s, slot)
  local L, T = slot.left, slot.top
  BENCH.infinity_source(BENCH.must(s, {name = "infinity-chest", position = {L + 0.5, T + 2.5}}), {"iron-plate"})
  BENCH.inserter(s, "fast-inserter", {L + 1.5, T + 2.5})
  BENCH.must(s, {name = "steel-chest", position = {L + 2.5, T + 2.5}})
  BENCH.must(s, {name = "steel-chest", position = {L + 2.5, T + 3.5}})
  BENCH.inserter(s, "fast-inserter", {L + 3.5, T + 2.5})
  BENCH.infinity_sink(BENCH.must(s, {name = "infinity-chest", position = {L + 4.5, T + 2.5}}))
end}
