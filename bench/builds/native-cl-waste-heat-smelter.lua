-- Native for cl-waste-heat-smelter: an electric furnace on the same copper ore
-- line, plus a base heat-interface at rest standing in for the heat part
-- (TEST-ENTITIES-2 6: "electric-furnace working + heat-interface static"), on
-- the same heat sink as the composed cell. The furnace crafts at speed 2, the
-- smelter at 1; the column compares per machine, not per plate.
CELL = {w = 7, h = 6, place = function(s, slot)
  local L, T = slot.left, slot.top
  local y = T + 1.5
  BENCH.infinity_source(BENCH.must(s, {name = "infinity-chest", position = {L + 0.5, y}}), {"copper-ore"})
  BENCH.inserter(s, "fast-inserter", {L + 1.5, y})
  BENCH.must(s, {name = "electric-furnace", position = {L + 3.5, y}})
  BENCH.inserter(s, "fast-inserter", {L + 5.5, y})
  BENCH.infinity_sink(BENCH.must(s, {name = "infinity-chest", position = {L + 6.5, y}}))
  BENCH.must(s, {name = "heat-interface", position = {L + 3.5, T + 3.5}})
  local sink = BENCH.must(s, {name = "heat-interface", position = {L + 3.5, T + 4.5}})
  sink.set_heat_setting{temperature = 15, mode = "at-most"}
end}
