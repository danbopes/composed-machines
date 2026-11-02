-- cl-dig-site: a dig-site-shaped machine with modules, conditions and a blocked status (S3). TEST-ENTITIES.md section 7.

local component = require("lib.component")

data:extend{
  {type = "module-category", name = "cl-creature"},
  {
    type = "module",
    name = "cl-creature-slow",
    icon = "__base__/graphics/icons/small-biter.png",
    subgroup = "module",
    order = "z[cl-creature]-a",
    category = "cl-creature",
    tier = 1,
    effect = {speed = 0},
    stack_size = 10,
  },
  {
    type = "module",
    name = "cl-creature-fast",
    icon = "__base__/graphics/icons/medium-biter.png",
    subgroup = "module",
    order = "z[cl-creature]-b",
    category = "cl-creature",
    tier = 2,
    effect = {speed = 1},
    stack_size = 10,
  },
  {
    type = "item",
    name = "cl-ration",
    icon = "__base__/graphics/icons/fish.png",
    subgroup = "raw-resource",
    order = "z[cl-ration]",
    stack_size = 100,
  },
}

-- The trash inventory of TEST-ENTITIES.md is left out: nothing in the dig site
-- writes to it, and its hidden container would skew the 1 + 4 part count the
-- benchmark compares against the native single entity.
component.define{
  name = "cl-dig-site",
  emulation = {like = "assembling-machine-2"},
  inventories = {
    {name = "food", role = "input", size = 2, filters = {"raw-fish", "cl-ration"}, automated_insertion_limit = 10,
      inserter_access = "insert", proxy_offset = {-1, 0}},
    {name = "ore", role = "output", size = 4, inserter_access = "extract", proxy_offset = {1, 0}},
  },
  module_slots = 4,
  allowed_module_categories = {"cl-creature"},
  allowed_effects = {"speed"},
  energy_source = {type = "electric", usage_priority = "primary-input", buffer_capacity = "400kJ", drain = "400kW"},
  energy_usage = "1W",
  process = {cycle_time = 20, start = "automatic", consume_at = "script"},
  conditions = {
    {type = "module_slot_filled", count = 1, status = "no_modules", diode = "red"},
    {type = "inventory_not_empty", inventory = "food", status = "no_ingredients", diode = "yellow"},
    {type = "inventory_below", inventory = "ore", max_count = 1000, status = "full_output", diode = "yellow"},
  },
  events = {cycle_started = true, cycle_finished = true},
  gui_title_key = "cl-dig-site.title",
}
