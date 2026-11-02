-- Composed: cl-brazier (simple-entity core + hidden burner reactor + fuel door,
-- 30-tick power-state pass, script light), refuelled by an inserter from an
-- infinity chest of coal through the fuel door, so it burns at steady state.
CELL = {w = 3, h = 1, place = function(s, slot)
  local L, y = slot.left, slot.top + 0.5
  BENCH.infinity_source(BENCH.must(s, {name = "infinity-chest", position = {L + 0.5, y}}), {"coal"})
  BENCH.inserter(s, "inserter", {L + 1.5, y})
  local c = BENCH.must(s, {name = "cl-brazier", position = {L + 2.5, y}, raise_built = true})
  remote.call("component_lab", "parts", c.unit_number)["energy:energy"].get_fuel_inventory().insert{name = "coal", count = 5}
end}
