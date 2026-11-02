-- Native for cl-cold-box: iron chest with the same yumako + a 10 kW consumer
-- EEI (TEST-ENTITIES 4: chests + eei-watchers).
CELL = {w = 3, h = 2, place = function(s, slot)
  local c = BENCH.must(s, {name = "iron-chest", position = {slot.left + 0.5, slot.top + 0.5}})
  c.insert{name = "yumako", count = 16 * prototypes.item["yumako"].stack_size}
  BENCH.eei_consumer(s, {slot.left + 2, slot.top + 1}, 10000)
end}
