-- Today's way (Renai's item cannon): a chest holding the plates, a
-- secondary-input EEI with a 40 MJ buffer and a 4 MW input limit on top of it
-- (cl-mass-driver-poll-eei), and ONE shared Lua walk every 15 ticks over all
-- cells: "buffer full and a plate present?" -> take the plate, zero the
-- buffer, fire the same slug 20 tiles north. The chest's bar is one slot and
-- it starts full, so the feeding inserter sleeps like the composed shell's.
CELL = {w = 3, h = 1, place = function(s, slot)
  local L, y = slot.left, slot.top + 0.5
  BENCH.infinity_source(BENCH.must(s, {name = "infinity-chest", position = {L + 0.5, y}}), {"iron-plate"})
  BENCH.inserter(s, "fast-inserter", {L + 1.5, y})
  local chest = BENCH.must(s, {name = "iron-chest", position = {L + 2.5, y}})
  chest.get_inventory(defines.inventory.chest).set_bar(2)
  chest.insert{name = "iron-plate", count = 100}
  local eei = BENCH.must(s, {name = "cl-mass-driver-poll-eei", position = {L + 2.5, y}})
  remote.call("component_lab", "mass_driver_poll_add", eei, chest)
end}
