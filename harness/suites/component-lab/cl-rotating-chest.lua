-- cl-rotating-chest: a storehouse that rotates (S0). TEST-ENTITIES-2.md section 4.
-- Inserters are observed on the fixture the mod builds and turns at on_init
-- (run with --fresh first); everything else is asserted within the suite's tick.

local CL = "component_lab"
local NAME = "cl-rotating-chest"
local INV = NAME .. "-inv-main"
local PROXY = NAME .. "-proxy-main"
local NORTH, EAST, SOUTH, WEST = defines.direction.north, defines.direction.east,
  defines.direction.south, defines.direction.west
local EDGE_TILES = 14

local function cl(fn, ...) return remote.call(CL, fn, ...) end

local row = require("_site").row{x = 0, y = 1000, half = 8}
local function site(width) return row:next(width or 20) end

local function build(direction)
  local s, pos = site()
  local core = s.create_entity{name = NAME, position = pos, direction = direction, force = "player", raise_built = true}
  assert_not_nil(core, "create_entity")
  return core, s, pos
end

local function main_of(core) return cl("call", core.unit_number, "inventory", "main") end

local function parts_of(core)
  local out = {}
  for k, e in pairs(cl("parts", core.unit_number) or {}) do out[k] = e end
  return out
end

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

local function all_invalid(parts)
  for key, e in pairs(parts) do
    if e.valid then return false, key end
  end
  return true
end

local function size(entity)
  local b = entity.bounding_box
  return math.floor(b.right_bottom.x - b.left_top.x + 0.5), math.floor(b.right_bottom.y - b.left_top.y + 0.5)
end

-- A turn rebuilds the shell, so the storehouse is found again by where it is.
local function core_near(s, pos)
  local found = s.find_entities_filtered{name = NAME, area = {{pos.x - 2, pos.y - 2}, {pos.x + 2, pos.y + 2}}}
  assert_eq(#found, 1, "one storehouse near " .. pos.x .. "," .. pos.y)
  return found[1]
end

local function rotate(core, reverse)
  local s, pos = core.surface, core.position
  assert_true(cl("rotate", core, reverse), "rotate accepted")
  return core_near(s, pos)
end

-- Every proxy is a door to the one hidden container and sits on an edge tile.
local function check_doors(core)
  local parts = parts_of(core)
  local inv = parts["inventory:main"]
  assert_true(inv and inv.valid, "hidden container")
  local w, h = size(core)
  local left, top = core.position.x - w / 2, core.position.y - h / 2
  local doors, tiles = 0, {}
  for key, e in pairs(parts) do
    if key:find("^proxy:main") then
      doors = doors + 1
      assert_eq(e.proxy_target_entity, inv, key .. " targets the container")
      local tx, ty = e.position.x - left - 0.5, e.position.y - top - 0.5
      assert_true(tx >= 0 and ty >= 0 and tx <= w - 1 and ty <= h - 1, key .. " inside the footprint")
      assert_true(tx == 0 or ty == 0 or tx == w - 1 or ty == h - 1, key .. " on an edge tile")
      local id = tx .. ":" .. ty
      assert_nil(tiles[id], key .. " shares a tile")
      tiles[id] = true
    end
  end
  assert_eq(doors, EDGE_TILES, "a door on every edge tile")
end

test("cl-rotating-chest: prototype is a recipe-less 6x3 rotatable shell, S0", function()
  assert_eq(cl("shape", NAME), "S0", "passive shape")
  local p = assert_prototype("entity", NAME)
  assert_eq(p.type, "assembling-machine")
  assert_nil(p.fixed_recipe, "no recipe")
  assert_nil(p.electric_energy_source_prototype, "draws no power")
  assert_nil(p.burner_prototype, "burns nothing")
  local b = p.collision_box
  assert_true(math.abs((b.right_bottom.x - b.left_top.x) - 5.8) < 0.01, "6 wide")
  assert_true(math.abs((b.right_bottom.y - b.left_top.y) - 2.8) < 0.01, "3 tall")
  assert_eq(p.module_inventory_size, 0, "no module slots")
  local inv = assert_prototype("entity", INV)
  assert_eq(inv.get_inventory_size(defines.inventory.chest), 240, "240 slots")
  assert_true(inv.hidden, "container hidden")
  assert_eq(assert_prototype("entity", PROXY).type, "proxy-container")
end)

test("cl-rotating-chest: build makes one container and a door on every edge tile", function()
  local core = build()
  local parts = parts_of(core)
  assert_eq(count(parts), 1 + EDGE_TILES, "container + doors")
  local w, h = size(core)
  assert_eq(w, 6, "built 6 wide")
  assert_eq(h, 3, "built 3 tall")
  check_doors(core)
  for _, e in pairs(parts) do assert_eq(cl("owner_of", e.unit_number), core.unit_number, e.name .. " owned") end
  assert_eq(main_of(core).insert{name = "iron-plate", count = 100}, 100, "inserted")
  local door = parts["proxy:main@5"].get_inventory(defines.inventory.proxy_main)
  assert_eq(door.get_item_count("iron-plate"), 100, "any door shows the contents")
  assert_true(main_of(core).supports_bar(), "inventory has a bar")
end)

-- TEST-ENTITIES-2 asks to verify the shell sleeps. It does not: an assembler
-- with no recipe is an UpdatableEntity (status no_recipe). The bench cell
-- measures what that costs per tick against two steel chests.
test("cl-rotating-chest: KNOWN-LIMIT the recipe-less shell is an updatable entity", function()
  local core = build()
  assert_true(core.is_updatable, "the shell is updatable (drop this limit if it ever is not)")
  assert_eq(core.status, defines.entity_status.no_recipe, "it idles as no_recipe")
  assert_eq(cl("record", core.unit_number).next_due, nil, "but no Lua is scheduled for it")
end)

test("cl-rotating-chest: rotate turns the box 90 degrees and keeps the contents", function()
  local core = build()
  local before = core.unit_number
  local parts = parts_of(core)
  main_of(core).insert{name = "iron-plate", count = 100}
  main_of(core).set_bar(50)
  local census = cl("census")[NAME]
  local turned = rotate(core)
  assert_eq(turned.direction, EAST, "facing east")
  local w, h = size(turned)
  assert_eq(w, 3, "now 3 wide")
  assert_eq(h, 6, "now 6 tall")
  assert_eq(main_of(turned).get_item_count("iron-plate"), 100, "100 plates kept")
  assert_eq(main_of(turned).get_bar(), 50, "bar kept")
  check_doors(turned)
  local ok, key = all_invalid(parts)
  assert_true(ok, "old part left behind: " .. tostring(key))
  assert_nil(cl("record", before), "old record dropped")
  assert_eq(cl("census")[NAME], census, "still one record")
  assert_eq(cl("record", turned.unit_number).data.turns, 1, "one turn recorded")
end)

test("cl-rotating-chest: four turns come back to the same place and facing", function()
  local core = build()
  local start = core.position
  main_of(core).insert{name = "copper-plate", count = 37}
  local seen = {}
  for i = 1, 4 do
    core = rotate(core)
    seen[i] = core.direction
  end
  assert_eq(seen[1], EAST)
  assert_eq(seen[2], SOUTH)
  assert_eq(seen[3], WEST)
  assert_eq(seen[4], NORTH)
  assert_eq(core.position.x, start.x, "x back")
  assert_eq(core.position.y, start.y, "y back")
  assert_eq(main_of(core).get_item_count("copper-plate"), 37, "contents through four turns")
  check_doors(core)
end)

test("cl-rotating-chest: a turn into an obstacle is refused and the chest is untouched", function()
  local core, s = build()
  local u = core.unit_number
  main_of(core).insert{name = "iron-plate", count = 10}
  local c = core.position
  -- Free for the 6x3, inside the turned 3x6.
  assert_not_nil(s.create_entity{name = "steel-chest", position = {c.x + 0.5, c.y - 2}, force = "player"}, "obstacle")
  assert_true(cl("rotate", core), "rotate call")
  assert_true(core.valid, "same entity")
  assert_eq(core.unit_number, u, "same unit")
  assert_eq(core.direction, NORTH, "flip undone")
  local w = size(core)
  assert_eq(w, 6, "still 6 wide")
  assert_eq(main_of(core).get_item_count("iron-plate"), 10, "contents untouched")
  check_doors(core)
  assert_eq(cl("record", u).data.blocked_turns, 1, "refusal recorded")
end)

-- The turned 3x6 covers the tile column at c.x and rows c.y - 3 .. c.y + 2; the
-- 6x3 it came from covers rows c.y - 1 .. c.y + 1, so row c.y - 3 is new ground.
local function assert_refused(core, u, what)
  assert_true(cl("rotate", core), "rotate call")
  assert_true(core.valid, what .. ": same entity")
  assert_eq(core.unit_number, u, what .. ": same unit")
  assert_eq(core.direction, NORTH, what .. ": flip undone")
  assert_eq(main_of(core).get_item_count("iron-plate"), 10, what .. ": contents untouched")
  check_doors(core)
  assert_eq(cl("record", u).data.blocked_turns, 1, what .. ": refusal recorded")
end

test("cl-rotating-chest: a turn onto water is refused", function()
  local core, s = build()
  local u = core.unit_number
  main_of(core).insert{name = "iron-plate", count = 10}
  local c = core.position
  local spot = {math.floor(c.x), math.floor(c.y - 3)}
  local before = s.get_tile(spot[1], spot[2]).name
  s.set_tiles({{name = "water", position = spot}}, false)
  local ok, err = pcall(assert_refused, core, u, "water")
  s.set_tiles({{name = before, position = spot}}, false)
  if not ok then error(err, 0) end
end)

test("cl-rotating-chest: a turn onto a ghost is refused and the ghost survives", function()
  local core, s = build()
  local u = core.unit_number
  main_of(core).insert{name = "iron-plate", count = 10}
  local c = core.position
  local ghost = s.create_entity{name = "entity-ghost", inner_name = "small-electric-pole",
    position = {c.x + 0.5, c.y - 2.5}, force = "player"}
  assert_not_nil(ghost, "ghost")
  assert_refused(core, u, "ghost")
  assert_true(ghost.valid, "the planned build is still there")
  ghost.destroy()
end)

test("cl-rotating-chest: placement takes all four directions", function()
  for _, d in ipairs({NORTH, EAST, SOUTH, WEST}) do
    local core = build(d)
    assert_eq(core.direction, d, "placed facing " .. d)
    local w = size(core)
    assert_eq(w, (d == EAST or d == WEST) and 3 or 6, "width for " .. d)
    check_doors(core)
  end
end)

test("cl-rotating-chest: script mine returns the contents and the chest", function()
  local core = build()
  local parts = parts_of(core)
  main_of(core).insert{name = "iron-plate", count = 100}
  main_of(core).insert{name = "stone", count = 300}
  local inv = game.create_inventory(20)
  assert_true(cl("mine", core, inv), "mined")
  assert_true(not core.valid, "core gone")
  local ok, key = all_invalid(parts)
  assert_true(ok, "part left behind: " .. tostring(key))
  assert_eq(inv.get_item_count("iron-plate"), 100, "plates returned")
  assert_eq(inv.get_item_count("stone"), 300, "stone returned")
  assert_eq(inv.get_item_count(NAME), 1, "storehouse item returned")
  inv.destroy()
end)

test("cl-rotating-chest: mining a turned chest returns what it held before the turn", function()
  local core = rotate((build()))
  main_of(core).insert{name = "iron-plate", count = 5}
  local inv = game.create_inventory(4)
  assert_true(cl("mine", core, inv), "mined")
  assert_eq(inv.get_item_count("iron-plate"), 5, "plates returned")
  assert_eq(inv.get_item_count(NAME), 1, "one storehouse item")
  inv.destroy()
end)

test("cl-rotating-chest: destroy removes every part; death spills the contents", function()
  local core = build()
  local u = core.unit_number
  local parts = parts_of(core)
  core.destroy{raise_destroy = true}
  local ok, key = all_invalid(parts)
  assert_true(ok, "part left behind: " .. tostring(key))
  assert_nil(cl("record", u), "registry entry")

  local dead, s = build()
  local dparts = parts_of(dead)
  main_of(dead).insert{name = "iron-plate", count = 30}
  local at = dead.position
  dead.die()
  ok, key = all_invalid(dparts)
  assert_true(ok, "part left behind after death: " .. tostring(key))
  local spilled = 0
  for _, e in pairs(s.find_entities_filtered{name = "item-on-ground", position = at, radius = 6}) do
    if e.stack.name == "iron-plate" then spilled = spilled + e.stack.count end
  end
  assert_eq(spilled, 30, "plates spilled")
end)

test("cl-rotating-chest: clone of a turned chest keeps facing, doors and contents", function()
  local core = rotate((build()))
  local s = core.surface
  main_of(core).insert{name = "iron-plate", count = 100}
  main_of(core).set_bar(12)
  s.clone_entities{entities = {core}, destination_offset = {6, 0}}
  local copy = s.find_entity(NAME, {core.position.x + 6, core.position.y})
  assert_not_nil(copy, "clone exists")
  assert_eq(copy.direction, EAST, "clone faces east")
  local w, h = size(copy)
  assert_eq(w, 3, "clone 3 wide")
  assert_eq(h, 6, "clone 6 tall")
  assert_true(parts_of(copy)["inventory:main"] ~= parts_of(core)["inventory:main"], "own container")
  assert_eq(main_of(copy).get_item_count("iron-plate"), 100, "contents cloned")
  assert_eq(main_of(copy).get_bar(), 12, "bar cloned")
  assert_eq(main_of(core).get_item_count("iron-plate"), 100, "source kept its contents")
  check_doors(copy)
end)

test("cl-rotating-chest: blueprint of a turned chest pastes turned and carries the bar", function()
  local core = rotate((build()))
  local s, c = core.surface, core.position
  main_of(core).insert{name = "iron-plate", count = 9}
  main_of(core).set_bar(40)
  local inv = game.create_inventory(1)
  inv.insert{name = "blueprint"}
  local bp = inv[1]
  local mapping = bp.create_blueprint{surface = s, force = "player",
    area = {{c.x - 2, c.y - 3.5}, {c.x + 2, c.y + 3.5}}}
  assert_eq(cl("tag_blueprint", bp, mapping), 1, "one core tagged")
  local entities = bp.get_blueprint_entities()
  assert_eq(#entities, 1, "no hidden part is blueprinted")
  assert_eq(entities[1].name, NAME)
  assert_eq(entities[1].direction, EAST, "blueprint faces east")
  assert_eq(bp.get_blueprint_entity_tags(1).component_lab.bars.main, 40, "bar in tags")

  local ghosts = bp.build_blueprint{surface = s, force = "player", position = {c.x + 6, c.y},
    skip_fog_of_war = false, build_mode = defines.build_mode.forced}
  assert_eq(#ghosts, 1, "one ghost")
  local _, revived = ghosts[1].revive{raise_revive = true}
  assert_not_nil(revived, "revived")
  assert_eq(revived.direction, EAST, "pasted facing east")
  local w, h = size(revived)
  assert_eq(w, 3, "pasted 3 wide")
  assert_eq(h, 6, "pasted 6 tall")
  assert_eq(main_of(revived).get_bar(), 40, "bar applied")
  assert_eq(main_of(revived).get_item_count(), 0, "contents are not blueprinted")
  check_doors(revived)
  inv.destroy()
end)

-- The engine flips a 6x3 shell 180 degrees and ignores a script direction
-- write, so a turn builds a new shell: anything holding the old LuaEntity or
-- unit_number (undo, other mods, wires if it had any) loses it. And
-- on_player_rotated_entity does not say which way the player turned, while
-- both R and shift-R flip, so a turn is always clockwise.
test("cl-rotating-chest: KNOWN-LIMIT a turn replaces the entity and is always clockwise", function()
  local core = build()
  local u = core.unit_number
  local turned = rotate(core, true)
  assert_true(not core.valid, "the old LuaEntity is gone (a native turn would keep it)")
  assert_true(turned.unit_number ~= u, "new unit_number")
  assert_eq(cl("record", turned.unit_number).data.turned_from, u, "the record knows where it came from")
  assert_eq(turned.direction, EAST, "reverse rotate still turned clockwise (native: west)")
end)

-- SPEC circuit_outputs = "contents": a native composed chest reads its own
-- inventory onto its wires for free. Here the shell can be wired (every
-- assembler can), but its control behaviour reads an assembler's own slots, and
-- the contents live in a hidden container a player cannot select, so nothing
-- reaches the wire. Publishing them would take a poll, which makes it S1.
test("cl-rotating-chest: KNOWN-LIMIT contents are not on the circuit network", function()
  local core = build()
  main_of(core).insert{name = "iron-plate", count = 10}
  assert_not_nil(core.get_wire_connector(defines.wire_connector_id.circuit_red, true), "the shell takes a wire")
  local cb = core.get_or_create_control_behavior()
  assert_eq(cb.type, defines.control_behavior.type.assembling_machine, "an assembler's control behaviour")
  assert_true(not parts_of(core)["inventory:main"].prototype.selectable_in_game, "the container cannot be wired by hand")
end)

-- ---- real ticks --------------------------------------------------------------

local function fixture()
  local fx = cl("rotating_chest_fixture")
  assert_not_nil(fx, "fixture armed at on_init (run with --fresh)")
  assert_not_nil(fx.snap, string.format("fixture incomplete at tick %d (snapshot due at %d)", game.tick, fx.snap_at))
  return fx
end

test("cl-rotating-chest: real ticks: inserters on all four sides of a turned chest", function()
  local fx = fixture()
  local snap = fx.snap
  assert_eq(fx.direction, EAST, "the fixture chest was turned at on_init")
  assert_eq(snap.west_drop, PROXY, "west (long side) inserter drops into a door")
  assert_eq(snap.north_drop, PROXY, "north (short side) inserter drops into a door")
  assert_eq(snap.east_pickup, PROXY, "east (long side) inserter picks from a door")
  assert_eq(snap.south_pickup, PROXY, "south (short side) inserter picks from a door")
  assert_true(snap.copper_left < 20, "copper went in from the west: " .. snap.copper_left .. " left")
  assert_true(snap.stone_left < 10, "stone went in from the north: " .. snap.stone_left .. " left")
  assert_true(snap.east_sink > 0, "items came out on the east: " .. snap.east_sink)
  assert_true(snap.south_sink > 0, "items came out on the south: " .. snap.south_sink)
  for item, n in pairs(fx.initial) do
    assert_eq(snap.totals[item], n, item .. " conserved across chest, doors and hands")
  end
end)

test("cl-rotating-chest: real ticks: re-arm the fixture for the next run", function()
  assert_true(cl("rotating_chest_arm_fixture"), "re-armed")
end)
