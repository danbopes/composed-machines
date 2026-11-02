-- Composed: cl-rotating-chest placed turned (east, 3x6: the orientation only the
-- emulation's replacement path can reach after placement) on an item flow across
-- its long sides: source -> fast inserter -> door -> 240-slot hidden container
-- -> door -> fast inserter -> sink. The recipe-less assembler shell, one hidden
-- container and 14 proxy doors per cell; no Lua runs after build.
CELL = {w = 7, h = 6, place = function(s, slot)
  local L, T = slot.left, slot.top
  BENCH.infinity_source(BENCH.must(s, {name = "infinity-chest", position = {L + 0.5, T + 2.5}}), {"iron-plate"})
  BENCH.inserter(s, "fast-inserter", {L + 1.5, T + 2.5})
  BENCH.must(s, {name = "cl-rotating-chest", position = {L + 3.5, T + 3}, direction = defines.direction.east,
    raise_built = true})
  BENCH.inserter(s, "fast-inserter", {L + 5.5, T + 3.5})
  BENCH.infinity_sink(BENCH.must(s, {name = "infinity-chest", position = {L + 6.5, T + 3.5}}))
end}
