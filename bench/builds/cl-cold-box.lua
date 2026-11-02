-- Composed: cl-cold-box (container + hidden EEI + 60-tick spoil pass) holding
-- 16 stacks of yumako, powered from the substation network.
CELL = {w = 3, h = 2, place = function(s, slot)
  local c = BENCH.must(s, {name = "cl-cold-box", position = {slot.left + 0.5, slot.top + 0.5}, raise_built = true})
  c.insert{name = "yumako", count = 16 * prototypes.item["yumako"].stack_size}
end}
