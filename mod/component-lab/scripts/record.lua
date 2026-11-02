-- The per-entity API entity scripts use. Records live in storage, so the
-- metatable is registered by name and re-linked on load.

local util = require("util")
local defs = require("scripts.defs")
local scheduler = require("scripts.scheduler")
local status = require("scripts.status")

local Record = {}
Record.__index = Record
script.register_metatable("component-lab.record", Record)

function Record.new(entity)
  local def = defs.by_name[entity.name]
  local settings = {}
  for _, s in ipairs(def.spec.settings or {}) do settings[s.name] = s.default end
  return setmetatable({
    unit_number = entity.unit_number,
    name = entity.name,
    entity = entity,
    parts = {},
    settings = settings,
    status = nil,
    data = {},
    next_due = nil,
  }, Record)
end

function Record:valid() return self.entity ~= nil and self.entity.valid end

--- Still in the world and still the registered record for its unit_number.
function Record:live()
  return self.entity ~= nil and self.entity.valid and storage.cl.records[self.unit_number] == self
end
function Record:def() return defs.by_name[self.name] end
function Record:spec() return defs.by_name[self.name].spec end

-- ---- parts -------------------------------------------------------------------

function Record:part(kind, key)
  local entity = self.parts[kind .. ":" .. key]
  return entity and entity.valid and entity or nil
end

--- The named inventory, wherever the emulation put it.
function Record:inventory(name)
  local def = defs.by_name[self.name]
  if def.native_inventory == name then
    return self.entity.get_inventory(defines.inventory.chest)
  end
  local part = self.parts["inventory:" .. name]
  return part and part.valid and part.get_inventory(defines.inventory.chest) or nil
end

--- The entity carrying the energy source: the shell itself, or the hidden EEI / reactor.
function Record:energy_entity()
  return self.parts["energy:energy"] or self.entity
end

function Record:fuel_inventory()
  return self:energy_entity().get_fuel_inventory()
end

--- (entity, fluid index) for fluid box i: the shell's own box or the hidden tank.
function Record:fluid_box(i)
  local tank = self.parts["tank:fluid" .. i]
  if tank then return tank, 1 end
  return self.entity, i
end

--- True while the burner has something to burn: a fuel item mid-burn or one
--- waiting in the slot. Works for a hidden reactor and for a burner shell.
function Record:has_fuel()
  local burner = self:energy_entity().burner
  if not burner then return false end
  return burner.remaining_burning_fuel > 0 or not burner.inventory.is_empty()
end

--- Sum of a signal on the core's red and green wires (0 when absent or unwired).
--- Quality defaults to "normal", the quality every suite combinator sends.
function Record:read_signal(name, signal_type, quality)
  return self.entity.get_signal(
    {type = signal_type or "virtual", name = name, quality = quality or "normal"},
    defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green) or 0
end

--- The V2 generation part: add `joules` to the hidden producer's buffer, which
--- the network drains at up to output_flow_limit. Returns what fit.
function Record:add_output_energy(joules)
  local eei = self:part("generator", "output")
  if not eei then error(self.name .. " declares no energy_output", 2) end
  local room = eei.electric_buffer_size - eei.energy
  local added = math.min(room, joules)
  if added > 0 then eei.energy = eei.energy + added end
  return math.max(added, 0)
end

--- The V2 heat output part: raise the hidden heat interface's buffer by
--- `joules` (temperature += joules / specific_heat, capped at max_temperature).
--- Returns the joules that fit.
function Record:add_heat(joules)
  local interface = self:part("heat", "heat")
  if not interface then error(self.name .. " declares no heat_buffer", 2) end
  local buffer = self:spec().heat_buffer
  local specific_heat = util.parse_energy(buffer.specific_heat)
  local room = (buffer.max_temperature - interface.temperature) * specific_heat
  local added = math.max(math.min(room, joules), 0)
  if added > 0 then interface.temperature = interface.temperature + added / specific_heat end
  return added
end

function Record:combinator()
  return self.parts["combinator:signals"] or (self.entity.type == "constant-combinator" and self.entity or nil)
end

--- Replace script-written output signals. filters: array of {name=, type=, quality=, count=}.
function Record:set_signals(filters)
  local cc = self:combinator()
  local cb = cc.get_or_create_control_behavior()
  local section = cb.get_section(1) or cb.add_section()
  local out = {}
  local limit = self:spec().max_output_signals or 20
  for i, f in ipairs(filters) do
    if i > limit then break end
    out[i] = {
      value = {type = f.type or "item", name = f.name, quality = f.quality or "normal", comparator = "="},
      min = f.count,
    }
  end
  section.filters = out
end

-- ---- scheduling --------------------------------------------------------------

--- Run the entity script's on_tick(rec, tick) at an absolute tick.
function Record:schedule_at(tick)
  self.next_due = scheduler.schedule(self.unit_number, tick)
  return self.next_due
end

--- Run on_tick(rec, tick) after delay ticks (minimum 1).
function Record:schedule(delay)
  return self:schedule_at(game.tick + math.max(1, delay or 1))
end

--- Run on_tick at the first tick after `after` (default now) whose phase
--- matches this record: tick % interval == unit_number % interval (SPEC 3.4),
--- so a blueprint full of equal machines does not poll on one tick.
--- interval defaults to the spec's tick_interval.
function Record:schedule_phase(interval, after)
  interval = interval or self:spec().tick_interval or 1
  local t = (after or game.tick) + 1
  return self:schedule_at(t + (self.unit_number - t) % interval)
end

function Record:unschedule() self.next_due = nil end

-- ---- events ------------------------------------------------------------------

function Record:event_id(flag)
  return defs.events[self.name][flag]
end

-- script.raise_event runs subscribers synchronously, and a subscriber may
-- remove the machine. Events raised while the library runs an entity handler
-- (scheduled on_tick, any subscribed event, a remote call) are therefore
-- queued and raised once the handler has returned, so no handler code ever
-- runs on a machine its own event removed. Named scheduler callbacks are
-- fixture drivers that read their own events back at once, so they raise
-- immediately; there, a raise on a removed machine is a no-op. The queue never outlives
-- the outermost batch, so it needs no place in storage.
local depth = 0
local queue = {}

local function flush()
  local q = queue
  queue = {}
  for i = 1, #q do
    local item = q[i]
    if item.rec:live() then script.raise_event(item.id, item.payload) end
  end
end

--- Run fn(...) with event raising deferred until it returns (nesting is fine;
--- only the outermost batch flushes). Returns fn's results.
function Record.batch(fn, ...)
  depth = depth + 1
  local results = table.pack(pcall(fn, ...))
  depth = depth - 1
  if not results[1] then
    if depth == 0 then queue = {} end
    error(results[2], 0)
  end
  if depth == 0 and #queue > 0 then flush() end
  return table.unpack(results, 2, results.n)
end

--- Raise the opt-in event `flag` (a SPEC 1.7 flag). Raising an undeclared flag is
--- a bug in the entity script, so it errors instead of silently dropping.
--- Returns whether the machine is still live, which is always true for a
--- deferred raise; a machine that is already gone raises nothing.
function Record:raise(flag, payload)
  local id = defs.events[self.name][flag]
  if not id then error(string.format("%s does not declare events.%s", self.name, flag), 2) end
  if not self:live() then return false end
  payload = payload or {}
  payload.entity = self.entity
  payload.unit_number = self.unit_number
  local st = storage.cl
  if st.log_events then
    local entry = {flag = flag, unit_number = self.unit_number, tick = game.tick}
    for k, v in pairs(payload) do
      if type(v) ~= "userdata" and type(v) ~= "table" then entry[k] = v end
    end
    st.event_log[#st.event_log + 1] = entry
  end
  if depth > 0 then
    queue[#queue + 1] = {rec = self, id = id, payload = payload}
    return true
  end
  script.raise_event(id, payload)
  return self:live()
end

--- The inventory_changed emulation: nothing reports transfers into a hidden or
--- native container, so entity scripts poll this. True when the named
--- inventory's contents differ from what the previous call saw; the first call
--- only records them, so call it once from on_created.
function Record:contents_changed(name)
  local parts = {}
  for _, c in pairs(self:inventory(name).get_contents()) do
    parts[#parts + 1] = c.name .. "/" .. c.quality .. "/" .. c.count
  end
  table.sort(parts)
  local sig = table.concat(parts, ",")
  local seen = self.data.contents_seen
  if not seen then
    seen = {}
    self.data.contents_seen = seen
  end
  local old = seen[name]
  seen[name] = sig
  return old ~= nil and old ~= sig
end

-- ---- status ------------------------------------------------------------------

--- Show `name` (a defines.entity_status key or no_modules / waiting_for_script) on
--- the core through custom_status. nil clears it. Writes only on change; raises
--- status_changed when the prototype declared it. Returns true if it changed.
function Record:set_status(name, opts)
  if self.status == name and not (opts and opts.force) then return false end
  local old = self.status
  self.status = name
  status.apply(self.entity, name, opts)
  if defs.events[self.name].status_changed then
    self:raise("status_changed", {old_status = old, new_status = name})
  end
  return true
end

--- First failing SPEC 1.5 condition, or nil when all hold.
function Record:check_conditions()
  return status.first_failing(self)
end

-- ---- settings ----------------------------------------------------------------

function Record:get_setting(name) return self.settings[name] end

function Record:set_setting(name, value, player_index)
  local declared
  for _, s in ipairs(self:spec().settings or {}) do
    if s.name == name then declared = s end
  end
  if not declared then error(self.name .. " has no setting '" .. tostring(name) .. "'", 2) end
  if declared.min and value < declared.min then value = declared.min end
  if declared.max and value > declared.max then value = declared.max end
  if self.settings[name] == value then return end
  self.settings[name] = value
  if defs.events[self.name].settings_changed then
    self:raise("settings_changed", {setting = name, player_index = player_index})
  end
end

-- ---- script-started process (SPEC 1.4 start = "script") ----------------------

--- Begin one cycle on a start = "script" shell. Returns false, reason when it cannot.
function Record:start_cycle()
  local process = self:spec().process
  if not process or process.start ~= "script" then error(self.name .. " is not start = \"script\"", 2) end
  local core = self.entity
  if not core.disabled_by_script then return false, "already_running" end
  if self.status == "no_power" or self.status == "no_fuel" then return false, self.status end
  core.disabled_by_script = false
  if defs.events[self.name].cycle_started then self:raise("cycle_started", {}) end
  self:set_status("working")
  return true
end

return Record
