-- Control-stage engine for composed machines. control.lua registers each entity
-- script with runtime.register(name, handlers) and then calls runtime.install().
--
-- Handler table (all optional):
--   on_created(rec, ctx)          parts exist; ctx.cause is the event kind, ctx.tags the
--                                 blueprint tags applied, ctx.source the record cloned from
--   before_mine(rec)              about to be mined; the native inventory is still full
--   on_removed(rec, mode, buffer) before parts go; mode mined|died|destroyed|orphaned
--   on_tick(rec, tick)            a tick this record scheduled with rec:schedule(...)
--   on_cycle_finished(rec, event) the shell's recipe finished (RecipeCraftedEvent)
--   on_pasted(to, from)           settings pasted between two cores of this prototype
--   on_rotated(rec, previous_dir) the core turned; parts are already at their new offsets
--   blueprint_tags(rec) -> table  extra tags carried through blueprints
--   apply_tags(rec, extra)        apply those tags on build
--   on_gui(rec, player, frame)    fill the relative frame instead of the default

local defs = require("scripts.defs")
local scheduler = require("scripts.scheduler")
local lifecycle = require("scripts.lifecycle")
local gui = require("scripts.gui")
local Record = require("scripts.record")
local fixtures = require("scripts.fixtures")

local runtime = {
  defs = defs,
  scheduler = scheduler,
  lifecycle = lifecycle,
  gui = gui,
  Record = Record,
  fixtures = fixtures,
}

local handlers = {}
local listeners = {}
-- Events that accept a filter list (runtime-api.json: events with a filter field).
-- Registering filters for any other event is a hard error at load, so a
-- subscriber that passes them by mistake must not take the whole mod down.
local FILTERABLE = {}
for _, name in ipairs({
  "on_built_entity", "on_cancelled_deconstruction", "on_cancelled_upgrade", "on_entity_cloned",
  "on_entity_damaged", "on_entity_died", "on_marked_for_deconstruction", "on_marked_for_upgrade",
  "on_player_mined_entity", "on_player_repaired_entity", "on_post_entity_died", "on_post_segmented_unit_died",
  "on_pre_ghost_deconstructed", "on_pre_ghost_upgraded", "on_pre_player_mined_item", "on_robot_built_entity",
  "on_robot_mined_entity", "on_robot_pre_mined", "on_sector_scanned", "on_segmented_unit_created",
  "on_segmented_unit_damaged", "on_segmented_unit_died", "on_space_platform_built_entity",
  "on_space_platform_mined_entity", "on_space_platform_pre_mined", "script_raised_built", "script_raised_destroy",
  "script_raised_destroy_segmented_unit", "script_raised_revive", "script_raised_teleported",
}) do
  local id = defines.events[name]
  if id then FILTERABLE[id] = true end
end
local listener_order = {}
local exposed = {}

-- Factorio keeps one handler per event per mod, so every registration in this
-- mod (the runtime's own and the entity scripts') goes through here and is
-- combined in install(). A listener without filters widens the event to all.
local function listen(id, fn, filters)
  local entry = listeners[id]
  if not entry then
    entry = {fns = {}, filters = {}, unfiltered = false}
    listeners[id] = entry
    listener_order[#listener_order + 1] = id
  end
  entry.fns[#entry.fns + 1] = fn
  if filters and not FILTERABLE[id] then
    log("component-lab: event " .. tostring(id) .. " takes no filters; subscribing to all of it")
    filters = nil
  end
  if filters then
    for _, f in ipairs(filters) do entry.filters[#entry.filters + 1] = f end
  else
    entry.unfiltered = true
  end
end

--- Subscribe an entity script to any event (main chunk only, before install).
--- Never call script.on_event directly from an entity script: it would replace
--- the runtime's handler for that event.
function runtime.subscribe(id, fn, filters) listen(id, fn, filters) end

--- Add a function to the component_lab remote interface (before install).
function runtime.expose(name, fn) exposed[name] = fn end

function runtime.register(name, h)
  if not defs.by_name[name] then error("component-lab: no composed machine prototype '" .. name .. "'", 2) end
  handlers[name] = h or {}
end

local function init_storage()
  storage.cl = storage.cl or {}
  local st = storage.cl
  st.records = st.records or {}
  st.owner = st.owner or {}
  st.due = st.due or {}
end

--- The record of a core (or of one of its hidden parts), or nil.
function runtime.get(entity)
  if not (entity and entity.valid and entity.unit_number) then return nil end
  local st = storage.cl
  local rec = st.records[entity.unit_number]
  if rec then return rec end
  local owner = st.owner[entity.unit_number]
  return owner and st.records[owner] or nil
end

--- Absolute-tick scheduling by unit_number, for code that holds no record.
function runtime.schedule(unit_number, due_tick)
  local rec = storage.cl.records[unit_number]
  if not rec then return nil end
  return rec:schedule_at(due_tick)
end

function runtime.raise(entity, flag, payload)
  local rec = runtime.get(entity)
  if rec then rec:raise(flag, payload) end
end

function runtime.set_status(entity, name, opts)
  local rec = runtime.get(entity)
  if rec then return rec:set_status(name, opts) end
end

function runtime.mine(entity, inventory) return lifecycle.mine(entity, inventory) end

-- ---- event wiring ------------------------------------------------------------

local function name_filters(names)
  local f = {}
  for _, n in ipairs(names) do f[#f + 1] = {filter = "name", name = n} end
  return f
end

local function on_built(event)
  local entity = event.entity or event.destination
  if entity and entity.valid and defs.by_name[entity.name] then
    lifecycle.materialise(entity, event.tags, event.name)
  end
end

local function on_mined(event)
  lifecycle.teardown(event.entity.unit_number, "mined", event.buffer)
end

local function on_pre_mined(event)
  lifecycle.before_mine(event.entity.unit_number)
end

local function on_pasted(event)
  lifecycle.pasted(event.source, event.destination)
end

local function on_died(event)
  lifecycle.teardown(event.entity.unit_number, "died")
end

local function on_destroy(event)
  lifecycle.teardown(event.entity.unit_number, "destroyed")
end

local function on_object_destroyed(event)
  if event.type == defines.target_type.entity and event.useful_id then
    if storage.cl.records[event.useful_id] then
      lifecycle.teardown(event.useful_id, "orphaned")
    else
      lifecycle.part_destroyed(event.useful_id)
    end
  end
end

local function on_rotated(event)
  local entity = event.entity
  local rec = entity.valid and storage.cl.records[entity.unit_number or 0]
  if rec then lifecycle.rotated(rec, event.previous_direction) end
end

local function on_cloned(event)
  local dest = event.destination
  if defs.by_name[dest.name] then
    lifecycle.cloned(event.source, dest)
  elseif defs.part_set[dest.name] then
    lifecycle.part_cloned(dest)
  end
end

-- on_object_destroyed for a lost part can arrive a tick late, so the
-- handler-facing paths heal first rather than trust that it has run.
local function run_tick(rec, tick)
  if not lifecycle.heal(rec) then return end
  local h = handlers[rec.name]
  if h and h.on_tick then h.on_tick(rec, tick) end
end

local function dispatch(unit_number, tick)
  local rec = storage.cl.records[unit_number]
  if not rec or rec.next_due ~= tick then return end
  rec.next_due = nil
  Record.batch(run_tick, rec, tick)
end

local function on_crafted(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end
  local rec = storage.cl.records[entity.unit_number]
  if not rec or not lifecycle.heal(rec) then return end
  local spec = rec:spec()
  if spec.process.start == "script" then
    entity.disabled_by_script = true
    rec:set_status("waiting_for_script")
  end
  if defs.events[rec.name].cycle_finished then
    rec:raise("cycle_finished", {cycles = 1, bonus_cycles = 0})
  end
  local h = handlers[rec.name]
  if h and h.on_cycle_finished then h.on_cycle_finished(rec, event) end
end

local function on_setup_blueprint(event)
  local bp = event.record
  if not (bp and bp.valid) then
    bp = event.stack
    if not (bp and bp.valid_for_read and bp.is_blueprint) then return end
  end
  local mapping = event.mapping and event.mapping.valid and event.mapping.get() or nil
  if mapping then runtime.tag_blueprint(bp, mapping) end
end

--- Write component tags into a blueprint (LuaItemStack or LuaRecord) given the
--- index -> entity mapping (event.mapping.get() or create_blueprint's return).
function runtime.tag_blueprint(bp, mapping)
  local records = storage.cl.records
  local count = 0
  for index, entity in pairs(mapping) do
    if entity.valid and entity.unit_number then
      local rec = records[entity.unit_number]
      if rec then
        bp.set_blueprint_entity_tag(index, "component_lab", lifecycle.blueprint_tags(rec))
        count = count + 1
      end
    end
  end
  return count
end

local function on_gui_opened(event)
  local entity = event.entity
  if not (entity and entity.valid) then return end
  local rec = storage.cl.records[entity.unit_number or 0]
  if not rec or not lifecycle.heal(rec) then return end
  local h = handlers[rec.name]
  gui.open(game.get_player(event.player_index), rec, h and h.on_gui)
end

local function on_gui_closed(event)
  if event.entity then gui.close(game.get_player(event.player_index)) end
end

-- Event ids handed to other mods (and the test suites) over remote.
local function event_ids()
  local out = {}
  for name, ids in pairs(defs.events) do out[name] = ids end
  return out
end

function runtime.install()
  for name in pairs(defs.by_name) do
    if not handlers[name] then handlers[name] = {} end
  end
  lifecycle.set_handlers(handlers)
  scheduler.set_dispatcher(dispatch)

  local cores = name_filters(defs.core_names)
  if #cores > 0 then
    for _, id in ipairs({
      defines.events.on_built_entity, defines.events.on_robot_built_entity,
      defines.events.on_space_platform_built_entity, defines.events.script_raised_built,
      defines.events.script_raised_revive,
    }) do
      listen(id, on_built, cores)
    end
    for _, id in ipairs({
      defines.events.on_player_mined_entity, defines.events.on_robot_mined_entity,
      defines.events.on_space_platform_mined_entity,
    }) do
      listen(id, on_mined, cores)
    end
    for _, id in ipairs({
      defines.events.on_pre_player_mined_item, defines.events.on_robot_pre_mined,
      defines.events.on_space_platform_pre_mined,
    }) do
      listen(id, on_pre_mined, cores)
    end
    listen(defines.events.on_entity_died, on_died, cores)
    listen(defines.events.script_raised_destroy, on_destroy, cores)

    local clone_filters = name_filters(defs.core_names)
    for _, n in ipairs(defs.part_names) do clone_filters[#clone_filters + 1] = {filter = "name", name = n} end
    listen(defines.events.on_entity_cloned, on_cloned, clone_filters)
  end

  listen(defines.events.on_object_destroyed, on_object_destroyed)
  listen(defines.events.on_player_setup_blueprint, on_setup_blueprint)
  listen(defines.events.on_entity_settings_pasted, on_pasted)
  listen(defines.events.on_player_rotated_entity, on_rotated)
  listen(defines.events.on_gui_opened, on_gui_opened)
  listen(defines.events.on_gui_closed, on_gui_closed)

  for recipe in pairs(defs.by_recipe) do
    listen(prototypes.recipe[recipe].on_crafted_event, on_crafted)
  end

  for _, id in ipairs(listener_order) do
    local entry = listeners[id]
    local fns = entry.fns
    local handler
    local function run(event) for i = 1, #fns do fns[i](event) end end
    handler = function(event) Record.batch(run, event) end
    -- A shared event delivers the union of every listener's filters, so a
    -- listener must re-check that the entity is one it cares about.
    local filters = (not entry.unfiltered and #entry.filters > 0) and entry.filters or nil
    script.on_event(id, handler, filters)
  end

  script.on_init(function()
    init_storage()
    for _, fn in ipairs(runtime.init_hooks) do fn() end
  end)
  script.on_configuration_changed(function()
    init_storage()
    for _, fn in ipairs(runtime.init_hooks) do fn() end
  end)
  script.on_load(function()
    scheduler.on_load()
    for _, fn in ipairs(runtime.load_hooks) do fn() end
  end)

  local interface = {
    event_ids = event_ids,
    shape = function(name) return defs.by_name[name] and defs.by_name[name].shape end,
    record = function(unit_number)
      local rec = storage.cl.records[unit_number]
      if not rec then return nil end
      return {name = rec.name, status = rec.status, settings = rec.settings, next_due = rec.next_due, data = rec.data}
    end,
    mine = function(entity, inventory) return lifecycle.mine(entity, inventory) end,
    -- Invoke a Record method by name on a core; for suites, which run in another mod.
    call = function(unit_number, method, ...)
      local rec = storage.cl.records[unit_number]
      if not rec then error("no composed machine with unit_number " .. tostring(unit_number)) end
      return rec[method](rec, ...)
    end,
    parts = function(unit_number)
      local rec = storage.cl.records[unit_number]
      return rec and rec.parts or nil
    end,
    count = function()
      local n = 0
      for _ in pairs(storage.cl.records) do n = n + 1 end
      return n
    end,
    census = function()
      local by_name = {}
      for _, rec in pairs(storage.cl.records) do by_name[rec.name] = (by_name[rec.name] or 0) + 1 end
      return by_name
    end,
    owner_of = function(unit_number) return storage.cl.owner[unit_number] end,
    -- LuaEntity.rotate raises on_player_rotated_entity only with by_player,
    -- and a headless server has none, so suites rotate through here.
    rotate = function(entity, reverse)
      local previous = entity.direction
      local ok = entity.rotate{reverse = reverse}
      local rec = storage.cl.records[entity.unit_number or 0]
      if ok and rec then lifecycle.rotated(rec, previous) end
      return ok
    end,
    tag_blueprint = function(bp, mapping) return runtime.tag_blueprint(bp, mapping) end,
    -- copy_settings without a player raises no on_entity_settings_pasted, so a
    -- headless suite takes the same path through here.
    paste = function(source, destination)
      destination.copy_settings(source)
      return lifecycle.pasted(source, destination)
    end,
    schedule = function(unit_number, tick) return runtime.schedule(unit_number, tick) end,
    bucket = function(tick) return scheduler.bucket(tick) end,
    dispatch = function(tick, unit_number) scheduler.dispatch_records(tick, unit_number) end,
    event_log = function(clear)
      local log = storage.cl.event_log
      if clear then storage.cl.event_log = {} end
      return log
    end,
    set_event_log = function(on)
      storage.cl.log_events = on and true or nil
      storage.cl.event_log = {}
    end,
  }
  for name, fn in pairs(exposed) do interface[name] = fn end
  for name, fn in pairs(interface) do
    interface[name] = function(...) return Record.batch(fn, ...) end
  end
  remote.add_interface("component_lab", interface)
end

--- Functions run from on_init and on_configuration_changed, after storage exists.
runtime.init_hooks = {}
--- Functions run from on_load (re-registering conditional handlers only; storage is read-only there).
runtime.load_hooks = {}

return runtime
