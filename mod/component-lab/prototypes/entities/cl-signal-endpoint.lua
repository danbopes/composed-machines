-- cl-signal-endpoint: a powered signal source with a status event (S1, electric, script output).
-- TEST-ENTITIES.md section 8.

local component = require("lib.component")

component.define{
  name = "cl-signal-endpoint",
  emulation = {like = "constant-combinator"},
  energy_source = {type = "electric", usage_priority = "secondary-input", buffer_capacity = "1MJ"},
  energy_usage = "50kW",
  activity = "always",
  tick_interval = 60,
  -- true borrows the constant combinator's four-direction connector set.
  circuit_connector = true,
  circuit_outputs = "script",
  max_output_signals = 20,
  events = {status_changed = true, power_state_changed = true},
}
