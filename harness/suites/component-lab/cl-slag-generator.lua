-- cl-slag-generator suite. TEST-ENTITIES-2.md section 5 (S3 + v2 generation).
-- Behaviour over cycles is read from the fixture the mod builds at map creation
-- (scripts/entities/cl-slag-generator.lua): a suite runs inside one tick.

local CL = "component_lab"
local NAME = "cl-slag-generator"
local CYCLE = NAME .. "-cycle"
local GENERATOR = NAME .. "-generator"
local MJ = 1e6
local PER_CYCLE = 6 * MJ
local BUFFER = 20 * MJ

local function cl(fn, ...) return remote.call(CL, fn, ...) end

local STATUS_NAME = {}
for k, v in pairs(defines.entity_status) do STATUS_NAME[v] = k end
local function status_of(v) return STATUS_NAME[v] or tostring(v) end

local sites = require("_site")
local row = sites.row{x = 0, y = 1720}
local function site(width) return row:next(width or 8) end

local function build(width)
  local s, pos = site(width)
  local core = s.create_entity{name = NAME, position = pos, force = "player", raise_built = true}
  assert_not_nil(core, "create_entity " .. NAME)
  return core, s, pos
end

local function generator_of(core)
  return cl("parts", core.unit_number)["generator:output"]
end

local function near(a, b, tol, msg)
  assert_true(math.abs(a - b) <= (tol or 1),
    string.format("%s: %.1f vs %.1f (tolerance %.1f)", msg or "near", a, b, tol or 1))
end

local function fixture()
  local f = cl("slag_fixture")
  assert_not_nil(f, "fixture armed at on_init (run with --fresh)")
  assert_true(f.snaps.ten ~= nil and f.snaps.resumed ~= nil,
    string.format("fixture incomplete at tick %d (needs tick %d): the server did not run long enough", game.tick, f.done_at))
  return f
end

-- ---- prototype ---------------------------------------------------------------

test("slag-generator: S3 burner shell with a fixed water -> stone recipe and one generator part", function()
  assert_eq(cl("shape", NAME), "S3", "shape")
  local def = prototypes.mod_data["component-lab--" .. NAME].data
  assert_eq(def.core_type, "assembling-machine", "core type")
  assert_eq(#def.parts, 1, "one hidden part")
  assert_eq(def.parts[1].kind, "generator", "part kind")
  assert_eq(def.parts[1].prototype, GENERATOR, "part prototype")
  local p = assert_prototype("entity", NAME)
  assert_eq(p.fixed_recipe and p.fixed_recipe.name, CYCLE, "fixed_recipe")
  assert_not_nil(p.burner_prototype, "the burner stays on the shell (activity = cycle)")
  assert_eq(p.burner_prototype.fuel_categories.chemical, true, "chemical fuel")
  assert_eq(p.get_max_energy_usage(), 1 * MJ / 60, "1 MW")
  assert_eq(p.fluidbox_prototypes[1].filter.name, "water", "water filter")
  assert_eq(p.fluidbox_prototypes[1].production_type, "input", "input box")
  local r = assert_prototype("recipe", CYCLE)
  assert_eq(r.energy, 4, "cycle_time")
  assert_eq(#r.ingredients, 1)
  assert_eq(r.ingredients[1].name, "water")
  assert_eq(r.ingredients[1].amount, 40)
  assert_eq(#r.products, 1, "the energy product is not an engine result")
  assert_eq(r.products[1].name, "stone")
  local energy_product
  for _, product in ipairs(def.spec.process.products) do
    if product.type == "energy" then energy_product = product end
  end
  assert_not_nil(energy_product, "the energy product is kept in the spec")
  assert_eq(energy_product.amount, "6MJ")
end)

test("slag-generator: the generator part is a hidden secondary-output EEI, 20 MJ buffer, 2 MW out, 0 W production", function()
  local g = assert_prototype("entity", GENERATOR)
  assert_eq(g.type, "electric-energy-interface")
  assert_true(g.hidden, "hidden")
  local es = g.electric_energy_source_prototype
  assert_eq(es.usage_priority, "secondary-output", "priority")
  assert_eq(es.buffer_capacity, BUFFER, "buffer")
  assert_eq(es.get_output_flow_limit(), 2 * MJ / 60, "output flow limit")
  assert_eq(es.get_input_flow_limit(), 0, "never charges from the network")
end)

-- ---- lifecycle -----------------------------------------------------------------

test("slag-generator: build registers the shell and places the generator at its centre", function()
  local core = build()
  assert_not_nil(cl("record", core.unit_number), "record")
  local g = generator_of(core)
  assert_not_nil(g, "generator part")
  assert_eq(g.name, GENERATOR)
  assert_eq(g.position.x, core.position.x, "x")
  assert_eq(g.position.y, core.position.y, "y")
  assert_eq(g.force.name, "player", "force")
  assert_eq(g.energy, 0, "starts empty")
  assert_eq(g.power_production, 0, "energy_production 0: only the script fills the buffer")
  assert_eq(core.get_recipe().name, CYCLE, "fixed recipe")
  assert_eq(cl("owner_of", g.unit_number), core.unit_number, "part maps back to its core")
end)

test("slag-generator: ghost revive (robot path) registers the shell with its generator", function()
  local s, pos = site()
  local ghost = s.create_entity{name = "entity-ghost", inner_name = NAME, position = pos, force = "player"}
  local _, core = ghost.revive{raise_revive = true}
  assert_not_nil(core, "revived")
  assert_not_nil(generator_of(core), "generator part")
end)

test("slag-generator: mining returns the item, the coal and the stone; the generator goes", function()
  local core = build()
  local u = core.unit_number
  local g = generator_of(core)
  core.get_fuel_inventory().insert{name = "coal", count = 7}
  assert_eq(core.get_output_inventory().insert{name = "stone", count = 3}, 3, "stone in the result slot")
  core.set_fluid(1, {name = "water", amount = 100})
  g.energy = 5 * MJ
  local inv = game.create_inventory(8)
  assert_true(cl("mine", core, inv), "mined")
  assert_true(not core.valid, "core gone")
  assert_true(not g.valid, "generator gone")
  assert_nil(cl("record", u), "record gone")
  assert_eq(inv.get_item_count(NAME), 1, "item")
  assert_eq(inv.get_item_count("coal"), 7, "coal")
  assert_eq(inv.get_item_count("stone"), 3, "stone")
  assert_eq(inv.get_item_count(), 11, "nothing else")
  inv.destroy()
end)

test("slag-generator: die and destroy{raise_destroy} drop the record and the generator", function()
  local a = build()
  local ua, ga = a.unit_number, generator_of(a)
  a.die()
  assert_nil(cl("record", ua), "record after die")
  assert_true(not ga.valid, "generator after die")
  local b = build()
  local ub, gb = b.unit_number, generator_of(b)
  b.destroy{raise_destroy = true}
  assert_nil(cl("record", ub), "record after destroy")
  assert_true(not gb.valid, "generator after destroy")
end)

test("slag-generator: clone to another surface carries fuel, stone, water and the buffered energy", function()
  local core, s = build()
  core.get_fuel_inventory().insert{name = "coal", count = 4}
  core.get_output_inventory().insert{name = "stone", count = 2}
  core.set_fluid(1, {name = "water", amount = 120})
  generator_of(core).energy = 7 * MJ
  local dest = sites.temp_surface("cl-slag-clone")
  dest.request_to_generate_chunks(core.position, 1)
  dest.force_generate_chunk_requests()
  s.clone_entities{entities = {core}, destination_offset = {0, 0}, destination_surface = dest}
  local copy = dest.find_entity(NAME, core.position)
  assert_not_nil(copy, "clone exists")
  assert_not_nil(cl("record", copy.unit_number), "clone registered")
  local g = generator_of(copy)
  assert_not_nil(g, "clone has a generator")
  assert_eq(g.surface.name, dest.name, "generator on the clone's surface")
  near(g.energy, 7 * MJ, 1, "buffered energy cloned")
  assert_eq(copy.get_fuel_inventory().get_item_count("coal"), 4, "coal")
  assert_eq(copy.get_output_inventory().get_item_count("stone"), 2, "stone")
  assert_eq(copy.get_fluid(1).amount, 120, "water")
  near(generator_of(core).energy, 7 * MJ, 1, "source untouched")
end)

test("slag-generator: blueprint holds one entity and the revived ghost gets a fresh generator", function()
  local core, s, pos = build(16)
  local inv = game.create_inventory(1)
  inv.insert{name = "blueprint"}
  local bp = inv[1]
  local mapping = bp.create_blueprint{surface = s, force = "player",
    area = {{pos[1] - 1.5, pos[2] - 1.5}, {pos[1] + 1.5, pos[2] + 1.5}}}
  assert_eq(cl("tag_blueprint", bp, mapping), 1, "one core tagged")
  local entities = bp.get_blueprint_entities()
  assert_eq(#entities, 1, "the hidden generator is not blueprinted")
  assert_eq(entities[1].name, NAME)
  local ghosts = bp.build_blueprint{surface = s, force = "player", position = {pos[1] + 8, pos[2]},
    skip_fog_of_war = false, build_mode = defines.build_mode.forced}
  assert_eq(#ghosts, 1, "one ghost")
  local _, revived = ghosts[1].revive{raise_revive = true}
  assert_not_nil(revived, "revived")
  assert_not_nil(generator_of(revived), "generator part on the revived shell")
  assert_eq(revived.get_recipe().name, CYCLE, "fixed recipe")
  inv.destroy()
end)

test("slag-generator: rotating turns the shell's water input and keeps the generator at the centre", function()
  local core = build()
  assert_eq(core.direction, defines.direction.north)
  assert_true(cl("rotate", core, false), "rotated")
  assert_eq(core.direction, defines.direction.east, "shell faces east")
  local g = generator_of(core)
  assert_true(g and g.valid, "generator survives the rotation")
  assert_eq(g.position.x, core.position.x)
  assert_eq(g.position.y, core.position.y)
end)

test("slag-generator: an idle shell with coal and no water burns nothing and makes nothing", function()
  local core = build()
  core.get_fuel_inventory().insert{name = "coal", count = 3}
  assert_true(not core.is_crafting(), "no cycle without water")
  assert_eq(generator_of(core).energy, 0, "no energy")
  assert_eq(cl("record", core.unit_number).next_due, nil, "no Lua poll while idle")
end)

-- ---- behaviour over cycles (fixture) -------------------------------------------

test("slag-generator: 10 cycles with water and coal deliver ~60 MJ to a consumer on the network, plus stone", function()
  local t = fixture().snaps.ten.run
  assert_true(t.cycles >= 10, "at least 10 cycles, got " .. t.cycles)
  assert_eq(t.finished, t.cycles, "one handler call per engine cycle")
  assert_eq(t.stone, t.finished, "one stone per cycle in the result slot")
  near(t.produced, PER_CYCLE * t.cycles, 1, "6 MJ added per cycle")
  assert_not_nil(t.sink, "sink EEI")
  near(t.sink + t.buffer, t.produced, 1, "every joule is in the buffer or delivered (no loss)")
  assert_true(t.sink >= 10 * PER_CYCLE - PER_CYCLE,
    string.format("sink received %.1f MJ, expected about 60 MJ minus at most one cycle still buffered", t.sink / MJ))
  assert_eq(t.pending, 0, "never blocked with a consumer present")
  assert_eq(status_of(t.status), "working", "status")
  assert_nil(t.custom, "no custom status while working")
  assert_true(t.coal < 20, "coal burnt")
end)

test("slag-generator: no water gives fluid_ingredient_shortage and no energy", function()
  local d = fixture().snaps.dry.dry
  assert_eq(status_of(d.status), "fluid_ingredient_shortage", "native status")
  assert_eq(d.cycles, 0, "no cycle")
  assert_eq(d.buffer, 0, "generator empty")
  assert_eq(d.stone, 0, "no stone")
  assert_eq(d.coal, 20, "no fuel burnt while starved")
  local later = fixture().snaps.resumed.dry
  assert_eq(later.cycles, 0, "still nothing ~1400 ticks later")
  assert_eq(later.buffer, 0, "still no energy")
end)

test("slag-generator: a full buffer with no consumer blocks the shell (full_output) and holds the remainder", function()
  local b = fixture().snaps.blocked.full
  assert_eq(b.cycles, 4, "6+6+6 fit in 20 MJ, the fourth cycle overflows")
  assert_eq(b.finished, 4, "no fifth cycle finished")
  near(b.buffer, BUFFER, 1, "buffer full")
  near(b.pending, 4 * PER_CYCLE - BUFFER, 1, "the 4 MJ that did not fit are held, not lost")
  assert_true(b.disabled, "shell disabled by script")
  assert_eq(b.custom, "entity-status.full-output", "full_output shown")
end)

test("slag-generator: emptying the buffer releases the block at the next poll and nothing is lost", function()
  local f = fixture()
  local r, later = f.snaps.released.full, f.snaps.resumed.full
  near(f.actions.drained, BUFFER, 1, "the fixture drained a full buffer")
  assert_eq(r.pending, 0, "held energy flushed")
  near(r.buffer, 4 * PER_CYCLE - BUFFER, 1, "the held 4 MJ are now in the buffer")
  assert_true(not r.disabled, "shell running again")
  assert_nil(r.custom, "full_output cleared")
  assert_true(later.cycles >= 5, "cycles resumed")
  near(later.buffer + later.pending + f.actions.drained, later.produced, 1, "every joule accounted for")
end)

test("slag-generator: KNOWN-LIMIT the block lands one cycle late (next cycle's water already taken)", function()
  local b = fixture().snaps.blocked.full
  -- Native: the overflowing cycle holds at progress 1 and the next one has not
  -- started. Emulation: the crafted event fires after the engine has already
  -- delivered the stone and begun the next cycle, so the shell freezes early in
  -- cycle 5 with its 40 water consumed.
  assert_eq(b.progress, 1, string.format(
    "KNOWN-LIMIT: the emulation can only block after the engine finished the cycle; the shell froze at progress %.3f "
    .. "of the next cycle, its water already consumed. A native energy product would hold at progress 1 "
    .. "with the stone and the next cycle's water untouched", b.progress))
end)
