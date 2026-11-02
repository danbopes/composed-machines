-- cl-hearth: a crafter that burns whether or not it works (S3, burner, activity = "always").
-- TEST-ENTITIES-2.md section 1. A void assembler shell with the stone furnace's
-- look crafts the fixed recipe; the burner sits on a hidden reactor that burns
-- while fuelled, and a per-entity pass gates the shell on the reactor's fuel.
--
-- The spec's `in` / `out` inventories are deliberately not declared: on a
-- process shell the library would turn them into hidden containers, but the
-- recipe consumes and produces through the shell's own slots, so those slots
-- are `in` (filtered to iron ore by the fixed recipe) and `out`.

local component = require("lib.component")

local furnace = data.raw["furnace"]["stone-furnace"]

component.define{
  name = "cl-hearth",
  emulation = {
    like = "stone-furnace",
    -- The shell has no burner, so the fuel door is a proxy onto the reactor's
    -- slot. South-west tile: the bench and suite inserters use the north row.
    fuel_proxy_offset = {-0.5, 0.5},
    prototype = {
      graphics_set = table.deepcopy(furnace.graphics_set),
      corpse = furnace.corpse,
      dying_explosion = furnace.dying_explosion,
      open_sound = furnace.open_sound,
      close_sound = furnace.close_sound,
      working_sound = table.deepcopy(furnace.working_sound),
      impact_category = furnace.impact_category,
      icon_draw_specification = table.deepcopy(furnace.icon_draw_specification),
      resistances = table.deepcopy(furnace.resistances),
    },
  },
  energy_source = {type = "burner", fuel_categories = {"chemical"}, effectivity = 1, fuel_inventory_size = 1},
  energy_usage = "90kW",
  activity = "always",
  process = {
    cycle_time = 3.2,
    ingredients = {{type = "item", name = "iron-ore", amount = 1}},
    products = {{type = "item", name = "iron-plate", amount = 1}},
  },
  events = {power_state_changed = true},
}
