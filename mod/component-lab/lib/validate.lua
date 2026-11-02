-- The SPEC.md section 1.9 rules that matter for the emulation, raised as data-stage
-- errors so `fh test` fails at map creation with the rule that was broken.

local util = require("util")

local validate = {}

local RESERVED = {fuel = true, burnt_result = true, modules = true}
local ROLES = {input = true, output = true, storage = true, trash = true}
local ACTIVITIES = {cycle = true, inventory_not_empty = true, always = true, script = true}
local CONDITION_TYPES = {
  inventory_not_empty = true, inventory_empty = true, inventory_below = true,
  module_slot_filled = true, fluid_at_least = true, powered = true, daylight = true,
}
local EXTRA_STATUSES = {no_modules = true, waiting_for_script = true}
local EVENT_FLAGS = {
  cycle_started = true, cycle_finished = true, status_changed = true, inventory_changed = true,
  power_state_changed = true, fluid_threshold = true, settings_changed = true,
}

local function fail(spec, rule, msg)
  error(string.format("component-lab: composed machine '%s' violates SPEC 1.9 rule %s: %s",
    tostring(spec.name), rule, msg), 3)
end

local function watts(v)
  if v == nil then return 0 end
  return util.parse_energy(v)
end

function validate.spec(spec)
  if type(spec) ~= "table" or type(spec.name) ~= "string" then
    error("component-lab: component.define needs a table with a string 'name'", 2)
  end
  local inventories = spec.inventories or {}
  local es = spec.energy_source
  local process = spec.process
  local events = spec.events or {}

  if #inventories == 0 and not es and not (spec.fluid_boxes and #spec.fluid_boxes > 0) and not process
      and (spec.module_slots or 0) == 0 and not spec.circuit_connector and spec.circuit_outputs ~= "script" then
    fail(spec, "1", "no parts; use simple-entity-with-owner")
  end

  if spec.energy_usage and not es then fail(spec, "2", "energy_usage requires energy_source") end
  if es then
    local kind = es.type
    if (kind == "burner" or kind == "fluid" or kind == "heat") and watts(spec.energy_usage) <= 0 then
      fail(spec, "2", kind .. " energy_source requires energy_usage > 0")
    end
    if kind == "void" and spec.energy_usage then fail(spec, "2", "void energy_source forbids energy_usage") end
    if kind == "void" and not process then fail(spec, "2", "void energy_source requires process") end
  end

  if not process and es and es.type ~= "electric" and es.type ~= "void" and not spec.activity then
    fail(spec, "3", "a " .. es.type .. " source without process needs an explicit activity")
  end
  if not process and watts(spec.energy_usage) > 0 and not spec.activity then
    fail(spec, "3", "energy_usage > 0 without process needs an explicit activity")
  end

  if spec.activity then
    if not ACTIVITIES[spec.activity] then fail(spec, "4", "unknown activity '" .. spec.activity .. "'") end
    if spec.activity == "cycle" and not process then fail(spec, "4", "activity 'cycle' requires process") end
    if spec.activity == "inventory_not_empty" and not spec.activity_inventories then
      fail(spec, "4", "activity 'inventory_not_empty' requires activity_inventories")
    end
  end

  local names = {}
  local trash = 0
  if #inventories > 8 then fail(spec, "13", "at most 8 inventories") end
  for _, inv in ipairs(inventories) do
    if type(inv.name) ~= "string" or not inv.name:match("^[a-z0-9_%-]+$") or #inv.name > 32 then
      fail(spec, "13", "inventory name '" .. tostring(inv.name) .. "' must be 1-32 chars [a-z0-9_-]")
    end
    if RESERVED[inv.name] then fail(spec, "13", "inventory name '" .. inv.name .. "' is reserved") end
    if names[inv.name] then fail(spec, "13", "duplicate inventory '" .. inv.name .. "'") end
    names[inv.name] = inv
    if not ROLES[inv.role] then fail(spec, "13", "inventory '" .. inv.name .. "' has no valid role") end
    if type(inv.size) ~= "number" or inv.size < 1 or inv.size > 1024 then
      fail(spec, "13", "inventory '" .. inv.name .. "' size must be 1-1024")
    end
    if inv.role == "trash" then
      trash = trash + 1
      if inv.spoil_modifier then fail(spec, "11", "no spoil_modifier on trash") end
      if inv.inserter_access == "insert" or inv.inserter_access == "both" then
        fail(spec, "11", "trash inserter_access must be none or extract")
      end
    end
    if inv.spoil_modifier and inv.spoil_modifier.requires_power and not es then
      fail(spec, "11", "spoil_modifier.requires_power requires energy_source")
    end
  end
  if trash > 1 then fail(spec, "13", "at most one trash inventory") end
  for _, n in ipairs(spec.activity_inventories or {}) do
    if not names[n] then fail(spec, "4", "activity_inventories names undeclared '" .. n .. "'") end
  end

  if process then
    if type(process.cycle_time) ~= "number" or process.cycle_time < 1 / 60 then
      fail(spec, "5", "process.cycle_time must be >= 1/60")
    end
    if process.consume_at == "script" then
      if process.ingredients and #process.ingredients > 0 then
        fail(spec, "5", "consume_at 'script' requires ingredients = {}")
      end
      if not events.cycle_started then fail(spec, "5", "consume_at 'script' requires events.cycle_started") end
    end
    if (process.start or "automatic") == "automatic" and not (process.ingredients and #process.ingredients > 0)
        and not (spec.conditions and #spec.conditions > 0) and not es and not events.cycle_finished then
      fail(spec, "6", "free-running cycle with nothing to wait for")
    end
    if process.allow_productivity and not (process.products and #process.products > 0) then
      fail(spec, "7", "allow_productivity requires products")
    end
  end

  if spec.conditions and #spec.conditions > 4 then fail(spec, "13", "at most 4 conditions") end
  for i, c in ipairs(spec.conditions or {}) do
    if not CONDITION_TYPES[c.type] then fail(spec, "8", "condition " .. i .. " has unknown type") end
    if c.inventory and not names[c.inventory] then
      fail(spec, "8", "condition " .. i .. " names undeclared inventory '" .. c.inventory .. "'")
    end
    if c.type == "fluid_at_least" and not (spec.fluid_boxes and spec.fluid_boxes[c.fluid_box]) then
      fail(spec, "8", "condition " .. i .. " fluid_box out of range")
    end
    if c.type == "module_slot_filled" and (spec.module_slots or 0) == 0 then
      fail(spec, "8", "module_slot_filled requires module_slots > 0")
    end
    if not c.status or not (defines.entity_status[c.status] or EXTRA_STATUSES[c.status]) then
      fail(spec, "8", "condition " .. i .. " status '" .. tostring(c.status) .. "' is not an entity status")
    end
  end

  if (spec.circuit_outputs and spec.circuit_outputs ~= "none") and not spec.circuit_connector
      and spec.circuit_outputs ~= "script" then
    fail(spec, "9", "circuit_outputs requires circuit_connector")
  end

  for flag, value in pairs(events) do
    if not EVENT_FLAGS[flag] then fail(spec, "10", "unknown event flag '" .. flag .. "'") end
    if value then
      if (flag == "cycle_started" or flag == "cycle_finished") and not process then
        fail(spec, "10", flag .. " requires process")
      end
      if flag == "fluid_threshold" and not (spec.fluid_thresholds and #spec.fluid_thresholds > 0) then
        fail(spec, "10", "fluid_threshold requires fluid_thresholds")
      end
      if flag == "power_state_changed" and not es then fail(spec, "10", "power_state_changed requires energy_source") end
      if flag == "settings_changed" and not (spec.settings and #spec.settings > 0) then
        fail(spec, "10", "settings_changed requires settings")
      end
      if flag == "inventory_changed" then
        for _, n in ipairs(value) do
          if not names[n] then fail(spec, "10", "inventory_changed names undeclared '" .. n .. "'") end
        end
      end
    end
  end

  local setting_names = {}
  if spec.settings and #spec.settings > 4 then fail(spec, "13", "at most 4 settings") end
  for _, s in ipairs(spec.settings or {}) do
    if setting_names[s.name] then fail(spec, "13", "duplicate setting '" .. tostring(s.name) .. "'") end
    setting_names[s.name] = true
    if s.type ~= "uint32" and s.type ~= "int32" and s.type ~= "bool" then
      fail(spec, "13", "setting '" .. tostring(s.name) .. "' type must be uint32, int32 or bool")
    end
  end

  local ti = spec.tick_interval or 1
  if ti < 1 or ti > 600 then fail(spec, "12", "tick_interval must be 1-600") end
  if ti > 1 and es and (es.type == "fluid" or es.type == "heat") then
    fail(spec, "12", "tick_interval > 1 with a fluid or heat source")
  end
end

return validate
