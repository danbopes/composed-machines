-- cl-slag-generator: power from a fluid with a solid byproduct (S3 + v2 generation).
-- TEST-ENTITIES-2.md section 5, V2-PARTS 1.1.

local component = require("lib.component")

local NAME = "cl-slag-generator"
local donor = data.raw["assembling-machine"]["assembling-machine-2"].fluid_boxes[1]

-- The spec's `inventories = {{name = "slag", role = "output", size = 2}}` is left
-- out on purpose: on a process shell the library would put it in a hidden
-- container behind a proxy, while the engine delivers the stone product into the
-- shell's own result slot. The result slot is therefore the slag inventory (one
-- slot per product, not two).
component.define{
  name = NAME,
  emulation = {like = "assembling-machine-2"},
  energy_source = {type = "burner", fuel_categories = {"chemical"}, effectivity = 1, fuel_inventory_size = 1},
  energy_usage = "1MW",
  energy_output = {usage_priority = "secondary-output", output_flow_limit = "2MW", buffer_capacity = "20MJ"},
  fluid_boxes = {
    {
      production_type = "input",
      volume = 200,
      filter = "water",
      pipe_picture = table.deepcopy(donor.pipe_picture),
      pipe_covers = table.deepcopy(donor.pipe_covers),
      pipe_connections = {{flow_direction = "input", direction = defines.direction.north, position = {0, -1}}},
    },
  },
  process = {
    cycle_time = 4,
    ingredients = {{type = "fluid", name = "water", amount = 40}},
    products = {{type = "energy", amount = "6MJ"}, {type = "item", name = "stone", amount = 1}},
  },
}
