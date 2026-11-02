-- cl-mass-driver: charges then fires a stack along its facing (S3 + trigger). TEST-ENTITIES-2.md section 7.
--
-- The SPEC form is energy_usage = "0W" with the cost carried by a 40 MJ buffer
-- and a 10 s cycle at the buffer's 4 MW input. A crafting machine has no "draw
-- the buffer's rate" mode, so the shell is given energy_usage = 4 MW instead:
-- 4 MW x 10 s is the same 40 MJ per shot, taken during the cycle.
--
-- The "shell" inventory is not declared as a composed inventory: the library
-- would put it in a hidden container behind a proxy, out of the fixed recipe's
-- reach. The assembler's own ingredient slot is that inventory; the fixed
-- recipe gives it the iron-plate filter, and the engine's automated insertion
-- limit stands in for automated_insertion_limit = 1.

local component = require("lib.component")

local bullet = data.raw.projectile["cannon-projectile"]

data:extend{
  -- The proposed trigger fires cannon-projectile. A real shell would wreck
  -- the test rows and every neighbouring bench cell, so the emulation fires a
  -- projectile with the same flight and no actions: the cost measured is the
  -- create_entity and the flight, which is what the trigger would cost too.
  {
    type = "projectile",
    name = "cl-mass-driver-slug",
    flags = {"not-on-map"},
    hidden = true,
    acceleration = 0,
    hit_collision_mask = {layers = {}},
    animation = table.deepcopy(bullet.animation),
  },
  -- The poll-mass-driver bench cell's buffer: Renai's item cannon carries its
  -- own EEI prototype because the base interface takes nothing from the network
  -- (input_flow_limit 0).
  {
    type = "electric-energy-interface",
    name = "cl-mass-driver-poll-eei",
    icon = "__base__/graphics/icons/accumulator.png",
    icon_size = 64,
    flags = {"not-on-map", "placeable-off-grid", "not-blueprintable", "not-deconstructable"},
    hidden = true,
    collision_box = {{-0.4, -0.4}, {0.4, 0.4}},
    collision_mask = {layers = {}},
    selectable_in_game = false,
    energy_source = {
      type = "electric",
      usage_priority = "secondary-input",
      buffer_capacity = "40MJ",
      input_flow_limit = "4MW",
      output_flow_limit = "0W",
      render_no_network_icon = false,
      render_no_power_icon = false,
    },
    energy_production = "0W",
    energy_usage = "0W",
  },
}

component.define{
  name = "cl-mass-driver",
  emulation = {
    like = "assembling-machine-2",
  },
  direction_count = 4,
  energy_source = {
    type = "electric",
    usage_priority = "secondary-input",
    buffer_capacity = "40MJ",
    -- The spec's 4 MW equals the shell's draw, so the buffer could never fill
    -- while cycling: the shell crafts at full speed but reports low_power for
    -- ever (measured on 2.1.24: low_power until the buffer is full, energy
    -- pinned at one tick of draw). Draw plus the spec's 4 MW charging rate
    -- fills the buffer in ~10.7 s, close to the spec's "charge 40 MJ at 4 MW";
    -- energy per shot is still 4 MW x 10 s.
    input_flow_limit = "8MW",
    -- The engine's default drain (energy_usage / 30) would add 133 kW idle and
    -- break "40 MJ per shot".
    drain = "0W",
  },
  energy_usage = "4MW",
  process = {
    cycle_time = 10,
    ingredients = {{type = "item", name = "iron-plate", amount = 1}},
    consume_at = "finish",
  },
  settings = {{name = "range", type = "uint32", default = 20, min = 5, max = 60}},
  events = {cycle_finished = true},
}
