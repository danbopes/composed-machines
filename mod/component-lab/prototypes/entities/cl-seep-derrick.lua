-- cl-seep-derrick: a fluid process with engine-side ingredients and products (S3). TEST-ENTITIES.md section 6.
-- Water stands in for pY drilling fluid so the suite needs no pY items.

local component = require("lib.component")

local donor = data.raw["assembling-machine"]["assembling-machine-2"].fluid_boxes[1]

local function box(production_type, filter, direction, y)
  return {
    production_type = production_type,
    volume = 1000,
    filter = filter,
    pipe_picture = table.deepcopy(donor.pipe_picture),
    pipe_covers = table.deepcopy(donor.pipe_covers),
    pipe_connections = {{flow_direction = production_type, direction = direction, position = {0, y}}},
  }
end

component.define{
  name = "cl-seep-derrick",
  emulation = {like = "assembling-machine-2"},
  fluid_boxes = {
    box("input", "water", defines.direction.north, -1),
    box("output", "crude-oil", defines.direction.south, 1),
  },
  energy_source = {type = "electric", usage_priority = "secondary-input", drain = "20kW"},
  energy_usage = "300kW",
  process = {
    cycle_time = 2,
    start = "automatic",
    ingredients = {{type = "fluid", name = "water", amount = 10}},
    products = {{type = "fluid", name = "crude-oil", amount = 100}},
    output_full_blocks = true,
  },
  conditions = {
    {type = "fluid_at_least", fluid_box = 1, amount = 10, status = "low_input_fluid", diode = "yellow"},
  },
  settings = {{name = "depletion", type = "uint32", default = 0, show_in_gui = false}},
  events = {cycle_finished = true},
}
