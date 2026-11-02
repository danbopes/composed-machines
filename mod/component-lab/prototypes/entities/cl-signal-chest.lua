-- cl-signal-chest: a chest with script-written signals (S0). TEST-ENTITIES.md section 2.

local component = require("lib.component")

component.define{
  name = "cl-signal-chest",
  emulation = {like = "wooden-chest"},
  inventories = {{name = "main", role = "storage", size = 16}},
  circuit_connector = true,
  circuit_outputs = "script",
  max_output_signals = 20,
  events = {inventory_changed = {"main"}},
}
