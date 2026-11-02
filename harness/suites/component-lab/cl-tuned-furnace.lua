-- cl-tuned-furnace suite. TEST-ENTITIES-2.md section 8.
-- Behaviour over ticks is read from the fixture the mod builds at map creation
-- (scripts/entities/cl-tuned-furnace.lua): a suite runs inside one tick.

local CL = "component_lab"
local NAME = "cl-tuned-furnace"
local CYCLE = NAME .. "-cycle"
local BASE_TICKS = 3.2 * 60

local function cl(fn, ...) return remote.call(CL, fn, ...) end

local STATUS_NAME = {}
for k, v in pairs(defines.entity_status) do STATUS_NAME[v] = k end
local function status_of(v) return STATUS_NAME[v] or tostring(v) end

local sites = require("_site")
local row = sites.row{x = 0, y = 1480}
local function site(width) return row:next(width or 8) end

local function build(width)
  local s, pos = site(width)
  local core = s.create_entity{name = NAME, position = pos, force = "player", raise_built = true}
  assert_not_nil(core, "create_entity " .. NAME)
  return core, s, pos
end

local function rate(core) return cl("record", core.unit_number).settings.rate end
local function speed(core) return (core.local_effect or {}).speed or 0 end
local function near(a, b) return math.abs(a - b) < 1e-4 end

-- Runs the pass the record has scheduled, as the scheduler would at that tick.
local function run_pass(core)
  local due = cl("record", core.unit_number).next_due
  assert_not_nil(due, "a pass is always scheduled")
  cl("dispatch", due, core.unit_number)
end

local function fixture()
  local f = cl("tuned_fixture")
  assert_not_nil(f, "fixture armed at on_init (run with --fresh)")
  assert_true(f.snaps.b ~= nil and f.snaps.pulse_end ~= nil,
    string.format("fixture incomplete at tick %d (needs tick %d): the server did not run long enough", game.tick, f.done_at))
  return f
end

-- ---- prototype ---------------------------------------------------------------

test("tuned-furnace: S3 electric shell, fixed ore->plate cycle, speed receiver, circuit connector, no hidden parts", function()
  assert_eq(cl("shape", NAME), "S3", "shape")
  local def = prototypes.mod_data["component-lab--" .. NAME].data
  assert_eq(def.core_type, "assembling-machine", "core type")
  assert_eq(#def.parts, 0, "the shell carries everything natively: no beacon, no combinator")
  local p = assert_prototype("entity", NAME)
  assert_eq(p.fixed_recipe and p.fixed_recipe.name, CYCLE, "fixed_recipe")
  assert_eq(p.get_crafting_speed(), 1, "base speed 1")
  assert_true(p.allowed_effects and p.allowed_effects.speed, "speed is an allowed effect")
  assert_true(p.effect_receiver and p.effect_receiver.uses_local_effects ~= false, "local effects reach the shell")
  assert_true(p.electric_energy_source_prototype ~= nil, "electric")
  local r = assert_prototype("recipe", CYCLE)
  assert_eq(r.energy, 3.2, "cycle_time")
  assert_eq(r.ingredients[1].name, "iron-ore")
  assert_eq(r.products[1].name, "iron-plate")
  local spec = def.spec
  assert_eq(spec.settings[1].name, "rate")
  assert_eq(spec.settings[1].default, 10)
  assert_eq(spec.circuit_inputs.settings[1].signal, "signal-R", "rate is bound to signal-R")
end)

-- ---- lifecycle -----------------------------------------------------------------

test("tuned-furnace: build registers the shell, rate defaults to 10, a pass is scheduled and speed is +0", function()
  local core = build()
  local rec = cl("record", core.unit_number)
  assert_not_nil(rec, "record")
  assert_eq(rec.settings.rate, 10, "rate default")
  assert_eq(next(cl("parts", core.unit_number)), nil, "no hidden parts")
  assert_eq(core.get_recipe().name, CYCLE, "fixed recipe set")
  assert_not_nil(rec.next_due, "pass scheduled")
  assert_true(rec.next_due - game.tick <= 30, "next pass within 30 ticks")
  assert_eq((rec.next_due - core.unit_number) % 30, 0, "pass phased on the unit number (SPEC 3.4)")
  assert_true(near(speed(core), 0), "rate 10 -> local_effect.speed 0")
  assert_not_nil(core.get_wire_connector(defines.wire_connector_id.circuit_red, true), "circuit connector")
end)

test("tuned-furnace: ghost revive (robot path) registers the shell", function()
  local s, pos = site()
  local ghost = s.create_entity{name = "entity-ghost", inner_name = NAME, position = pos, force = "player"}
  local _, core = ghost.revive{raise_revive = true}
  assert_not_nil(core, "revived")
  assert_not_nil(cl("record", core.unit_number), "record")
  assert_eq(rate(core), 10)
end)

test("tuned-furnace: the rate setting drives local_effect.speed = rate/10 - 1, clamped to 1..40", function()
  local core = build()
  local u = core.unit_number
  local cases = {{30, 30, 2}, {5, 5, -0.5}, {40, 40, 3}, {99, 40, 3}, {0, 1, -0.9}, {10, 10, 0}, {25, 25, 1.5}}
  for _, c in ipairs(cases) do
    cl("call", u, "set_setting", "rate", c[1])
    run_pass(core)
    assert_eq(rate(core), c[2], "rate after set_setting(" .. c[1] .. ")")
    assert_true(near(speed(core), c[3]), string.format("rate %d: speed %s, want %s", c[2], speed(core), c[3]))
  end
  cl("call", u, "set_setting", "rate", 30)
  run_pass(core)
  assert_true(near(core.crafting_speed, 3), "crafting_speed with rate 30 is 3x, got " .. core.crafting_speed)
end)

test("tuned-furnace: the speed floor follows effect_receiver.speed_limits (rate 1 asks for -0.9)", function()
  local core = build()
  cl("call", core.unit_number, "set_setting", "rate", 1)
  run_pass(core)
  assert_true(near(speed(core), -0.9), "local_effect keeps what was written")
  assert_true(core.crafting_speed >= 0.2 - 1e-4, "speed_limits.low = -0.8 caps the slowdown: crafting_speed " .. core.crafting_speed)
end)

test("tuned-furnace: mining refunds the item plus the ore and plates in the shell", function()
  local core = build()
  local u = core.unit_number
  core.insert{name = "iron-ore", count = 7}
  core.get_inventory(defines.inventory.crafter_output).insert{name = "iron-plate", count = 3}
  local inv = game.create_inventory(8)
  assert_true(cl("mine", core, inv), "mined")
  assert_true(not core.valid, "core gone")
  assert_nil(cl("record", u), "record gone")
  assert_eq(inv.get_item_count(NAME), 1, "item refunded")
  assert_eq(inv.get_item_count("iron-ore"), 7, "ore refunded")
  assert_eq(inv.get_item_count("iron-plate"), 3, "plates refunded")
  inv.destroy()
end)

test("tuned-furnace: die and destroy{raise_destroy} drop the record", function()
  local a = build()
  local ua = a.unit_number
  a.die()
  assert_nil(cl("record", ua), "record after die")
  local b = build()
  local ub = b.unit_number
  b.destroy{raise_destroy = true}
  assert_nil(cl("record", ub), "record after destroy")
end)

test("tuned-furnace: clone to another surface carries rate and the speed, and keeps polling", function()
  local core, s = build()
  cl("call", core.unit_number, "set_setting", "rate", 30)
  run_pass(core)
  local dest = sites.temp_surface("cl-tuned-clone")
  dest.request_to_generate_chunks(core.position, 1)
  dest.force_generate_chunk_requests()
  s.clone_entities{entities = {core}, destination_offset = {0, 0}, destination_surface = dest}
  local copy = dest.find_entity(NAME, core.position)
  assert_not_nil(copy, "clone exists")
  local rec = cl("record", copy.unit_number)
  assert_not_nil(rec, "clone registered")
  assert_eq(rec.settings.rate, 30, "rate cloned")
  assert_true(near(speed(copy), 2), "clone runs at +200%")
  assert_not_nil(rec.next_due, "clone has its own pass")
  assert_eq(rate(core), 30, "source untouched")
end)

test("tuned-furnace: blueprint carries the default rate and a changed one to revived ghosts", function()
  local a, s, pos = build(24)
  local b = s.create_entity{name = NAME, position = {pos[1] + 4, pos[2]}, force = "player", raise_built = true}
  cl("call", b.unit_number, "set_setting", "rate", 25)
  local inv = game.create_inventory(1)
  inv.insert{name = "blueprint"}
  local bp = inv[1]
  local mapping = bp.create_blueprint{surface = s, force = "player",
    area = {{pos[1] - 1.5, pos[2] - 1.5}, {pos[1] + 5.5, pos[2] + 1.5}}}
  assert_eq(cl("tag_blueprint", bp, mapping), 2, "two cores tagged")
  assert_eq(#bp.get_blueprint_entities(), 2, "two entities, nothing hidden")
  local ghosts = bp.build_blueprint{surface = s, force = "player", position = {pos[1] + 12, pos[2]},
    skip_fog_of_war = false, build_mode = defines.build_mode.forced}
  assert_eq(#ghosts, 2, "two ghosts")
  local rates = {}
  for _, g in pairs(ghosts) do
    local _, revived = g.revive{raise_revive = true}
    assert_not_nil(revived, "revived")
    run_pass(revived)
    rates[#rates + 1] = rate(revived)
    assert_true(near(speed(revived), rate(revived) / 10 - 1), "revived shell applies its rate")
  end
  table.sort(rates)
  assert_eq(rates[1], 10, "default rate survives blueprint -> ghost -> revive")
  assert_eq(rates[2], 25, "changed rate survives blueprint -> ghost -> revive")
  assert_true(a.valid, "source intact")
  inv.destroy()
end)

test("tuned-furnace: paste copies the rate and applies the speed at once", function()
  local a, s, pos = build(12)
  local b = s.create_entity{name = NAME, position = {pos[1] + 4, pos[2]}, force = "player", raise_built = true}
  cl("call", a.unit_number, "set_setting", "rate", 5)
  assert_true(cl("paste", a, b), "paste handled")
  assert_eq(rate(b), 5, "rate pasted")
  assert_true(near(speed(b), -0.5), "speed applied on paste, before the next pass")
end)

-- ---- behaviour over ticks (fixture) ------------------------------------------

test("tuned-furnace: signal-R = 30 sets rate 30 and speed +2 within one pass", function()
  local a = fixture().snaps.a.fast
  assert_eq(a.rate, 30, "rate written from the signal")
  assert_true(near(a.speed, 2), "local_effect.speed " .. a.speed)
  assert_true(near(a.crafting_speed, 3), "crafting_speed " .. a.crafting_speed)
  assert_eq(status_of(a.status), "working")
end)

test("tuned-furnace: signal-R = 30 crafts about 3x the default over 1200 ticks", function()
  local f = fixture()
  local function made(role) return f.snaps.b[role].finished - f.snaps.a[role].finished end
  assert_eq(f.snaps.b.default.tick - f.snaps.a.default.tick, 1200, "window")
  local default, fast = made("default"), made("fast")
  local want_default, want_fast = 1200 / BASE_TICKS, 1200 * 3 / BASE_TICKS
  assert_true(math.abs(default - want_default) <= 1, string.format("default: %d plates, want %.2f", default, want_default))
  assert_true(math.abs(fast - want_fast) <= 1, string.format("signal 30: %d plates, want %.2f", fast, want_fast))
  assert_true(fast >= 2.5 * default, string.format("fast %d vs default %d", fast, default))
end)

test("tuned-furnace: signal-R = 5 gives speed -0.5 and half the plates", function()
  local f = fixture()
  local a = f.snaps.a.slow
  assert_eq(a.rate, 5)
  assert_true(near(a.speed, -0.5), "local_effect.speed " .. a.speed)
  local made = f.snaps.b.slow.finished - a.finished
  local want = 1200 * 0.5 / BASE_TICKS
  assert_true(math.abs(made - want) <= 1, string.format("signal 5: %d plates, want %.2f", made, want))
end)

test("tuned-furnace: no signal leaves the configured rate in charge", function()
  local f = fixture()
  assert_eq(f.snaps.a.default.rate, 10, "no wire, rate stays at its setting")
  assert_true(near(f.snaps.b.default.speed, 0), "speed 0")
end)

test("tuned-furnace: enable condition false gives disabled_by_control_behavior and no crafting", function()
  local f = fixture()
  local a, b = f.snaps.a.off, f.snaps.b.off
  assert_eq(status_of(a.status), "disabled_by_control_behavior", "status at a")
  assert_eq(status_of(b.status), "disabled_by_control_behavior", "status at b")
  assert_eq(a.finished, 0, "nothing crafted before a")
  assert_eq(b.finished, 0, "nothing crafted over 1200 ticks")
  assert_eq(b.ore, 30, "no ore consumed")
  assert_eq(a.rate, 30, "the rate signal is still read while disabled")
end)

test("tuned-furnace: a pulse between two passes leaves the rate untouched (emulation behaviour)", function()
  local f = fixture()
  local peak, after = f.snaps.pulse_peak.pulse, f.snaps.pulse_end.pulse
  assert_eq(f.pulse.on - f.pulse.pass, 2, "pulse starts just after a pass")
  assert_true(f.pulse.off < f.pulse.pass + 30, "pulse ends before the next pass")
  assert_eq(peak.rate, 10, "rate during the pulse")
  assert_true(near(after.speed, 0), "speed after the pulse")
  assert_true(after.crafting or after.finished == 1, "the fed cycle ran")
end)

test("tuned-furnace: KNOWN-LIMIT a signal-R pulse shorter than the 30-tick pass is missed", function()
  local f = fixture()
  local after = f.snaps.pulse_end.pulse
  -- The native entity reads its bound signal at cycle start (V2-PARTS 1.3). The
  -- cycle started mid-pulse, so at rate 30 it takes 64 ticks and is long done
  -- 100 ticks after the feed; the 30-tick poll never saw the pulse and ran it at
  -- rate 10 (192 ticks).
  assert_eq(after.finished, 1, string.format(
    "KNOWN-LIMIT: the %d-tick pulse fell between two 30-tick polls; the fed cycle ran at rate %d (progress %.2f after 100 ticks) where the native cycle-start read would have used rate 30",
    f.pulse.off - f.pulse.on, after.rate, after.progress))
end)
