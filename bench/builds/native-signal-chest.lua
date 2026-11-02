-- Native for cl-signal-chest: wooden chest on the same item flow, wired (red)
-- to a constant combinator with one signal (TEST-ENTITIES 2: signal-chests).
CELL = {w = 6, h = 1, place = function(s, slot)
  local L, y = slot.left, slot.top + 0.5
  BENCH.infinity_source(BENCH.must(s, {name = "infinity-chest", position = {L + 0.5, y}}), {"iron-plate"})
  BENCH.inserter(s, "fast-inserter", {L + 1.5, y})
  local c = BENCH.must(s, {name = "wooden-chest", position = {L + 2.5, y}})
  BENCH.inserter(s, "fast-inserter", {L + 3.5, y})
  BENCH.infinity_sink(BENCH.must(s, {name = "infinity-chest", position = {L + 4.5, y}}))
  local cc = BENCH.must(s, {name = "constant-combinator", position = {L + 5.5, y}})
  cc.get_control_behavior().get_section(1).set_slot(1,
    {value = {type = "item", name = "iron-plate", quality = "normal"}, min = 1})
  local red = defines.wire_connector_id.circuit_red
  c.get_wire_connector(red, true).connect_to(cc.get_wire_connector(red, true))
end}
