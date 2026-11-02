-- cl-cold-box: SPEC 1.3 spoil modifier (m = 8, requires_power) on a container,
-- emulated by a once-per-interval pass.
--
-- The native part stamps on transfer (remaining * m in, remaining / m out).
-- Lua cannot do that: LuaItemStack.spoil_tick refuses any value beyond
-- now + the item's spoil ticks, so a stamped fresh stack is unrepresentable.
-- Instead stacks stay on the 1x clock and each powered pass pushes them back
-- by the interval's worth of slowed ageing, elapsed * (1 - 1/m). The spoil
-- tick is therefore always the honest one; what a removal the mod cannot see
-- loses is only the credit for the part of the interval since the last pass.

local runtime = require("scripts.runtime")
local scheduler = require("scripts.scheduler")
local defs = require("scripts.defs")

local INVENTORY = "cold"

local function params(rec)
  local spec = rec:spec()
  return spec.inventories[1].spoil_modifier.multiplier, spec.tick_interval or 1
end

-- Pushes one stack back by `credit` ticks, never past full freshness (the
-- engine rejects that), and never on a stack that has already spoiled.
local function credit_stack(stack, credit, now)
  if credit <= 0 or not stack.valid_for_read then return end
  local tick = stack.spoil_tick
  if tick <= now then return end
  local cap = now + prototypes.item[stack.name].get_spoil_ticks(stack.quality)
  local out = tick + credit
  if out > cap then out = cap end
  stack.spoil_tick = out
end

local function credit_for(rec, now)
  local data = rec.data
  if not data.powered then return 0 end
  local m = params(rec)
  return math.floor((now - data.last_pass) * (1 - 1 / m))
end

local function credit_inventory(inv, credit, now)
  if credit <= 0 or not inv then return end
  for i = 1, #inv do
    local stack = inv[i]
    if stack.valid_for_read and stack.spoil_tick > 0 then credit_stack(stack, credit, now) end
  end
end

local function pass(rec)
  local now = game.tick
  local data = rec.data
  local inv = rec:inventory(INVENTORY)
  local empty = inv.is_empty()
  -- activity = "inventory_not_empty": a disabled EEI neither draws nor drains.
  rec:energy_entity().disabled_by_script = empty
  local failing = rec:check_conditions()
  local powered = failing == nil
  if data.powered ~= powered then
    -- A full buffer now means the network fed it through the whole interval;
    -- an empty one means it did not, so a transition interval gets no credit.
    data.powered = false
    rec:raise("power_state_changed", {powered = powered})
  end
  if not empty then credit_inventory(inv, credit_for(rec, now), now) end
  data.powered = powered
  data.last_pass = now
  if failing then
    rec:set_status(failing.status, {diode = failing.diode})
  else
    rec:set_status(empty and "normal" or "working")
  end
end

-- Credit for the part of the interval since the last pass, given to stacks
-- leaving through a path the mod sees. Stacks are already on the 1x clock, so
-- this is the whole of what the native unstamp would do here.
local function settle(rec, inv)
  local now = game.tick
  credit_inventory(inv, credit_for(rec, now), now)
end

local handlers = {}

function handlers.on_created(rec)
  local data = rec.data
  data.last_pass = data.last_pass or game.tick
  rec:schedule_phase()
end

function handlers.on_tick(rec, tick)
  pass(rec)
  rec:schedule_phase(nil, tick)
end

-- Settles in place while the box still holds its stacks; powered = false
-- then stops on_removed from crediting them a second time.
function handlers.before_mine(rec)
  settle(rec, rec:inventory(INVENTORY))
  rec.data.powered = false
end

function handlers.on_removed(rec)
  if rec.entity.valid then settle(rec, rec:inventory(INVENTORY)) end
  rec.data.powered = false
end

-- The script removal path the mod can see. Moves up to `count` of `item` into
-- `destination`, settled; returns how many moved.
local function take(unit_number, destination, item, count)
  local rec = storage.cl.records[unit_number]
  if not rec then error("no composed machine with unit_number " .. tostring(unit_number)) end
  local now = game.tick
  local credit = credit_for(rec, now)
  local inv = rec:inventory(INVENTORY)
  local scratch = game.create_inventory(1)
  local tmp = scratch[1]
  local moved = 0
  for i = 1, #inv do
    if moved >= count then break end
    local stack = inv[i]
    if stack.valid_for_read and stack.name == item then
      tmp.transfer_stack(stack, math.min(count - moved, stack.count))
      if tmp.spoil_tick > 0 then credit_stack(tmp, credit, now) end
      local n = destination.insert(tmp)
      moved = moved + n
      if n < tmp.count then
        tmp.count = tmp.count - n
        stack.transfer_stack(tmp)
      end
      tmp.clear()
    end
  end
  scratch.destroy()
  return moved
end

runtime.expose("cold_box_take", take)
runtime.expose("cold_box_pass", function(unit_number)
  local rec = storage.cl.records[unit_number]
  if rec then pass(rec) end
end)


-- ---- real-tick scenario for the suite ------------------------------------------
-- A suite runs inside one tick, and ageing, draining a buffer and an inserter
-- swing all need real ticks. So the fixtures are built at on_init (map
-- creation, tick 0) and a named driver passes the boxes at fixed ticks and
-- snapshots what it saw; the suite, which runs ~350 ticks later, reads the
-- snapshots. Driver-owned boxes are unscheduled so their credit is exact.

local SCENARIO = "cl-cold-box-scenario"
local ORIGIN = {x = -1600, y = -1600}
local STEPS = {5, 65, 125, 200, 205, 265}
local DRIVEN = {"a", "c", "b", "t", "m"}

local function snapshot_box(rec)
  local inv = rec:inventory(INVENTORY)
  local stack = inv[1]
  return {
    tick = stack.valid_for_read and stack.spoil_tick or 0,
    status = rec.status,
    diode = rec.entity.custom_status and rec.entity.custom_status.diode or nil,
    energy = rec:energy_entity().energy,
    disabled = rec:energy_entity().disabled_by_script,
    powered = rec.data.powered,
  }
end

local function build_scenario()
  local s = game.surfaces.nauvis
  local X, Y = ORIGIN.x, ORIGIN.y
  s.request_to_generate_chunks({X + 20, Y}, 2)
  s.force_generate_chunk_requests()
  -- Generated chunks may hold worms and nests, which would shoot the fixtures.
  local area = {{X - 96, Y - 96}, {X + 136, Y + 96}}
  for _, e in pairs(s.find_entities_filtered{area = area, force = "enemy"}) do e.destroy() end
  -- Fresh maps get a new seed, so the fixture ground is made buildable.
  local tiles = {}
  for x = X - 8, X + 48 do
    for y = Y - 8, Y + 8 do tiles[#tiles + 1] = {name = "grass-1", position = {x, y}} end
  end
  s.set_tiles(tiles)
  for _, e in pairs(s.find_entities_filtered{area = {{X - 8, Y - 8}, {X + 48, Y + 8}}}) do e.destroy() end
  local function place(name, x, y, extra)
    local spec = {name = name, position = {x, y}, force = "player"}
    for k, v in pairs(extra or {}) do spec[k] = v end
    local e = s.create_entity(spec)
    if not e then error("cl-cold-box scenario: could not place " .. name) end
    return e
  end
  local function box(x, y, fish)
    local core = place("cl-cold-box", x, y)
    -- Events raised during on_init are not delivered.
    local rec = runtime.lifecycle.materialise(core, nil, "scenario")
    if fish then core.get_inventory(defines.inventory.chest).insert{name = "raw-fish", count = fish} end
    return rec
  end

  local feed1 = place("electric-energy-interface", X - 2, Y - 1)
  feed1.electric_buffer_size = 1000000
  feed1.power_production = 100000
  feed1.energy = 1000000
  place("medium-electric-pole", X + 0.5, Y + 0.5)
  local recs = {
    a = box(X + 2.5, Y + 0.5, 10),
    s = box(X + 2.5, Y - 1.5, 10),
    c = box(X - 1.5, Y + 2.5, 1),
    t = box(X + 3.5, Y + 0.5, 10),
    m = box(X + 3.5, Y - 1.5, 5),
  }
  local inserter = place("fast-inserter", X - 0.5, Y + 2.5, {direction = defines.direction.east})
  if inserter.pickup_position.x > inserter.position.x then inserter.direction = defines.direction.west end
  inserter.disabled_by_script = true
  local chest = place("wooden-chest", X + 0.5, Y + 2.5)

  local X2 = X + 40
  local feed2 = place("electric-energy-interface", X2 - 2, Y - 1)
  feed2.power_production = 0
  feed2.electric_buffer_size = 1000000
  feed2.energy = 1000000
  place("medium-electric-pole", X2 + 0.5, Y + 0.5)
  recs.b = box(X2 + 2.5, Y + 0.5, nil)

  for _, k in ipairs(DRIVEN) do recs[k]:unschedule() end
  local units = {}
  for k, rec in pairs(recs) do units[k] = rec.unit_number end
  storage.cl.cold_box = {
    t0 = game.tick, units = units, feed1 = feed1, feed2 = feed2, inserter = inserter, chest = chest,
    snaps = {}, events = {},
  }
  for _, dt in ipairs(STEPS) do scheduler.schedule(SCENARIO, game.tick + dt) end
end

scheduler.on_named(SCENARIO, function(tick)
  local sc = storage.cl.cold_box
  if not sc then return end
  local dt = tick - sc.t0
  local recs = {}
  for k, u in pairs(sc.units) do recs[k] = storage.cl.records[u] end
  for _, k in ipairs(DRIVEN) do if recs[k] then pass(recs[k]) end end
  local snap = {tick = tick, feed2 = sc.feed2.energy}
  for k, rec in pairs(recs) do snap[k] = snapshot_box(rec) end
  local d = sc.chest.get_inventory(defines.inventory.chest)[1]
  snap.d = d.valid_for_read and d.spoil_tick or 0
  sc.snaps[dt] = snap
  if dt == 65 then
    sc.inserter.disabled_by_script = false
    recs.b.entity.get_inventory(defines.inventory.chest).insert{name = "raw-fish", count = 10}
  elseif dt == 125 then
    sc.feed1.power_production = 0
    sc.feed1.energy = 0
  elseif dt == 200 then
    sc.feed1.power_production = 100000
  end
end)

runtime.subscribe(defs.events["cl-cold-box"].power_state_changed, function(event)
  local sc = storage.cl and storage.cl.cold_box
  if sc then
    sc.events[#sc.events + 1] = {unit_number = event.unit_number, powered = event.powered, tick = event.tick}
  end
end)

runtime.init_hooks[#runtime.init_hooks + 1] = function()
  if not storage.cl.cold_box then build_scenario() end
end

runtime.expose("cold_box_scenario", function() return storage.cl.cold_box end)

return handlers
