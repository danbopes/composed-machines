-- Composed: cl-dig-site (assembler shell + 2 hidden containers + 2 proxies,
-- 61-tick idle pass, script-gated cycles) on an iron-ore patch tile, fed fish
-- through the food proxy, ore taken from the ore proxy, one creature module.
CELL = {w = 7, h = 3, place = function(s, slot)
  local L, y = slot.left, slot.top + 1.5
  s.create_entity{name = "iron-ore", position = {L + 3.5, y}, amount = 10000000}
  BENCH.infinity_source(BENCH.must(s, {name = "infinity-chest", position = {L + 0.5, y}}), {"raw-fish"})
  BENCH.inserter(s, "fast-inserter", {L + 1.5, y})
  local c = BENCH.must(s, {name = "cl-dig-site", position = {L + 3.5, y}, raise_built = true})
  c.get_module_inventory().insert{name = "cl-creature-fast", count = 1}
  BENCH.inserter(s, "fast-inserter", {L + 5.5, y})
  BENCH.infinity_sink(BENCH.must(s, {name = "infinity-chest", position = {L + 6.5, y}}))
end}
