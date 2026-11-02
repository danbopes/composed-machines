-- Throwaway composed machines that exist only so the library's own tests
-- (ai-harness/suites/component-lab/_lib.lua) can exercise every part kind.

local component = require("lib.component")

component.define{
  name = "cl-libtest",
  emulation = {like = "iron-chest"},
  inventories = {
    {name = "main", role = "storage", size = 8},
    {name = "extra", role = "input", size = 4, with_bar = true},
  },
  energy_source = {type = "electric", usage_priority = "secondary-input", buffer_capacity = "10kJ"},
  energy_usage = "10kW",
  activity = "always",
  fluid_boxes = {
    {
      production_type = "input-output",
      volume = 100,
      pipe_connections = {{direction = defines.direction.north, position = {0, 0}}},
    },
  },
  circuit_connector = true,
  circuit_outputs = "script",
  settings = {{name = "level", type = "uint32", default = 3, min = 0, max = 10}},
  events = {status_changed = true, settings_changed = true},
  tick_interval = 60,
}

component.define{
  name = "cl-libtest-machine",
  emulation = {like = "assembling-machine-2"},
  inventories = {
    {name = "input", role = "input", size = 2, proxy_offset = {-1, 0}},
    {name = "output", role = "output", size = 2, proxy_offset = {1, 0}},
  },
  energy_source = {
    type = "burner",
    fuel_categories = {"chemical"},
    effectivity = 1,
    fuel_inventory_size = 1,
    burnt_inventory_size = 1,
  },
  energy_usage = "90kW",
  module_slots = 2,
  allowed_effects = {"speed", "consumption"},
  process = {cycle_time = 1, start = "script", consume_at = "script"},
  events = {cycle_started = true, cycle_finished = true},
}

component.define{
  name = "cl-libtest-burner",
  emulation = {like = "wooden-chest"},
  inventories = {{name = "main", role = "storage", size = 4}},
  energy_source = {type = "burner", fuel_categories = {"chemical"}, effectivity = 1, fuel_inventory_size = 1},
  energy_usage = "20kW",
  activity = "inventory_not_empty",
  activity_inventories = {"main"},
  events = {power_state_changed = true},
}

-- Second-pass parts: a passive rotatable shell with two doors to one inventory,
-- an always-burning shell carrying the v2 generation and heat parts, and a
-- part-only burner on a simple-entity-with-owner core.
component.define{
  name = "cl-libtest-rotor",
  emulation = {like = "assembling-machine-2", core = "assembling-machine"},
  direction_count = 4,
  inventories = {{name = "main", role = "storage", size = 8, proxy_offsets = {{-1, 0}, {1, 0}}}},
}

component.define{
  name = "cl-libtest-rotor-long",
  emulation = {
    like = "assembling-machine-2",
    core = "assembling-machine",
    prototype = {collision_box = {{-2.9, -1.4}, {2.9, 1.4}}, selection_box = {{-3, -1.5}, {3, 1.5}}},
  },
  direction_count = 4,
  inventories = {{name = "main", role = "storage", size = 8}},
}

component.define{
  name = "cl-libtest-hearth",
  emulation = {like = "assembling-machine-2", fuel_proxy_offset = {0, -1}},
  energy_source = {type = "burner", fuel_categories = {"chemical"}, effectivity = 1, fuel_inventory_size = 1},
  energy_usage = "90kW",
  activity = "always",
  process = {
    cycle_time = 1,
    ingredients = {{type = "item", name = "iron-ore", amount = 1}},
    products = {{type = "item", name = "iron-plate", amount = 1}},
  },
  energy_output = {usage_priority = "secondary-output", output_flow_limit = "2MW", buffer_capacity = "20MJ"},
  heat_buffer = {
    max_temperature = 500,
    specific_heat = "1MJ",
    max_transfer = "1GW",
    connections = {{position = {0, 1}, direction = defines.direction.south}},
  },
}

component.define{
  name = "cl-libtest-brazier",
  emulation = {fuel_proxy_offset = true},
  energy_source = {type = "burner", fuel_categories = {"chemical"}, effectivity = 1, fuel_inventory_size = 1},
  energy_usage = "30kW",
  activity = "always",
}
