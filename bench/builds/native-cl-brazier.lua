-- Native for cl-brazier: the emulation's burner reactor with no script
-- (cl-brazier-native-burner: the hidden part plus a collision box so an inserter
-- can reach it), the always-burning part with no polling, refuelled the same
-- way, plus a small-lamp on the row below (the engine's own light at no update
-- cost). Together they are what a native composed brazier would cost at most.
CELL = {w = 3, h = 2, place = function(s, slot)
  local L, y = slot.left, slot.top + 0.5
  BENCH.infinity_source(BENCH.must(s, {name = "infinity-chest", position = {L + 0.5, y}}), {"coal"})
  BENCH.inserter(s, "inserter", {L + 1.5, y})
  BENCH.must(s, {name = "cl-brazier-native-burner", position = {L + 2.5, y}})
  BENCH.must(s, {name = "small-lamp", position = {L + 2.5, y + 1}})
end}
