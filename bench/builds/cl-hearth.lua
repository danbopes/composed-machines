-- Composed: cl-hearth (void assembler shell + hidden burner reactor + fuel door,
-- one scheduled pass per hearth every 20 ticks), fed iron ore by an inserter into
-- the shell, plates taken out to a sink, 50 coal in the reactor. The reactor
-- burns 90 kW whether or not the shell crafts: the S3 "always" cost.
CELL = {w = 6, h = 2, place = function(s, slot)
  local L, T = slot.left, slot.top
  BENCH.infinity_source(BENCH.must(s, {name = "infinity-chest", position = {L + 0.5, T + 0.5}}), {"iron-ore"})
  BENCH.inserter(s, "fast-inserter", {L + 1.5, T + 0.5})
  local c = BENCH.must(s, {name = "cl-hearth", position = {L + 3, T + 1}, raise_built = true})
  remote.call("component_lab", "parts", c.unit_number)["energy:energy"].get_fuel_inventory().insert{name = "coal", count = 50}
  BENCH.inserter(s, "fast-inserter", {L + 4.5, T + 0.5})
  BENCH.infinity_sink(BENCH.must(s, {name = "infinity-chest", position = {L + 5.5, T + 0.5}}))
end}
