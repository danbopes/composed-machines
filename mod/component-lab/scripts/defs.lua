-- Everything the runtime knows about composed machines comes from the mod-data
-- records component.define wrote. Read once at script load; the ids below are
-- generated in a fixed order so they are identical on every peer and every load.

local MOD_DATA_TYPE = "component-lab.spec"

local defs = {
  by_name = {},
  by_recipe = {},
  core_names = {},
  part_names = {},
  part_set = {},
  events = {},
}

local EVENT_ORDER = {
  "cycle_started", "cycle_finished", "status_changed", "inventory_changed",
  "power_state_changed", "fluid_threshold", "settings_changed",
}

local names = {}
for _, record in pairs(prototypes.mod_data) do
  if record.data_type == MOD_DATA_TYPE then names[#names + 1] = record.data.name end
end
table.sort(names)

for _, name in ipairs(names) do
  local def = prototypes.mod_data["component-lab--" .. name].data
  defs.by_name[name] = def
  defs.core_names[#defs.core_names + 1] = name
  if def.cycle_recipe then defs.by_recipe[def.cycle_recipe] = name end
  for _, part in ipairs(def.parts) do
    if not defs.part_set[part.prototype] then
      defs.part_set[part.prototype] = true
      defs.part_names[#defs.part_names + 1] = part.prototype
    end
  end
  local declared = def.spec.events or {}
  local ids = {}
  for _, flag in ipairs(EVENT_ORDER) do
    if declared[flag] then ids[flag] = script.generate_event_name() end
  end
  defs.events[name] = ids
end

defs.EVENT_ORDER = EVENT_ORDER

return defs
