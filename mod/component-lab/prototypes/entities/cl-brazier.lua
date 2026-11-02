-- cl-brazier: a burner light that announces when fuel runs out (S1). TEST-ENTITIES-2.md section 2.
-- No process and no inventories, so the core is a simple-entity-with-owner with
-- the small lamp's look, and the burner is a hidden reactor that burns whenever
-- it holds fuel (activity = "always"). The fuel slot is reached through a proxy
-- on the core's tile so inserters can refuel it.

local component = require("lib.component")

local lamp = data.raw.lamp["small-lamp"]

component.define{
  name = "cl-brazier",
  emulation = {
    like = "small-lamp",
    fuel_proxy_offset = true,
    prototype = {picture = table.deepcopy(lamp.picture_off), render_layer = "object"},
  },
  -- The proposed light_flicker is left off the burner: the hidden reactor would
  -- carry it, and the light is the script's rendering instead (graphics_set below).
  energy_source = {
    type = "burner",
    fuel_categories = {"chemical"},
    effectivity = 1,
    fuel_inventory_size = 1,
    burnt_inventory_size = 0,
  },
  energy_usage = "30kW",
  activity = "always",
  events = {power_state_changed = true},
  graphics_set = {
    working_visualisations = {{
      light = {intensity = 0.8, size = 12, color = {1, 0.6, 0.2}},
      draw_in_states = {"working"},
    }},
  },
}

-- The door is a proxy, and a proxy is two-way: an inserter picking up from the
-- brazier tile would take the fuel out of the reactor, which a native burner
-- never gives up. The core is a simple entity with nothing to pick from, so the
-- door is the only pickup target on that tile and must refuse removal.
local door = data.raw["proxy-container"]["cl-brazier-proxy-fuel"]
door.flags[#door.flags + 1] = "no-automated-item-removal"

-- Bench only (native-cl-brazier): the same reactor as the hidden part, but with
-- a collision box so an inserter can find and refuel it the way the composed
-- cell's inserter refuels the fuel door. The hidden part has none on purpose.
local native = table.deepcopy(data.raw.reactor["cl-brazier-burner"])
native.name = "cl-brazier-native-burner"
native.collision_box = {{-0.35, -0.35}, {0.35, 0.35}}
data:extend{native}
