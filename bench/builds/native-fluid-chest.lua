-- Native for cl-fluid-chest: wooden chest + storage tank kept full by an
-- infinity pipe (TEST-ENTITIES 1: chests + tanks).
CELL = {w = 3, h = 4, place = function(s, slot)
  local L, T = slot.left, slot.top
  BENCH.infinity_pipe(s, {L + 0.5, T + 0.5}, "water", 1)
  local c = BENCH.must(s, {name = "wooden-chest", position = {L + 2.5, T + 0.5}})
  c.insert{name = "iron-plate", count = 100}
  BENCH.must(s, {name = "storage-tank", position = {L + 1.5, T + 2.5}})
end}
