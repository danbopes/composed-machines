-- Composed: cl-waste-heat-smelter (electric assembler shell crafting copper ore
-- into plates + hidden heat-interface fed 400 kJ per crafted event), ore in from
-- an infinity chest, plates out to a sink, and its heat carried by one heat pipe
-- into a base heat-interface held at most 15 C, so heat flows at steady state.
-- h = 6 leaves a gap row so the sink never touches the next row's cell.
CELL = {w = 7, h = 6, place = function(s, slot)
  local L, T = slot.left, slot.top
  local y = T + 1.5
  BENCH.infinity_source(BENCH.must(s, {name = "infinity-chest", position = {L + 0.5, y}}), {"copper-ore"})
  BENCH.inserter(s, "fast-inserter", {L + 1.5, y})
  BENCH.must(s, {name = "cl-waste-heat-smelter", position = {L + 3.5, y}, raise_built = true})
  BENCH.inserter(s, "fast-inserter", {L + 5.5, y})
  BENCH.infinity_sink(BENCH.must(s, {name = "infinity-chest", position = {L + 6.5, y}}))
  BENCH.must(s, {name = "heat-pipe", position = {L + 3.5, T + 3.5}})
  local sink = BENCH.must(s, {name = "heat-interface", position = {L + 3.5, T + 4.5}})
  sink.set_heat_setting{temperature = 15, mode = "at-most"}
end}
