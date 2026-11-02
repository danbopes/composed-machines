-- cl-creep-collector: energy per unit of script-chosen work (S3, electric,
-- start = "script"). TEST-ENTITIES-2.md section 3.

local component = require("lib.component")

component.define{
  name = "cl-creep-collector",
  emulation = {like = "assembling-machine-2"},
  energy_source = {type = "electric", usage_priority = "secondary-input", drain = "5kW"},
  energy_usage = "400kW",
  inventories = {
    -- Outside the shell's box: an inserter reaching into a process shell takes
    -- from the shell, not from a proxy on that tile (README, second pass facts).
    {name = "spoils", role = "output", size = 4, proxy_offset = {2, 0}},
  },
  process = {cycle_time = 2, start = "script", consume_at = "script"},
  -- TEST-ENTITIES-2.md lists only cycle_finished, but SPEC 1.9 rule 5 requires
  -- cycle_started whenever consume_at = "script".
  events = {cycle_started = true, cycle_finished = true},
  conditions = {
    {type = "inventory_below", inventory = "spoils", max_count = 200, status = "full_output", diode = "yellow"},
  },
}

-- The "today" column (TEST-ENTITIES-2.md: poll-creep-collector): Rampant's
-- pattern is a mod-defined consumer EEI whose buffer holds one unit of work and
-- charges at the machine's rate, with Lua deducting the unit when it acts. The
-- base EEI charges without a flow limit, so it cannot stand in for this.
local eei = table.deepcopy(data.raw["electric-energy-interface"]["electric-energy-interface"])
eei.name = "cl-creep-collector-poll-eei"
eei.minable = nil
eei.gui_mode = "none"
eei.energy_source = {
  type = "electric",
  usage_priority = "secondary-input",
  buffer_capacity = "800kJ",
  input_flow_limit = "400kW",
  output_flow_limit = "0W",
  drain = "5kW",
}
eei.energy_production = "0W"
eei.energy_usage = "0W"
data:extend{eei}
