-- cl-cold-box: a powered chest that slows spoilage (S1, electric watcher). TEST-ENTITIES.md section 4.

local component = require("lib.component")

component.define{
  name = "cl-cold-box",
  emulation = {like = "iron-chest"},
  inventories = {{
    name = "cold",
    role = "storage",
    size = 16,
    with_bar = true,
    spoil_modifier = {multiplier = 8, requires_power = true},
  }},
  energy_source = {type = "electric", usage_priority = "secondary-input", drain = "0W"},
  energy_usage = "10kW",
  activity = "inventory_not_empty",
  activity_inventories = {"cold"},
  tick_interval = 60,
  conditions = {{type = "powered", status = "no_power", diode = "red"}},
  events = {power_state_changed = true},
}

