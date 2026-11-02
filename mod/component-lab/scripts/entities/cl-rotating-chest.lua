-- cl-rotating-chest: a storehouse that rotates (S0). TEST-ENTITIES-2.md section 4.
--
-- Nothing ticks: the contents live in a hidden container that inserters reach
-- through the edge proxies, so after it is built the storehouse costs no Lua.
--
-- The one thing done here is the quarter turn. A non-square crafting machine is
-- only flipped 180 degrees by the engine after placement (box unchanged; the
-- library's KNOWN-LIMIT test), and a script write to `direction` is silently
-- ignored for it (probed on 2.1.24). So a flip of a non-square shell is
-- converted into a turn the way WideChests #9 asked for: replace the shell with
-- one facing 90 degrees clockwise of where it was and move the hidden contents
-- across. If the turned footprint is blocked (an entity, a ghost, or a tile the
-- shell cannot stand on), the flip is undone, as a native rotate would refuse.

local runtime = require("scripts.runtime")
local util = require("util")

local NAME = "cl-rotating-chest"
local lifecycle = runtime.lifecycle

-- Set while this script rotates a core itself, so the on_rotated it causes is
-- not taken for a player's rotate.
local reverting = false

local function is_square(entity)
  local b = entity.prototype.collision_box
  return math.abs((b.right_bottom.x - b.left_top.x) - (b.right_bottom.y - b.left_top.y)) < 0.01
end

local function wide(direction)
  return direction == defines.direction.north or direction == defines.direction.south
end

-- An even side centres on a tile edge and an odd side on a tile centre, so a
-- 6x3 that turns has to move half a tile on both axes. Moving back the same way
-- on the next turn keeps a storehouse turned four times where it started.
local function turned_position(position, to_direction)
  if wide(to_direction) then return {position.x - 0.5, position.y + 0.5} end
  return {position.x + 0.5, position.y - 0.5}
end

local function turned_box(entity, position, direction)
  local b = entity.prototype.collision_box
  local hw, hh = (b.right_bottom.x - b.left_top.x) / 2, (b.right_bottom.y - b.left_top.y) / 2
  if not wide(direction) then hw, hh = hh, hw end
  return {{position[1] - hw, position[2] - hh}, {position[1] + hw, position[2] + hh}}
end

local function collides(a, b)
  for layer in pairs(a) do
    if b[layer] then return true end
  end
  return false
end

-- create_entity runs no placement check, so everything the native rotate would
-- refuse has to be refused here. can_place_entity cannot be asked instead: the
-- old core overlaps the turned footprint and always blocks it.
local function blocked(rec, box)
  local core = rec.entity
  local surface = core.surface
  local mask = core.prototype.collision_mask.layers
  for _, e in pairs(surface.find_entities_filtered{area = box}) do
    if e ~= core and runtime.get(e) ~= rec then
      -- A ghost is the player's planned build; building over it would delete it.
      local layers = e.type == "entity-ghost" and e.ghost_prototype.collision_mask.layers
        or e.prototype.collision_mask.layers
      if collides(mask, layers) then return e end
    end
  end
  -- Water, lava, out-of-map and a platform's empty space all carry layers the
  -- shell collides with. Inset so tiles that only touch the box edge are skipped.
  local tile_area = {{box[1][1] + 0.01, box[1][2] + 0.01}, {box[2][1] - 0.01, box[2][2] - 0.01}}
  local tiles = surface.find_tiles_filtered{area = tile_area, collision_mask = mask, limit = 1}
  if tiles[1] then return tiles[1] end
  return nil
end

local function undo_flip(rec, previous)
  local core = rec.entity
  local flipped = core.direction
  reverting = true
  core.rotate{}
  lifecycle.rotated(rec, flipped)
  reverting = false
  rec.data.blocked_turns = (rec.data.blocked_turns or 0) + 1
  return core.direction == previous
end

local function move_contents(from, to)
  for i = 1, math.min(#from, #to) do
    if from[i].valid_for_read then
      to[i].set_stack(from[i])
      from[i].clear()
    end
  end
  if from.supports_bar() and to.supports_bar() then to.set_bar(from.get_bar()) end
end

local function turn(rec, previous)
  local core = rec.entity
  local target = (previous + 4) % 16
  local position = turned_position(core.position, target)
  local obstacle = blocked(rec, turned_box(core, position, target))
  if obstacle then
    undo_flip(rec, previous)
    return
  end
  local replacement = core.surface.create_entity{
    name = NAME, position = position, direction = target, force = core.force, quality = core.quality,
    create_build_effect_smoke = false, raise_built = false,
  }
  if not replacement then
    undo_flip(rec, previous)
    return
  end
  replacement.health = core.health
  local fresh = lifecycle.materialise(replacement, nil, "turn")
  fresh.settings = util.table.deepcopy(rec.settings)
  fresh.data = util.table.deepcopy(rec.data)
  fresh.data.turns = (fresh.data.turns or 0) + 1
  fresh.data.turned_from = rec.unit_number
  move_contents(rec:inventory("main"), fresh:inventory("main"))
  -- Torn down directly rather than through raise_destroy, because events raised
  -- during on_init (the fixture turns a chest there) are never delivered. The
  -- hidden container is empty by now, so the "destroyed" mode loses nothing.
  lifecycle.teardown(rec.unit_number, "destroyed")
  core.destroy()
  return fresh
end

-- ---- real-tick fixture ---------------------------------------------------------
-- A suite runs inside one tick, so the inserter check runs on a storehouse built
-- and turned at on_init: four burner inserters, one on each side of the turned
-- (3x6) footprint, two feeding it and two emptying it, snapshotted at SNAP_AT.

local ORIGIN = {-2800, 1000.5}
local SNAP_AT = 900
local PLATES, COPPER, STONE = 100, 20, 10

local function fixture() return storage.cl.rotating_chest_fixture end

local function count_all(fx)
  local inv = fx.core.valid and runtime.get(fx.core)
  local main = inv and inv:inventory("main")
  local x = fx.extras
  local function n(e, item) return e.valid and e.get_item_count(item) or 0 end
  local function held(e, item)
    local h = e.valid and e.held_stack
    return (h and h.valid_for_read and h.name == item) and h.count or 0
  end
  local out = {}
  for _, item in ipairs({"iron-plate", "copper-plate", "stone"}) do
    local total = (main and main.get_item_count(item) or 0)
    for _, e in pairs(x) do
      if e.type == "inserter" then total = total + held(e, item) else total = total + n(e, item) end
    end
    out[item] = total
  end
  return out
end

local function snapshot()
  local fx = fixture()
  if not fx then return end
  local x = fx.extras
  local rec = fx.core.valid and runtime.get(fx.core)
  local main = rec and rec:inventory("main")
  local function target(e, field) return e.valid and e[field] and e[field].name end
  fx.snap = {
    tick = game.tick,
    copper_left = x.west_source.get_item_count("copper-plate"),
    stone_left = x.north_source.get_item_count("stone"),
    east_sink = x.east_sink.get_item_count(),
    south_sink = x.south_sink.get_item_count(),
    stored_copper = main and main.get_item_count("copper-plate") or 0,
    stored_stone = main and main.get_item_count("stone") or 0,
    west_drop = target(x.west_inserter, "drop_target"),
    north_drop = target(x.north_inserter, "drop_target"),
    east_pickup = target(x.east_inserter, "pickup_target"),
    south_pickup = target(x.south_inserter, "pickup_target"),
    totals = count_all(fx),
  }
end

local function arm_fixture()
  local old = fixture()
  if old then
    if old.core.valid then old.core.destroy{raise_destroy = true} end
    for _, e in pairs(old.extras) do
      if e.valid then e.destroy() end
    end
  end
  local surface = game.surfaces.nauvis
  surface.request_to_generate_chunks(ORIGIN, 1)
  surface.force_generate_chunk_requests()
  local area = {{ORIGIN[1] - 8, ORIGIN[2] - 8}, {ORIGIN[1] + 8, ORIGIN[2] + 8}}
  for _, e in pairs(surface.find_entities_filtered{area = area}) do
    if e.valid and e.type ~= "character" and not runtime.get(e) then e.destroy() end
  end
  local tiles = {}
  for x = area[1][1], area[2][1] do
    for y = area[1][2], area[2][2] do tiles[#tiles + 1] = {name = "refined-concrete", position = {x, y}} end
  end
  surface.set_tiles(tiles, true, true)

  local core = surface.create_entity{name = NAME, position = ORIGIN, force = "player"}
  local rec = lifecycle.materialise(core, nil, "fixture")
  rec:inventory("main").insert{name = "iron-plate", count = PLATES}
  local previous = core.direction
  core.rotate{}
  lifecycle.rotated(rec, previous)
  local turned = assert(runtime.get(surface.find_entities_filtered{name = NAME, area = area}[1]), "turned core")
  local c = turned.entity.position

  local north, west = defines.direction.north, defines.direction.west
  local function put(name, dx, dy, opts)
    local e = surface.create_entity{name = name, position = {c.x + dx, c.y + dy}, force = "player",
      direction = opts and opts.direction}
    if e.type == "inserter" then e.get_fuel_inventory().insert{name = "coal", count = 5} end
    if opts and opts.items then e.insert(opts.items) end
    return e
  end
  -- Burner inserters face the side they pick up from.
  local extras = {
    west_source = put("iron-chest", -3, -1.5, {items = {name = "copper-plate", count = COPPER}}),
    west_inserter = put("burner-inserter", -2, -1.5, {direction = west}),
    east_inserter = put("burner-inserter", 2, 1.5, {direction = west}),
    east_sink = put("iron-chest", 3, 1.5),
    north_source = put("iron-chest", 0, -4.5, {items = {name = "stone", count = STONE}}),
    north_inserter = put("burner-inserter", 0, -3.5, {direction = north}),
    south_inserter = put("burner-inserter", 0, 3.5, {direction = north}),
    south_sink = put("iron-chest", 0, 4.5),
  }
  storage.cl.rotating_chest_fixture = {
    tick = game.tick, snap_at = game.tick + SNAP_AT, core = turned.entity, extras = extras,
    direction = turned.entity.direction, initial = {["iron-plate"] = PLATES, ["copper-plate"] = COPPER, stone = STONE},
  }
  runtime.scheduler.schedule("cl_rotating_chest_snap", game.tick + SNAP_AT)
  runtime.fixtures.hold_until(game.tick + SNAP_AT)
  return storage.cl.rotating_chest_fixture
end

runtime.scheduler.on_named("cl_rotating_chest_snap", snapshot)

runtime.init_hooks[#runtime.init_hooks + 1] = function()
  if not storage.cl.rotating_chest_fixture then arm_fixture() end
end

runtime.expose("rotating_chest_fixture", function() return storage.cl.rotating_chest_fixture end)
runtime.expose("rotating_chest_arm_fixture", function() arm_fixture() return true end)

return {
  on_rotated = function(rec, previous)
    if reverting or is_square(rec.entity) then return end
    if (rec.entity.direction - previous) % 16 ~= 8 then return end
    turn(rec, previous)
  end,
}
