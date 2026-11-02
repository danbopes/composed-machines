-- Creating, cloning and removing the hidden parts. Every build path funnels into
-- materialise, every removal path into teardown, so an entity script never has
-- to know which event brought the core into or out of the world.

local util = require("util")
local defs = require("scripts.defs")
local Record = require("scripts.record")

local lifecycle = {}

local handlers = {}
-- True only while this module clones parts itself; on_entity_cloned for those
-- parts must not be mistaken for orphans copied by an area clone.
local cloning_parts = false

local TAG = "component_lab"

function lifecycle.set_handlers(h) handlers = h end
function lifecycle.handler(name) return handlers[name] or {} end

local function state() return storage.cl end

local function rotate(offset, direction)
  local x, y = offset[1] or offset.x or 0, offset[2] or offset.y or 0
  if direction == defines.direction.east then return -y, x end
  if direction == defines.direction.south then return -x, -y end
  if direction == defines.direction.west then return y, -x end
  return x, y
end

local function part_position(core, part)
  local dx, dy = rotate(part.offset or {0, 0}, core.direction)
  return {core.position.x + dx, core.position.y + dy}
end

local function adopt(rec, part, entity)
  rec.parts[part.kind .. ":" .. part.key] = entity
  state().owner[entity.unit_number] = rec.unit_number
end

local function connect_wires(core, cc)
  for _, id in ipairs({defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green}) do
    local a = core.get_wire_connector(id, true)
    local b = cc.get_wire_connector(id, true)
    if a and b then a.connect_to(b, false, defines.wire_origin.script) end
  end
end

local function link(rec, def)
  for _, part in ipairs(def.parts) do
    local entity = rec.parts[part.kind .. ":" .. part.key]
    if part.kind == "proxy" and part.target then
      entity.proxy_target_entity = rec.parts[part.target]
      entity.proxy_target_inventory = defines.inventory.fuel
    elseif part.kind == "proxy" then
      entity.proxy_target_entity = rec.parts["inventory:" .. (part.inventory or part.key)]
      entity.proxy_target_inventory = defines.inventory.chest
    elseif part.kind == "combinator" then
      connect_wires(rec.entity, entity)
    end
  end
end

-- A static multi-item filter list ("any of these in any slot") has no
-- hidden-container equivalent, so slot i is pinned to filters[i]: each listed
-- item can use one slot. Clones copy the slot filters with the part.
local function pin_filters(rec, def)
  for _, inv_spec in ipairs(def.spec.inventories or {}) do
    local filters = inv_spec.filters
    local inv = filters and def.native_inventory ~= inv_spec.name and rec:inventory(inv_spec.name)
    if inv then
      for i, item in ipairs(filters) do
        if i > #inv then break end
        inv.set_filter(i, {name = item})
      end
    end
  end
end

-- A native machine has no separately killable pieces. Indestructible stops
-- damage; die(), destroy() and editor deletion still remove a part, so each one
-- is also registered and lifecycle.heal rebuilds it.
local function harden(entity)
  if not entity then return nil end
  entity.destructible = false
  script.register_on_object_destroyed(entity)
  return entity
end

local function create_part(core, part)
  return harden(core.surface.create_entity{
    name = part.prototype,
    position = part_position(core, part),
    direction = part.kind == "tank" and core.direction or nil,
    force = core.force,
    create_build_effect_smoke = false,
    raise_built = false,
  })
end

function lifecycle.blueprint_tags(rec)
  local bars = {}
  for _, inv_spec in ipairs(rec:spec().inventories or {}) do
    if rec:def().native_inventory ~= inv_spec.name then
      local inv = rec:inventory(inv_spec.name)
      if inv and inv.supports_bar() and inv.get_bar() <= #inv then bars[inv_spec.name] = inv.get_bar() end
    end
  end
  local tags = {settings = util.table.deepcopy(rec.settings), bars = bars}
  local h = lifecycle.handler(rec.name)
  if h.blueprint_tags then tags.extra = h.blueprint_tags(rec) end
  return tags
end

function lifecycle.apply_tags(rec, tags)
  if type(tags) ~= "table" then return end
  for name, value in pairs(tags.settings or {}) do
    if rec.settings[name] ~= nil then rec.settings[name] = value end
  end
  for name, bar in pairs(tags.bars or {}) do
    local inv = rec:inventory(name)
    if inv and inv.supports_bar() then inv.set_bar(bar) end
  end
  local h = lifecycle.handler(rec.name)
  if h.apply_tags and tags.extra ~= nil then h.apply_tags(rec, tags.extra) end
end

local function finish(rec, def, context)
  local process = def.spec.process
  if process and process.start == "script" then
    rec.entity.disabled_by_script = true
    rec:set_status("waiting_for_script")
  end
  local h = lifecycle.handler(rec.name)
  if h.on_created then h.on_created(rec, context) end
end

--- Build every hidden part for a freshly built core. Idempotent: a second build
--- event for the same core (e.g. a mod raising script_raised_built after
--- on_built_entity) returns the existing record.
function lifecycle.materialise(core, tags, cause)
  local st = state()
  local existing = st.records[core.unit_number]
  if existing then return existing end
  local def = defs.by_name[core.name]
  local rec = Record.new(core)
  st.records[core.unit_number] = rec
  for _, part in ipairs(def.parts) do
    adopt(rec, part, create_part(core, part))
  end
  link(rec, def)
  pin_filters(rec, def)
  script.register_on_object_destroyed(core)
  local component_tags = tags and tags[TAG]
  if component_tags then lifecycle.apply_tags(rec, component_tags) end
  finish(rec, def, {cause = cause, tags = component_tags})
  return rec
end

--- A core was cloned. Parts are cloned from the source's parts so contents, fuel
--- and fluid travel with them; an unregistered source gets fresh parts.
function lifecycle.cloned(source, destination)
  local st = state()
  local src = source.valid and st.records[source.unit_number]
  if not src then return lifecycle.materialise(destination, nil, "clone") end
  if st.records[destination.unit_number] then return st.records[destination.unit_number] end
  local def = defs.by_name[destination.name]
  local rec = Record.new(destination)
  st.records[destination.unit_number] = rec
  rec.settings = util.table.deepcopy(src.settings)
  rec.data = util.table.deepcopy(src.data)
  for _, part in ipairs(def.parts) do
    local from = src.parts[part.kind .. ":" .. part.key]
    local entity
    if from and from.valid then
      cloning_parts = true
      entity = from.clone{
        position = part_position(destination, part),
        surface = destination.surface,
        force = destination.force,
        create_build_effect_smoke = false,
      }
      cloning_parts = false
      harden(entity)
    end
    adopt(rec, part, entity or create_part(destination, part))
  end
  link(rec, def)
  script.register_on_object_destroyed(destination)
  if src.status then rec:set_status(src.status, {force = true}) end
  local h = lifecycle.handler(rec.name)
  if h.on_created then h.on_created(rec, {cause = "clone", source = src}) end
  return rec
end

--- Rebuild every hidden part that is gone, so no entity script is handed a
--- dead one. A rebuilt part starts empty: what the old one held went with it.
--- Returns false when the core is gone or a part cannot be placed.
function lifecycle.heal(rec)
  if not rec.entity.valid then return false end
  local def = defs.by_name[rec.name]
  local rebuilt = false
  for _, part in ipairs(def.parts) do
    local entity = rec.parts[part.kind .. ":" .. part.key]
    if not (entity and entity.valid) then
      entity = create_part(rec.entity, part)
      if not entity then return false end
      adopt(rec, part, entity)
      rebuilt = true
    end
  end
  if rebuilt then
    link(rec, def)
    pin_filters(rec, def)
  end
  return true
end

--- The core turned or flipped: move every part to its offset for the new
--- facing (and turn the tanks with it), then run the script's on_rotated.
--- Parts that do not rotate natively (a heat interface's connections) stay
--- as they are; that is a limit of the emulation, not of the composed type.
function lifecycle.rotated(rec, previous_direction)
  if not lifecycle.heal(rec) then return end
  local core = rec.entity
  for _, part in ipairs(defs.by_name[rec.name].parts) do
    local entity = rec.parts[part.kind .. ":" .. part.key]
    entity.teleport(part_position(core, part))
    if part.kind == "tank" then entity.direction = core.direction end
  end
  local h = lifecycle.handler(rec.name)
  if h.on_rotated then h.on_rotated(rec, previous_direction) end
end

--- A registered hidden part was destroyed (on_object_destroyed).
function lifecycle.part_destroyed(unit_number)
  local st = state()
  local owner = st.owner[unit_number]
  if not owner then return end
  st.owner[unit_number] = nil
  local rec = st.records[owner]
  if rec then lifecycle.heal(rec) end
end

--- Copy-paste between two cores of the same prototype. The engine copies only
--- the core's own settings; SPEC settings and the hidden combinator's sections
--- are the emulation's, so they are carried here, then the entity script's
--- on_pasted(to, from) runs. Returns true when both ends are composed machines.
function lifecycle.pasted(source, destination)
  local records = state().records
  local from = records[source.unit_number or 0]
  local to = records[destination.unit_number or 0]
  if not (from and to and from.name == to.name) then return false end
  to.settings = util.table.deepcopy(from.settings)
  local a, b = from.parts["combinator:signals"], to.parts["combinator:signals"]
  if a and b and a.valid and b.valid then b.copy_settings(a) end
  local h = lifecycle.handler(to.name)
  if h.on_pasted then h.on_pasted(to, from) end
  return true
end

--- An area clone copied a hidden part on its own. The core's clone builds its
--- parts from the source, so a stray copy would be a second, ownerless part.
function lifecycle.part_cloned(destination)
  if cloning_parts then return end
  if not state().owner[destination.unit_number] then destination.destroy() end
end

local function hidden_inventories(rec, def)
  local out = {}
  for _, part in ipairs(def.parts) do
    local entity = rec.parts[part.kind .. ":" .. part.key]
    if entity and entity.valid then
      if part.kind == "inventory" then
        out[#out + 1] = entity.get_inventory(defines.inventory.chest)
      elseif part.kind == "energy" and entity.burner then
        out[#out + 1] = entity.burner.inventory
        out[#out + 1] = entity.burner.burnt_result_inventory
      end
    end
  end
  return out
end

local function spill(surface, position, stack, force)
  surface.spill_item_stack{position = position, stack = stack, enable_looted = true, force = force, allow_belts = false}
end

local function anchor(rec)
  if rec.entity.valid then return rec.entity end
  for _, entity in pairs(rec.parts) do
    if entity.valid then return entity end
  end
  return nil
end

local function move_out(rec, def, buffer, spill_rest)
  local at = anchor(rec)
  if not at then return end
  local surface, position, force = at.surface, at.position, at.force
  for _, inv in ipairs(hidden_inventories(rec, def)) do
    for i = 1, #inv do
      local stack = inv[i]
      if stack.valid_for_read then
        local moved = buffer and buffer.insert(stack) or 0
        if moved < stack.count then
          if moved > 0 then stack.count = stack.count - moved end
          if spill_rest then spill(surface, position, stack, force) end
        end
        stack.clear()
      end
    end
  end
end

--- Remove a core's parts. mode: "mined" (contents to buffer, overflow spilled),
--- "died" (contents spilled), "destroyed" (script_raised_destroy: contents gone,
--- as for a destroyed chest), "orphaned" (on_object_destroyed: the core vanished
--- without an event we handle, e.g. mined by a player-less character or destroyed
--- without raise_destroy; contents are spilled because the cause is unknown).
function lifecycle.teardown(unit_number, mode, buffer)
  local st = state()
  local rec = st.records[unit_number]
  if not rec then return end
  local def = defs.by_name[rec.name]
  local h = lifecycle.handler(rec.name)
  if h.on_removed then h.on_removed(rec, mode, buffer) end
  if mode == "mined" then
    move_out(rec, def, buffer, true)
  elseif mode == "died" or mode == "orphaned" then
    move_out(rec, def, nil, true)
  end
  for _, entity in pairs(rec.parts) do
    if entity.valid then
      st.owner[entity.unit_number] = nil
      entity.destroy()
    end
  end
  rec.next_due = nil
  st.records[unit_number] = nil
end

--- A core is about to be mined: its native inventory still holds its contents.
--- LuaEntity.mine and player/robot mining move them before any removal event,
--- so an entity script that adjusts what is mined has to do it here.
function lifecycle.before_mine(unit_number)
  local rec = state().records[unit_number]
  if not rec or not lifecycle.heal(rec) then return end
  local h = lifecycle.handler(rec.name)
  if h.before_mine then h.before_mine(rec) end
end

--- Mine a core by script into `inventory`, hidden contents included.
--- LuaEntity.mine raises no event carrying a buffer, so this is the script path.
function lifecycle.mine(core, inventory)
  local rec = state().records[core.unit_number]
  if rec then
    lifecycle.before_mine(rec.unit_number)
    local def = defs.by_name[rec.name]
    move_out(rec, def, inventory, true)
  end
  return core.mine{inventory = inventory, raise_destroyed = true}
end

return lifecycle
