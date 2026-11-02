-- custom_status from part state, plus the SPEC 1.5 condition evaluator.

local status = {}

-- Statuses the composed type adds; 2.1.24 has no engine string for them.
local EXTRA_LABELS = {
  no_modules = {"cl-status.no-modules"},
  waiting_for_script = {"cl-status.waiting-for-script"},
}

local GREEN = {working = true, normal = true, fully_charged = true}
local RED = {
  no_power = true, no_fuel = true, not_plugged_in_electric_network = true, disabled = true,
  disabled_by_script = true, no_modules = true, no_minable_resources = true, low_temperature = true,
  no_input_fluid = true, marked_for_deconstruction = true, frozen = true,
}

function status.label(name)
  return EXTRA_LABELS[name] or {"entity-status." .. string.gsub(name, "_", "-")}
end

function status.diode(name)
  if GREEN[name] then return defines.entity_status_diode.green end
  if RED[name] then return defines.entity_status_diode.red end
  return defines.entity_status_diode.yellow
end

function status.apply(entity, name, opts)
  if not (entity and entity.valid) then return end
  if name == nil then
    entity.custom_status = nil
    return
  end
  opts = opts or {}
  local diode = opts.diode
  if type(diode) == "string" then diode = defines.entity_status_diode[diode] end
  entity.custom_status = {
    diode = diode or status.diode(name),
    label = opts.label or status.label(name),
  }
end

local function item_total(inv)
  if not inv then return 0 end
  return inv.get_item_count()
end

local evaluators = {
  inventory_not_empty = function(rec, c) local inv = rec:inventory(c.inventory) return inv and not inv.is_empty() end,
  inventory_empty = function(rec, c) local inv = rec:inventory(c.inventory) return inv == nil or inv.is_empty() end,
  inventory_below = function(rec, c) return item_total(rec:inventory(c.inventory)) < c.max_count end,
  module_slot_filled = function(rec, c)
    local inv = rec.entity.get_module_inventory()
    return inv ~= nil and (#inv - inv.count_empty_stacks()) >= (c.count or 1)
  end,
  fluid_at_least = function(rec, c)
    local entity, index = rec:fluid_box(c.fluid_box)
    local fluid = entity.get_fluid(index)
    return fluid ~= nil and fluid.amount >= c.amount
  end,
  powered = function(rec)
    local e = rec:energy_entity()
    if e.burner then return e.burner.currently_burning ~= nil or not e.burner.inventory.is_empty() end
    return e.energy > 0
  end,
  daylight = function(rec, c) return rec.entity.surface.darkness < c.threshold end,
}

function status.first_failing(rec)
  for _, c in ipairs(rec:spec().conditions or {}) do
    if not evaluators[c.type](rec, c) then return c end
  end
  return nil
end

return status
