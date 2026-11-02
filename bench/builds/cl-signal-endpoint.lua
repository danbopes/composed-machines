-- Composed: cl-signal-endpoint (constant-combinator core + hidden 50 kW EEI,
-- 60-tick power poll) publishing one signal.
CELL = {w = 3, h = 2, place = function(s, slot)
  local c = BENCH.must(s, {name = "cl-signal-endpoint", position = {slot.left + 0.5, slot.top + 0.5}, raise_built = true})
  remote.call("component_lab", "endpoint_publish", c.unit_number,
    {{name = "iron-plate", type = "item", quality = "normal", count = 1}})
end}
