-- Native for cl-hearth: what the composed type would cost if it were two native
-- entities, the sum TEST-ENTITIES-2 section 1 compares against. A stone furnace
-- working the same ore -> plate line (the S3 burner crafter, which sleeps
-- between crafts), plus the hearth's own hidden reactor prototype with coal and
-- no script attached (the always-burning part on its own, 90 kW).
CELL = {w = 6, h = 2, place = function(s, slot)
  local L, T = slot.left, slot.top
  BENCH.infinity_source(BENCH.must(s, {name = "infinity-chest", position = {L + 0.5, T + 0.5}}), {"iron-ore"})
  BENCH.inserter(s, "fast-inserter", {L + 1.5, T + 0.5})
  local f = BENCH.must(s, {name = "stone-furnace", position = {L + 3, T + 1}})
  f.get_fuel_inventory().insert{name = "coal", count = 50}
  local r = BENCH.must(s, {name = "cl-hearth-burner", position = {L + 3, T + 1}})
  r.get_fuel_inventory().insert{name = "coal", count = 50}
  BENCH.inserter(s, "fast-inserter", {L + 4.5, T + 0.5})
  BENCH.infinity_sink(BENCH.must(s, {name = "infinity-chest", position = {L + 5.5, T + 0.5}}))
end}
