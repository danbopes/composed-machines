-- Third column for cl-waste-heat-smelter: a base nuclear-reactor burning uranium fuel
-- cells, the engine's own heat-buffer owner pushing heat every tick, into the
-- same pipe + at-most-15 C heat-interface sink. It prices a native HeatBuffer
-- owner that is always hot (TEST-ENTITIES-2 6). Ten cells outlast settle plus
-- five 3600-tick runs; h = 8 keeps the sink clear of the next row's reactor.
CELL = {w = 5, h = 8, place = function(s, slot)
  local L, T = slot.left, slot.top
  local r = BENCH.must(s, {name = "nuclear-reactor", position = {L + 2.5, T + 2.5}})
  r.get_fuel_inventory().insert{name = "uranium-fuel-cell", count = 10}
  BENCH.must(s, {name = "heat-pipe", position = {L + 2.5, T + 5.5}})
  local sink = BENCH.must(s, {name = "heat-interface", position = {L + 2.5, T + 6.5}})
  sink.set_heat_setting{temperature = 15, mode = "at-most"}
end}
