-- cl-seep-derrick suite. TEST-ENTITIES.md section 6.
-- Behaviour over ticks is read from the fixture the mod builds at map creation
-- (scripts/entities/cl-seep-derrick.lua): a suite runs inside one tick.

local CL = "component_lab"
local NAME = "cl-seep-derrick"
local CYCLE = NAME .. "-cycle"

local function cl(fn, ...) return remote.call(CL, fn, ...) end

local STATUS_NAME = {}
for k, v in pairs(defines.entity_status) do STATUS_NAME[v] = k end
local function status_of(v) return STATUS_NAME[v] or tostring(v) end

local sites = require("_site")
local row = sites.row{x = 640, y = 80}
local function site(width) return row:next(width or 8) end

local function build(width)
  local s, pos = site(width)
  local core = s.create_entity{name = NAME, position = pos, force = "player", raise_built = true}
  assert_not_nil(core, "create_entity " .. NAME)
  return core, s, pos
end

local function fixture()
  local f = cl("seep_fixture")
  assert_not_nil(f, "fixture armed at on_init (run with --fresh)")
  assert_true(f.snaps.c ~= nil,
    string.format("fixture incomplete at tick %d (needs tick %d): the server did not run long enough", game.tick, f.done_at))
  assert_eq(game.speed, 1, "the fixture must hand game.speed back to the other suites")
  return f
end

local function snap(label, role) return fixture().snaps[label][role] end

local function depletion(core) return cl("record", core.unit_number).settings.depletion end

-- ---- prototype ---------------------------------------------------------------

test("seep-derrick: S3 assembler shell with a fixed, hidden cycle recipe and no hidden parts", function()
  assert_eq(cl("shape", NAME), "S3", "shape")
  local def = prototypes.mod_data["component-lab--" .. NAME].data
  assert_eq(def.core_type, "assembling-machine", "core type")
  assert_eq(#def.parts, 0, "the shell carries everything natively")
  local p = assert_prototype("entity", NAME)
  assert_eq(p.fixed_recipe and p.fixed_recipe.name, CYCLE, "fixed_recipe")
  assert_eq(p.get_crafting_speed(), 1, "crafting speed = base_speed")
  assert_eq(p.fluidbox_prototypes[1].filter.name, "water", "input filter")
  assert_eq(p.fluidbox_prototypes[2].filter.name, "crude-oil", "output filter")
  local r = assert_prototype("recipe", CYCLE)
  assert_true(r.hidden, "cycle recipe hidden")
  assert_true(r.hidden_from_player_crafting, "not hand-craftable")
  assert_eq(r.energy, 2, "cycle_time")
  assert_eq(r.ingredients[1].name, "water")
  assert_eq(r.ingredients[1].amount, 10)
  assert_eq(r.products[1].name, "crude-oil")
  assert_eq(r.products[1].amount, 100)
  local cats = {}
  for k, v in pairs(r.categories) do cats[#cats + 1] = type(k) == "string" and k or v end
  assert_eq(#cats, 1, "one category")
  assert_eq(cats[1], CYCLE, "own category, so no other machine can run it")
end)

-- ---- lifecycle -----------------------------------------------------------------

test("seep-derrick: build registers the shell, sets the fixed recipe and is updatable", function()
  local core = build()
  local rec = cl("record", core.unit_number)
  assert_not_nil(rec, "record")
  assert_eq(rec.settings.depletion, 0, "setting default")
  assert_eq(next(cl("parts", core.unit_number)), nil, "no hidden parts")
  assert_eq(core.get_recipe().name, CYCLE, "fixed recipe set")
  assert_true(core.is_updatable, "shell.is_updatable (an assembler always ticks)")
end)

test("seep-derrick: ghost revive (robot path) registers the shell", function()
  local s, pos = site()
  local ghost = s.create_entity{name = "entity-ghost", inner_name = NAME, position = pos, force = "player"}
  local _, core = ghost.revive{raise_revive = true}
  assert_not_nil(core, "revived")
  assert_not_nil(cl("record", core.unit_number), "record")
end)

test("seep-derrick: mining refunds only the item (fluids are lost, no module slots)", function()
  local core = build()
  local u = core.unit_number
  core.set_fluid(1, {name = "water", amount = 300})
  core.set_fluid(2, {name = "crude-oil", amount = 400})
  local inv = game.create_inventory(8)
  assert_true(cl("mine", core, inv), "mined")
  assert_true(not core.valid, "core gone")
  assert_nil(cl("record", u), "record gone")
  assert_eq(inv.get_item_count(NAME), 1, "item refunded")
  assert_eq(inv.get_item_count(), 1, "nothing else refunded")
  inv.destroy()
end)

test("seep-derrick: die and destroy{raise_destroy} drop the record", function()
  local a = build()
  local ua = a.unit_number
  a.die()
  assert_nil(cl("record", ua), "record after die")
  local b = build()
  local ub = b.unit_number
  b.destroy{raise_destroy = true}
  assert_nil(cl("record", ub), "record after destroy")
end)

test("seep-derrick: clone to another surface carries fluids and depletion", function()
  local core, s = build()
  core.set_fluid(1, {name = "water", amount = 25})
  core.set_fluid(2, {name = "crude-oil", amount = 300})
  cl("call", core.unit_number, "set_setting", "depletion", 11)
  local dest = sites.temp_surface("cl-seep-clone")
  dest.request_to_generate_chunks(core.position, 1)
  dest.force_generate_chunk_requests()
  s.clone_entities{entities = {core}, destination_offset = {0, 0}, destination_surface = dest}
  local copy = dest.find_entity(NAME, core.position)
  assert_not_nil(copy, "clone exists")
  assert_not_nil(cl("record", copy.unit_number), "clone registered")
  assert_eq(depletion(copy), 11, "depletion cloned")
  assert_eq(copy.get_fluid(1).amount, 25, "input fluid cloned")
  assert_eq(copy.get_fluid(2).amount, 300, "output fluid cloned")
  assert_eq(depletion(core), 11, "source untouched")
end)

test("seep-derrick: blueprint has one entity, no settable recipe, and carries depletion to the revived ghost", function()
  local core, s, pos = build(16)
  cl("call", core.unit_number, "set_setting", "depletion", 7)
  local inv = game.create_inventory(1)
  inv.insert{name = "blueprint"}
  local bp = inv[1]
  local mapping = bp.create_blueprint{surface = s, force = "player",
    area = {{pos[1] - 1.5, pos[2] - 1.5}, {pos[1] + 1.5, pos[2] + 1.5}}}
  assert_eq(cl("tag_blueprint", bp, mapping), 1, "one core tagged")
  local entities = bp.get_blueprint_entities()
  assert_eq(#entities, 1, "one entity")
  assert_eq(entities[1].name, NAME)
  assert_true(entities[1].recipe == nil or entities[1].recipe == CYCLE, "only the fixed recipe can be in the blueprint")
  assert_eq(bp.get_blueprint_entity_tags(1).component_lab.settings.depletion, 7, "depletion in tags")

  local ghosts = bp.build_blueprint{surface = s, force = "player", position = {pos[1] + 8, pos[2]},
    skip_fog_of_war = false, build_mode = defines.build_mode.forced}
  assert_eq(#ghosts, 1, "one ghost")
  local _, revived = ghosts[1].revive{raise_revive = true}
  assert_not_nil(revived, "revived")
  assert_eq(depletion(revived), 7, "depletion survives blueprint -> ghost -> revive")
  assert_eq(revived.get_recipe().name, CYCLE, "revived shell runs the fixed recipe")
  inv.destroy()
end)

test("seep-derrick: the fixed recipe cannot be replaced by script", function()
  local core = build()
  local ok = pcall(core.set_recipe, "iron-gear-wheel")
  assert_true(not ok or core.get_recipe().name == CYCLE, "set_recipe on a fixed_recipe shell changed the recipe")
end)

-- KNOWN GAP: Factorio's undo restores the entity without script state, and the
-- emulation keeps depletion in storage. Undo needs a player, which a headless
-- server has none of; the death ghost is the same no-tags rebuild path and is
-- asserted instead. The native SPEC `settings` would ride on the entity and
-- survive both.
test("seep-derrick: depletion is lost when the shell is rebuilt without tags (undo / death ghost, known gap)", function()
  local core, s, pos = build()
  cl("call", core.unit_number, "set_setting", "depletion", 9)
  local force = game.forces.player
  local was = force.create_ghost_on_entity_death
  force.create_ghost_on_entity_death = true
  core.die()
  force.create_ghost_on_entity_death = was
  local ghost = s.find_entity("entity-ghost", pos)
  assert_not_nil(ghost, "death ghost")
  assert_nil(ghost.tags and ghost.tags.component_lab, "the engine's death ghost carries no script tags")
  local _, revived = ghost.revive{raise_revive = true}
  assert_not_nil(revived, "revived")
  assert_eq(depletion(revived), 0, "depletion reset: the emulation cannot carry script state through an engine rebuild")
end)

-- ---- fluid API and conditions --------------------------------------------------

test("seep-derrick: remove_fluid(index, amount) positional works on the shell", function()
  local core = build()
  local entity, index = cl("call", core.unit_number, "fluid_box", 1)
  assert_eq(entity, core, "fluid box 1 is the shell's own")
  assert_eq(index, 1)
  core.set_fluid(1, {name = "water", amount = 30})
  local removed = core.remove_fluid(1, 10)
  assert_not_nil(removed, "removed")
  assert_eq(removed.name, "water")
  assert_eq(removed.amount, 10, "removed amount")
  assert_eq(core.get_fluid(1).amount, 20, "left in box 1")
  assert_eq(core.get_fluid_count("water"), 20, "get_fluid_count")
end)

test("seep-derrick: idle shell without water shows low_input_fluid and clears it when water arrives", function()
  local core = build()
  local u = core.unit_number
  local cs = core.custom_status
  assert_not_nil(cs, "custom_status set on an empty derrick")
  assert_eq(cs.label[1], "entity-status.low-input-fluid", "condition status")
  assert_eq(cs.diode, defines.entity_status_diode.yellow, "condition diode")
  local due = cl("record", u).next_due
  assert_not_nil(due, "poll scheduled while the condition fails")
  core.set_fluid(1, {name = "water", amount = 100})
  cl("dispatch", due, u)
  assert_nil(core.custom_status, "status cleared once water is present")
  assert_nil(cl("record", u).next_due, "poll stops when the condition holds")
end)

-- ---- behaviour over ticks (fixture) ------------------------------------------

test("seep-derrick: with water piped in, crude appears at 100 per 120 ticks", function()
  local a, b = snap("a", "flow"), snap("b", "flow")
  assert_eq(b.tick - a.tick, 120, "snapshot spacing")
  assert_eq(b.crude - a.crude, 100, "crude over 120 ticks")
  assert_eq(status_of(a.status), "working", "status")
  assert_eq(a.crude, 100 * a.finished, "every product is in the output box")
  assert_nil(a.custom, "no condition status while working")
end)

test("seep-derrick: water cut gives fluid_ingredient_shortage and progress holds", function()
  local a, b, c = snap("a", "starve"), snap("b", "starve"), snap("c", "starve")
  assert_eq(status_of(a.status), "fluid_ingredient_shortage", "native status")
  assert_eq(status_of(b.status), "fluid_ingredient_shortage", "still starved")
  assert_eq(a.progress, b.progress, "crafting_progress holds while starved")
  assert_eq(a.crude, 100, "one cycle from 15 water")
  assert_eq(b.crude, 100, "no production while starved")
  assert_eq(a.custom, "entity-status.low-input-fluid", "the condition's status is shown")
  assert_eq(a.custom_diode, defines.entity_status_diode.yellow, "condition diode")
  assert_eq(status_of(c.status), "working", "runs again after refill")
  assert_nil(c.custom, "condition status cleared by the poll")
  assert_true(c.crafting, "a cycle started after refill")
  assert_eq(c.cycles, 1, "no cycle finished while starved")
end)

test("seep-derrick: blocked output gives full_output, progress clamps at 1, no product lost", function()
  local f = fixture()
  local a, b, c = f.snaps.a.blocked, f.snaps.b.blocked, f.snaps.c.blocked
  assert_eq(status_of(a.status), "full_output", "status with 950/1000 crude")
  assert_eq(status_of(b.status), "full_output", "still blocked")
  assert_eq(a.progress, 1, "progress clamped at 1")
  assert_eq(b.progress, 1, "progress still 1")
  assert_eq(a.finished, 0, "no cycle completed while blocked")
  assert_eq(b.crude, 950, "output box untouched while blocked")
  assert_eq(f.actions.removed, 500, "remove_fluid(2, 500) unblocked it")
  assert_true(c.finished >= 1, "cycles resumed after unblocking")
  assert_eq(c.crude + f.actions.removed, 950 + 100 * c.finished, "every product accounted for")
end)

test("seep-derrick: each cycle raises exactly one crafted event and one depletion step", function()
  local f = fixture()
  for label, by_role in pairs(f.snaps) do
    for role, s in pairs(by_role) do
      local where = role .. "@" .. label
      assert_eq(s.cycles, s.finished, where .. ": crafted handler calls vs products_finished")
      assert_eq(s.raised, s.finished, where .. ": cycle_finished events vs products_finished")
      assert_eq(s.depletion, s.finished, where .. ": depletion vs products_finished")
    end
  end
end)
