-- Composed: cl-tuned-furnace (electric assembler shell, ore -> plate 3.2 s, a
-- 30-tick Lua pass per machine reading signal-R and writing local_effect),
-- fed ore by inserter from an infinity chest, plates out to a sink, with a
-- constant combinator holding signal-R = 25 (speed +1.5, what two speed-3
-- modules in one beacon give the beacon column). h = 9 is the beacon column's
-- footprint, kept here so all three columns share one grid and substation count.
CELL = {w = 7, h = 9, place = function(s, slot)
  local L, T = slot.left, slot.top
  local y = T + 1.5
  BENCH.infinity_source(BENCH.must(s, {name = "infinity-chest", position = {L + 0.5, y}}), {"iron-ore"})
  BENCH.inserter(s, "fast-inserter", {L + 1.5, y})
  local f = BENCH.must(s, {name = "cl-tuned-furnace", position = {L + 3.5, y}, raise_built = true})
  BENCH.inserter(s, "fast-inserter", {L + 5.5, y})
  BENCH.infinity_sink(BENCH.must(s, {name = "infinity-chest", position = {L + 6.5, y}}))
  local cc = BENCH.must(s, {name = "constant-combinator", position = {L + 0.5, T + 3.5}})
  cc.get_or_create_control_behavior().add_section().filters =
    {{value = {type = "virtual", name = "signal-R", quality = "normal", comparator = "="}, min = 25}}
  local red = defines.wire_connector_id.circuit_red
  cc.get_wire_connector(red, true).connect_to(f.get_wire_connector(red, true))
end}
