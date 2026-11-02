-- Composed: cl-fuelled-chest holding items (so it is active) with coal in the
-- hidden burner reactor; the reactor burns and the per-entity poll runs.
CELL = {w = 1, h = 1, place = function(s, slot)
  local c = BENCH.must(s, {name = "cl-fuelled-chest", position = {slot.left + 0.5, slot.top + 0.5}, raise_built = true})
  c.insert{name = "iron-plate", count = 10}
  local parts = remote.call("component_lab", "parts", c.unit_number)
  parts["energy:energy"].get_fuel_inventory().insert{name = "coal", count = 50}
end}
