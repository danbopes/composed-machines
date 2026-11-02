-- Composed: cl-seep-derrick (assembler shell, water -> crude every 2 s, crafted
-- handler bumps depletion) between a water infinity pipe and a draining one.
-- h = 6 leaves a gap row so one cell's drain pipe never touches the next
-- row's supply pipe.
CELL = {w = 3, h = 6, place = function(s, slot)
  local x, T = slot.left + 1.5, slot.top
  BENCH.infinity_pipe(s, {x, T + 0.5}, "water", 1)
  BENCH.must(s, {name = "cl-seep-derrick", position = {x, T + 2.5}, raise_built = true})
  BENCH.infinity_pipe(s, {x, T + 4.5}, "crude-oil", 0)
end}
