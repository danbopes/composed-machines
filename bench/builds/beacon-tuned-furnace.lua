-- Third column for cl-tuned-furnace: the pre-2.1.13 way to give one machine a
-- runtime speed. The same shell, unscripted (no raise_built), gets a beacon of
-- its own below it; one shared 30-tick walk in the mod (tuned_furnace_beacon_add)
-- reads signal-R off each shell's wire and swaps speed-3 modules when it
-- changes. signal-R = 25 -> two modules -> +1.5, matching the other columns.
-- h = 9: a beacon reaches 3 tiles past its edge, so the next cell's shell must
-- start 9 tiles below this one's top to stay out of range.
CELL = {w = 7, h = 9, place = function(s, slot)
  local L, T = slot.left, slot.top
  local y = T + 1.5
  BENCH.infinity_source(BENCH.must(s, {name = "infinity-chest", position = {L + 0.5, y}}), {"iron-ore"})
  BENCH.inserter(s, "fast-inserter", {L + 1.5, y})
  local f = BENCH.must(s, {name = "cl-tuned-furnace", position = {L + 3.5, y}})
  BENCH.inserter(s, "fast-inserter", {L + 5.5, y})
  BENCH.infinity_sink(BENCH.must(s, {name = "infinity-chest", position = {L + 6.5, y}}))
  local cc = BENCH.must(s, {name = "constant-combinator", position = {L + 0.5, T + 3.5}})
  cc.get_or_create_control_behavior().add_section().filters =
    {{value = {type = "virtual", name = "signal-R", quality = "normal", comparator = "="}, min = 25}}
  local red = defines.wire_connector_id.circuit_red
  cc.get_wire_connector(red, true).connect_to(f.get_wire_connector(red, true))
  local b = BENCH.must(s, {name = "beacon", position = {L + 3.5, T + 4.5}})
  remote.call("component_lab", "tuned_furnace_beacon_add", f, b)
end}
