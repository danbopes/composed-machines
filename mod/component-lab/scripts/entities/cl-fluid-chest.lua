-- cl-fluid-chest and cl-fluid-chest-watch: runtime handlers. TEST-ENTITIES.md section 1.
--
-- The fluid lives in the hidden storage tank (rec:fluid_box(1)); the core is a
-- plain container, so the plain chest costs no Lua at all after it is built. The
-- watched chest polls its box once per poll_interval through the library
-- scheduler: that poll is the whole cost the native S1 threshold would remove.

local runtime = require("scripts.runtime")
local defs = require("scripts.defs")

local PLAIN = "cl-fluid-chest"
local WATCH = "cl-fluid-chest-watch"
local OURS = {[PLAIN] = true, [WATCH] = true}

local function amount_in(rec, box)
  local entity, index = rec:fluid_box(box)
  local fluid = entity.get_fluid(index)
  return fluid and fluid.amount or 0
end

local function thresholds(rec) return rec:spec().fluid_thresholds end

local function init_thresholds(rec)
  local above = {}
  for i, t in ipairs(thresholds(rec)) do above[i] = amount_in(rec, t.fluid_box) >= t.amount end
  rec.data.above = above
end

-- SPEC 1.8: below on the crossing from >= amount to < amount, above only once the
-- box is back at amount + hysteresis, so a level hovering at the line stays quiet.
local function evaluate(rec)
  local above = rec.data.above
  for i, t in ipairs(thresholds(rec)) do
    local amount = amount_in(rec, t.fluid_box)
    local now
    if above[i] and amount < t.amount then
      now = false
    elseif not above[i] and amount >= t.amount + (t.hysteresis or 0) then
      now = true
    end
    if now ~= nil then
      above[i] = now
      rec:raise("fluid_threshold", {fluid_box = t.fluid_box, amount = amount, above = now})
    end
  end
end

local function poll_interval(rec) return rec:spec().emulation.poll_interval end

local function tank(rec) return rec.parts["tank:fluid1"] end

-- The core is a container and has no direction, so the tank's direction is the
-- entity's orientation and the record is its only durable copy.
local function set_direction(rec, direction)
  local t = tank(rec)
  if t.direction ~= direction then t.direction = direction end
  rec.data.direction = t.direction
end

local function rotate(rec, reverse)
  local turn = reverse and 12 or 4
  set_direction(rec, (tank(rec).direction + turn) % 16)
  return rec.data.direction
end

local handlers = {}

function handlers.on_created(rec, ctx)
  if rec.data.direction == nil then rec.data.direction = tank(rec).direction end
  if rec.name ~= WATCH then return end
  if ctx.cause ~= "clone" or not rec.data.above then init_thresholds(rec) end
  rec.data.first_poll = rec:schedule_phase(poll_interval(rec))
end

function handlers.on_tick(rec, tick)
  evaluate(rec)
  rec.data.last_poll = tick
  rec:schedule_at(tick + poll_interval(rec))
end

function handlers.blueprint_tags(rec) return {direction = rec.data.direction} end

function handlers.apply_tags(rec, extra)
  if extra.direction then set_direction(rec, extra.direction) end
end

function handlers.on_gui(rec, player, frame)
  local entity, index = rec:fluid_box(1)
  local fluid = entity.get_fluid(index)
  local capacity = entity.get_fluid_capacity(index)
  local caption = fluid and {"", {"fluid-name." .. fluid.name}, string.format(": %.0f / %.0f", fluid.amount, capacity)}
    or string.format("0 / %.0f", capacity)
  frame.add{type = "label", caption = caption}
end

local function on_rotate_input(event)
  local player = game.get_player(event.player_index)
  if not player or player.cursor_stack.valid_for_read or player.cursor_ghost then return end
  local rec = runtime.get(player.selected)
  if rec and OURS[rec.name] and rec.entity.force == player.force then
    rotate(rec, event.input_name == "cl-fluid-chest-reverse-rotate")
  end
end
runtime.subscribe("cl-fluid-chest-rotate", on_rotate_input)
runtime.subscribe("cl-fluid-chest-reverse-rotate", on_rotate_input)

-- What a mod listening to the threshold event receives; suites read it back.
runtime.subscribe(defs.events[WATCH].fluid_threshold, function(event)
  local seen = storage.fluid_chest and storage.fluid_chest.seen
  if seen then
    seen[#seen + 1] = {unit_number = event.unit_number, tick = event.tick or game.tick, above = event.above,
      amount = event.amount, fluid_box = event.fluid_box}
  end
end)

-- Fill probe: an infinity pipe feeding a watched chest from map creation, so a
-- suite (which runs inside one tick) can see what real ticks did to it.
local function arm_fill_probe()
  local surface = game.surfaces.nauvis
  local at = {1500.5, -1480.5}
  surface.request_to_generate_chunks(at, 1)
  surface.force_generate_chunk_requests()
  local tiles = {}
  for x = -3, 3 do
    for y = -3, 3 do tiles[#tiles + 1] = {name = "grass-1", position = {at[1] + x, at[2] + y}} end
  end
  surface.set_tiles(tiles)
  for _, e in pairs(surface.find_entities_filtered{area = {{at[1] - 3, at[2] - 3}, {at[1] + 3, at[2] + 3}}}) do
    e.destroy()
  end
  local pipe = surface.create_entity{name = "infinity-pipe", position = {at[1], at[2] - 1}, force = "player"}
  pipe.set_infinity_pipe_filter{name = "water", percentage = 1, mode = "at-least"}
  local core = surface.create_entity{name = WATCH, position = at, force = "player"}
  -- Events raised from on_init are not delivered, so build the parts directly.
  local rec = runtime.lifecycle.materialise(core, nil, "probe")
  storage.fluid_chest.fill_probe = {unit_number = core.unit_number, position = at, pipe = pipe, armed_at = game.tick,
    first_poll = rec.data.first_poll, start_amount = amount_in(rec, 1)}
end

runtime.init_hooks[#runtime.init_hooks + 1] = function()
  storage.fluid_chest = storage.fluid_chest or {seen = {}}
  if not storage.fluid_chest.fill_probe then arm_fill_probe() end
end

runtime.expose("fluid_chest_rotate", function(unit_number, reverse)
  local rec = storage.cl.records[unit_number]
  return rec and OURS[rec.name] and rotate(rec, reverse) or nil
end)
runtime.expose("fluid_chest_seen", function(clear)
  local seen = storage.fluid_chest.seen
  if clear then storage.fluid_chest.seen = {} end
  return seen
end)
runtime.expose("fluid_chest_fill_probe", function() return storage.fluid_chest.fill_probe end)

return handlers
