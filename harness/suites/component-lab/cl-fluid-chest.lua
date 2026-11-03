-- cl-fluid-chest suite. TEST-ENTITIES.md section 1.
-- Suites run in one tick: multi-tick behaviour is read from the fill probe armed
-- at map creation, or driven through the scheduler with synthetic dispatch.

local CL = "component_lab"
local PLAIN, WATCH = "cl-fluid-chest", "cl-fluid-chest-watch"
local TANK = "cl-fluid-chest-tank-1"
local POLL = 60
local NORTH, EAST, SOUTH, WEST = defines.direction.north, defines.direction.east,
  defines.direction.south, defines.direction.west

local function cl(fn, ...) return remote.call(CL, fn, ...) end

-- Each site gets its own cleared land patch, away from every other suite's rows.
local row = require("_site").row{x = 1500, y = -1500, half = 4, tile = "grass-1"}
local function site(width) return row:next(width) end

local function build(name, width)
  local s, pos = site(width)
  local core = s.create_entity{name = name, position = pos, force = "player", raise_built = true}
  assert_not_nil(core, "create_entity " .. name)
  return core, s, pos
end

local function tank_name(core) return core.name .. "-tank-1" end

local function tank_of(core) return cl("parts", core.unit_number)["tank:fluid1"] end

local function amount(entity)
  local f = entity.get_fluid(1)
  return f and f.amount or 0
end

local function neighbours(entity)
  local out = {}
  for _, n in pairs(entity.get_fluid_box_neighbours(1) or {}) do out[n.entity.unit_number] = n.entity end
  return out
end

local function count_parts(parts)
  local n = 0
  for _ in pairs(parts) do n = n + 1 end
  return n
end

-- Fire the watched chest's pending poll now, as the server would at next_due.
local function poll(core)
  local due = cl("record", core.unit_number).next_due
  assert_not_nil(due, "a poll is pending")
  cl("dispatch", due, core.unit_number)
  return due
end

test("cl-fluid-chest: prototypes, shapes and parts", function()
  assert_eq(cl("shape", PLAIN), "S0", "plain chest")
  assert_eq(cl("shape", WATCH), "S1", "threshold event makes it S1")
  local core = assert_prototype("entity", PLAIN)
  assert_eq(core.type, "container")
  assert_eq(core.get_inventory_size(defines.inventory.chest), 16, "16 slots")
  local t = assert_prototype("entity", TANK)
  assert_eq(t.type, "storage-tank")
  assert_true(t.hidden, "tank hidden")
  assert_eq(t.fluid_capacity, 200, "tank volume")
  local data = prototypes.mod_data["component-lab--" .. WATCH].data
  assert_eq(data.watch, "fluid_threshold", "watcher")
  assert_eq(#data.parts, 1, "one hidden part")
end)

test("cl-fluid-chest: build creates one tank under the core; nothing ticks", function()
  local core = build(PLAIN)
  local parts = cl("parts", core.unit_number)
  assert_eq(count_parts(parts), 1, "only the tank")
  local t = parts["tank:fluid1"]
  assert_true(t and t.valid, "tank valid")
  assert_eq(t.name, TANK)
  assert_eq(t.position.x, core.position.x, "tank x")
  assert_eq(t.position.y, core.position.y, "tank y")
  assert_eq(cl("owner_of", t.unit_number), core.unit_number, "tank owned by the core")
  assert_eq(t.direction, NORTH)
  assert_true(not core.is_updatable, "container core is not updatable")
  assert_true(not t.is_updatable, "storage tank is not updatable")
  assert_nil(cl("record", core.unit_number).next_due, "S0 schedules no poll")
  local inv = cl("call", core.unit_number, "inventory", "main")
  assert_eq(#inv, 16)
  assert_true(inv.supports_bar(), "main has a bar")
end)

test("cl-fluid-chest: watched chest schedules one phased poll within the interval", function()
  local core = build(WATCH)
  local due = cl("record", core.unit_number).next_due
  assert_not_nil(due, "poll scheduled")
  assert_true(due > game.tick and due <= game.tick + POLL, "first poll within " .. POLL .. " ticks")
  local bucket = cl("bucket", due)
  assert_true(bucket ~= nil and bucket[#bucket] == core.unit_number, "in its bucket")
  local after = poll(core)
  assert_eq(cl("record", core.unit_number).next_due, after + POLL, "re-armed one interval later")
end)

test("cl-fluid-chest: infinity pipe fills the tank to 200 over real ticks", function()
  local probe = cl("fluid_chest_fill_probe")
  assert_not_nil(probe, "fill probe armed at on_init (run with --fresh)")
  assert_true(game.tick > probe.armed_at, "ticks have passed since the probe")
  assert_eq(probe.start_amount, 0, "empty when built")
  local core = game.surfaces.nauvis.find_entity(WATCH, probe.position)
  assert_true(core and core.valid, "probe chest alive")
  local t = tank_of(core)
  assert_true(neighbours(t)[probe.pipe.unit_number] ~= nil, "tank connected to the pipe")
  local f = t.get_fluid(1)
  assert_not_nil(f, "fluid arrived")
  assert_eq(f.name, "water")
  assert_eq(f.amount, 200, "full")
end)

test("cl-fluid-chest: fill probe's poll ran on a real tick within 60 ticks", function()
  local probe = cl("fluid_chest_fill_probe")
  assert_not_nil(probe, "fill probe armed at on_init (run with --fresh)")
  assert_true(probe.first_poll - probe.armed_at <= POLL, "first poll <= " .. POLL .. " ticks after build")
  local rec = cl("record", probe.unit_number)
  if game.tick > probe.first_poll then
    assert_eq(rec.data.last_poll ~= nil and rec.data.last_poll >= probe.first_poll, true, "poll fired")
    local seen = cl("fluid_chest_seen")
    local crossing
    for _, e in ipairs(seen) do if e.unit_number == probe.unit_number then crossing = crossing or e end end
    assert_not_nil(crossing, "the fill crossed the threshold")
    assert_true(crossing.above, "crossing is upward")
    assert_eq(crossing.tick, probe.first_poll, "seen at the first poll")
  else
    -- The suite ran before the poll's tick: it must still be queued for it.
    local bucket = cl("bucket", probe.first_poll)
    local queued = false
    for _, u in ipairs(bucket or {}) do if u == probe.unit_number then queued = true end end
    assert_true(queued, "poll still queued for tick " .. probe.first_poll .. " (now " .. game.tick .. ")")
  end
end)

test("cl-fluid-chest: threshold fires below once, above once past 160 (hysteresis)", function()
  local core = build(WATCH)
  local u = core.unit_number
  local t = tank_of(core)
  t.set_fluid(1, {name = "water", amount = 200})
  poll(core)
  cl("set_event_log", true)
  cl("fluid_chest_seen", true)

  -- Worst case: the level changes on the tick right after a poll, so the
  -- latency is the gap between two polls.
  local function step(level)
    local changed_after = cl("record", u).data.last_poll
    t.set_fluid(1, {name = "water", amount = level})
    local due = poll(core)
    local events = {}
    for _, e in ipairs(cl("event_log", true) or {}) do if e.unit_number == u then events[#events + 1] = e end end
    return events, due - changed_after
  end

  local events, latency = step(100)
  assert_eq(#events, 1, "one crossing draining 200 -> 100")
  assert_eq(events[1].flag, "fluid_threshold")
  assert_eq(events[1].above, false, "below")
  assert_eq(events[1].fluid_box, 1)
  assert_eq(events[1].amount, 100)
  assert_true(latency >= 1 and latency <= POLL, "emulated latency " .. latency .. " <= " .. POLL)
  for _, level in ipairs({145, 155, 159.9, 120}) do
    events = step(level)
    assert_eq(#events, 0, "nothing at " .. level .. " (inside the hysteresis band or still below)")
  end
  events = step(165)
  assert_eq(#events, 1, "one crossing refilling past 160")
  assert_eq(events[1].above, true, "above")
  for _, level in ipairs({200, 151, 150}) do
    events = step(level)
    assert_eq(#events, 0, "nothing at " .. level .. " (still >= 150)")
  end
  events = step(149)
  assert_eq(#events, 1, "below again under 150")
  cl("set_event_log", false)

  local seen = {}
  for _, e in ipairs(cl("fluid_chest_seen", true)) do if e.unit_number == u then seen[#seen + 1] = e end end
  assert_eq(#seen, 3, "a listener on the raised event saw every crossing")
  assert_eq(seen[1].above, false)
  assert_eq(seen[2].above, true)
  assert_eq(seen[3].above, false)
end)

test("cl-fluid-chest: plain chest never polls and raises nothing", function()
  local core = build(PLAIN)
  local t = tank_of(core)
  t.set_fluid(1, {name = "water", amount = 10})
  assert_nil(cl("record", core.unit_number).next_due, "no poll")
  assert_nil(cl("event_ids")[PLAIN].fluid_threshold, "no event declared")
end)

test("cl-fluid-chest: mining returns items and loses the fluid", function()
  local core = build(WATCH)
  local u = core.unit_number
  local t = tank_of(core)
  core.get_inventory(defines.inventory.chest).insert{name = "iron-plate", count = 30}
  t.set_fluid(1, {name = "water", amount = 120})
  local inv = game.create_inventory(8)
  assert_true(cl("mine", core, inv), "mined")
  assert_true(not core.valid, "core gone")
  assert_true(not t.valid, "tank gone")
  assert_nil(cl("record", u), "registry entry")
  assert_eq(inv.get_item_count("iron-plate"), 30, "items returned")
  assert_eq(inv.get_item_count(WATCH), 1, "chest returned")
  assert_eq(inv.get_item_count("water-barrel"), 0, "fluid is not turned into items")
  inv.destroy()
end)

-- A dying chest destroys its contents natively, and fluid has nowhere to spill.
test("cl-fluid-chest: death removes the tank and the record", function()
  local core, s, pos = build(PLAIN)
  local t = tank_of(core)
  core.get_inventory(defines.inventory.chest).insert{name = "copper-plate", count = 7}
  t.set_fluid(1, {name = "water", amount = 50})
  local u = core.unit_number
  core.die()
  assert_true(not t.valid, "tank gone")
  assert_nil(cl("record", u), "registry entry")
  assert_eq(s.count_entities_filtered{name = TANK, position = pos, radius = 2}, 0, "no tank left")
end)

test("cl-fluid-chest: script destroy with raise_destroy removes the tank", function()
  local core = build(PLAIN)
  local u = core.unit_number
  local t = tank_of(core)
  core.destroy{raise_destroy = true}
  assert_true(not t.valid, "tank gone")
  assert_nil(cl("record", u), "registry entry")
end)

test("cl-fluid-chest: clone carries fluid, items, orientation and threshold state", function()
  local core, s, pos = build(WATCH, 20)
  assert_true(cl("rotate", core), "rotate accepted")
  tank_of(core).set_fluid(1, {name = "water", amount = 180})
  poll(core)
  core.get_inventory(defines.inventory.chest).insert{name = "iron-gear-wheel", count = 5}
  s.clone_entities{entities = {core}, destination_offset = {6, 0}}
  local copy = s.find_entity(WATCH, {pos[1] + 6, pos[2]})
  assert_not_nil(copy, "clone exists")
  local t = tank_of(copy)
  assert_true(t and t.valid, "clone has a tank")
  assert_eq(t.position.x, copy.position.x, "tank under the clone")
  assert_eq(amount(t), 180, "fluid cloned")
  assert_eq(t.direction, EAST, "orientation cloned")
  assert_eq(copy.get_inventory(defines.inventory.chest).get_item_count("iron-gear-wheel"), 5, "items cloned")
  local rec = cl("record", copy.unit_number)
  assert_eq(rec.data.above[1], true, "threshold state cloned")
  assert_not_nil(rec.next_due, "clone polls on its own")
  local p = copy.position
  assert_eq(s.count_entities_filtered{name = tank_name(copy), area = {{p.x - 0.5, p.y - 0.5}, {p.x + 0.5, p.y + 0.5}}}, 1,
    "exactly one tank")
  assert_eq(amount(tank_of(core)), 180, "source untouched")
end)

test("cl-fluid-chest: rotating the core rotates the tank's connections", function()
  local core, s, pos = build(PLAIN)
  local t = tank_of(core)
  local east_pipe = s.create_entity{name = "pipe", position = {pos[1] + 1, pos[2]}, force = "player"}
  local north_pipe = s.create_entity{name = "pipe", position = {pos[1], pos[2] - 1}, force = "player"}
  assert_true(neighbours(t)[north_pipe.unit_number] ~= nil, "north pipe connected facing north")
  assert_nil(neighbours(t)[east_pipe.unit_number], "east pipe not connected facing north")
  assert_true(core.supports_direction, "the container core rotates (direction_count = 4)")
  assert_true(cl("rotate", core), "rotate accepted")
  assert_eq(core.direction, EAST, "core rotated")
  assert_eq(t.direction, EAST, "tank follows")
  assert_true(neighbours(t)[east_pipe.unit_number] ~= nil, "east pipe connected after rotating")
  assert_nil(neighbours(t)[north_pipe.unit_number], "north pipe dropped after rotating")
  assert_true(cl("rotate", core, true), "reverse rotation")
  assert_eq(t.direction, NORTH, "tank back north")
  assert_true(neighbours(t)[north_pipe.unit_number] ~= nil, "north pipe back")
end)

local function blueprint_of(s, pos)
  local inv = game.create_inventory(1)
  inv.insert{name = "blueprint"}
  local bp = inv[1]
  local mapping = bp.create_blueprint{surface = s, force = "player",
    area = {{pos[1] - 0.9, pos[2] - 0.9}, {pos[1] + 0.9, pos[2] + 0.9}}}
  cl("tag_blueprint", bp, mapping)
  return bp, inv
end

local function revive_all(ghosts)
  local out = {}
  for _, g in ipairs(ghosts) do
    local _, revived = g.revive{raise_revive = true}
    if revived then out[#out + 1] = revived end
  end
  return out
end

test("cl-fluid-chest: blueprint round-trip keeps one entity and the orientation", function()
  local core, s, pos = build(WATCH, 20)
  assert_true(cl("rotate", core), "rotate accepted")
  core.get_inventory(defines.inventory.chest).set_bar(5)
  local bp, inv = blueprint_of(s, pos)
  local entities = bp.get_blueprint_entities()
  assert_eq(#entities, 1, "one blueprint entity")
  assert_eq(entities[1].name, WATCH, "the core, no storage-tank")
  local bar = core.get_inventory(defines.inventory.chest).get_bar()
  assert_not_nil(entities[1].bar, "native bar carried")
  assert_eq(entities[1].direction, EAST, "orientation carried natively by the blueprint entity")
  local ghosts = bp.build_blueprint{surface = s, force = "player", position = {pos[1] + 6, pos[2]},
    skip_fog_of_war = false, build_mode = defines.build_mode.forced}
  assert_eq(#ghosts, 1, "one ghost")
  local built = revive_all(ghosts)
  assert_eq(#built, 1, "revived")
  local copy = built[1]
  assert_not_nil(cl("record", copy.unit_number), "registered")
  assert_eq(copy.direction, EAST, "core built facing east")
  assert_eq(tank_of(copy).direction, EAST, "tank built facing the core")
  assert_eq(copy.get_inventory(defines.inventory.chest).get_bar(), bar, "bar applied")
  assert_not_nil(cl("record", copy.unit_number).next_due, "revived watched chest polls")
  inv.destroy()
end)

-- Containers rotate since 2.1.7, so the ghost carries the blueprint's rotation
-- and the tank is built facing it with no tag involved.
test("cl-fluid-chest: rotated blueprint placement rotates the tank", function()
  local core, s, pos = build(PLAIN, 20)
  local bp, inv = blueprint_of(s, pos)
  local ghosts = bp.build_blueprint{surface = s, force = "player", position = {pos[1] + 6, pos[2]},
    direction = EAST, skip_fog_of_war = false, build_mode = defines.build_mode.forced}
  assert_eq(#ghosts, 1, "one ghost")
  local built = revive_all(ghosts)
  inv.destroy()
  assert_eq(#built, 1, "revived")
  assert_eq(built[1].direction, EAST, "core built rotated")
  assert_eq(tank_of(built[1]).direction, EAST, "tank built rotated")
end)
