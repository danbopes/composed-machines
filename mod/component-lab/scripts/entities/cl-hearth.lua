-- cl-hearth: runtime. The hidden reactor burns whenever it holds fuel, whether or
-- not the shell crafts; the shell runs on void, so this pass is what stops it
-- crafting without fuel. It runs every POLL ticks, and when the reactor is on its
-- last item it is brought forward to the tick that item burns out, so a flame-out
-- stops the shell on time. Fuel taken out from outside (proxy, script) between
-- passes is only seen at the next pass: the KNOWN-LIMIT in the suite.

local util = require("util")
local runtime = require("scripts.runtime")

local NAME = "cl-hearth"
-- TEST-ENTITIES-2.md section 1 sets the pass interval the emulation is measured at.
local POLL = 20

local burn_per_tick = nil
local function fuel_per_tick()
  if not burn_per_tick then
    local reactor = prototypes.entity[NAME .. "-burner"]
    burn_per_tick = reactor.get_max_energy_usage() / reactor.burner_prototype.effectivity
  end
  return burn_per_tick
end

local function next_delay(burner)
  if burner.inventory.is_empty() and burner.remaining_burning_fuel > 0 then
    local ticks = math.ceil(burner.remaining_burning_fuel / fuel_per_tick())
    if ticks < POLL then return math.max(1, ticks) end
  end
  return POLL
end

local function record_transition(rec, powered)
  local log = rec.data.power_log
  local shell = rec.entity
  log[#log + 1] = {tick = game.tick, powered = powered, progress = shell.crafting_progress,
    finished = shell.products_finished}
  -- Kept for the suite only; bounded so a long-lived hearth cannot grow storage.
  if #log > 8 then table.remove(log, 1) end
end

local function poll(rec, quiet)
  local reactor = rec:energy_entity()
  if not (reactor and reactor.valid and rec.entity.valid) then return POLL end
  local powered = rec:has_fuel()
  if rec.data.powered ~= powered then
    local first = rec.data.powered == nil
    rec.data.powered = powered
    rec.entity.disabled_by_script = not powered
    if not (quiet or first) then
      record_transition(rec, powered)
      rec:raise("power_state_changed", {powered = powered})
    end
  end
  -- Fuelled, the shell's own status (working, no ingredients, output full) is
  -- the native one; only the missing burner needs saying.
  if powered then rec:set_status(nil) else rec:set_status("no_fuel") end
  return next_delay(reactor.burner)
end

local function fuel_energy(burner)
  local total = burner.remaining_burning_fuel
  local stack = burner.inventory[1]
  if stack.valid_for_read then total = total + stack.count * stack.prototype.fuel_value end
  return total
end

-- ---- real-tick fixtures ------------------------------------------------------
-- A suite runs inside one tick, so burning, crafting and flame-out are observed
-- on hearths built at on_init (re-armed by the suite for the next run).
--   idle:     coal, no ore. Burns at 90 kW and crafts nothing.
--   working:  coal and ore. Burns at the same 90 kW and makes plates.
--   flameout: ore and FLAMEOUT_TICKS of fuel already burning, nothing waiting.
--             Must stop on the tick it burns out, then REFUEL_AT a coal arrives.
--   fed:      nothing inside; burner inserters bring ore into the shell and coal
--             through the fuel door, and take plates out of the shell.

local FIXTURE_ORIGIN = {-520, 420}
local FLAMEOUT_TICKS = 30
local REFUEL_AT = 200
local SNAP_AT = 600

local function fixture_state() return storage.cl.hearth_fixture end

local function snapshot()
  local fx = fixture_state()
  if not fx then return end
  fx.snap = {tick = game.tick, units = {}}
  for role, e in pairs(fx.entities) do
    local rec = e.valid and runtime.get(e)
    if rec then
      local reactor = rec:energy_entity()
      fx.snap.units[role] = {
        energy = fuel_energy(reactor.burner),
        coal = reactor.burner.inventory.get_item_count("coal"),
        plates = e.get_inventory(defines.inventory.crafter_output).get_item_count("iron-plate"),
        finished = e.products_finished,
        status = e.status,
        custom = rec.status,
        disabled = e.disabled_by_script,
        log = util.table.deepcopy(rec.data.power_log),
      }
    end
  end
  local x = fx.extras
  fx.snap.fed = {
    ore_left = x.ore_chest.valid and x.ore_chest.get_item_count("iron-ore"),
    coal_left = x.coal_chest.valid and x.coal_chest.get_item_count("coal"),
    plates_out = x.out_chest.valid and x.out_chest.get_item_count("iron-plate"),
    coal_target = x.coal_inserter.valid and x.coal_inserter.drop_target and x.coal_inserter.drop_target.name,
  }
end

local function arm_fixture()
  local old = fixture_state()
  if old then
    for _, e in pairs(old.entities) do
      if e.valid then e.destroy{raise_destroy = true} end
    end
    for _, e in pairs(old.extras or {}) do
      if e.valid then e.destroy() end
    end
  end
  local surface = game.surfaces.nauvis
  surface.request_to_generate_chunks(FIXTURE_ORIGIN, 1)
  surface.force_generate_chunk_requests()
  local area = {{FIXTURE_ORIGIN[1] - 3, FIXTURE_ORIGIN[2] - 3}, {FIXTURE_ORIGIN[1] + 19, FIXTURE_ORIGIN[2] + 3}}
  for _, e in pairs(surface.find_entities_filtered{area = area}) do
    if e.valid and e.type ~= "character" and not runtime.get(e) then e.destroy() end
  end
  local tiles = {}
  for x = area[1][1], area[2][1] do
    for y = area[1][2], area[2][2] do tiles[#tiles + 1] = {name = "refined-concrete", position = {x, y}} end
  end
  surface.set_tiles(tiles, true, true)

  local function place(dx, ore, coal)
    local core = surface.create_entity{name = NAME, position = {FIXTURE_ORIGIN[1] + dx, FIXTURE_ORIGIN[2]},
      force = "player"}
    -- Events raised from on_init are not delivered, so build the parts directly.
    local rec = runtime.lifecycle.materialise(core, nil, "fixture")
    if ore then core.get_inventory(defines.inventory.crafter_input).insert{name = "iron-ore", count = ore} end
    if coal then rec:fuel_inventory().insert{name = "coal", count = coal} end
    return rec
  end
  local idle = place(0, nil, 2)
  local working = place(4, 50, 2)
  local flameout = place(8, 50, nil)
  local fed = place(14, nil, nil)
  local fx0, fy0 = fed.entity.position.x, fed.entity.position.y
  local function put(name, x, y, opts)
    local e = surface.create_entity{name = name, position = {fx0 + x, fy0 + y}, force = "player",
      direction = opts and opts.direction}
    if e.type == "inserter" then e.get_fuel_inventory().insert{name = "coal", count = 5} end
    if opts and opts.items then e.insert(opts.items) end
    return e
  end
  local west = defines.direction.west
  local extras = {
    ore_chest = put("iron-chest", -2.5, -0.5, {items = {name = "iron-ore", count = 20}}),
    ore_inserter = put("burner-inserter", -1.5, -0.5, {direction = west}),
    coal_chest = put("iron-chest", -2.5, 0.5, {items = {name = "coal", count = 10}}),
    coal_inserter = put("burner-inserter", -1.5, 0.5, {direction = west}),
    out_inserter = put("burner-inserter", 1.5, -0.5, {direction = west}),
    out_chest = put("iron-chest", 2.5, -0.5),
  }
  local burner = flameout:energy_entity().burner
  burner.currently_burning = "coal"
  burner.remaining_burning_fuel = FLAMEOUT_TICKS * fuel_per_tick()

  local entities = {idle = idle.entity, working = working.entity, flameout = flameout.entity, fed = fed.entity}
  local energy = {}
  for role, rec in pairs({idle = idle, working = working, flameout = flameout, fed = fed}) do
    rec:schedule(poll(rec, true))
    energy[role] = fuel_energy(rec:energy_entity().burner)
  end
  storage.cl.hearth_fixture = {
    tick = game.tick, entities = entities, extras = extras, energy = energy,
    flameout_ticks = FLAMEOUT_TICKS, refuel_at = game.tick + REFUEL_AT,
    snap_at = game.tick + SNAP_AT, poll = POLL, fuel_per_tick = fuel_per_tick(),
  }
  runtime.scheduler.schedule("cl_hearth_refuel", game.tick + REFUEL_AT)
  runtime.scheduler.schedule("cl_hearth_snap", game.tick + SNAP_AT)
  runtime.fixtures.hold_until(game.tick + SNAP_AT)
  return storage.cl.hearth_fixture
end

runtime.scheduler.on_named("cl_hearth_refuel", function()
  local fx = fixture_state()
  local e = fx and fx.entities.flameout
  local rec = e and e.valid and runtime.get(e)
  if rec then rec:fuel_inventory().insert{name = "coal", count = 1} end
end)
runtime.scheduler.on_named("cl_hearth_snap", snapshot)

runtime.init_hooks[#runtime.init_hooks + 1] = function()
  if not storage.cl.hearth_fixture then arm_fixture() end
end

runtime.expose("hearth_fixture", function() return storage.cl.hearth_fixture end)
runtime.expose("hearth_arm_fixture", function() arm_fixture() return true end)
runtime.expose("hearth_poll", function(unit_number)
  local rec = storage.cl.records[unit_number]
  if rec then return poll(rec) end
end)
runtime.expose("hearth_fuel_energy", function(unit_number)
  local rec = storage.cl.records[unit_number]
  return rec and fuel_energy(rec:energy_entity().burner) or nil
end)

-- ---- handlers ----------------------------------------------------------------

return {
  on_created = function(rec)
    rec.data.power_log = rec.data.power_log or {}
    -- A clone copies the source's data; forgetting the state forces the gate
    -- write so the copy's shell matches its own reactor.
    rec.data.powered = nil
    rec:schedule(poll(rec, true))
  end,
  on_tick = function(rec)
    rec:schedule(poll(rec))
  end,
}
