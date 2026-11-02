-- cl-seep-derrick: the native shell does all the fluid work; this script only adds
-- what the composed type would: the depletion counter per cycle and the SPEC 1.5
-- condition status the shell cannot show on its own.

local runtime = require("scripts.runtime")

local NAME = "cl-seep-derrick"
-- Polling runs only while a condition fails on an idle shell, so a working derrick
-- costs no Lua between cycles.
local CONDITION_POLL = 60

local function refresh_condition(rec)
  local failing = rec:check_conditions()
  -- The shell consumes ingredients when a cycle starts, so a running cycle with an
  -- emptied input box is not starved yet.
  if failing and not rec.entity.is_crafting() then
    rec:set_status(failing.status, {diode = failing.diode})
    rec:schedule(CONDITION_POLL)
  else
    rec:set_status(nil)
    rec:unschedule()
  end
end

-- ---- timed fixture -------------------------------------------------------------
-- A suite runs inside one tick about 30 ticks after boot, and the harness boots a
-- pristine copy of the map every run, so nothing a suite builds can be watched over
-- a 120-tick cycle. The fixture is built at map creation instead and records
-- snapshots on its own schedule; the suite only reads them. scripts/fixtures.lua
-- holds game.speed up until c so it finishes before the suite starts.

-- The suite starts after roughly half a second of wall time, so the whole fixture
-- has to fit in a few hundred ticks even on a loaded box: a is after the first
-- cycle, b one cycle later, c one condition poll after the refill at b.
local SNAPS = {a = 135, b = 255, c = 320}
local ORIGIN = {x = -259.5, y = 40.5}

local function fixture_state() return storage.cl.seep_fixture end

local function snapshot(entity)
  if not entity.valid then return {valid = false} end
  local rec = runtime.get(entity)
  local crude = entity.get_fluid(2)
  local water = entity.get_fluid(1)
  local cs = entity.custom_status
  return {
    tick = game.tick,
    crude = crude and crude.amount or 0,
    water = water and water.amount or 0,
    status = entity.status,
    custom = cs and cs.label[1] or nil,
    custom_diode = cs and cs.diode or nil,
    progress = entity.crafting_progress,
    crafting = entity.is_crafting(),
    finished = entity.products_finished,
    cycles = rec and rec.data.cycles or 0,
    raised = rec and rec.data.raised or 0,
    depletion = rec and rec:get_setting("depletion") or -1,
  }
end

local function take(label)
  local st = fixture_state()
  if not st then return end
  st.snaps[label] = {}
  for role, entity in pairs(st.units) do st.snaps[label][role] = snapshot(entity) end
end

local function prepare_ground(surface)
  local area = {{ORIGIN.x - 6, ORIGIN.y - 6}, {ORIGIN.x + 20, ORIGIN.y + 12}}
  surface.request_to_generate_chunks({ORIGIN.x, ORIGIN.y}, 2)
  surface.force_generate_chunk_requests()
  local tiles = {}
  for x = math.floor(area[1][1]), math.ceil(area[2][1]) do
    for y = math.floor(area[1][2]), math.ceil(area[2][2]) do
      tiles[#tiles + 1] = {name = "refined-concrete", position = {x, y}}
    end
  end
  surface.set_tiles(tiles, true, true)
  for _, e in pairs(surface.find_entities_filtered{area = area}) do
    if e.valid and e.type ~= "character" then e.destroy() end
  end
end

local function water_pipe(surface, x, y)
  local pipe = surface.create_entity{name = "infinity-pipe", position = {x, y}, force = "player"}
  pipe.set_infinity_pipe_filter{name = "water", percentage = 1, mode = "exactly"}
  return pipe
end

local function derrick(surface, dx)
  local core = surface.create_entity{name = NAME, position = {ORIGIN.x + dx, ORIGIN.y}, force = "player"}
  -- Events raised from on_init are not delivered, so the parts are built directly.
  runtime.lifecycle.materialise(core, nil, "fixture")
  return core
end

local function arm_fixture()
  local surface = game.surfaces.nauvis
  prepare_ground(surface)
  local eei = surface.create_entity{name = "electric-energy-interface", position = {ORIGIN.x + 6.5, ORIGIN.y + 7.5}, force = "player"}
  eei.power_production = 1e7
  eei.electric_buffer_size = 1e8
  eei.energy = 1e8
  surface.create_entity{name = "substation", position = {ORIGIN.x + 6.5, ORIGIN.y + 4.5}, force = "player"}

  local units = {flow = derrick(surface, 0), starve = derrick(surface, 6), blocked = derrick(surface, 12)}
  water_pipe(surface, ORIGIN.x, ORIGIN.y - 2)
  water_pipe(surface, ORIGIN.x + 12, ORIGIN.y - 2)
  -- One cycle's worth plus change: an idle shell holding two products' worth of
  -- output reports full_output ahead of the missing ingredient.
  units.starve.set_fluid(1, {name = "water", amount = 15})
  units.blocked.set_fluid(2, {name = "crude-oil", amount = 950})

  local by_unit = {}
  for role, e in pairs(units) do by_unit[e.unit_number] = role end
  storage.cl.seep_fixture = {
    armed_at = game.tick, units = units, by_unit = by_unit, snaps = {}, actions = {},
    done_at = game.tick + SNAPS.c,
  }
  for label, delay in pairs(SNAPS) do runtime.scheduler.schedule("seep_fixture_" .. label, game.tick + delay) end
  runtime.fixtures.hold_until(game.tick + SNAPS.c)
  return storage.cl.seep_fixture
end

runtime.scheduler.on_named("seep_fixture_a", function() take("a") end)
runtime.scheduler.on_named("seep_fixture_b", function()
  take("b")
  local st = fixture_state()
  if not st then return end
  st.units.starve.set_fluid(1, {name = "water", amount = 1000})
  local removed = st.units.blocked.remove_fluid(2, 500)
  st.actions.removed = removed and removed.amount or 0
end)
runtime.scheduler.on_named("seep_fixture_c", function()
  take("c")
end)

runtime.init_hooks[#runtime.init_hooks + 1] = function()
  if not storage.cl.seep_fixture then arm_fixture() end
end

-- Counts the opt-in cycle_finished event on fixture derricks only, so the bench
-- cell measures the entity script without this test hook.
runtime.subscribe(runtime.defs.events[NAME].cycle_finished, function(event)
  local st = storage.cl.seep_fixture
  if not (st and event.unit_number and st.by_unit[event.unit_number]) then return end
  local rec = storage.cl.records[event.unit_number]
  if rec then rec.data.raised = (rec.data.raised or 0) + 1 end
end)

runtime.expose("seep_fixture", function() return storage.cl.seep_fixture end)
runtime.expose("seep_arm_fixture", function()
  local old = storage.cl.seep_fixture
  if old then
    for _, e in pairs(old.units) do
      if e.valid then e.destroy{raise_destroy = true} end
    end
  end
  storage.cl.seep_fixture = nil
  return arm_fixture()
end)

return {
  on_created = function(rec)
    refresh_condition(rec)
  end,
  on_tick = function(rec)
    refresh_condition(rec)
  end,
  on_cycle_finished = function(rec)
    rec.data.cycles = (rec.data.cycles or 0) + 1
    rec:set_setting("depletion", rec:get_setting("depletion") + 1)
    refresh_condition(rec)
  end,
}
