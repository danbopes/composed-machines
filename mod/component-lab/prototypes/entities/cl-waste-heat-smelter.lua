-- cl-waste-heat-smelter: a crafter that heats a heat-pipe network (S3 + heat output). TEST-ENTITIES-2.md section 6.

local component = require("lib.component")

local furnace = data.raw["furnace"]["electric-furnace"]

-- The spec's product list is {copper-plate, {type = "heat", amount = "400kJ"}}.
-- A recipe cannot carry a heat result, so the shell's recipe gets the item
-- product only and the heat product rides in emulation.heat_product, where the
-- handler reads it on every crafted event.
component.define{
  name = "cl-waste-heat-smelter",
  emulation = {
    like = "electric-furnace",
    heat_product = "400kJ",
    prototype = {
      graphics_set = table.deepcopy(furnace.graphics_set),
      working_sound = table.deepcopy(furnace.working_sound),
    },
  },
  direction_count = 4,
  energy_source = {type = "electric", usage_priority = "secondary-input"},
  energy_usage = "180kW",
  heat_buffer = {
    max_temperature = 500,
    specific_heat = "1MJ",
    max_transfer = "1GW",
    minimum_glow_temperature = 200,
    connections = {{position = {0, 1}, direction = defines.direction.south}},
  },
  -- The spec's "in" / "out" inventories are the shell's own recipe slots: the
  -- recipe is fixed to one ore and one plate, so the engine already enforces the
  -- filter and size and inserters reach them natively, with no proxy.
  process = {
    cycle_time = 3.2,
    ingredients = {{type = "item", name = "copper-ore", amount = 1}},
    products = {{type = "item", name = "copper-plate", amount = 1}},
  },
}
