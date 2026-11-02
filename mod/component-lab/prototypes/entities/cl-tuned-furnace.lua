-- cl-tuned-furnace: speed as a circuit-bound setting (S3 + circuit input). TEST-ENTITIES-2.md section 8.
-- The spec's `in` / `out` inventories are the shell's own ingredient and result
-- slots: with engine-side ingredients a process shell holds them natively, so
-- hidden containers would only add a detour for inserters.

local component = require("lib.component")

local furnace = data.raw["furnace"]["electric-furnace"]

component.define{
  name = "cl-tuned-furnace",
  emulation = {
    like = "electric-furnace",
    prototype = {
      graphics_set = table.deepcopy(furnace.graphics_set),
      working_sound = table.deepcopy(furnace.working_sound),
      open_sound = table.deepcopy(furnace.open_sound),
      close_sound = table.deepcopy(furnace.close_sound),
      corpse = furnace.corpse,
      dying_explosion = furnace.dying_explosion,
    },
  },
  energy_source = {type = "electric", usage_priority = "secondary-input"},
  energy_usage = "200kW",
  process = {
    cycle_time = 3.2,
    start = "automatic",
    ingredients = {{type = "item", name = "iron-ore", amount = 1}},
    products = {{type = "item", name = "iron-plate", amount = 1}},
  },
  -- local_effect only reaches a receiver whose allowed_effects include it; the
  -- same list lets a beacon reach the shell for the beacon-tuned-furnace column.
  allowed_effects = {"speed"},
  effect_receiver = {base_effect = {speed = 0}, speed_limits = {low = -0.8, high = 3}},
  settings = {{name = "rate", type = "uint32", default = 10, min = 1, max = 40}},
  circuit_connector = true,
  circuit_inputs = {enable_disable = true, settings = {{setting = "rate", signal = "signal-R"}}},
}
