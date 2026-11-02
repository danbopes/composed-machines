-- Composed: cl-timed-converter (burner assembler shell + 2 hidden containers +
-- 2 proxies, script-started cycles) fed iron ore through the input proxy and
-- emptied through the output proxy, with coal in the shell.
CELL = {w = 7, h = 3, place = function(s, slot)
  local L, y = slot.left, slot.top + 1.5
  BENCH.infinity_source(BENCH.must(s, {name = "infinity-chest", position = {L + 0.5, y}}), {"iron-ore"})
  BENCH.inserter(s, "fast-inserter", {L + 1.5, y})
  local c = BENCH.must(s, {name = "cl-timed-converter", position = {L + 3.5, y}, raise_built = true})
  c.get_fuel_inventory().insert{name = "coal", count = 50}
  BENCH.inserter(s, "fast-inserter", {L + 5.5, y})
  BENCH.infinity_sink(BENCH.must(s, {name = "infinity-chest", position = {L + 6.5, y}}))
end}
