-- Native for cl-signal-endpoint: constant combinator with one signal + a
-- 50 kW consumer EEI (TEST-ENTITIES 8: endpoints).
CELL = {w = 3, h = 2, place = function(s, slot)
  local cc = BENCH.must(s, {name = "constant-combinator", position = {slot.left + 0.5, slot.top + 0.5}})
  cc.get_control_behavior().get_section(1).set_slot(1,
    {value = {type = "item", name = "iron-plate", quality = "normal"}, min = 1})
  BENCH.eei_consumer(s, {slot.left + 2, slot.top + 1}, 50000)
end}
