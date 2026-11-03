-- cl-fluid-chest: a chest with a fluid box. TEST-ENTITIES.md section 1.
-- Two prototypes: the plain one is S0; the watched one adds a fluid threshold
-- event, which SPEC section 2 makes S1.

local component = require("lib.component")

local function fluid_chest(name)
  return {
    name = name,
    direction_count = 4,
    emulation = {like = "wooden-chest", poll_interval = 60},
    inventories = {{name = "main", role = "storage", size = 16, with_bar = true}},
    fluid_boxes = {
      {
        production_type = "input-output",
        volume = 200,
        pipe_connections = {
          {direction = defines.direction.north, position = {0, 0}},
          {direction = defines.direction.south, position = {0, 0}},
        },
      },
    },
  }
end

component.define(fluid_chest("cl-fluid-chest"))

local watch = fluid_chest("cl-fluid-chest-watch")
watch.fluid_thresholds = {{fluid_box = 1, amount = 150, hysteresis = 10}}
watch.events = {fluid_threshold = true}
component.define(watch)
