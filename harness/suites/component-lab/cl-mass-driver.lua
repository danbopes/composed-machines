-- cl-mass-driver suite (TEST-ENTITIES-2.md section 7). Synchronous tests cover
-- the prototype, lifecycle, settings and the shot itself (fired through the
-- handler's own function); everything that needs a real 600-tick cycle reads
-- the scenario the mod armed at map creation (run with --fresh).

local CL = "component_lab"
local NAME = "cl-mass-driver"
local SLUG = "cl-mass-driver-slug"
local CYCLE_TICKS = 600
local SHOT_J = 40e6

local function cl(fn, ...) return remote.call(CL, fn, ...) end

-- This suite's own row: no other suite builds on y = 1600.
local row = require("_site").row{x = 0, y = 1600, half = 8}
local function site(width) return row:next(width or 14) end

local d = defines.direction

local function build(opts)
  opts = opts or {}
  local s, pos = site(opts.width)
  local core = s.create_entity{name = NAME, position = pos, direction = opts.direction, force = "player",
    raise_built = true}
  assert_not_nil(core, "create_entity " .. NAME)
  return core, s, pos
end

local function input(core) return core.get_inventory(defines.inventory.crafter_input) end
local function range_of(u) return cl("record", u).settings.range end

local function slugs(s, pos, radius)
  return s.find_entities_filtered{name = SLUG, position = pos, radius = radius or 4}
end

local function scenario()
  local sc = cl("md_scenario")
  assert_not_nil(sc, "scenario armed at on_init (run with --fresh)")
  assert_not_nil(sc.done_tick, "scenario finished (game.tick " .. game.tick .. ")")
  return sc
end

local function blueprint_of(s, pos)
  local inv = game.create_inventory(1)
  inv.insert{name = "blueprint"}
  local bp = inv[1]
  local mapping = bp.create_blueprint{surface = s, force = "player",
    area = {{pos[1] - 2, pos[2] - 2}, {pos[1] + 2, pos[2] + 2}}}
  cl("tag_blueprint", bp, mapping)
  return bp, inv
end

-- ---- prototypes -------------------------------------------------------------

test("cl-mass-driver: prototype is an S3 electric shell with a 40 MJ buffer", function()
  local p = assert_prototype("entity", NAME)
  assert_eq(p.type, "assembling-machine", "shell type")
  assert_eq(cl("shape", NAME), "S3", "shape")
  local es = p.electric_energy_source_prototype
  assert_not_nil(es, "electric source")
  assert_eq(es.buffer_capacity, SHOT_J, "buffer_capacity")
  assert_true(math.abs(es.get_input_flow_limit() - 8e6 / 60) < 1, "input_flow_limit: 4 MW draw + 4 MW charge")
  assert_eq(es.drain, 0, "no drain")
  assert_true(math.abs(p.get_max_energy_usage() - 4e6 / 60) < 1, "4 MW while cycling")
  local recipe = assert_prototype("recipe", NAME .. "-cycle")
  assert_eq(recipe.energy, 10, "cycle_time")
  assert_eq(#recipe.ingredients, 1, "one ingredient")
  assert_eq(recipe.ingredients[1].name, "iron-plate", "ingredient")
  assert_eq(recipe.ingredients[1].amount, 1, "one plate per shot")
  assert_eq(#recipe.products, 0, "no product: the shot is the output")
  assert_eq(assert_prototype("entity", SLUG).type, "projectile", "slug")
  local def = prototypes.mod_data["component-lab--" .. NAME].data
  assert_eq(#def.parts, 0, "no hidden parts: the shell's ingredient slot is the 'shell' inventory")
  assert_eq(def.spec.settings[1].name, "range", "range setting")
end)

-- ---- lifecycle --------------------------------------------------------------

test("cl-mass-driver: build registers the record with range default 20", function()
  local core = build()
  local rec = cl("record", core.unit_number)
  assert_not_nil(rec, "record")
  assert_eq(rec.settings.range, 20, "default range")
  assert_eq(core.get_recipe().name, NAME .. "-cycle", "fixed recipe")
  assert_true(core.is_updatable, "shell is updatable")
end)

test("cl-mass-driver: shell input takes iron plates only", function()
  local core = build()
  assert_true(core.insert{name = "iron-plate", count = 1} >= 1, "plate accepted")
  assert_eq(input(core).get_item_count("iron-plate") >= 1, true, "plate in the shell's input")
  assert_eq(input(core).insert{name = "copper-plate", count = 1}, 0, "copper refused")
end)

test("cl-mass-driver: range setting is clamped to 5..60", function()
  local core = build()
  local u = core.unit_number
  cl("call", u, "set_setting", "range", 100)
  assert_eq(range_of(u), 60, "clamped to max")
  cl("call", u, "set_setting", "range", 1)
  assert_eq(range_of(u), 5, "clamped to min")
  cl("call", u, "set_setting", "range", 33)
  assert_eq(range_of(u), 33, "in range")
end)

test("cl-mass-driver: a shot creates one slug flying along the facing to range", function()
  local cases = {
    {d.north, 0, -1}, {d.east, 1, 0}, {d.south, 0, 1}, {d.west, -1, 0},
  }
  for _, case in ipairs(cases) do
    local core, s, pos = build{direction = case[1], width = 70}
    local u = core.unit_number
    cl("call", u, "set_setting", "range", 25)
    local shot = cl("mass_driver_fire", u)
    local here = slugs(s, {pos[1] + case[2] * 1.5, pos[2] + case[3] * 1.5}, 0.6)
    assert_eq(#here, 1, "one slug at the muzzle, direction " .. case[1])
    assert_eq(shot.x, pos[1] + case[2] * 25, "target x, direction " .. case[1])
    assert_eq(shot.y, pos[2] + case[3] * 25, "target y, direction " .. case[1])
    assert_eq(cl("record", u).data.shots, 1, "shot counted")
    here[1].destroy()
  end
end)

test("cl-mass-driver: rotating turns the shot", function()
  local core, s, pos = build{width = 40}
  assert_eq(core.direction, d.north, "placed north")
  assert_true(cl("rotate", core), "rotate accepted (square shell turns 90 degrees)")
  assert_eq(core.direction, d.east, "now east")
  local shot = cl("mass_driver_fire", core.unit_number)
  assert_eq(shot.x, pos[1] + 20, "fires east")
  assert_eq(shot.y, pos[2], "not north")
  for _, e in pairs(slugs(s, pos, 4)) do e.destroy() end
end)

test("cl-mass-driver: script mine returns the waiting plate and the driver", function()
  local core = build()
  core.insert{name = "iron-plate", count = 1}
  local inv = game.create_inventory(8)
  local u = core.unit_number
  assert_true(cl("mine", core, inv), "mined")
  assert_true(not core.valid, "core gone")
  assert_nil(cl("record", u), "record removed")
  assert_eq(inv.get_item_count("iron-plate"), 1, "plate returned")
  assert_eq(inv.get_item_count(NAME), 1, "the driver")
  inv.destroy()
end)

test("cl-mass-driver: destroy and death drop the record", function()
  local core = build()
  local u = core.unit_number
  core.destroy{raise_destroy = true}
  assert_nil(cl("record", u), "destroy dropped the record")
  local victim = build()
  u = victim.unit_number
  victim.die()
  assert_nil(cl("record", u), "death dropped the record")
end)

test("cl-mass-driver: clone keeps range, facing and the waiting plate", function()
  local core, s = build{direction = d.west}
  local u = core.unit_number
  cl("call", u, "set_setting", "range", 42)
  core.insert{name = "iron-plate", count = 1}
  s.clone_entities{entities = {core}, destination_offset = {0, 5}}
  local copy = s.find_entity(NAME, {core.position.x, core.position.y + 5})
  assert_not_nil(copy, "clone exists")
  assert_not_nil(cl("record", copy.unit_number), "clone registered")
  assert_eq(range_of(copy.unit_number), 42, "range cloned")
  assert_eq(copy.direction, d.west, "facing cloned")
  assert_eq(input(copy).get_item_count("iron-plate"), 1, "plate cloned")
  local shot = cl("mass_driver_fire", copy.unit_number)
  assert_eq(shot.x, copy.position.x - 42, "clone fires west at its own range")
  for _, e in pairs(slugs(s, copy.position, 4)) do e.destroy() end
end)

test("cl-mass-driver: range setting and facing survive blueprint paste", function()
  local core, s, pos = build{direction = d.south}
  cl("call", core.unit_number, "set_setting", "range", 37)
  local bp, inv = blueprint_of(s, pos)
  local entities = bp.get_blueprint_entities()
  assert_eq(#entities, 1, "one entity in the blueprint")
  assert_eq(entities[1].name, NAME)
  local ghosts = bp.build_blueprint{surface = s, force = "player", position = {pos[1] + 6, pos[2]},
    skip_fog_of_war = false, build_mode = defines.build_mode.forced}
  assert_eq(#ghosts, 1, "one ghost")
  local _, revived = ghosts[1].revive{raise_revive = true}
  assert_not_nil(revived, "revived")
  assert_eq(revived.direction, d.south, "facing from the blueprint")
  assert_eq(range_of(revived.unit_number), 37, "range from the blueprint tags")
  inv.destroy()
end)

test("cl-mass-driver: paste settings copies range", function()
  local a = build()
  local b = build()
  cl("call", a.unit_number, "set_setting", "range", 51)
  cl("paste", a, b)
  assert_eq(range_of(b.unit_number), 51, "range pasted")
end)

-- ---- timed behaviour (scenario armed at on_init) ----------------------------

test("cl-mass-driver: plate in, power on: one slug after one cycle, plate consumed", function()
  local sc = scenario()
  local f, w = sc.final.powered, sc.watch.powered
  assert_eq(f.shots, 1, "one shot")
  assert_eq(f.products, 1, "one cycle finished")
  assert_eq(f.input, 0, "plate consumed")
  assert_not_nil(w.first, "a slug was seen")
  local fired = f.last_shot.tick - sc.t0
  -- A plate inserted during on_init starts crafting in that same tick's
  -- entity update, so the shot can land at t0 + 599.
  assert_true(fired >= CYCLE_TICKS - 1 and fired <= CYCLE_TICKS + 2, "fired after one 10 s cycle (tick +" .. fired .. ")")
  -- The watch runs in on_tick, before entity updates, so it sees the slug
  -- the tick after the craft that created it.
  assert_eq(w.first.tick, f.last_shot.tick + 1, "slug seen right after the finishing tick")
  assert_eq(w.max, 1, "exactly one slug")
  assert_true(w.last.x > w.first.x + 10, "slug flew east (" .. w.first.x .. " -> " .. w.last.x .. ")")
end)

-- The shell reports low_power until its buffer is full (measured), which is
-- the emulation's "charging"; the powered fixture starts charged.
test("cl-mass-driver: charged, powered driver cycles at full speed and reports working", function()
  local sc = scenario()
  assert_true(math.abs(sc.mid.progress - 0.5) < 0.01, "half a cycle at tick 300 (" .. sc.mid.progress .. ")")
  assert_eq(sc.mid.status, defines.entity_status.working, "working, not low_power")
end)

test("cl-mass-driver: no plate left: status item_ingredient_shortage, no further shot", function()
  local sc = scenario()
  assert_eq(sc.final.powered.status, defines.entity_status.item_ingredient_shortage, "powered driver after its shot")
  local idle = sc.final.idle
  assert_eq(idle.status, defines.entity_status.item_ingredient_shortage, "driver never given a plate")
  assert_eq(idle.shots, 0, "no shot without a plate")
  assert_nil(sc.watch.idle.first, "no slug without a plate")
end)

test("cl-mass-driver: charged buffer alone pays for one shot (~40 MJ drained)", function()
  local sc = scenario()
  -- The prototype reads 40 MJ, but a crafting machine's live buffer is
  -- larger (42.67 MJ measured on 2.1.24); energy per shot does not depend on it.
  assert_true(sc.buffer_size >= SHOT_J, "live buffer holds at least 40 MJ (" .. sc.buffer_size .. ")")
  assert_true(math.abs(sc.buffer_start - SHOT_J) < 1, "charged to 40 MJ (" .. sc.buffer_start .. ")")
  local f = sc.final.buffer
  assert_eq(f.shots, 1, "fired off the buffer with no network")
  local drained = sc.buffer_start - f.energy
  assert_true(math.abs(drained - SHOT_J) < SHOT_J * 0.01,
    "drained ~40 MJ (" .. string.format("%.0f", drained) .. " J)")
  assert_true(sc.mid.buffer_energy < sc.buffer_start * 0.6 and sc.mid.buffer_energy > sc.buffer_start * 0.4,
    "half drained at mid-cycle (" .. string.format("%.0f", sc.mid.buffer_energy) .. ")")
end)

test("cl-mass-driver: range setting bounds the flight", function()
  local sc = scenario()
  local f, w = sc.final.range, sc.watch.range
  assert_eq(f.shots, 1, "one shot")
  assert_not_nil(w.first, "slug seen")
  local flight = w.last.tick - w.first.tick
  assert_true(flight >= 5 and flight <= 8, "range 8 at speed 1 lives ~6.5 ticks (" .. flight .. ")")
  assert_true(w.last.y < w.first.y, "flew north")
  assert_eq(f.last_shot.y, f.position.y - 8, "target 8 tiles north of centre")
  assert_eq(f.last_shot.x, f.position.x, "straight north")
end)

test("cl-mass-driver: mine mid-cycle returns the in-flight plate, no shot", function()
  local sc = scenario()
  local m = sc.mined
  assert_not_nil(m, "mined at mid-cycle")
  assert_true(m.progress > 0.3 and m.progress < 0.7, "mid-cycle (" .. m.progress .. ")")
  assert_true(m.ok, "mined")
  assert_eq(m.plates, 1, "plate returned (return_ingredients_on_change)")
  assert_eq(m.drivers, 1, "driver returned")
  assert_nil(sc.watch.mine.first, "no slug from the mined driver")
end)

test("cl-mass-driver: clone mid-cycle carries progress and range, both fire", function()
  local sc = scenario()
  local c = sc.clone
  assert_not_nil(c, "clone taken")
  assert_true(c.source_progress > 0.3 and c.source_progress < 0.7, "source mid-cycle")
  assert_eq(c.copy_progress, c.source_progress, "crafting_progress cloned")
  assert_eq(c.copy_direction, d.south, "facing cloned")
  assert_eq(c.copy_range, 30, "range cloned")
  assert_eq(sc.final.clone.shots, 1, "source fired")
  assert_eq(sc.final.copy.shots, 1, "clone fired")
  assert_not_nil(sc.watch.copy.first, "clone's slug seen")
  assert_true(sc.watch.copy.last.y > sc.watch.copy.first.y, "clone's slug flew south")
end)

test("cl-mass-driver: KNOWN-LIMIT consume_at = finish keeps the plate in the input until the shot", function()
  local sc = scenario()
  assert_true(sc.mid.crafting, "mid-cycle sample taken while crafting")
  assert_eq(sc.mid.input, 1,
    "EMULATION LIMIT: an assembler takes its ingredients when the cycle starts, so the plate leaves the " ..
    "input slot at tick 0 of the charge, not when the shot fires; an inserter or player can never take back " ..
    "a plate the native consume_at = finish would still hold (input mid-cycle: " .. sc.mid.input .. ")")
end)
