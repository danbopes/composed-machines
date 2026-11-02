-- cl-brazier: runtime. TEST-ENTITIES-2.md section 2.
-- The native S1 would raise power_state_changed from the burner itself the tick
-- it runs dry. Today nothing signals that, so a per-entity pass every 30 ticks
-- diffs has_fuel(), raises the event on a transition, writes the status and
-- toggles the light. This latency and the pass are what the benchmark measures.

local runtime = require("scripts.runtime")

local NAME = "cl-brazier"
local POLL = 30

local function light_spec(rec)
  return rec:spec().graphics_set.working_visualisations[1].light
end

local function light_of(rec)
  local id = rec.data.light_id
  local obj = id and rendering.get_object_by_id(id)
  if obj and obj.valid then return obj end
  return nil
end

-- A clone arrives holding the source's light id; that light follows the
-- source, so every core draws its own.
local function draw_light(rec)
  local spec = light_spec(rec)
  local obj = rendering.draw_light{
    sprite = "utility/light_medium",
    target = rec.entity,
    surface = rec.entity.surface,
    intensity = spec.intensity,
    -- utility/light_medium spans about 6 tiles at scale 1; size is the radius in tiles.
    scale = spec.size / 6,
    color = spec.color,
    visible = rec.data.powered == true,
  }
  rec.data.light_id = obj.id
  return obj
end

local function poll(rec, quiet)
  local powered = rec:has_fuel()
  if rec.data.powered ~= powered then
    local first = rec.data.powered == nil
    rec.data.powered = powered
    local light = light_of(rec) or draw_light(rec)
    light.visible = powered
    if not (quiet or first) then
      local log = rec.data.power_log
      log[#log + 1] = {tick = game.tick, powered = powered}
      -- Kept for the suite only; bounded so a long-lived brazier cannot grow storage.
      if #log > 8 then table.remove(log, 1) end
      rec:raise("power_state_changed", {powered = powered})
    end
  end
  rec:set_status(powered and "working" or "no_fuel")
end

local function fuel_plan(rec)
  local reactor = rec:energy_entity()
  local proxy = reactor.item_request_proxy
  if proxy and proxy.valid then return proxy.insert_plan end
  local stack = rec:fuel_inventory()[1]
  if not stack.valid_for_read then return nil end
  return {{
    id = {name = stack.name, quality = stack.quality.name},
    items = {in_inventory = {{inventory = defines.inventory.fuel, stack = 0, count = stack.count}}},
  }}
end

local function fuel_energy(burner)
  local total = burner.remaining_burning_fuel + burner.heat
  local stack = burner.inventory[1]
  if stack.valid_for_read then total = total + stack.count * stack.prototype.fuel_value end
  return total
end

-- ---- real-tick fixtures ------------------------------------------------------
-- A suite runs inside one tick, so burning and flame-out are observed on
-- braziers built earlier: at on_init for a fresh map, re-armed by the suite for a
-- --keep server. About 30 ticks pass before the suite runs, so the flame-out
-- brazier holds 2 ticks of fuel (1 kJ at 30 kW) and polls first at tick 10.

local FIXTURE_ORIGIN = {-2400.5, 2400.5}
local FLAMEOUT_JOULES = 1000
local FLAMEOUT_FIRST_POLL = 10
-- A burner inserter needs well over 30 ticks to swing a first load across.
local INSERTER_TICKS = 300
local PULLED_COAL = 10

local function arm_fixtures()
  local old = storage.cl.brazier_fixtures
  if old then
    for _, f in pairs(old.braziers) do
      if f.entity.valid then f.entity.destroy{raise_destroy = true} end
    end
    for _, e in pairs(old.helpers or {}) do
      if e.valid then e.destroy() end
    end
  end
  local surface = game.surfaces.nauvis
  surface.request_to_generate_chunks(FIXTURE_ORIGIN, 1)
  surface.force_generate_chunk_requests()
  local function place(dx)
    local core = surface.create_entity{
      name = NAME,
      position = {FIXTURE_ORIGIN[1] + dx, FIXTURE_ORIGIN[2]},
      force = "player",
    }
    -- Events raised from on_init are not delivered, so build the parts directly.
    return runtime.lifecycle.materialise(core, nil, "fixture")
  end
  local steady = place(0)
  steady:fuel_inventory().insert{name = "coal", count = 2}
  poll(steady, true)
  local flameout = place(3)
  local burner = flameout:energy_entity().burner
  burner.currently_burning = "wood"
  burner.remaining_burning_fuel = FLAMEOUT_JOULES
  poll(flameout, true)
  flameout:schedule(FLAMEOUT_FIRST_POLL)
  local fed = place(8)
  local chest = surface.create_entity{name = "infinity-chest", force = "player",
    position = {FIXTURE_ORIGIN[1] + 6, FIXTURE_ORIGIN[2]}}
  chest.set_infinity_container_filter(1, {name = "coal", count = 50, mode = "exactly"})
  local inserter = surface.create_entity{name = "burner-inserter", force = "player",
    position = {FIXTURE_ORIGIN[1] + 7, FIXTURE_ORIGIN[2]}, direction = defines.direction.east}
  if inserter.drop_position.x < inserter.position.x then inserter.direction = defines.direction.west end
  inserter.get_fuel_inventory().insert{name = "coal", count = 5}
  poll(fed, true)
  -- An inserter facing away from a fuelled brazier: it must not drain the door.
  local pulled = place(13)
  pulled:fuel_inventory().insert{name = "coal", count = PULLED_COAL}
  poll(pulled, true)
  local pull_sink = surface.create_entity{name = "iron-chest", force = "player",
    position = {FIXTURE_ORIGIN[1] + 15, FIXTURE_ORIGIN[2]}}
  local puller = surface.create_entity{name = "burner-inserter", force = "player",
    position = {FIXTURE_ORIGIN[1] + 14, FIXTURE_ORIGIN[2]}, direction = defines.direction.west}
  if puller.pickup_position.x > puller.position.x then puller.direction = defines.direction.east end
  puller.get_fuel_inventory().insert{name = "coal", count = 5}
  runtime.fixtures.hold_until(game.tick + INSERTER_TICKS)
  local braziers = {}
  for key, rec in pairs({steady = steady, flameout = flameout, fed = fed, pulled = pulled}) do
    braziers[key] = {
      entity = rec.entity,
      unit_number = rec.unit_number,
      energy = fuel_energy(rec:energy_entity().burner),
    }
  end
  storage.cl.brazier_fixtures = {
    tick = game.tick,
    braziers = braziers,
    helpers = {chest, inserter, pull_sink, puller},
    inserter = inserter,
    puller = puller,
    pull_sink = pull_sink,
    pulled_coal = PULLED_COAL,
    inserter_ticks = INSERTER_TICKS,
    flameout_joules = FLAMEOUT_JOULES,
    flameout_first_poll = FLAMEOUT_FIRST_POLL,
  }
end

runtime.init_hooks[#runtime.init_hooks + 1] = function()
  if not storage.cl.brazier_fixtures then arm_fixtures() end
end

local function light_state(rec)
  local light = light_of(rec)
  if not light then return nil end
  return {
    visible = light.visible,
    intensity = light.intensity,
    target = light.target and light.target.entity,
    color = light.color,
  }
end

runtime.expose("brazier_fixtures", function()
  local fx = storage.cl.brazier_fixtures
  if not fx then return nil end
  local out = {
    tick = fx.tick,
    braziers = {},
    inserter_ticks = fx.inserter_ticks,
    inserter_drop_target = fx.inserter.valid and fx.inserter.drop_target or nil,
    puller_pickup_target = fx.puller and fx.puller.valid and fx.puller.pickup_target or nil,
    pull_sink_count = fx.pull_sink and fx.pull_sink.valid and fx.pull_sink.get_item_count() or nil,
    pulled_coal = fx.pulled_coal,
    flameout_joules = fx.flameout_joules,
    flameout_first_poll = fx.flameout_first_poll,
  }
  for key, f in pairs(fx.braziers) do
    local rec = runtime.get(f.entity)
    out.braziers[key] = {
      unit_number = f.unit_number,
      energy_at_arm = f.energy,
      energy_now = rec and fuel_energy(rec:energy_entity().burner) or nil,
      burning = rec and rec:energy_entity().burner.currently_burning ~= nil,
      fuel_count = rec and rec:fuel_inventory().get_item_count() or nil,
      door = rec and rec:part("proxy", "fuel"),
      light = rec and light_state(rec),
    }
  end
  return out
end)
runtime.expose("brazier_arm_fixtures", function() arm_fixtures() return true end)
runtime.expose("brazier_poll", function(unit_number)
  local rec = storage.cl.records[unit_number]
  if rec then poll(rec) end
end)
runtime.expose("brazier_light", function(unit_number)
  local rec = storage.cl.records[unit_number]
  return rec and light_state(rec)
end)

-- ---- handlers ----------------------------------------------------------------

return {
  on_created = function(rec)
    rec.data.power_log = rec.data.power_log or {}
    rec.data.powered = nil
    rec.data.light_id = nil
    poll(rec, true)
    rec:schedule(POLL)
  end,
  on_tick = function(rec)
    poll(rec)
    rec:schedule(POLL)
  end,
  blueprint_tags = function(rec)
    local plan = fuel_plan(rec)
    return plan and {fuel_plan = plan} or nil
  end,
  apply_tags = function(rec, extra)
    if type(extra) == "table" and extra.fuel_plan then
      local reactor = rec:energy_entity()
      reactor.surface.create_entity{
        name = "item-request-proxy",
        position = reactor.position,
        force = reactor.force,
        target = reactor,
        modules = extra.fuel_plan,
      }
    end
  end,
}
