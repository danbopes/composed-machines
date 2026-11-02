-- cl-timed-converter: a machine shell whose logic is in Lua (S3, script start). TEST-ENTITIES.md section 5.

local component = require("lib.component")

-- The input filter list names it, and the test needs a stack that carries data
-- the handler must read from the real item rather than from its own bookkeeping.
data:extend{
  {
    type = "item-with-tags",
    name = "cl-tagged-sample",
    icon = "__base__/graphics/icons/iron-chest.png",
    icon_size = 64,
    subgroup = "storage",
    order = "z[component-lab]-tagged-sample",
    stack_size = 1,
    hidden = true,
  },
}

component.define{
  name = "cl-timed-converter",
  emulation = {like = "assembling-machine-2"},
  inventories = {
    {
      name = "input",
      role = "input",
      size = 4,
      filters = {"iron-ore", "copper-ore", "stone", "cl-tagged-sample"},
      automated_insertion_limit = 20,
      proxy_offset = {-1, 0},
    },
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
  process = {cycle_time = 5, start = "script", consume_at = "script"},
  events = {inventory_changed = {"input"}, cycle_started = true, cycle_finished = true},
}
