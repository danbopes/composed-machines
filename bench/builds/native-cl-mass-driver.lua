-- Native for cl-mass-driver: the shell on its own, an assembling-machine-2
-- working with no Lua behind it (TEST-ENTITIES-2 section 7). Iron gear wheels
-- from plates, bulk inserter in (a fast one cannot keep up), fast inserter out
-- to an infinity sink, as in assembler.lua, so the column is "the same native
-- crafter, minus the shot".
CELL = {w = 7, h = 3, place = function(s, slot)
  local L, y = slot.left, slot.top + 1.5
  BENCH.infinity_source(BENCH.must(s, {name = "infinity-chest", position = {L + 0.5, y}}), {"iron-plate"})
  BENCH.inserter(s, "bulk-inserter", {L + 1.5, y})
  local m = BENCH.must(s, {name = "assembling-machine-2", position = {L + 3.5, y}})
  m.set_recipe("iron-gear-wheel")
  BENCH.inserter(s, "fast-inserter", {L + 5.5, y})
  BENCH.infinity_sink(BENCH.must(s, {name = "infinity-chest", position = {L + 6.5, y}}))
end}
