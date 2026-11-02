-- Native for cl-seep-derrick: a chemical plant on lubricant (one fluid in, one
-- out, 1 s) between a heavy-oil infinity pipe and a draining one. No base
-- assembler recipe turns one fluid into another, so this is the closest
-- native fluid-to-fluid crafter (TEST-ENTITIES 6 asks for fluid-assembler).
-- h = 6 leaves a gap row so one cell's drain pipe never touches the next
-- row's supply pipe.
CELL = {w = 3, h = 6, place = function(s, slot)
  local L, T = slot.left, slot.top
  BENCH.infinity_pipe(s, {L + 0.5, T + 0.5}, "heavy-oil", 1)
  local m = BENCH.must(s, {name = "chemical-plant", position = {L + 1.5, T + 2.5}})
  m.force.recipes["lubricant"].enabled = true
  m.set_recipe("lubricant")
  BENCH.infinity_pipe(s, {L + 0.5, T + 4.5}, "lubricant", 0)
end}
