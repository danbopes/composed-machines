-- cl-tuned-furnace: the shell crafts natively; this script is the entity-side pull
-- of V2-PARTS 1.3. Every PASS ticks it reads signal-R, writes the `rate` setting
-- and turns the setting into the shell's native local_effect (2.1.13), so no
-- prototype per speed and no hidden beacon. The enable condition needs nothing:
-- the shell's own GenericOnOffControlBehavior already gives
-- disabled_by_control_behavior.

local runtime = require("scripts.runtime")

local NAME = "cl-tuned-furnace"
local PASS = 30
local SIGNAL = "signal-R"

local function speed_for(rate) return rate / 10 - 1 end

-- Like the inserter's stack-size override, a missing or non-positive signal
-- leaves the configured setting in charge instead of forcing the minimum.
local function apply(rec)
  local signal = rec:read_signal(SIGNAL)
  if signal > 0 then rec:set_setting("rate", signal) end
  local rate = rec:get_setting("rate")
  -- Compared as the integer setting: rate / 10 - 1 is not exact in binary for
  -- most rates, and the engine may store the effect at lower precision.
  if rec.data.applied ~= rate then
    rec.entity.local_effect = {speed = speed_for(rate)}
    rec.data.applied = rate
  end
end

local function pass(rec)
  apply(rec)
  rec:schedule_phase(PASS)
end

-- ---- beacon-tuned-furnace bench column -----------------------------------------
-- The pre-2.1.13 way to give one machine a runtime speed: a beacon beside it and
-- one shared on_nth_tick-style walk that reads the signal and swaps modules. The
-- shells in that column are placed without raise_built, so they have no record
-- and none of the pass above runs for them.

local BEACON_POLL = "cl-tuned-furnace-beacon-poll"
local MODULE = "speed-module-3"

local function beacon_modules_for(rate)
  local per_module = prototypes.item[MODULE].module_effects.speed
    * prototypes.entity["beacon"].distribution_effectivity
  local n = math.floor(math.max(speed_for(rate), 0) / per_module + 0.5)
  return math.min(n, 2)
end

runtime.scheduler.on_named(BEACON_POLL, function(tick)
  local cells = storage.cl.tuned_beacon_poll
  if not cells then return end
  local red, green = defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green
  local filter = {type = "virtual", name = SIGNAL, quality = "normal"}
  -- A bench rebuild deletes the surface under the cells; drop them rather than
  -- walking dead references forever.
  local live = {}
  for _, cell in pairs(cells) do
    if cell.furnace.valid and cell.beacon.valid then
      live[#live + 1] = cell
      local signal = cell.furnace.get_signal(filter, red, green) or 0
      local rate = signal > 0 and math.min(math.max(signal, 1), 40) or 10
      if cell.rate ~= rate then
        cell.rate = rate
        local inv = cell.beacon.get_inventory(defines.inventory.beacon_modules)
        inv.clear()
        local n = beacon_modules_for(rate)
        if n > 0 then inv.insert{name = MODULE, count = n} end
      end
    end
  end
  storage.cl.tuned_beacon_poll = live
  if #live > 0 then runtime.scheduler.schedule(BEACON_POLL, tick + PASS) end
end)

runtime.expose("tuned_furnace_beacon_add", function(furnace, beacon)
  storage.cl.tuned_beacon_poll = storage.cl.tuned_beacon_poll or {}
  table.insert(storage.cl.tuned_beacon_poll, {furnace = furnace, beacon = beacon})
  if #storage.cl.tuned_beacon_poll == 1 then runtime.scheduler.schedule(BEACON_POLL, game.tick + 1) end
end)

-- ---- timed fixture -------------------------------------------------------------
-- A suite runs inside one tick, so speed over 1200 ticks, the disabled status and
-- a pulsed signal are watched by machines built at map creation; the suite only
-- reads the snapshots. a: one pass after every wire is live. b: 1200 ticks later.

local MEASURE = 1200
local SNAP_A = 60
local ORIGIN = {x = -1000.5, y = 1480.5}
local ORE = 30

local function fixture_state() return storage.cl.tuned_fixture end

local function snapshot(entity)
  if not entity.valid then return {valid = false} end
  local rec = runtime.get(entity)
  local le = entity.local_effect
  return {
    tick = game.tick,
    finished = entity.products_finished,
    speed = le and le.speed or 0,
    crafting_speed = entity.crafting_speed,
    rate = rec and rec:get_setting("rate") or -1,
    status = entity.status,
    crafting = entity.is_crafting(),
    progress = entity.crafting_progress,
    ore = entity.get_item_count("iron-ore"),
    plates = entity.get_item_count("iron-plate"),
  }
end

local function take(label, roles)
  local st = fixture_state()
  if not st then return end
  st.snaps[label] = st.snaps[label] or {}
  for role, entity in pairs(st.units) do
    if not roles or roles[role] then st.snaps[label][role] = snapshot(entity) end
  end
end

local function prepare_ground(surface)
  local area = {{ORIGIN.x - 8, ORIGIN.y - 8}, {ORIGIN.x + 44, ORIGIN.y + 10}}
  surface.request_to_generate_chunks({ORIGIN.x + 18, ORIGIN.y}, 2)
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

local function signal_source(surface, furnace, value)
  local cc = surface.create_entity{name = "constant-combinator", force = "player",
    position = {furnace.position.x - 2.5, furnace.position.y - 1}}
  local cb = cc.get_or_create_control_behavior()
  local section = cb.get_section(1) or cb.add_section()
  section.filters = {{value = {type = "virtual", name = SIGNAL, quality = "normal", comparator = "="}, min = value}}
  local red = defines.wire_connector_id.circuit_red
  cc.get_wire_connector(red, true).connect_to(furnace.get_wire_connector(red, true))
  return cc, cb
end

local function furnace(surface, dx, ore)
  local core = surface.create_entity{name = NAME, position = {ORIGIN.x + dx, ORIGIN.y}, force = "player"}
  -- Events raised from on_init are not delivered, so the parts are built directly.
  runtime.lifecycle.materialise(core, nil, "fixture")
  if ore > 0 then core.insert{name = "iron-ore", count = ore} end
  return core
end

local function arm_fixture()
  local surface = game.surfaces.nauvis
  prepare_ground(surface)
  local eei = surface.create_entity{name = "electric-energy-interface", force = "player",
    position = {ORIGIN.x + 12, ORIGIN.y + 6}}
  eei.power_production = 1e8
  eei.electric_buffer_size = 1e9
  eei.energy = 1e9
  surface.create_entity{name = "substation", position = {ORIGIN.x + 8, ORIGIN.y + 4}, force = "player"}
  surface.create_entity{name = "substation", position = {ORIGIN.x + 26, ORIGIN.y + 4}, force = "player"}

  local units = {
    default = furnace(surface, 0, ORE),
    fast = furnace(surface, 8, ORE),
    slow = furnace(surface, 16, ORE),
    off = furnace(surface, 24, ORE),
    pulse = furnace(surface, 32, 0),
  }
  signal_source(surface, units.fast, 30)
  signal_source(surface, units.slow, 5)
  -- signal-R is on the wire, but the enable condition reads signal-E, which is absent.
  signal_source(surface, units.off, 30)
  local ocb = units.off.get_or_create_control_behavior()
  ocb.circuit_enable_disable = true
  ocb.circuit_condition = {first_signal = {type = "virtual", name = "signal-E", quality = "normal"}, comparator = ">", constant = 0}
  local _, pcb = signal_source(surface, units.pulse, 30)
  pcb.enabled = false

  local t0 = game.tick
  -- The pulse starts two ticks after one of the pulse unit's passes and is gone
  -- ten ticks later, long before the next one; ore arrives mid-pulse, so a native
  -- entity reading the signal at cycle start would run that cycle at rate 30.
  local u = units.pulse.unit_number
  local after = t0 + SNAP_A + 1
  local p = after + (u - after) % PASS
  local st = {
    armed_at = t0, units = units, snaps = {}, pulse_cb = pcb,
    a = t0 + SNAP_A, b = t0 + SNAP_A + MEASURE,
    pulse = {pass = p, on = p + 2, feed = p + 4, off = p + 12, snap = p + 104},
  }
  st.done_at = math.max(st.b, st.pulse.snap)
  storage.cl.tuned_fixture = st
  local sched = runtime.scheduler.schedule
  sched("tuned_fixture_a", st.a)
  sched("tuned_fixture_b", st.b)
  sched("tuned_fixture_pulse_on", st.pulse.on)
  sched("tuned_fixture_pulse_feed", st.pulse.feed)
  sched("tuned_fixture_pulse_off", st.pulse.off)
  sched("tuned_fixture_pulse_snap", st.pulse.snap)
  runtime.fixtures.hold_until(st.done_at)
  return st
end

local NOT_PULSE = {default = true, fast = true, slow = true, off = true}
runtime.scheduler.on_named("tuned_fixture_a", function() take("a", NOT_PULSE) end)
runtime.scheduler.on_named("tuned_fixture_b", function() take("b", NOT_PULSE) end)
runtime.scheduler.on_named("tuned_fixture_pulse_on", function()
  local st = fixture_state()
  if st and st.pulse_cb.valid then st.pulse_cb.enabled = true end
end)
runtime.scheduler.on_named("tuned_fixture_pulse_feed", function()
  local st = fixture_state()
  if not st then return end
  take("pulse_feed", {pulse = true})
  if st.units.pulse.valid then st.units.pulse.insert{name = "iron-ore", count = 1} end
end)
runtime.scheduler.on_named("tuned_fixture_pulse_off", function()
  local st = fixture_state()
  if not st then return end
  take("pulse_peak", {pulse = true})
  if st.pulse_cb.valid then st.pulse_cb.enabled = false end
end)
runtime.scheduler.on_named("tuned_fixture_pulse_snap", function() take("pulse_end", {pulse = true}) end)

runtime.init_hooks[#runtime.init_hooks + 1] = function()
  if not storage.cl.tuned_fixture then arm_fixture() end
end

runtime.expose("tuned_fixture", function()
  local st = storage.cl.tuned_fixture
  if not st then return nil end
  return {armed_at = st.armed_at, a = st.a, b = st.b, pulse = st.pulse, done_at = st.done_at, snaps = st.snaps}
end)

-- ---- handlers ------------------------------------------------------------------

return {
  on_created = function(rec)
    -- A clone or blueprint brings the setting but not the applied effect.
    rec.data.applied = nil
    pass(rec)
  end,
  on_tick = function(rec)
    pass(rec)
  end,
  on_pasted = function(to)
    to.data.applied = nil
    apply(to)
  end,
  on_gui = function(rec, _, frame)
    local rate = rec:get_setting("rate")
    frame.add{type = "label", caption = {"", "rate ", rate, " (", SIGNAL, "), speed ", string.format("%+.0f%%", speed_for(rate) * 100)}}
  end,
}
