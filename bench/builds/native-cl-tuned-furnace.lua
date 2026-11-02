-- Native for cl-tuned-furnace: the same shell prototype placed without
-- raise_built, so no record and no Lua pass, with local_effect.speed = 1.5 set
-- once at build time. That is what the native composed machine would cost: the
-- engine applies the bound setting itself and the speed rides on the entity.
-- Same feed, sink, wired combinator and h = 9 grid as the other two columns.
CELL = {w = 7, h = 9, place = function(s, slot)
  local L, T = slot.left, slot.top
  local y = T + 1.5
  BENCH.infinity_source(BENCH.must(s, {name = "infinity-chest", position = {L + 0.5, y}}), {"iron-ore"})
  BENCH.inserter(s, "fast-inserter", {L + 1.5, y})
  local f = BENCH.must(s, {name = "cl-tuned-furnace", position = {L + 3.5, y}})
  f.local_effect = {speed = 1.5}
  BENCH.inserter(s, "fast-inserter", {L + 5.5, y})
  BENCH.infinity_sink(BENCH.must(s, {name = "infinity-chest", position = {L + 6.5, y}}))
  local cc = BENCH.must(s, {name = "constant-combinator", position = {L + 0.5, T + 3.5}})
  cc.get_or_create_control_behavior().add_section().filters =
    {{value = {type = "virtual", name = "signal-R", quality = "normal", comparator = "="}, min = 25}}
  local red = defines.wire_connector_id.circuit_red
  cc.get_wire_connector(red, true).connect_to(f.get_wire_connector(red, true))
end}
