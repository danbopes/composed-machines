-- Native for cl-fuelled-chest: wooden chest + a standalone burner reactor (the
-- emulation's own hidden reactor prototype, no script attached) with coal:
-- the exact native cost of the ticking part (TEST-ENTITIES 3: burner-reactors).
CELL = {w = 1, h = 1, place = function(s, slot)
  local p = {slot.left + 0.5, slot.top + 0.5}
  local c = BENCH.must(s, {name = "wooden-chest", position = p})
  c.insert{name = "iron-plate", count = 10}
  local r = BENCH.must(s, {name = "cl-fuelled-chest-burner", position = p})
  r.get_fuel_inventory().insert{name = "coal", count = 50}
end}
