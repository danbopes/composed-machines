-- Composed: cl-mass-driver (4 MW draw / 40 MJ buffer / 8 MW input electric assembler shell, fixed
-- 1-plate 10 s recipe, no hidden parts; the cycle_finished handler fires a
-- harmless slug 20 tiles north). Fed iron plates by a fast inserter from an
-- infinity chest; the plate is the only input and the shot the only output,
-- so there is no sink. The shell's insertion limit lets the inserter sleep.
CELL = {w = 5, h = 3, place = function(s, slot)
  local L, y = slot.left, slot.top + 1.5
  BENCH.infinity_source(BENCH.must(s, {name = "infinity-chest", position = {L + 0.5, y}}), {"iron-plate"})
  BENCH.inserter(s, "fast-inserter", {L + 1.5, y})
  local c = BENCH.must(s, {name = "cl-mass-driver", position = {L + 3.5, y}, raise_built = true})
  c.insert{name = "iron-plate", count = 2}
  -- Charging the buffer takes ~6400 ticks, longer than the settle, and the
  -- shell reports low_power until it is full.
  c.energy = c.electric_buffer_size
end}
