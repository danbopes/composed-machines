-- cl-timed-converter: an S3 shell whose start and consumption belong to Lua
-- (TEST-ENTITIES.md section 5). The shell idles disabled_by_script, so it burns
-- no fuel and leaves the active list; a per-record poll watches the hidden input
-- (proxy insertion raises no event) and starts one cycle per item.

local NAME = "cl-timed-converter"
-- The native type would see an insertion at the inventory flush of the same
-- tick; ten ticks is the latency/cost trade TEST-ENTITIES.md specifies.
local POLL = 10

local RESULTS = {
  ["iron-ore"] = "iron-plate",
  ["copper-ore"] = "copper-plate",
  ["stone"] = "stone-brick",
  ["cl-tagged-sample"] = "cl-tagged-sample",
}

local function choose(inv)
  for i = 1, #inv do
    local stack = inv[i]
    if stack.valid_for_read and RESULTS[stack.name] then return i, stack end
  end
  return nil
end

local function fuelled(rec)
  local burner = rec.entity.burner
  return burner.remaining_burning_fuel > 0 or not burner.inventory.is_empty()
end

local function flush_pending(rec)
  local pending = rec.data.pending
  if not pending then return true end
  local moved = rec:inventory("output").insert(pending)
  if moved >= pending.count then
    rec.data.pending = nil
    return true
  end
  pending.count = pending.count - moved
  return false
end

local function try_start(rec)
  if not rec.entity.disabled_by_script then return end
  if not flush_pending(rec) then
    rec:set_status("full_output")
    return
  end
  local slot, stack = choose(rec:inventory("input"))
  if not slot then
    rec:set_status("waiting_for_script")
    return
  end
  local quality = stack.quality.name
  if not rec:inventory("output").can_insert{name = RESULTS[stack.name], quality = quality} then
    rec:set_status("full_output")
    return
  end
  if not fuelled(rec) then
    rec:set_status("no_fuel")
    return
  end
  -- start_cycle refuses while the record still reads no_fuel.
  if rec.status ~= "waiting_for_script" then rec:set_status("waiting_for_script") end
  rec.data.current = {slot = slot, name = stack.name, quality = quality, started = game.tick}
  if rec:start_cycle() then
    -- While the shell runs, the engine's own status (working, no fuel, low
    -- power) is the truth; a custom "working" would hide a mid-cycle fuel-out.
    rec:set_status(nil)
  else
    rec.data.current = nil
  end
end

local function find_stack(inv, current)
  local stack = inv[current.slot]
  if stack and stack.valid_for_read and stack.name == current.name and stack.quality.name == current.quality then
    return stack
  end
  for i = 1, #inv do
    stack = inv[i]
    if stack.valid_for_read and stack.name == current.name and stack.quality.name == current.quality then
      return stack
    end
  end
  return nil
end

local function derive_tags(tags)
  local seed = tags.seed or 0
  return {seed = seed, derived = seed * 3 + 1, generation = (tags.generation or 0) + 1}
end

local function finish(rec)
  local current = rec.data.current
  rec.data.current = nil
  if not current then return end
  -- The item may have been taken out mid-cycle; then the cycle yields nothing.
  local stack = find_stack(rec:inventory("input"), current)
  if not stack then return end
  local result = {name = RESULTS[current.name], quality = current.quality, count = 1}
  if stack.is_item_with_tags then result.tags = derive_tags(stack.tags) end
  if stack.count > 1 then stack.count = stack.count - 1 else stack.clear() end
  rec.data.cycles = (rec.data.cycles or 0) + 1
  rec.data.pending = result
  flush_pending(rec)
end

local function poll(rec)
  if rec:contents_changed("input") then rec:raise("inventory_changed", {inventory = "input"}) end
  try_start(rec)
end

local function return_pending(rec, mode, buffer)
  local pending = rec.data.pending
  if not pending then return end
  rec.data.pending = nil
  local moved = (mode == "mined" and buffer) and buffer.insert(pending) or 0
  if moved < pending.count and (mode ~= "destroyed") and rec.entity.valid then
    pending.count = pending.count - moved
    rec.entity.surface.spill_item_stack{position = rec.entity.position, stack = pending, force = rec.entity.force}
  end
end

local handlers = {
  on_created = function(rec, ctx)
    if ctx.cause ~= "clone" then rec:contents_changed("input") end
    rec:schedule(1)
  end,

  on_tick = function(rec)
    poll(rec)
    rec:schedule(POLL)
  end,

  on_cycle_finished = function(rec)
    finish(rec)
    try_start(rec)
  end,

  on_removed = return_pending,
}

-- ---- timed scenario, for the suite ---------------------------------------------
-- A suite runs inside one tick, but cycles take 300. The fixtures are therefore
-- built at map creation (on_init), observed by scheduled probes while the server
-- runs, and the suite only reads what was recorded. game.speed is raised until the
-- last probe so the record is complete by the time the harness calls the suite.

local runtime = require("scripts.runtime")
local scheduler = require("scripts.scheduler")
local defs = require("scripts.defs")

local PROBE = "cl_tc_probe"
local WATCH = "cl_tc_watch"
local ORIGIN = {x = 2000, y = -640}
local DONE_AT = 660

local function sc() return storage.cl.tc_scenario end

local function prepare_area(surface)
  local area = {{ORIGIN.x - 8, ORIGIN.y - 8}, {ORIGIN.x + 80, ORIGIN.y + 16}}
  surface.request_to_generate_chunks({ORIGIN.x + 36, ORIGIN.y}, 3)
  surface.force_generate_chunk_requests()
  for _, e in pairs(surface.find_entities_filtered{area = area}) do
    if e.type ~= "character" then e.destroy() end
  end
  local tiles = {}
  for x = area[1][1], area[2][1] do
    for y = area[1][2], area[2][2] do tiles[#tiles + 1] = {name = "refined-concrete", position = {x, y}} end
  end
  surface.set_tiles(tiles)
end

local function place(surface, slot, fuel)
  local core = surface.create_entity{
    name = NAME, position = {ORIGIN.x + slot * 10 + 0.5, ORIGIN.y + 0.5}, force = "player",
  }
  -- Events raised during on_init are not delivered, so build the parts directly.
  local rec = runtime.lifecycle.materialise(core, nil, "scenario")
  if fuel then rec:fuel_inventory().insert{name = "coal", count = fuel} end
  return rec
end

local function feeding_inserter(surface, rec)
  local x, y = rec.entity.position.x, rec.entity.position.y
  local chest = surface.create_entity{name = "iron-chest", position = {x - 3, y}, force = "player"}
  chest.insert{name = "iron-ore", count = 1}
  local inserter = surface.create_entity{name = "burner-inserter", position = {x - 2, y}, force = "player"}
  for _, dir in ipairs({defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west}) do
    inserter.direction = dir
    if inserter.drop_position.x > inserter.position.x + 0.5 then break end
  end
  inserter.get_fuel_inventory().insert{name = "coal", count = 5}
  return chest, inserter
end

local function burner_state(rec)
  local burner = rec.entity.burner
  return {fuel = burner.inventory.get_item_count(), remaining = burner.remaining_burning_fuel,
    burning = burner.currently_burning and burner.currently_burning.name.name or nil}
end

local actions = {}

actions[100] = function(s) s.progress[#s.progress + 1] = {tick = game.tick, value = s.entities.twice.crafting_progress} end
actions[200] = actions[100]
actions[290] = actions[100]
actions[300] = function(s) s.idle_after = burner_state(storage.cl.records[s.units.idle]) end

actions[150] = function(s)
  local source = s.entities.clone
  local surface = source.surface
  surface.clone_entities{entities = {source}, destination_offset = {0, 6}}
  local copy = surface.find_entity(NAME, {source.position.x, source.position.y + 6})
  s.entities.clone_copy = copy
  s.clone = {
    tick = game.tick,
    source_progress = source.crafting_progress,
    copy_progress = copy and copy.crafting_progress,
    copy_disabled = copy and copy.disabled_by_script,
    copy_unit = copy and copy.unit_number,
    copy_current = copy and storage.cl.records[copy.unit_number] and storage.cl.records[copy.unit_number].data.current
      and storage.cl.records[copy.unit_number].data.current.name,
  }
end

actions[DONE_AT] = function(s)
  s.done_tick = game.tick
end

scheduler.on_named(PROBE, function(tick)
  local s = sc()
  if not s then return end
  local fn = actions[tick - s.t0]
  if fn then fn(s) end
end)

scheduler.on_named(WATCH, function(tick)
  local s = sc()
  if not s or s.ore_arrived then return end
  local inv = storage.cl.records[s.units.inserter]:inventory("input")
  if not inv.is_empty() then
    s.ore_arrived = tick
  elseif tick - s.t0 < DONE_AT then
    scheduler.schedule(WATCH, tick + 1)
  end
end)

local function log_event(kind)
  return function(event)
    local s = sc()
    if not s then return end
    local per = s[kind]
    local list = per[event.unit_number]
    if not list then list = {} per[event.unit_number] = list end
    list[#list + 1] = {tick = event.tick, products = event.entity.valid and event.entity.products_finished or nil}
  end
end

local ids = defs.events[NAME]
runtime.subscribe(ids.cycle_started, log_event("started"))
runtime.subscribe(ids.cycle_finished, log_event("finished"))
runtime.subscribe(ids.inventory_changed, log_event("changed"))

local function arm()
  local surface = game.surfaces.nauvis
  prepare_area(surface)
  local s = {t0 = game.tick, units = {}, entities = {}, progress = {}, started = {}, finished = {}, changed = {}}
  storage.cl.tc_scenario = s

  local idle = place(surface, 0, 5)
  s.idle_before = burner_state(idle)

  local fed = place(surface, 1, 5)
  s.feed_chest, s.feed_inserter = feeding_inserter(surface, fed)

  local twice = place(surface, 2, 5)
  twice:inventory("input").insert{name = "iron-ore", count = 2}

  local speed = place(surface, 3, 5)
  speed.entity.get_module_inventory().insert{name = "speed-module", count = 1}
  speed:inventory("input").insert{name = "iron-ore", count = 1}

  local tagged = place(surface, 4, 5)
  local input = tagged:inventory("input")
  input.insert{name = "cl-tagged-sample", count = 1}
  local _, stack = choose(input)
  stack.tags = {seed = 7}

  local cloned = place(surface, 5, 5)
  cloned:inventory("input").insert{name = "iron-ore", count = 1}

  for key, rec in pairs({idle = idle, inserter = fed, twice = twice, speed = speed, tagged = tagged, clone = cloned}) do
    s.units[key] = rec.unit_number
    s.entities[key] = rec.entity
  end

  for offset in pairs(actions) do scheduler.schedule(PROBE, s.t0 + offset) end
  scheduler.schedule(WATCH, s.t0 + 1)
  runtime.fixtures.hold_until(s.t0 + DONE_AT)
end

runtime.init_hooks[#runtime.init_hooks + 1] = function()
  if not storage.cl.tc_scenario then arm() end
end

runtime.expose("tc_scenario", function() return storage.cl.tc_scenario end)

return handlers
