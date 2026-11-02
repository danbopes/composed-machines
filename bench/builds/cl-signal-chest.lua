-- Composed: cl-signal-chest on an item flow (source -> inserter -> chest ->
-- inserter -> sink), so its inventory_changed poll sees real changes, with one
-- published signal in the hidden combinator.
CELL = {w = 6, h = 1, place = function(s, slot)
  local L, y = slot.left, slot.top + 0.5
  BENCH.infinity_source(BENCH.must(s, {name = "infinity-chest", position = {L + 0.5, y}}), {"iron-plate"})
  BENCH.inserter(s, "fast-inserter", {L + 1.5, y})
  local c = BENCH.must(s, {name = "cl-signal-chest", position = {L + 2.5, y}, raise_built = true})
  BENCH.inserter(s, "fast-inserter", {L + 3.5, y})
  BENCH.infinity_sink(BENCH.must(s, {name = "infinity-chest", position = {L + 4.5, y}}))
  remote.call("component_lab", "signal_chest_publish", c.unit_number,
    {{name = "iron-plate", type = "item", quality = "normal", count = 1}})
end}
