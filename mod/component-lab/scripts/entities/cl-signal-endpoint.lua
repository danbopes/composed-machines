-- cl-signal-endpoint: runtime handlers. TEST-ENTITIES.md section 8.
--
-- The native S1 type would read its electric source every tick_interval ticks
-- and gate its script output on power. The emulation does the same from the
-- scheduler: one poll per instance per tick_interval, phase unit_number %
-- tick_interval (SPEC 3.4), writing status, cb.enabled and the two events on
-- transitions only.

local runtime = require("scripts.runtime")
local scheduler = require("scripts.scheduler")

local NAME = "cl-signal-endpoint"
local POWERED = {working = true, low_power = true}
local FULL = 0.999

local endpoint = {}

-- Status follows the network's supply on the last electric update, not the
-- buffer: a 1MJ buffer would otherwise hide a cut for 20 polls, and the
-- assertion (and aai-signal-transmission's poll) want "no power" within one.
-- Factorio satisfies every consumer of one priority class by the same fraction,
-- so the class fraction is this EEI's own satisfaction.
function endpoint.supply_status(eei)
  local sub = eei.electric_network
  if sub == nil then return "not_plugged_in_electric_network" end
  local flow = sub.parent_network.flow_last_tick
  local got
  if flow.secondary_demand > 0 then
    got = flow.secondary_demand_usage
  else
    got = eei.energy > 0 and 1 or 0
  end
  if got <= 0 then return "no_power" end
  if got < FULL then return "low_power" end
  return "working"
end

function endpoint.poll(rec)
  local status = endpoint.supply_status(rec:energy_entity())
  local powered = POWERED[status] == true
  rec:set_status(status)
  -- Reconciled every poll, not only on transitions: copy-paste and blueprints
  -- carry the combinator's on/off switch, which is where the power gate lives.
  local cb = rec:combinator().get_or_create_control_behavior()
  if cb.enabled ~= powered then cb.enabled = powered end
  if powered ~= rec.data.powered then
    rec.data.powered = powered
    rec:raise("power_state_changed", {powered = powered})
  end
  return status
end

--- signals: array of {name=, type=, quality=, count=}; at most max_output_signals are kept.
function endpoint.publish(rec, signals)
  rec:set_signals(signals)
end

runtime.expose("endpoint_publish", function(unit_number, signals)
  local rec = storage.cl.records[unit_number]
  if not rec then error("no " .. NAME .. " with unit_number " .. tostring(unit_number)) end
  endpoint.publish(rec, signals)
end)

runtime.expose("endpoint_poll", function(unit_number)
  local rec = storage.cl.records[unit_number]
  if not rec then error("no " .. NAME .. " with unit_number " .. tostring(unit_number)) end
  return endpoint.poll(rec)
end)

-- ---- real-tick rig --------------------------------------------------------
-- A suite runs inside one tick and the server reaches it about 30 ticks after
-- load, so power transitions are observed by a scripted scenario armed at
-- on_init (map creation): it drives the network one step every two ticks,
-- forces a poll, and records what the game shows. The suite reads the record.

local RIG = "cl_signal_endpoint_rig"
local RIG_X, RIG_Y = -600, 200
local GEN_ON = 100e6 / 60
local GEN_BROWN = 25e3 / 60
local SIGNALS = {
  {type = "item", name = "iron-plate", count = 10},
  {type = "item", name = "copper-plate", count = 20},
}

local function rig_state() return storage.cl.endpoint_rig end

local function wire_signals(chest)
  local out = {}
  for _, s in pairs(chest.get_signals(defines.wire_connector_id.circuit_red) or {}) do
    out[s.signal.name] = s.count
  end
  return out
end

local function set_generation(gen, per_tick)
  gen.electric_buffer_size = math.max(per_tick, 1)
  gen.power_production = per_tick
  gen.energy = 0
end

local function place_pole(r)
  r.pole = r.surface.create_entity{name = "small-electric-pole", position = {RIG_X - 1.5, RIG_Y + 0.5}, force = "player"}
end

local function observe(r, label)
  local rec = storage.cl.records[r.unit_number]
  local status = endpoint.poll(rec)
  r.obs[label] = {
    tick = game.tick,
    status = status,
    enabled = rec:combinator().get_or_create_control_behavior().enabled,
    energy = rec:energy_entity().energy,
    events = #r.events,
    stats_in = r.pole and r.pole.electric_network_statistics.get_input_count("cl-signal-endpoint-eei"),
  }
end

local function read_wire(r, label)
  r.obs[label].wire = wire_signals(r.chest)
  r.obs[label].wire_tick = game.tick
end

-- Each step runs at its tick; the next step is two ticks later so the electric
-- update and the circuit update both land in between.
local STEPS = {
  function(r) observe(r, "steady") end,
  function(r)
    read_wire(r, "steady")
    observe(r, "steady2")
    set_generation(r.gen, 0)
  end,
  function(r) observe(r, "cut") end,
  function(r)
    read_wire(r, "cut")
    observe(r, "cut2")
    set_generation(r.gen, GEN_ON)
  end,
  function(r) observe(r, "restored") end,
  function(r)
    read_wire(r, "restored")
    r.pole.destroy()
    r.pole = nil
  end,
  function(r)
    observe(r, "unplugged")
    place_pole(r)
  end,
  function(r)
    observe(r, "replugged")
    set_generation(r.gen, GEN_BROWN)
  end,
  function(r)
    observe(r, "brownout")
    set_generation(r.gen, GEN_ON)
  end,
  function(r)
    observe(r, "final")
    r.done_tick = game.tick
  end,
}

scheduler.on_named(RIG, function(tick)
  local r = rig_state()
  if not r or r.done_tick then return end
  r.step = r.step + 1
  STEPS[r.step](r)
  if r.step < #STEPS then scheduler.schedule(RIG, tick + 2) end
end)

local function build_rig()
  local surface = game.surfaces.nauvis
  surface.request_to_generate_chunks({RIG_X, RIG_Y}, 1)
  surface.force_generate_chunk_requests()
  local r = {surface = surface, step = 0, obs = {}, events = {}, armed_at = game.tick}
  r.gen = surface.create_entity{name = "hidden-electric-energy-interface", position = {RIG_X - 3.5, RIG_Y + 0.5}, force = "player"}
  set_generation(r.gen, GEN_ON)
  place_pole(r)
  local core = surface.create_entity{name = NAME, position = {RIG_X + 0.5, RIG_Y + 0.5}, force = "player"}
  -- Events raised from on_init are not delivered, so the parts are built directly.
  local rec = runtime.lifecycle.materialise(core, nil, "rig")
  endpoint.publish(rec, SIGNALS)
  r.chest = surface.create_entity{name = "wooden-chest", position = {RIG_X + 2.5, RIG_Y + 0.5}, force = "player"}
  core.get_wire_connector(defines.wire_connector_id.circuit_red, true)
    .connect_to(r.chest.get_wire_connector(defines.wire_connector_id.circuit_red, true), false, defines.wire_origin.player)
  r.core = core
  r.unit_number = core.unit_number
  storage.cl.endpoint_rig = r
  scheduler.schedule(RIG, game.tick + 2)
end

local function record_event(flag)
  return function(event)
    local r = rig_state()
    if not (r and event.unit_number == r.unit_number) or r.done_tick then return end
    r.events[#r.events + 1] = {flag = flag, tick = event.tick, new_status = event.new_status, powered = event.powered}
  end
end

for _, flag in ipairs({"status_changed", "power_state_changed"}) do
  runtime.subscribe(runtime.defs.events[NAME][flag], record_event(flag))
end

runtime.init_hooks[#runtime.init_hooks + 1] = function()
  if not storage.cl.endpoint_rig then build_rig() end
end

runtime.expose("endpoint_rig", function()
  local r = rig_state()
  if not r then return nil end
  return {unit_number = r.unit_number, core = r.core, obs = r.obs, events = r.events,
    done_tick = r.done_tick, armed_at = r.armed_at, step = r.step}
end)

return {
  on_created = function(rec, ctx)
    if ctx.cause ~= "clone" then
      rec.data.powered = false
      rec:combinator().get_or_create_control_behavior().enabled = false
    end
    rec:schedule_phase()
  end,

  on_tick = function(rec, tick)
    endpoint.poll(rec)
    rec:schedule_phase(nil, tick)
  end,

  on_gui = function(rec, _, frame)
    local eei = rec:energy_entity()
    frame.add{type = "label", caption = {"cl-signal-endpoint.status", {"entity-status." .. string.gsub(rec.status or "normal", "_", "-")}}}
    frame.add{type = "label", caption = {"cl-signal-endpoint.buffer",
      string.format("%.0f", eei.energy / 1000), string.format("%.0f", eei.electric_buffer_size / 1000)}}
  end,
}
