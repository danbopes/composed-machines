-- cl-slag-generator: the shell burns coal and turns water into stone natively;
-- this script is the v2 generation part. On each cycle_finished it puts the
-- cycle's energy product into the hidden producer EEI, which the network drains
-- at up to output_flow_limit. When the buffer cannot take a whole cycle the
-- remainder is held and the shell is disabled until it fits, which is as close
-- as the emulation gets to the native full_output block (see the suite's
-- KNOWN-LIMIT for what still differs). A running generator costs no Lua between
-- cycles; only a blocked one polls.

local util = require("util")
local runtime = require("scripts.runtime")

local NAME = "cl-slag-generator"
local BLOCKED_POLL = 30
-- Buffer arithmetic is in floating-point joules; anything below this is rounding.
local EPSILON = 1

local cycle_energy_cache
local function cycle_energy(rec)
  if not cycle_energy_cache then
    cycle_energy_cache = 0
    for _, product in ipairs(rec:spec().process.products) do
      if product.type == "energy" then cycle_energy_cache = cycle_energy_cache + util.parse_energy(product.amount) end
    end
  end
  return cycle_energy_cache
end

-- Pushes held energy into the buffer; true once nothing is held.
local function flush(rec)
  local pending = rec.data.pending
  if not pending then return true end
  pending = pending - rec:add_output_energy(pending)
  if pending < EPSILON then
    rec.data.pending = nil
    return true
  end
  rec.data.pending = pending
  return false
end

local function block(rec)
  rec.entity.disabled_by_script = true
  rec:set_status("full_output")
  rec:schedule(BLOCKED_POLL)
end

local function unblock(rec)
  rec.entity.disabled_by_script = false
  rec:set_status(nil)
  rec:unschedule()
end

local handlers = {
  on_created = function(rec, ctx)
    -- A clone copies the held energy in rec.data; make sure it stays blocked
    -- and keeps polling under its own unit number.
    if ctx.cause == "clone" and rec.data.pending then block(rec) end
  end,

  on_cycle_finished = function(rec)
    local energy = cycle_energy(rec)
    rec.data.cycles = (rec.data.cycles or 0) + 1
    rec.data.produced = (rec.data.produced or 0) + energy
    rec.data.pending = (rec.data.pending or 0) + energy
    if not flush(rec) then block(rec) end
  end,

  on_tick = function(rec)
    if flush(rec) then unblock(rec) else rec:schedule(BLOCKED_POLL) end
  end,
}

-- ---- timed fixture -------------------------------------------------------------
-- A suite runs inside one tick, so behaviour over cycles is recorded by a fixture
-- built at map creation; the suite only reads the snapshots. Three generators,
-- each on its own island (substations 40 tiles apart never link):
--   run   water + coal + a sink EEI on the same network: 10 cycles of delivery
--   dry   coal, no water: fluid_ingredient_shortage, nothing produced
--   full  water + coal, no network at all: the buffer fills and the shell blocks;
--         the buffer is then emptied by script to show the block release

local ORIGIN = {x = -800.5, y = 1760.5}
local SPACING = 40
local TEN_CYCLES_SETTLE = 200
local SNAPS = {dry = 120, blocked = 1100, released = 1150, resumed = 1400}
local DONE_AT = 2750

local function fixture_state() return storage.cl.slag_fixture end

local function snapshot(role, entity)
  if not entity.valid then return {valid = false} end
  local rec = runtime.get(entity)
  local generator = rec and rec:part("generator", "output")
  local water = entity.get_fluid(1)
  local cs = entity.custom_status
  local out = entity.get_output_inventory()
  local st = fixture_state()
  return {
    tick = game.tick,
    status = entity.status,
    custom = cs and cs.label[1] or nil,
    disabled = entity.disabled_by_script,
    progress = entity.crafting_progress,
    crafting = entity.is_crafting(),
    finished = entity.products_finished,
    water = water and water.amount or 0,
    stone = out and out.get_item_count("stone") or 0,
    coal = entity.get_fuel_inventory().get_item_count("coal"),
    buffer = generator and generator.energy or -1,
    buffer_size = generator and generator.electric_buffer_size or -1,
    cycles = rec and rec.data.cycles or 0,
    produced = rec and rec.data.produced or 0,
    pending = rec and rec.data.pending or 0,
    sink = st.sinks[role] and st.sinks[role].valid and st.sinks[role].energy or nil,
  }
end

local function take(label)
  local st = fixture_state()
  if not st then return end
  st.snaps[label] = {}
  for role, entity in pairs(st.units) do st.snaps[label][role] = snapshot(role, entity) end
end

local function prepare_ground(surface)
  local area = {{ORIGIN.x - 10, ORIGIN.y - 10}, {ORIGIN.x + 2 * SPACING + 12, ORIGIN.y + 10}}
  surface.request_to_generate_chunks({ORIGIN.x + SPACING, ORIGIN.y}, 3)
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

local function generator_at(surface, x, opts)
  local core = surface.create_entity{name = NAME, position = {x, ORIGIN.y}, force = "player"}
  -- Events raised from on_init are not delivered, so the parts are built directly.
  runtime.lifecycle.materialise(core, nil, "fixture")
  core.get_fuel_inventory().insert{name = "coal", count = 20}
  if opts.water then
    local pipe = surface.create_entity{name = "infinity-pipe", position = {x, ORIGIN.y - 2}, force = "player"}
    pipe.set_infinity_pipe_filter{name = "water", percentage = 1, mode = "exactly"}
  end
  local sink
  if opts.sink then
    surface.create_entity{name = "substation", position = {x + 3, ORIGIN.y}, force = "player"}
    -- A drawless, producing-nothing interface with a large empty buffer charges
    -- from any surplus, so its energy is exactly what the network handed over.
    sink = surface.create_entity{name = "electric-energy-interface", position = {x + 6, ORIGIN.y}, force = "player"}
    sink.power_production = 0
    sink.power_usage = 0
    sink.electric_buffer_size = 1e9
    sink.energy = 0
  end
  return core, sink
end

local function arm_fixture()
  local surface = game.surfaces.nauvis
  prepare_ground(surface)
  local run, sink = generator_at(surface, ORIGIN.x, {water = true, sink = true})
  local dry = generator_at(surface, ORIGIN.x + SPACING, {sink = true})
  local full = generator_at(surface, ORIGIN.x + 2 * SPACING, {water = true})
  local by_unit = {[run.unit_number] = "run", [dry.unit_number] = "dry", [full.unit_number] = "full"}
  storage.cl.slag_fixture = {
    armed_at = game.tick, units = {run = run, dry = dry, full = full}, by_unit = by_unit,
    sinks = {run = sink}, snaps = {}, actions = {}, done_at = game.tick + DONE_AT,
  }
  for label, delay in pairs(SNAPS) do runtime.scheduler.schedule("slag_fixture_" .. label, game.tick + delay) end
  runtime.fixtures.hold_until(game.tick + DONE_AT)
end

for label in pairs(SNAPS) do
  runtime.scheduler.on_named("slag_fixture_" .. label, function()
    take(label)
    local st = fixture_state()
    if label == "blocked" and st then
      local rec = runtime.get(st.units.full)
      local generator = rec and rec:part("generator", "output")
      if generator then
        st.actions.drained = generator.energy
        generator.energy = 0
      end
    end
  end)
end

runtime.scheduler.on_named("slag_fixture_ten", function() take("ten") end)

-- Polls the run generator's cycle count from the fixture side, so the entity's
-- own handlers carry no test hook into the bench cells.
local WATCH = "slag_fixture_watch"
runtime.scheduler.on_named(WATCH, function(tick)
  local st = fixture_state()
  if not st then return end
  local rec = st.units.run.valid and runtime.get(st.units.run)
  if rec and (rec.data.cycles or 0) >= 10 then
    st.actions.tenth_cycle_seen = tick
    runtime.scheduler.schedule("slag_fixture_ten", tick + TEN_CYCLES_SETTLE)
  elseif tick < st.done_at then
    runtime.scheduler.schedule(WATCH, tick + 1)
  end
end)

runtime.init_hooks[#runtime.init_hooks + 1] = function()
  if not storage.cl.slag_fixture then
    arm_fixture()
    runtime.scheduler.schedule(WATCH, game.tick + 1)
  end
end

runtime.expose("slag_fixture", function() return storage.cl.slag_fixture end)

return handlers
