-- Native for cl-slag-generator: the two halves it fakes, each as the engine runs
-- it. A steam-engine on a 165 C steam infinity pipe (the engine's own continuous
-- generator, the generation part's cost) and a stone-furnace smelting iron ore on
-- coal from an infinity chest, plates out to a sink (the S3 burner crafter shape).
-- The same 2 MW consumer EEI as the composed cell drains the engine.
CELL = {w = 7, h = 9, place = function(s, slot)
  local L, T = slot.left, slot.top
  local y = T + 1.5
  BENCH.infinity_source(BENCH.must(s, {name = "infinity-chest", position = {L + 0.5, y}}), {"iron-ore", "coal"})
  BENCH.inserter(s, "fast-inserter", {L + 1.5, y})
  BENCH.must(s, {name = "stone-furnace", position = {L + 3, T + 2}})
  BENCH.inserter(s, "fast-inserter", {L + 4.5, y})
  BENCH.infinity_sink(BENCH.must(s, {name = "infinity-chest", position = {L + 5.5, y}}))
  local steam = BENCH.must(s, {name = "infinity-pipe", position = {L + 0.5, T + 4.5}})
  steam.set_infinity_pipe_filter{name = "steam", temperature = 165, percentage = 1, mode = "exactly"}
  BENCH.must(s, {name = "steam-engine", position = {L + 3.5, T + 4.5}, direction = defines.direction.east})
  BENCH.eei_consumer(s, {L + 1, T + 7}, 2e6)
end}
