-- cl-creep-collector suite (TEST-ENTITIES-2.md section 3). Synchronous tests
-- drive the target poll through the scheduler's synthetic dispatch; anything
-- that needs real cycles and real power reads the scenario the mod armed at map
-- creation (run with --fresh).

local CL = "component_lab"
local NAME = "cl-creep-collector"
local UNIT_J = 800e3
local DRAIN_W = 5e3

local function cl(fn, ...) return remote.call(CL, fn, ...) end

-- Wide sites: the collector searches 8 tiles around itself.
local row = require("_site").row{x = 0, y = 1360, half = 12}
local function site() return row:next(24) end

local function build()
  local s, pos = site()
  local core = s.create_entity{name = NAME, position = pos, force = "player", raise_built = true}
  assert_not_nil(core, "create_entity " .. NAME)
  return core, s, pos
end

local function parts(u) return cl("parts", u) or {} end
local function spoils(u) return cl("call", u, "inventory", "spoils") end

local function poll(u)
  local due = cl("record", u).next_due
  assert_not_nil(due, "a poll is scheduled")
  cl("dispatch", due, u)
end

local function tree(s, pos, dx, dy)
  local t = s.create_entity{name = "tree-01", position = {pos[1] + dx, pos[2] + dy}}
  assert_not_nil(t, "tree placed")
  return t
end

local function label(core) return core.custom_status and core.custom_status.label[1] end

local function scenario()
  local s = cl("creep_scenario")
  assert_not_nil(s, "scenario armed at on_init (run with --fresh)")
  assert_not_nil(s.done_tick, "scenario finished (game.tick " .. game.tick .. ")")
  return s
end

-- ---- prototypes -------------------------------------------------------------

test("cl-creep-collector: prototypes and shape S3", function()
  local p = assert_prototype("entity", NAME)
  assert_eq(p.type, "assembling-machine", "shell type")
  assert_eq(cl("shape", NAME), "S3", "shape")
  local es = p.electric_energy_source_prototype
  assert_not_nil(es, "electric shell")
  assert_true(math.abs(p.energy_usage * 60 - 400e3) < 1, "400 kW (" .. p.energy_usage * 60 .. ")")
  assert_true(math.abs(es.drain * 60 - DRAIN_W) < 1, "5 kW drain (" .. es.drain * 60 .. ")")
  local recipe = assert_prototype("recipe", NAME .. "-cycle")
  assert_eq(recipe.energy, 2, "cycle_time")
  assert_eq(#recipe.ingredients, 0, "consume_at script: no engine ingredients")
  assert_eq(#recipe.products, 0, "no engine products")
  assert_prototype("entity", "cl-creep-collector-poll-eei")
end)

-- ---- lifecycle --------------------------------------------------------------

test("cl-creep-collector: build creates the spoils container and an outside proxy", function()
  local core = build()
  local u = core.unit_number
  local p = parts(u)
  for _, key in ipairs({"inventory:spoils", "proxy:spoils"}) do
    assert_true(p[key] ~= nil and p[key].valid, "part " .. key)
    assert_eq(cl("owner_of", p[key].unit_number), u, key .. " owner")
  end
  assert_eq(p["proxy:spoils"].proxy_target_entity, p["inventory:spoils"], "proxy target")
  assert_eq(p["proxy:spoils"].position.x, core.position.x + 2, "proxy just east of the shell")
  assert_eq(#spoils(u), 4, "spoils size")
end)

test("cl-creep-collector: an inserter east of the shell reaches the proxy, not the shell", function()
  local core, s, pos = build()
  local ins = s.create_entity{name = "inserter", position = {pos[1] + 3, pos[2]}, force = "player",
    direction = defines.direction.west}
  local at = s.find_entities_filtered{position = ins.pickup_position}
  local names = {}
  for _, e in pairs(at) do names[#names + 1] = e.name end
  table.sort(names)
  assert_eq(table.concat(names, ","), "cl-creep-collector-proxy-spoils",
    "the pickup tile holds the proxy, not the shell")
end)

-- ---- target choice and conditions -------------------------------------------

test("cl-creep-collector: no target idles disabled with waiting_for_script", function()
  local core = build()
  local u = core.unit_number
  poll(u)
  assert_true(core.disabled_by_script, "disabled_by_script")
  assert_true(not core.is_crafting(), "not crafting")
  assert_eq(label(core), "cl-status.waiting-for-script", "custom status")
  local due = cl("record", u).next_due
  assert_eq(due - game.tick, 60, "looks again in 60 ticks")
end)

test("cl-creep-collector: a tree in range starts one cycle; out of range does not", function()
  local core, s, pos = build()
  local u = core.unit_number
  local far = tree(s, pos, 9, 0)
  poll(u)
  assert_true(core.disabled_by_script, "a tree 9 tiles off is out of range")
  local near = tree(s, pos, -5, 4)
  poll(u)
  assert_true(not core.disabled_by_script, "enabled for a cycle")
  assert_nil(core.custom_status, "engine status shows while running")
  assert_eq(cl("record", u).data.target, near, "the tree in range is the target")
  assert_nil(cl("record", u).next_due, "no poll while a cycle runs")
  assert_true(far.valid and near.valid, "targets are removed at the end of the cycle, not the start")
end)

test("cl-creep-collector: the nearest target wins, rocks count", function()
  local core, s, pos = build()
  local u = core.unit_number
  tree(s, pos, 6, 0)
  local rock = s.create_entity{name = "big-rock", position = {pos[1] - 3, pos[2] - 3}}
  assert_not_nil(rock, "rock placed")
  poll(u)
  assert_eq(cl("record", u).data.target, rock, "nearest target is the rock")
end)

test("cl-creep-collector: spoils at 200 items holds with full_output", function()
  local core, s, pos = build()
  local u = core.unit_number
  spoils(u).insert{name = "wood", count = 200}
  tree(s, pos, 3, 3)
  poll(u)
  assert_true(core.disabled_by_script, "no cycle into a full output")
  assert_eq(label(core), "entity-status.full-output", "full_output status")
  assert_eq(core.custom_status.diode, defines.entity_status_diode.yellow, "yellow diode")
  spoils(u).remove{name = "wood", count = 1}
  poll(u)
  assert_true(not core.disabled_by_script, "starts once below 200")
end)

-- ---- removal, clone, blueprint ----------------------------------------------

test("cl-creep-collector: script mine returns spoils and the collector", function()
  local core = build()
  local u = core.unit_number
  spoils(u).insert{name = "wood", count = 12}
  spoils(u).insert{name = "stone", count = 7}
  local p = parts(u)
  local inv = game.create_inventory(8)
  assert_true(cl("mine", core, inv), "mined")
  assert_true(not core.valid, "core gone")
  for key, part in pairs(p) do assert_true(not part.valid, key .. " removed") end
  assert_nil(cl("record", u), "record removed")
  assert_eq(inv.get_item_count("wood"), 12, "wood returned")
  assert_eq(inv.get_item_count("stone"), 7, "stone returned")
  assert_eq(inv.get_item_count(NAME), 1, "the collector")
  inv.destroy()
end)

test("cl-creep-collector: destroy and death remove every part; death spills spoils", function()
  local core = build()
  local p = parts(core.unit_number)
  core.destroy{raise_destroy = true}
  for key, part in pairs(p) do assert_true(not part.valid, "destroy left " .. key) end

  local victim, s, pos = build()
  local u = victim.unit_number
  p = parts(u)
  spoils(u).insert{name = "wood", count = 9}
  victim.die()
  for key, part in pairs(p) do assert_true(not part.valid, "death left " .. key) end
  assert_nil(cl("record", u), "record removed")
  local spilled = 0
  for _, e in pairs(s.find_entities_filtered{name = "item-on-ground", position = pos, radius = 5}) do
    if e.stack.name == "wood" then spilled = spilled + e.stack.count end
  end
  assert_eq(spilled, 9, "spilled spoils")
end)

test("cl-creep-collector: clone copies parts, spoils and the running cycle", function()
  local core, s, pos = build()
  local u = core.unit_number
  spoils(u).insert{name = "wood", count = 8}
  local t = tree(s, pos, -4, -4)
  poll(u)
  s.clone_entities{entities = {core}, destination_offset = {0, 6}}
  local copy = s.find_entity(NAME, {core.position.x, core.position.y + 6})
  assert_not_nil(copy, "clone exists")
  local cu = copy.unit_number
  local p = parts(cu)
  for _, key in ipairs({"inventory:spoils", "proxy:spoils"}) do
    assert_true(p[key] ~= nil and p[key].valid, "cloned part " .. key)
    assert_eq(p[key].position.y, copy.position.y, key .. " at the clone")
  end
  assert_eq(p["proxy:spoils"].proxy_target_entity, p["inventory:spoils"], "clone's proxy targets the clone's container")
  assert_eq(spoils(cu).get_item_count("wood"), 8, "spoils cloned")
  assert_eq(copy.disabled_by_script, false, "running state cloned")
  assert_eq(cl("record", cu).data.target, t, "target cloned")
end)

test("cl-creep-collector: blueprint holds one entity; the revived copy idles and searches", function()
  local core, s, pos = build()
  local inv = game.create_inventory(1)
  inv.insert{name = "blueprint"}
  local bp = inv[1]
  local mapping = bp.create_blueprint{surface = s, force = "player",
    area = {{pos[1] - 3, pos[2] - 2}, {pos[1] + 3, pos[2] + 2}}}
  cl("tag_blueprint", bp, mapping)
  local entities = bp.get_blueprint_entities()
  assert_eq(#entities, 1, "no container or proxy in the blueprint")
  assert_eq(entities[1].name, NAME)
  local ghosts = bp.build_blueprint{surface = s, force = "player", position = {pos[1], pos[2] + 6},
    skip_fog_of_war = false, build_mode = defines.build_mode.forced}
  assert_eq(#ghosts, 1, "one ghost")
  local _, revived = ghosts[1].revive{raise_revive = true}
  assert_not_nil(revived, "revived")
  local ru = revived.unit_number
  assert_not_nil(cl("record", ru), "revived core registered")
  assert_true(revived.disabled_by_script, "revived core idles")
  assert_not_nil(parts(ru)["proxy:spoils"], "revived proxy")
  assert_not_nil(cl("record", ru).next_due, "revived core searches")
  inv.destroy()
end)

-- ---- timed behaviour (scenario armed at on_init) ----------------------------

-- The shell draws its 5 kW drain while idle (disabled_by_script does not stop
-- it), as any idle assembler does; the native type would do the same. So the
-- expected draw is 3 x 800 kJ plus drain over the whole window plus the one
-- fill of the shell's own buffer.
local function expected_draw(ticks, cycles, buffer)
  return cycles * UNIT_J + DRAIN_W * ticks / 60 + buffer
end

test("cl-creep-collector: three trees, three cycles, 3 x 800 kJ of real power", function()
  local s = scenario()
  local cell, fin, final = s.cells.trio, s.finished.trio, s.final.trio
  assert_eq(#fin, 3, "three cycle_finished events")
  for i = 2, 3 do
    assert_eq(fin[i].tick - fin[i - 1].tick, 120, "back-to-back 2 s cycles")
  end
  assert_eq(final.products, 3, "products_finished")
  assert_eq(fin[3].targets, 0, "all three trees gone after the third cycle")
  assert_eq(fin[2].targets, 1, "one at a time")
  assert_eq(final.targets, 0, "still gone at the end")
  assert_true(final.chest_wood > 0, "the burner inserter took wood out through the proxy")
  assert_eq(final.spoils_wood + final.chest_wood + final.held_wood, 12, "3 x 4 wood harvested")
  local used = cell.energy0 - fin[3].energy
  local expected = expected_draw(fin[3].tick - s.t0, 3, final.buffer)
  local err = math.abs(used - expected) / (3 * UNIT_J)
  assert_true(err <= 0.02, string.format("drew %.0f J, expected %.0f J (3 x 800 kJ +- 2%%, off %.2f%%)",
    used, expected, err * 100))
  assert_true(final.disabled, "idle once the trees are gone")
  assert_eq(final.custom, "cl-status.waiting-for-script", "waiting_for_script")
end)

test("cl-creep-collector: idle shell reports disabled, draws only its drain", function()
  local s = scenario()
  local mid, final = s.idle_mid, s.final.idle
  assert_true(final.disabled, "disabled_by_script")
  assert_true(not final.crafting, "not crafting")
  assert_eq(final.custom, "cl-status.waiting-for-script", "custom status")
  assert_eq(final.updatable, mid.updatable, "is_updatable stable while idle (" .. tostring(final.updatable) .. ")")
  assert_eq(#s.finished.idle, 0, "no cycles")
  local used = s.cells.idle.energy0 - final.energy
  local expected = expected_draw(final.tick - s.t0, 0, final.buffer)
  assert_true(math.abs(used - expected) <= 0.02 * expected,
    string.format("idle draw %.0f J, drain + buffer fill %.0f J", used, expected))
end)

test("cl-creep-collector: full spoils start no cycle and draw only the drain", function()
  local s = scenario()
  local final = s.final.full
  assert_eq(#s.finished.full, 0, "no cycles")
  assert_true(final.disabled, "disabled")
  assert_eq(final.custom, "entity-status.full-output", "full_output")
  assert_eq(final.targets, 1, "the tree is untouched")
  local used = s.cells.full.energy0 - final.energy
  local expected = expected_draw(final.tick - s.t0, 0, final.buffer)
  assert_true(math.abs(used - expected) <= 0.02 * expected,
    string.format("full draw %.0f J, drain + buffer fill %.0f J", used, expected))
end)

test("cl-creep-collector: a rock yields stone", function()
  local s = scenario()
  assert_eq(#s.finished.rock, 1, "one cycle")
  assert_eq(s.final.rock.targets, 0, "rock removed")
  assert_true(spoils(s.cells.rock.unit).get_item_count("stone") > 0, "stone in spoils")
end)

test("cl-creep-collector: the Rampant poll cell harvests at the same energy per unit", function()
  local s = scenario()
  local p = s.poll_final
  assert_not_nil(p, "poll cell sampled")
  assert_eq(p.harvested, 3, "three units of work")
  assert_eq(p.targets, 0, "trees removed")
  assert_eq(p.wood, 12, "wood in the chest")
end)

-- A recipe with no ingredients begins its next craft the tick the last one
-- ends, before the library can disable the shell, so a collector that has run
-- reports is_crafting() while it waits; one that never ran does not. The native
-- type would report idle. It has advanced one tick (1/120) before freezing, so
-- the next script-started cycle is one tick short; visible to any mod reading it.
test("cl-creep-collector: KNOWN-LIMIT a shell that has run reports is_crafting while it waits", function()
  local s = scenario()
  local ran, never = s.final.trio, s.final.idle
  assert_true(ran.disabled and never.disabled, "both idle")
  assert_eq(never.crafting, false, "never ran: not crafting")
  assert_eq(ran.crafting, true, "ran: still reports crafting (native: idle)")
  assert_true(ran.progress < 1 / 120 + 1e-9, "the frozen craft is at most one tick in (" .. ran.progress .. ")")
end)
