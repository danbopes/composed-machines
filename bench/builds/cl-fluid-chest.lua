-- Composed: cl-fluid-chest-watch (container + hidden storage tank + 60-tick
-- threshold poll), its tank kept full by an infinity pipe on the north side.
CELL = {w = 2, h = 3, place = function(s, slot)
  local x, y = slot.left + 0.5, slot.top + 0.5
  BENCH.infinity_pipe(s, {x, y}, "water", 1)
  local c = BENCH.must(s, {name = "cl-fluid-chest-watch", position = {x, y + 1}, raise_built = true})
  c.insert{name = "iron-plate", count = 100}
end}
