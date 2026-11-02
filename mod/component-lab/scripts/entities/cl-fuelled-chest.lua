-- cl-fuelled-chest: runtime. The hidden reactor burns whenever it is enabled and
-- fuelled; the native S1 would sleep on the main inventory's wake list, but a
-- container raises no transfer event, so a per-entity poll stands in for it:
-- it gates the reactor on the main inventory, diffs the power state and writes
-- the status on transitions only.

local runtime = require("scripts.runtime")

local NAME = "cl-fuelled-chest"
-- TEST-ENTITIES.md section 3 sets the poll granularity the emulation is measured at.
local POLL = 30

local function fuelled(burner)
  return burner.currently_burning ~= nil or not burner.inventory.is_empty()
end

-- Native status precedence (SPEC section 5): the energy source's no_fuel beats
-- working, and an idle S1 with nothing failing shows its default status (none).
local function status_for(has_fuel, occupied)
  if not has_fuel then return "no_fuel" end
  if occupied then return "working" end
  return nil
end

local function poll(rec, quiet)
  local reactor = rec:energy_entity()
  if not (reactor and reactor.valid) then return end
  local occupied = not rec:inventory("main").is_empty()
  local asleep = not occupied
  if rec.data.asleep ~= asleep then
    rec.data.asleep = asleep
    reactor.disabled_by_script = asleep
  end
  local has_fuel = fuelled(reactor.burner)
  if rec.data.powered ~= has_fuel then
    local first = rec.data.powered == nil
    rec.data.powered = has_fuel
    if not (quiet or first) then
      local log = rec.data.power_log
      log[#log + 1] = {tick = game.tick, powered = has_fuel}
      -- Kept for the suite only; bounded so a long-lived chest cannot grow storage.
      if #log > 8 then table.remove(log, 1) end
      rec:raise("power_state_changed", {powered = has_fuel})
    end
  end
  rec:set_status(status_for(has_fuel, occupied))
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

local function request_fuel(rec, plan)
  local reactor = rec:energy_entity()
  return reactor.surface.create_entity{
    name = "item-request-proxy",
    position = reactor.position,
    force = reactor.force,
    target = reactor,
    modules = plan,
  }
end

-- ---- real-tick fixtures ------------------------------------------------------
-- A suite runs inside one tick, so burning and flame-out are observed on chests
-- built earlier: at on_init for a fresh map, re-armed by the suite for a --keep
-- server. The harness boots a pristine copy of the map, so only ~30 ticks pass
-- before the suite runs: the flame-out chest holds 3 ticks of fuel and polls
-- first at tick 10 instead of 30.

local FIXTURE_ORIGIN = {-400.5, 300.5}
local FLAMEOUT_JOULES = 1000
local FLAMEOUT_FIRST_POLL = 10

local function fuel_energy(burner)
  local total = burner.remaining_burning_fuel + burner.heat
  local stack = burner.inventory[1]
  if stack.valid_for_read then total = total + stack.count * stack.prototype.fuel_value end
  return total
end

local function arm_fixtures()
  local old = storage.cl.fuelled_fixtures
  if old then
    for _, f in pairs(old.chests) do
      if f.entity.valid then f.entity.destroy{raise_destroy = true} end
    end
  end
  local surface = game.surfaces.nauvis
  surface.request_to_generate_chunks(FIXTURE_ORIGIN, 1)
  surface.force_generate_chunk_requests()
  local function place(dx, items, fuel)
    local core = surface.create_entity{
      name = NAME,
      position = {FIXTURE_ORIGIN[1] + dx, FIXTURE_ORIGIN[2]},
      force = "player",
    }
    -- Events raised from on_init are not delivered, so build the parts directly.
    local rec = runtime.lifecycle.materialise(core, nil, "fixture")
    if items then rec:inventory("main").insert(items) end
    if fuel then rec:fuel_inventory().insert(fuel) end
    poll(rec, true)
    return rec
  end
  local burning = place(0, {name = "iron-plate", count = 10}, {name = "coal", count = 2})
  local idle = place(3, nil, {name = "coal", count = 2})
  local flameout = place(6, {name = "iron-plate", count = 10}, nil)
  local burner = flameout:energy_entity().burner
  burner.currently_burning = "coal"
  burner.remaining_burning_fuel = FLAMEOUT_JOULES
  poll(flameout, true)
  flameout:schedule(FLAMEOUT_FIRST_POLL)
  local chests = {}
  for key, rec in pairs({burning = burning, idle = idle, flameout = flameout}) do
    chests[key] = {
      entity = rec.entity,
      unit_number = rec.unit_number,
      energy = fuel_energy(rec:energy_entity().burner),
    }
  end
  storage.cl.fuelled_fixtures = {
    tick = game.tick,
    chests = chests,
    flameout_joules = FLAMEOUT_JOULES,
    flameout_first_poll = FLAMEOUT_FIRST_POLL,
  }
  return storage.cl.fuelled_fixtures
end

runtime.init_hooks[#runtime.init_hooks + 1] = function()
  if not storage.cl.fuelled_fixtures then arm_fixtures() end
end

runtime.expose("fuelled_fixtures", function()
  local fx = storage.cl.fuelled_fixtures
  if not fx then return nil end
  local out = {
    tick = fx.tick,
    chests = {},
    flameout_joules = fx.flameout_joules,
    flameout_first_poll = fx.flameout_first_poll,
  }
  for key, f in pairs(fx.chests) do
    local rec = runtime.get(f.entity)
    out.chests[key] = {
      unit_number = f.unit_number,
      energy_at_arm = f.energy,
      energy_now = rec and fuel_energy(rec:energy_entity().burner) or nil,
      burning = rec and rec:energy_entity().burner.currently_burning ~= nil,
    }
  end
  return out
end)
runtime.expose("fuelled_arm_fixtures", function() arm_fixtures() return true end)
runtime.expose("fuelled_poll", function(unit_number)
  local rec = storage.cl.records[unit_number]
  if rec then poll(rec) end
end)
runtime.expose("fuelled_fuel_energy", function(unit_number)
  local rec = storage.cl.records[unit_number]
  return rec and fuel_energy(rec:energy_entity().burner) or nil
end)

-- ---- handlers ----------------------------------------------------------------

return {
  on_created = function(rec, ctx)
    rec.data.power_log = rec.data.power_log or {}
    -- The clone copied the source's data; forcing the gate write keeps the copy's
    -- reactor in step even if clone() did not carry disabled_by_script.
    rec.data.asleep = nil
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
    if type(extra) == "table" and extra.fuel_plan then request_fuel(rec, extra.fuel_plan) end
  end,
}
