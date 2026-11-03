-- Data stage: component.define(spec) turns a SPEC.md-shaped composed-machine
-- description into the prototypes SPEC.md section 12 says stand in for it today:
-- a visible core of the nearest native type, the hidden parts that fake whatever
-- the core type cannot hold, an item, a recipe, and a mod-data record carrying
-- the whole spec so the runtime never re-derives anything.

local util = require("util")
local hidden = require("lib.hidden")
local validate = require("lib.validate")

local component = {}

component.MOD_DATA_TYPE = "component-lab.spec"
component.MOD_DATA_PREFIX = "component-lab--"
-- emulation.prototype / emulation.item are merged with pairs(), which cannot
-- express "unset this inherited field"; this value can.
component.CLEAR = {}

local FALLBACK_LIKE = {
  ["container"] = "iron-chest",
  ["assembling-machine"] = "assembling-machine-2",
  ["constant-combinator"] = "constant-combinator",
  ["simple-entity-with-owner"] = "simple-entity-with-owner",
}

local function find_entity(name, preferred_type)
  if data.raw[preferred_type] and data.raw[preferred_type][name] then
    return data.raw[preferred_type][name]
  end
  for type_name, by_name in pairs(data.raw) do
    local proto = by_name[name]
    if proto and proto.collision_box ~= nil and type_name ~= "item" then
      return proto
    end
  end
  return nil
end

local function energy_watts(value)
  if value == nil then return 0 end
  return util.parse_energy(value) * 60
end

function component.derive_shape(spec)
  local es = spec.energy_source
  local events = spec.events or {}
  local watch = nil
  if es and (es.type == "burner" or es.type == "fluid" or es.type == "heat") then
    watch = es.type
  elseif energy_watts(spec.energy_usage) > 0 and (spec.activity or (spec.process and "cycle" or "always")) ~= "cycle" then
    watch = "activity"
  elseif events.power_state_changed then
    watch = "power_state_changed"
  elseif spec.fluid_thresholds and #spec.fluid_thresholds > 0 and events.fluid_threshold then
    watch = "fluid_threshold"
  end
  if not watch then
    for _, c in pairs(spec.conditions or {}) do
      if c.type == "powered" or c.type == "daylight" then watch = c.type break end
    end
  end
  if not watch then
    for _, inv in pairs(spec.inventories or {}) do
      if inv.spoil_modifier and inv.spoil_modifier.requires_power then watch = "spoil_modifier" break end
    end
  end

  if spec.process then
    if es == nil or es.type == "void" then return "S2", watch end
    return "S3", watch
  end
  if watch then return "S1", watch end
  return "S0", nil
end

-- A native burner shell stops burning whenever it stops crafting. activity =
-- "always" is the modder asking for the opposite, so the burner moves to a
-- hidden reactor (which burns while fuelled) and the shell runs on void.
local function burner_on_part(spec, ctype)
  local es = spec.energy_source
  if not es or es.type == "void" then return false end
  if ctype ~= "assembling-machine" then return true end
  return es.type == "burner" and spec.activity == "always" and spec.process ~= nil
end

local function core_type(spec)
  local emu = spec.emulation or {}
  if emu.core then return emu.core end
  if spec.process then return "assembling-machine" end
  if spec.inventories and #spec.inventories > 0 then return "container" end
  if spec.circuit_outputs == "script" then return "constant-combinator" end
  return "simple-entity-with-owner"
end

-- What each part becomes on this core type. The list is the contract with the
-- runtime: it materialises exactly these, in this order, and nothing else.
local function plan_parts(spec, ctype)
  local parts = {}
  local native_inventory = nil
  local name = spec.name

  for i, inv in ipairs(spec.inventories or {}) do
    if i == 1 and ctype == "container" then
      native_inventory = inv.name
    else
      parts[#parts + 1] = {kind = "inventory", key = inv.name, prototype = name .. "-inv-" .. inv.name}
      local access = inv.inserter_access or (inv.role == "trash" and "extract") or "both"
      if access ~= "none" then
        -- One proxy reaches one tile; a long machine reachable from several
        -- sides lists several offsets, all doors to the same inventory.
        for j, offset in ipairs(inv.proxy_offsets or {inv.proxy_offset or {0, 0}}) do
          parts[#parts + 1] = {
            kind = "proxy",
            key = j == 1 and inv.name or (inv.name .. "@" .. j),
            inventory = inv.name,
            prototype = name .. "-proxy-" .. inv.name,
            offset = offset,
          }
        end
      end
    end
  end

  local es = spec.energy_source
  if burner_on_part(spec, ctype) then
    if es.type == "electric" then
      parts[#parts + 1] = {kind = "energy", key = "energy", prototype = name .. "-eei", energy = "electric"}
    elseif es.type == "burner" then
      parts[#parts + 1] = {kind = "energy", key = "energy", prototype = name .. "-burner", energy = "burner"}
    elseif es.type ~= "void" then
      error(string.format("component-lab: %s: energy_source type '%s' has no emulation on a %s core",
        name, es.type, ctype))
    end
  end

  local emu = spec.emulation or {}
  if emu.fuel_proxy_offset then
    if not (es and es.type == "burner" and burner_on_part(spec, ctype)) then
      error("component-lab: " .. name .. ": emulation.fuel_proxy_offset needs a burner on a hidden reactor")
    end
    parts[#parts + 1] = {
      kind = "proxy",
      key = "fuel",
      target = "energy:energy",
      prototype = name .. "-proxy-fuel",
      offset = emu.fuel_proxy_offset == true and {0, 0} or emu.fuel_proxy_offset,
    }
  end

  if spec.energy_output then
    parts[#parts + 1] = {kind = "generator", key = "output", prototype = name .. "-generator"}
  end

  if spec.heat_buffer then
    parts[#parts + 1] = {kind = "heat", key = "heat", prototype = name .. "-heat"}
  end

  if ctype ~= "assembling-machine" then
    for i, _ in ipairs(spec.fluid_boxes or {}) do
      parts[#parts + 1] = {kind = "tank", key = "fluid" .. i, index = i, prototype = name .. "-tank-" .. i}
    end
  end

  if spec.circuit_outputs == "script" and ctype ~= "constant-combinator" then
    parts[#parts + 1] = {kind = "combinator", key = "signals", prototype = name .. "-cc"}
  end

  return parts, native_inventory
end

local function base_core(spec, ctype)
  local emu = spec.emulation or {}
  local like_name = emu.like or FALLBACK_LIKE[ctype]
  local like = find_entity(like_name, ctype)
  if like == nil then error("component-lab: " .. spec.name .. ": emulation.like '" .. tostring(like_name) .. "' not found") end

  local core
  if like.type == ctype then
    core = table.deepcopy(like)
  else
    core = {
      type = ctype,
      icon = like.icon,
      icon_size = like.icon_size,
      icons = table.deepcopy(like.icons),
      collision_box = table.deepcopy(like.collision_box),
      selection_box = table.deepcopy(like.selection_box),
      max_health = like.max_health or 200,
    }
  end
  core.name = spec.name
  core.minable = {mining_time = 0.2, result = spec.name}
  core.flags = {"placeable-neutral", "player-creation"}
  core.fast_replaceable_group = nil
  core.next_upgrade = nil
  core.placeable_by = nil
  core.hidden = nil
  return core, like
end

-- The engine lets a crafting machine rotate only if it has a fluid box (or a
-- fluid/heat source); a connectionless one that never switches off is the
-- cheapest way to honour direction_count = 4, on passive and process shells.
local function rotatable(core, spec)
  if (spec.direction_count or 1) > 1 and not core.fluid_boxes then
    core.fluid_boxes = {{production_type = "input", volume = 1, pipe_connections = {}}}
    core.fluid_boxes_off_when_no_fluid_recipe = false
  end
end

local function shell_fields(core, spec, recipe_name)
  local process = spec.process
  core.crafting_categories = {recipe_name}
  core.fixed_recipe = recipe_name
  core.crafting_speed = process.base_speed or 1
  core.energy_source = burner_on_part(spec, "assembling-machine") and {type = "void"}
    or table.deepcopy(spec.energy_source or {type = "void"})
  core.energy_usage = spec.energy_usage or "1W"
  if energy_watts(core.energy_usage) <= 0 then core.energy_usage = "1W" end
  core.fluid_boxes = table.deepcopy(spec.fluid_boxes)
  core.fluid_boxes_off_when_no_fluid_recipe = false
  rotatable(core, spec)
  core.module_slots = spec.module_slots or 0
  core.allowed_effects = spec.allowed_effects or {}
  core.allowed_module_categories = spec.allowed_module_categories
  core.effect_receiver = spec.effect_receiver
  core.gui_title_key = spec.gui_title_key
  core.show_recipe_icon = false
  core.show_recipe_icon_on_map = false
  core.vector_to_place_result = spec.vector_to_place_result
end

-- An assembling machine used only for what the engine gives it for free:
-- rotation, a 4-way box, a relative GUI anchor. It has a category no recipe
-- belongs to, so it never crafts, never draws power and inserters ignore it.
local function passive_shell_fields(core, spec, category)
  core.crafting_categories = {category}
  core.fixed_recipe = nil
  core.crafting_speed = 1
  core.energy_source = {type = "void"}
  core.energy_usage = "1W"
  core.fluid_boxes = nil
  rotatable(core, spec)
  -- An inserter picking up from a tile inside the shell targets the shell, not
  -- the proxy under it; refusing automated removal makes it fall through to
  -- the proxy. The shell holds nothing, so nothing is lost.
  core.flags[#core.flags + 1] = "no-automated-item-removal"
  core.flags[#core.flags + 1] = "no-automated-item-insertion"
  core.module_slots = 0
  core.allowed_effects = {}
  core.allowed_module_categories = nil
  core.effect_receiver = nil
  core.gui_title_key = spec.gui_title_key
  core.show_recipe_icon = false
  core.show_recipe_icon_on_map = false
end

-- Energy and heat products have no recipe equivalent; they stay in the spec
-- (mod-data) for the entity script, and the engine recipe carries the rest.
local function recipe_results(products)
  local out = {}
  for _, p in ipairs(products or {}) do
    if p.type == "item" or p.type == "fluid" or p.type == nil then out[#out + 1] = table.deepcopy(p) end
  end
  return out
end

local function process_recipe(spec, recipe_name)
  local process = spec.process
  local consume_engine = (process.consume_at or "start") ~= "script"
  return {
    {type = "recipe-category", name = recipe_name},
    {
      type = "recipe",
      name = recipe_name,
      categories = {recipe_name},
      energy_required = process.cycle_time,
      ingredients = consume_engine and table.deepcopy(process.ingredients or {}) or {},
      results = recipe_results(process.products),
      hidden = true,
      hide_from_player_crafting = true,
      enabled = true,
      allow_productivity = process.allow_productivity or false,
      raise_on_crafted = true,
      icon = "__base__/graphics/icons/signal/signal_dot.png",
    },
  }
end

local function circuit_from(core, like, spec)
  if spec.circuit_connector == nil or spec.circuit_connector == false then return end
  if spec.circuit_connector ~= true then
    core.circuit_connector = spec.circuit_connector
  elseif like.circuit_connector then
    core.circuit_connector = table.deepcopy(like.circuit_connector)
  else
    local donor = data.raw["container"]["iron-chest"]
    core.circuit_connector = table.deepcopy(donor.circuit_connector)
  end
  core.circuit_wire_max_distance = spec.circuit_wire_max_distance or 9
end

-- SPEC rule 12 / 3.4: an electric source updated every tick_interval ticks
-- must hold a whole interval of draw, so the loader sizes the buffer to that
-- when the modder gives none, and refuses an explicit one below it.
local function interval_electric_source(spec)
  local source = table.deepcopy(spec.energy_source)
  local ti = spec.tick_interval or 1
  local need = util.parse_energy(spec.energy_usage or "0W") * ti
  if ti > 1 and need > 0 then
    if source.buffer_capacity == nil then
      source.buffer_capacity = need .. "J"
    elseif util.parse_energy(source.buffer_capacity) < need - 0.5 then
      error(string.format("component-lab: %s violates SPEC rule 12: buffer_capacity %s is below one tick_interval of draw (%.0fJ)",
        spec.name, source.buffer_capacity, need))
    end
  end
  return source
end

local function part_prototype(spec, part, icon, core, inventory)
  local kind = part.kind
  if kind == "inventory" then return hidden.container(part.prototype, icon, inventory) end
  if kind == "proxy" then return hidden.proxy(part.prototype, icon) end
  if kind == "energy" and part.energy == "electric" then
    return hidden.eei(part.prototype, icon, interval_electric_source(spec), spec.energy_usage or "0W")
  end
  if kind == "energy" and part.energy == "burner" then
    return hidden.reactor(part.prototype, icon, spec.energy_source, spec.energy_usage)
  end
  if kind == "tank" then return hidden.tank(part.prototype, icon, spec.fluid_boxes[part.index]) end
  if kind == "combinator" then return hidden.combinator(part.prototype, icon) end
  if kind == "generator" then return hidden.eei_producer(part.prototype, icon, spec.energy_output) end
  if kind == "heat" then return hidden.heat_interface(part.prototype, icon, spec.heat_buffer, core.collision_box) end
end

-- Several parts may share one prototype (an inventory's extra proxies).
local function hidden_part_prototypes(spec, parts, icon, core)
  local out = {}
  local by_name = {}
  local made = {}
  for _, inv in ipairs(spec.inventories or {}) do by_name[inv.name] = inv end
  for _, part in ipairs(parts) do
    if not made[part.prototype] then
      made[part.prototype] = true
      out[#out + 1] = part_prototype(spec, part, icon, core, by_name[part.key])
    end
  end
  return out
end

-- mod-data may only hold plain data, and the emulation's prototype overrides can
-- carry sprites that the runtime never needs.
local function runtime_spec(spec)
  local copy = table.deepcopy(spec)
  if copy.emulation then
    copy.emulation.prototype = nil
    copy.emulation.item = nil
    copy.emulation.recipe = nil
  end
  if copy.circuit_connector ~= nil then copy.circuit_connector = copy.circuit_connector and true or false end
  for _, box in pairs(copy.fluid_boxes or {}) do
    box.pipe_covers = nil
    box.pipe_picture = nil
  end
  return copy
end

--- Define one composed machine. Returns the core prototype table (already
--- extended) so a caller can inspect it.
function component.define(spec)
  validate.spec(spec)
  local ctype = core_type(spec)
  local shape, watch = component.derive_shape(spec)
  local parts, native_inventory = plan_parts(spec, ctype)
  local emu = spec.emulation or {}

  local core, like = base_core(spec, ctype)
  local icon = core.icon or (core.icons and core.icons[1].icon) or "__base__/graphics/icons/wooden-chest.png"
  local recipe_name = nil
  local protos = {}

  if ctype == "container" then
    local first = spec.inventories[1]
    core.inventory_size = first.size
    if first.filters or first.filters_editable then
      core.inventory_type = "with_filters_and_bar"
    elseif first.with_bar == false then
      core.inventory_type = "normal"
    else
      core.inventory_type = "with_bar"
    end
    core.quality_affects_inventory_size = first.quality_affects_size or false
    core.default_status = spec.default_status
    -- Containers take direction_count since 2.1.7, so a ghost or blueprint
    -- carries the facing and the hidden tanks follow it like any other core.
    circuit_from(core, like, spec)
    local dirs = spec.direction_count or 1
    if dirs > 1 then
      core.direction_count = dirs
      local pic = core.picture
      if pic and not pic.north then core.picture = {north = pic, east = pic, south = pic, west = pic} end
      local cc = core.circuit_connector
      if cc and #cc ~= dirs then
        local one = cc[1] or cc
        core.circuit_connector = {}
        for i = 1, dirs do core.circuit_connector[i] = table.deepcopy(one) end
      end
    end
  elseif ctype == "assembling-machine" and spec.process then
    recipe_name = spec.name .. "-cycle"
    shell_fields(core, spec, recipe_name)
    circuit_from(core, like, spec)
    for _, p in ipairs(process_recipe(spec, recipe_name)) do protos[#protos + 1] = p end
  elseif ctype == "assembling-machine" then
    local category = spec.name .. "-none"
    passive_shell_fields(core, spec, category)
    circuit_from(core, like, spec)
    protos[#protos + 1] = {type = "recipe-category", name = category}
  elseif ctype == "constant-combinator" then
    core.minable = {mining_time = 0.1, result = spec.name}
  end

  for k, v in pairs(emu.prototype or {}) do
    if v == component.CLEAR then core[k] = nil else core[k] = v end
  end
  protos[#protos + 1] = core

  for _, p in ipairs(hidden_part_prototypes(spec, parts, icon, core)) do protos[#protos + 1] = p end

  local item = {
    type = "item",
    name = spec.name,
    icon = core.icon,
    icon_size = core.icon_size,
    icons = core.icons,
    subgroup = "storage",
    order = "z[component-lab]-" .. spec.name,
    place_result = spec.name,
    stack_size = 50,
  }
  for k, v in pairs(emu.item or {}) do
    if v == component.CLEAR then item[k] = nil else item[k] = v end
  end
  protos[#protos + 1] = item

  local recipe = {
    type = "recipe",
    name = spec.name,
    enabled = true,
    energy_required = 1,
    ingredients = {{type = "item", name = "iron-plate", amount = 5}},
    results = {{type = "item", name = spec.name, amount = 1}},
  }
  for k, v in pairs(emu.recipe or {}) do recipe[k] = v end
  protos[#protos + 1] = recipe

  local part_names = {}
  for _, p in ipairs(parts) do part_names[#part_names + 1] = p.prototype end

  protos[#protos + 1] = {
    type = "mod-data",
    name = component.MOD_DATA_PREFIX .. spec.name,
    data_type = component.MOD_DATA_TYPE,
    data = {
      name = spec.name,
      shape = shape,
      watch = watch,
      core_type = ctype,
      native_inventory = native_inventory,
      cycle_recipe = recipe_name,
      parts = parts,
      part_names = part_names,
      spec = runtime_spec(spec),
    },
  }

  data:extend(protos)
  log(string.format('composed-machine "%s": shape %s%s, core %s, %d hidden part(s)',
    spec.name, shape, watch and (" (watcher: " .. watch .. ")") or "", ctype, #parts))
  return core
end

return component
