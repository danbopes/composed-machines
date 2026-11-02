-- cl-waste-heat-smelter suite. TEST-ENTITIES-2.md section 6.
-- In-tick tests cover the parts, lifecycle and heat connectivity; the 50-plate
-- craft and the idle/starved behaviour read the fixture the entity script builds
-- at map creation, so run with --fresh after any prototype or on_init change.

local NAME = "cl-waste-heat-smelter"
local HEAT = NAME .. "-heat"
local SPECIFIC_HEAT = 1e6
local HEAT_PER_CYCLE = 400e3

local CL = "component_lab"
local function cl(fn, ...) return remote.call(CL, fn, ...) end

local row = require("_site").row{x = 0, y = 1840, half = 8}
local function site(width) return row:next(width or 12) end

local function build(opts)
  opts = opts or {}
  local s, pos = site()
  local core = s.create_entity{name = NAME, position = pos, force = "player", direction = opts.direction,
    raise_built = true}
  assert_not_nil(core, "create_entity " .. NAME)
  return core, core.unit_number, s, pos
end

local function parts(u)
  local out = {}
  for key, e in pairs(cl("parts", u) or {}) do out[key] = e end
  return out
end

local function heat_part(u) return parts(u)["heat:heat"] end

local function neighbours_include(entity, other)
  for _, n in pairs(entity.heat_neighbours or {}) do
    if n == other then return true end
  end
  return false
end

local function count_near(s, pos)
  return s.count_entities_filtered{area = {{pos[1] - 1.5, pos[2] - 1.5}, {pos[1] + 1.5, pos[2] + 1.5}},
    name = {NAME, HEAT}}
end

local function fixture()
  local f = cl("whs_fixture")
  assert_not_nil(f, "fixture is built at on_init (run with --fresh)")
  assert_not_nil(f.samples.idle, "fixture finished sampling (tick " .. game.tick .. ", t0 " .. f.t0 .. ")")
  return f
end

-- ---- prototypes and parts -------------------------------------------------

test("cl-waste-heat-smelter: prototypes, shape S3, electric shell + hidden heat interface", function()
  local p = assert_prototype("entity", NAME)
  assert_eq(p.type, "assembling-machine", "core type")
  assert_eq(p.fixed_recipe.name, NAME .. "-cycle", "fixed recipe")
  assert_eq(p.electric_energy_source_prototype ~= nil, true, "electric shell")
  assert_eq(cl("shape", NAME), "S3", "shape")
  local h = assert_prototype("entity", HEAT)
  assert_eq(h.type, "heat-interface", "heat part type")
  assert_eq(h.heat_buffer_prototype.max_temperature, 500, "max temperature")
  assert_eq(h.heat_buffer_prototype.specific_heat, SPECIFIC_HEAT, "1 MJ per degree")
  local recipe = prototypes.recipe[NAME .. "-cycle"]
  assert_eq(recipe.energy, 3.2, "cycle time")
  assert_eq(#recipe.products, 1, "the recipe carries only the plate; heat is the handler's")
  assert_eq(recipe.products[1].name, "copper-plate", "product")
  assert_eq(recipe.ingredients[1].name, "copper-ore", "ingredient")
  local def = prototypes.mod_data["component-lab--" .. NAME].data
  assert_eq(table.concat(def.part_names, ","), HEAT, "one hidden part")
end)

test("cl-waste-heat-smelter: build gives 1 core + 1 heat interface; only the shell is updatable", function()
  local core, u, s, pos = build()
  assert_eq(count_near(s, pos), 2, "entities per smelter (native: 1)")
  local h = heat_part(u)
  assert_not_nil(h, "heat part")
  assert_eq(h.position.x, pos[1], "heat part centred on the core")
  assert_eq(h.position.y, pos[2], "heat part centred on the core")
  assert_true(core.is_updatable, "shell is updatable")
  assert_eq(h.temperature, 15, "starts at default temperature")
  assert_eq(core.get_recipe().name, NAME .. "-cycle", "fixed recipe set")
end)

test("cl-waste-heat-smelter: a heat pipe south of the core connects; west of it does not", function()
  local _, u, s, pos = build()
  local south = s.create_entity{name = "heat-pipe", position = {pos[1], pos[2] + 2}, force = "player"}
  local west = s.create_entity{name = "heat-pipe", position = {pos[1] - 2, pos[2]}, force = "player"}
  local h = heat_part(u)
  assert_true(neighbours_include(h, south), "south pipe is a heat neighbour of the interface")
  assert_true(not neighbours_include(h, west), "west pipe is not (only the declared connection)")
end)

test("cl-waste-heat-smelter: the handler's heat flows into the pipe", function()
  local _, u, s, pos = build()
  local pipe = s.create_entity{name = "heat-pipe", position = {pos[1], pos[2] + 2}, force = "player"}
  assert_eq(cl("call", u, "add_heat", HEAT_PER_CYCLE), HEAT_PER_CYCLE, "one cycle's heat fits")
  assert_eq(heat_part(u).temperature, 15.4, "0.4 degrees per cycle on 1 MJ/degree")
  assert_eq(pipe.temperature, 15, "conduction happens in the heat pass, not in the same tick")
end)

-- ---- the 50-plate craft (fixture) -------------------------------------------

test("cl-waste-heat-smelter: fixture: 50 plates crafted, every heat pipe warmed", function()
  local f = fixture()
  local crafted = f.samples.crafted
  local plates = 0
  for i, rig in ipairs(f.rigs) do
    local at = crafted.rigs[i]
    local tag = "rig " .. i .. ": "
    assert_eq(at.products, f.ore, tag .. "cycles finished")
    plates = plates + at.plates
    assert_eq(at.lost, 0, tag .. "no heat lost below max_temperature")
    local rise_pipe = at.pipe - rig.pipe_before
    local rise_iface = at.interface - rig.interface_before
    -- Each rig makes 10 x 400 kJ = 4 MJ into two 1 MJ/degree buffers. Heat only
    -- flows across a gradient of at least 1 degree (min_temperature_gradient),
    -- so the pipe ends within a degree of the interface.
    local total = (rise_pipe + rise_iface) * SPECIFIC_HEAT
    assert_true(math.abs(total - f.ore * HEAT_PER_CYCLE) < 1,
      string.format("%sheat conserved: %.1f J in pipe + interface for %d J made", tag, total, f.ore * HEAT_PER_CYCLE))
    assert_true(rise_pipe > 1, string.format("%sthe pipe rose %.2f degrees (interface %.2f)", tag, rise_pipe, rise_iface))
    assert_true(math.abs(rise_iface - rise_pipe) < 1.0001, tag .. "pipe and interface within the 1-degree gradient")
    assert_true(f.samples.mid.rigs[i].interface > rig.interface_before, tag .. "already warming after 3 cycles")
  end
  assert_eq(plates, 50, "50 plates across the rigs")
end)

test("cl-waste-heat-smelter: fixture: out of ore (plates taken) it stops heating, status item_ingredient_shortage", function()
  local f = fixture()
  local crafted, idle = f.samples.crafted, f.samples.idle
  assert_true(idle.tick - crafted.tick >= 600, "sampled 600 ticks apart")
  for i = 1, #f.rigs do
    local tag = "rig " .. i .. ": "
    assert_eq(idle.rigs[i].products, crafted.rigs[i].products, tag .. "no cycle while idle")
    assert_eq(idle.rigs[i].pipe, crafted.rigs[i].pipe, tag .. "pipe temperature stopped rising")
    assert_eq(idle.rigs[i].interface, crafted.rigs[i].interface, tag .. "interface temperature stopped rising")
    assert_eq(idle.rigs[i].status, defines.entity_status.item_ingredient_shortage, tag .. "idle status")
  end
end)

test("cl-waste-heat-smelter: fixture: never fed -> item_ingredient_shortage, no heat at all", function()
  local f = fixture()
  assert_eq(f.samples.idle.starved_status, defines.entity_status.item_ingredient_shortage, "status")
  assert_eq(f.samples.idle.starved_pipe, f.starved.pipe_before, "pipe untouched")
  assert_eq(f.starved.core.products_finished, 0, "nothing crafted")
end)

-- ---- rotation -----------------------------------------------------------------

test("cl-waste-heat-smelter: the shell rotates and the heat part stays centred", function()
  local core, u = build()
  local turned = cl("rotate", core, false)
  assert_true(turned, "rotate accepted")
  assert_eq(core.direction, defines.direction.east, "facing east")
  local h = heat_part(u)
  assert_true(h.valid, "heat part survived")
  assert_eq(h.position.x, core.position.x, "still centred")
end)

test("cl-waste-heat-smelter: KNOWN-LIMIT the heat connection follows a rotation", function()
  local core, u, s, pos = build()
  cl("rotate", core, false)
  local west = s.create_entity{name = "heat-pipe", position = {pos[1] - 2, pos[2]}, force = "player"}
  local south = s.create_entity{name = "heat-pipe", position = {pos[1], pos[2] + 2}, force = "player"}
  local h = heat_part(u)
  -- Facing east, the spec's south connection {0, 1} turns to the west side.
  assert_true(neighbours_include(h, west) and not neighbours_include(h, south),
    "EMULATION LIMIT: the hidden heat-interface has no direction (supports_direction = " ..
    tostring(h.supports_direction) .. "), so its connections keep the prototype's south side after the " ..
    "core turns (west pipe connected: " .. tostring(neighbours_include(h, west)) .. ", south pipe connected: " ..
    tostring(neighbours_include(h, south)) .. "); a native HeatBuffer owner rotates its connections")
end)

test("cl-waste-heat-smelter: KNOWN-LIMIT built facing east, the connection faces west", function()
  local _, u, s, pos = build({direction = defines.direction.east})
  local west = s.create_entity{name = "heat-pipe", position = {pos[1] - 2, pos[2]}, force = "player"}
  assert_true(neighbours_include(heat_part(u), west),
    "EMULATION LIMIT: a smelter placed (or blueprinted) facing east still connects south only; " ..
    "per-direction heat connections need a native HeatBuffer owner or one hidden prototype per direction")
end)

-- ---- blueprint, removal, clone ----------------------------------------------

test("cl-waste-heat-smelter: blueprint has one entity and revives with its heat part", function()
  local _, _, s, pos = build()
  local inv = game.create_inventory(1)
  inv.insert{name = "blueprint"}
  local bp = inv[1]
  local mapping = bp.create_blueprint{surface = s, force = "player",
    area = {{pos[1] - 1.5, pos[2] - 1.5}, {pos[1] + 1.5, pos[2] + 1.5}}}
  cl("tag_blueprint", bp, mapping)
  local entities = bp.get_blueprint_entities()
  assert_eq(#entities, 1, "hidden heat part is not blueprinted")
  assert_eq(entities[1].name, NAME)
  local ghosts = bp.build_blueprint{surface = s, force = "player", position = {pos[1] + 6, pos[2]},
    skip_fog_of_war = false, build_mode = defines.build_mode.forced}
  assert_eq(#ghosts, 1, "one ghost")
  local _, revived = ghosts[1].revive{raise_revive = true}
  assert_not_nil(revived, "revived")
  local h = heat_part(revived.unit_number)
  assert_not_nil(h, "revived smelter has its heat part")
  assert_eq(h.temperature, 15, "fresh buffer")
  inv.destroy()
end)

test("cl-waste-heat-smelter: mining returns ore, plates and the smelter; heat part gone", function()
  local core, u = build()
  core.get_inventory(defines.inventory.crafter_input).insert{name = "copper-ore", count = 7}
  core.get_inventory(defines.inventory.crafter_output).insert{name = "copper-plate", count = 5}
  local h = heat_part(u)
  local buffer = game.create_inventory(8)
  assert_true(cl("mine", core, buffer), "mined")
  assert_eq(buffer.get_item_count("copper-ore"), 7, "ore returned")
  assert_eq(buffer.get_item_count("copper-plate"), 5, "plates returned")
  assert_eq(buffer.get_item_count(NAME), 1, "smelter item returned")
  assert_true(not h.valid, "heat interface removed")
  assert_nil(cl("record", u), "record gone")
  buffer.destroy()
end)

test("cl-waste-heat-smelter: destroy with raise_destroy and death remove the heat part", function()
  local a, ua = build()
  local ha = heat_part(ua)
  a.destroy{raise_destroy = true}
  assert_true(not ha.valid, "destroyed: heat part removed")
  assert_nil(cl("record", ua), "destroyed: record gone")
  local b, ub = build()
  local hb = heat_part(ub)
  b.die()
  assert_true(not hb.valid, "died: heat part removed")
  assert_nil(cl("record", ub), "died: record gone")
end)

test("cl-waste-heat-smelter: the heat part is indestructible", function()
  local _, u = build()
  local h = heat_part(u)
  assert_true(not h.destructible, "indestructible")
end)

test("cl-waste-heat-smelter: clone carries its own heat part and its temperature", function()
  local core, u, s, pos = build()
  core.get_inventory(defines.inventory.crafter_input).insert{name = "copper-ore", count = 3}
  cl("call", u, "add_heat", 85e6)
  s.clone_entities{entities = {core}, destination_offset = {6, 0}}
  local copy = s.find_entity(NAME, {pos[1] + 6, pos[2]})
  assert_not_nil(copy, "clone exists")
  local hc = heat_part(copy.unit_number)
  assert_not_nil(hc, "clone has a heat part")
  assert_true(hc ~= heat_part(u), "its own")
  assert_eq(hc.position.x, copy.position.x, "at the clone")
  assert_eq(hc.temperature, 100, "temperature cloned")
  assert_eq(copy.get_inventory(defines.inventory.crafter_input).get_item_count("copper-ore"), 3, "ore cloned")
  assert_eq(count_near(s, {pos[1] + 6, pos[2]}), 2, "one core + one heat part at the clone")
end)
