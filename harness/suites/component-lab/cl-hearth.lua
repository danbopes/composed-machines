-- cl-hearth suite. TEST-ENTITIES-2.md section 1.
-- Same-tick behaviour is driven through the entity's pass (hearth_poll) or a
-- synthetic scheduler dispatch; burning, crafting and flame-out over real ticks
-- are read from the fixture the mod arms at on_init (run with --fresh first).

local CL = "component_lab"
local NAME = "cl-hearth"
local CYCLE = NAME .. "-cycle"
local WATTS = 90000
local PER_TICK = WATTS / 60
local POLL = 20

local function cl(fn, ...) return remote.call(CL, fn, ...) end

local STATUS_NAME = {}
for k, v in pairs(defines.entity_status) do STATUS_NAME[v] = k end
local function status_name(v) return STATUS_NAME[v] or tostring(v) end

-- This suite's own row: no other suite builds on y = 1240.
local row = require("_site").row{x = 0, y = 1240}
local function site(width) return row:next(width or 10) end

local function build()
  local s, pos = site()
  local core = s.create_entity{name = NAME, position = pos, force = "player", raise_built = true}
  assert_not_nil(core, "create_entity " .. NAME)
  return core, s, core.position
end

local function parts_of(core)
  local out = {}
  for key, e in pairs(cl("parts", core.unit_number) or {}) do out[key] = e end
  return out
end

local function reactor_of(core) return parts_of(core)["energy:energy"] end
local function fuel_of(core) return cl("call", core.unit_number, "fuel_inventory") end
local function input_of(core) return core.get_inventory(defines.inventory.crafter_input) end
local function output_of(core) return core.get_inventory(defines.inventory.crafter_output) end
local function poll(core) return cl("hearth_poll", core.unit_number) end
local function rec_of(core) return cl("record", core.unit_number) end

local function all_invalid(parts)
  for key, e in pairs(parts) do
    if e.valid then return false, key end
  end
  return true
end

local function power_events(u, log)
  local out = {}
  for _, e in ipairs(log or {}) do
    if e.unit_number == u and e.flag == "power_state_changed" then out[#out + 1] = e end
  end
  return out
end

-- ---- prototype ---------------------------------------------------------------

test("hearth: S3 burner-always shape; void shell with a fixed recipe; burner on a hidden reactor", function()
  assert_eq(cl("shape", NAME), "S3", "shape")
  local def = prototypes.mod_data["component-lab--" .. NAME].data
  assert_eq(def.watch, "burner", "watcher")
  assert_eq(def.core_type, "assembling-machine", "core type")
  assert_eq(def.spec.activity, "always", "activity")
  local kinds = {}
  for _, p in ipairs(def.parts) do kinds[#kinds + 1] = p.kind .. ":" .. p.key end
  table.sort(kinds)
  assert_eq(table.concat(kinds, ","), "energy:energy,proxy:fuel", "only the reactor and its fuel door are hidden")
  local shell = assert_prototype("entity", NAME)
  assert_eq(shell.type, "assembling-machine")
  assert_nil(shell.burner_prototype, "no burner on the shell")
  assert_true(shell.void_energy_source_prototype ~= nil, "shell runs on void")
  assert_eq(shell.fixed_recipe and shell.fixed_recipe.name, CYCLE, "fixed recipe")
  local r = assert_prototype("recipe", CYCLE)
  assert_eq(r.energy, 3.2, "cycle_time")
  assert_eq(r.ingredients[1].name, "iron-ore")
  assert_eq(r.products[1].name, "iron-plate")
  local reactor = assert_prototype("entity", NAME .. "-burner")
  assert_eq(reactor.type, "reactor")
  assert_true(reactor.hidden and reactor.has_flag("not-blueprintable"), "hidden part")
  assert_eq(reactor.get_max_energy_usage(), PER_TICK, "90 kW")
  assert_true(reactor.burner_prototype.fuel_categories.chemical ~= nil, "burns chemical fuel")
  assert_eq(assert_prototype("entity", NAME .. "-proxy-fuel").type, "proxy-container", "fuel door")
end)

-- ---- build / gate ------------------------------------------------------------

test("hearth: build materialises the reactor and fuel door; unfuelled reads no_fuel and is gated", function()
  local core = build()
  local parts = parts_of(core)
  local reactor, door = parts["energy:energy"], parts["proxy:fuel"]
  assert_true(reactor and reactor.valid, "reactor part")
  assert_eq(cl("owner_of", reactor.unit_number), core.unit_number, "reactor owned by the core")
  assert_eq(reactor.position.x, core.position.x, "reactor under the core")
  assert_eq(door.proxy_target_entity, reactor, "door targets the reactor")
  assert_eq(door.proxy_target_inventory, defines.inventory.fuel, "door targets the fuel slot")
  assert_eq(door.position.x, core.position.x - 0.5, "door on the south-west tile (x)")
  assert_eq(door.position.y, core.position.y + 0.5, "door on the south-west tile (y)")
  assert_true(core.disabled_by_script, "shell gated with no fuel")
  assert_eq(rec_of(core).status, "no_fuel", "status")
  assert_eq(core.custom_status.label[1], "entity-status.no-fuel", "label")
  assert_eq(core.custom_status.diode, defines.entity_status_diode.red, "red diode")
end)

test("hearth: one pass per hearth, every 20 ticks, re-armed by the pass", function()
  local core = build()
  local u = core.unit_number
  local due = rec_of(core).next_due
  assert_eq(due, game.tick + POLL, "first pass one interval after build")
  local found = false
  for _, k in ipairs(cl("bucket", due) or {}) do if k == u then found = true end end
  assert_true(found, "unit in its bucket")
  fuel_of(core).insert{name = "coal", count = 1}
  cl("dispatch", due, u)
  assert_true(not core.disabled_by_script, "the dispatched pass ungated the shell")
  assert_nil(rec_of(core).status, "fuelled: no custom status")
  assert_eq(rec_of(core).next_due, game.tick + POLL, "re-armed")
end)

test("hearth: the fuel door feeds the reactor; fuel slot takes chemical fuel only", function()
  local core = build()
  local door = parts_of(core)["proxy:fuel"].get_inventory(defines.inventory.proxy_main)
  assert_eq(door.insert{name = "iron-plate", count = 5}, 0, "iron plate refused")
  assert_eq(door.insert{name = "coal", count = 4}, 4, "coal through the door")
  assert_eq(fuel_of(core).get_item_count("coal"), 4, "landed in the reactor")
  assert_true(cl("call", core.unit_number, "has_fuel"), "has_fuel")
  poll(core)
  assert_true(not core.disabled_by_script, "ungated")
end)

test("hearth: fuelled and idle, the shell shows its own status, not no_fuel", function()
  local core = build()
  fuel_of(core).insert{name = "coal", count = 2}
  poll(core)
  assert_nil(core.custom_status, "no custom status")
  assert_true(core.status ~= defines.entity_status.no_fuel and core.status ~= defines.entity_status.disabled_by_script,
    "engine status " .. status_name(core.status))
  assert_true(not reactor_of(core).disabled_by_script, "the reactor is never gated: it burns while idle")
end)

test("hearth: power_state_changed once per transition, none for a repeated pass", function()
  local core = build()
  local u = core.unit_number
  input_of(core).insert{name = "iron-ore", count = 5}
  cl("set_event_log", true)
  poll(core)
  fuel_of(core).insert{name = "coal", count = 1}
  poll(core)
  poll(core)
  assert_true(not core.disabled_by_script, "fuelled: running")
  fuel_of(core).clear()
  reactor_of(core).burner.currently_burning = nil
  poll(core)
  assert_true(core.disabled_by_script, "fuel out: gated within one pass")
  assert_eq(rec_of(core).status, "no_fuel", "no_fuel within one pass")
  assert_eq(core.custom_status.diode, defines.entity_status_diode.red, "red")
  poll(core)
  fuel_of(core).insert{name = "coal", count = 1}
  poll(core)
  assert_true(not core.disabled_by_script, "fuel back: running")
  assert_nil(rec_of(core).status, "fuel back: native status again")
  local mine = power_events(u, cl("event_log", true))
  cl("set_event_log", false)
  assert_eq(#mine, 3, "one event per transition")
  assert_eq(mine[1].powered, true, "fuelled")
  assert_eq(mine[2].powered, false, "fuel out")
  assert_eq(mine[3].powered, true, "fuel back")
  assert_eq(type(cl("event_ids")[NAME].power_state_changed), "number", "event id exposed")
end)

test("hearth: on its last item the next pass lands on the burn-out tick", function()
  local core = build()
  local burner = reactor_of(core).burner
  burner.currently_burning = "coal"
  burner.remaining_burning_fuel = PER_TICK * 7.5
  assert_eq(poll(core), 8, "8 ticks of fuel left: next pass in 8")
  fuel_of(core).insert{name = "coal", count = 1}
  assert_eq(poll(core), POLL, "fuel waiting: the normal interval")
  fuel_of(core).clear()
  burner.remaining_burning_fuel = PER_TICK * 100
  assert_eq(poll(core), POLL, "more than one interval left: the normal interval")
end)

-- ---- lifecycle ---------------------------------------------------------------

test("hearth: script mine returns fuel, ore, plates and the hearth", function()
  local core = build()
  local u = core.unit_number
  local parts = parts_of(core)
  input_of(core).insert{name = "iron-ore", count = 7}
  output_of(core).insert{name = "iron-plate", count = 3}
  fuel_of(core).insert{name = "coal", count = 5}
  local inv = game.create_inventory(20)
  assert_true(cl("mine", core, inv), "mined")
  assert_true(not core.valid, "core gone")
  local ok, key = all_invalid(parts)
  assert_true(ok, "part left behind: " .. tostring(key))
  assert_nil(cl("record", u), "registry entry")
  assert_eq(inv.get_item_count("coal"), 5, "fuel returned")
  assert_eq(inv.get_item_count("iron-ore"), 7, "ore returned")
  assert_eq(inv.get_item_count("iron-plate"), 3, "plates returned")
  assert_eq(inv.get_item_count(NAME), 1, "hearth returned")
  inv.destroy()
end)

test("hearth: destroy with raise_destroy removes the parts", function()
  local core = build()
  local u = core.unit_number
  local parts = parts_of(core)
  core.destroy{raise_destroy = true}
  local ok, key = all_invalid(parts)
  assert_true(ok, "part left behind: " .. tostring(key))
  assert_nil(cl("record", u), "registry entry")
end)

test("hearth: death spills the fuel and removes the parts", function()
  local core, s, pos = build()
  local parts = parts_of(core)
  fuel_of(core).insert{name = "coal", count = 6}
  core.die()
  local ok, key = all_invalid(parts)
  assert_true(ok, "part left behind: " .. tostring(key))
  local spilled = 0
  for _, e in pairs(s.find_entities_filtered{name = "item-on-ground", position = pos, radius = 5}) do
    if e.stack.name == "coal" then spilled = spilled + e.stack.count end
  end
  assert_eq(spilled, 6, "spilled coal")
end)

test("hearth: clone carries the burn, fuel, contents and gate", function()
  local core, s = build()
  local u = core.unit_number
  input_of(core).insert{name = "iron-ore", count = 4}
  fuel_of(core).insert{name = "coal", count = 2}
  local burner = reactor_of(core).burner
  burner.currently_burning = "wood"
  burner.remaining_burning_fuel = 123456
  poll(core)
  s.clone_entities{entities = {core}, destination_offset = {5, 0}}
  local copy = s.find_entity(NAME, {core.position.x + 5, core.position.y})
  assert_not_nil(copy, "clone exists")
  local reactor = reactor_of(copy)
  assert_true(reactor ~= nil and reactor.valid and reactor ~= reactor_of(core), "own reactor")
  assert_eq(reactor.position.x, copy.position.x, "reactor at the clone")
  local cb = reactor.burner.currently_burning
  assert_eq(cb and cb.name.name, "wood", "burning item cloned")
  assert_eq(reactor.burner.remaining_burning_fuel, 123456, "remaining burn cloned")
  assert_eq(fuel_of(copy).get_item_count("coal"), 2, "fuel cloned")
  assert_eq(input_of(copy).get_item_count("iron-ore"), 4, "ore cloned")
  assert_eq(parts_of(copy)["proxy:fuel"].proxy_target_entity, reactor, "door re-linked to the clone's reactor")
  assert_true(not copy.disabled_by_script, "clone of a fuelled hearth runs")
  assert_not_nil(rec_of(copy).next_due, "clone polls")
  assert_eq(s.count_entities_filtered{name = NAME .. "-burner", position = copy.position}, 1, "one reactor")

  fuel_of(core).clear()
  burner.currently_burning = nil
  poll(core)
  s.clone_entities{entities = {core}, destination_offset = {0, 4}}
  local cold = s.find_entity(NAME, {core.position.x, core.position.y + 4})
  assert_not_nil(cold, "second clone")
  assert_true(cold.disabled_by_script, "clone of a cold hearth is gated")
  assert_eq(rec_of(cold).status, "no_fuel", "and says why")
  assert_eq(u, core.unit_number, "source untouched")
end)

test("hearth: blueprint has one entity; the revived ghost gets its parts", function()
  local core, s, pos = build()
  fuel_of(core).insert{name = "coal", count = 4}
  input_of(core).insert{name = "iron-ore", count = 2}
  local inv = game.create_inventory(1)
  inv.insert{name = "blueprint"}
  local bp = inv[1]
  local mapping = bp.create_blueprint{surface = s, force = "player",
    area = {{pos.x - 2, pos.y - 2}, {pos.x + 2, pos.y + 2}}}
  cl("tag_blueprint", bp, mapping)
  local entities = bp.get_blueprint_entities()
  assert_eq(#entities, 1, "the reactor and door are not blueprinted")
  assert_eq(entities[1].name, NAME)
  local ghosts = bp.build_blueprint{surface = s, force = "player", position = {pos.x + 6, pos.y},
    skip_fog_of_war = false, build_mode = defines.build_mode.forced}
  assert_eq(#ghosts, 1, "one ghost")
  local _, revived = ghosts[1].revive{raise_revive = true}
  assert_not_nil(revived, "revived")
  local parts = parts_of(revived)
  assert_true(parts["energy:energy"] and parts["energy:energy"].valid, "revived reactor")
  assert_true(parts["proxy:fuel"] and parts["proxy:fuel"].valid, "revived fuel door")
  assert_eq(input_of(revived).get_item_count(), 0, "contents are not blueprinted")
  assert_true(revived.disabled_by_script, "unfuelled until fuel arrives")
  assert_eq(rec_of(revived).status, "no_fuel", "no_fuel")
  inv.destroy()
end)

-- The native type gates crafting on the burner itself. The emulation's shell
-- runs on void, so fuel taken out from outside between passes leaves it
-- crafting until the next pass, up to 20 ticks. (A flame-out is not affected:
-- the pass is scheduled on the burn-out tick, see the real-tick test.)
test("hearth: KNOWN-LIMIT fuel removed between passes leaves the shell crafting until the next pass", function()
  local core = build()
  input_of(core).insert{name = "iron-ore", count = 5}
  fuel_of(core).insert{name = "coal", count = 1}
  poll(core)
  fuel_of(core).clear()
  reactor_of(core).burner.currently_burning = nil
  assert_true(not cl("call", core.unit_number, "has_fuel"), "the burner is cold")
  assert_true(core.disabled_by_script,
    "KNOWN-LIMIT: the shell keeps crafting on a cold burner until the next pass (up to 20 ticks); " ..
    "a native composed machine stops on the same tick")
end)

-- ---- real ticks --------------------------------------------------------------

local function fixture()
  local fx = cl("hearth_fixture")
  assert_not_nil(fx, "fixture armed at on_init (run with --fresh)")
  assert_not_nil(fx.snap, string.format("fixture incomplete at tick %d (needs tick %d): the server did not run long enough",
    game.tick, fx.snap_at))
  return fx, fx.snap.tick - fx.tick
end

test("hearth: real ticks: fuelled and idle it burns 90 kW and crafts nothing", function()
  local fx, elapsed = fixture()
  local u = fx.snap.units.idle
  local burnt = fx.energy.idle - u.energy
  assert_true(math.abs(burnt - PER_TICK * elapsed) <= PER_TICK * 2,
    string.format("burnt %.0f J over %d ticks, expected %.0f J", burnt, elapsed, PER_TICK * elapsed))
  assert_eq(u.coal, 1, "one of the two coal went into the burner")
  assert_eq(u.finished, 0, "no plates")
  assert_eq(u.status, defines.entity_status.item_ingredient_shortage, "status " .. status_name(u.status))
  assert_nil(u.custom, "no custom status")
end)

test("hearth: real ticks: working it burns the same 90 kW and makes plates", function()
  local fx, elapsed = fixture()
  local u = fx.snap.units.working
  local burnt = fx.energy.working - u.energy
  assert_true(math.abs(burnt - PER_TICK * elapsed) <= PER_TICK * 2,
    string.format("burnt %.0f J over %d ticks, expected %.0f J", burnt, elapsed, PER_TICK * elapsed))
  local cycles = math.floor(elapsed / 192)
  assert_true(u.finished >= cycles - 1 and u.finished <= cycles,
    string.format("%d plates over %d ticks of a 3.2 s cycle", u.finished, elapsed))
  assert_eq(u.plates, u.finished, "plates in the output")
  assert_eq(u.status, defines.entity_status.working, "status " .. status_name(u.status))
  assert_eq(#u.log, 0, "no power transitions")
end)

test("hearth: real ticks: a flame-out stops the shell on the burn-out tick; refuel restarts it within a pass", function()
  local fx = fixture()
  local u = fx.snap.units.flameout
  assert_eq(#u.log, 2, "two transitions: out, back")
  local out, back = u.log[1], u.log[2]
  assert_eq(out.powered, false, "went cold")
  local late = out.tick - (fx.tick + fx.flameout_ticks)
  assert_true(late >= 0 and late <= 1, string.format("noticed %d ticks after the burn-out", late))
  assert_eq(back.powered, true, "refuelled")
  local lag = back.tick - fx.refuel_at
  assert_true(lag >= 0 and lag <= fx.poll, string.format("refuel noticed after %d ticks", lag))
  assert_eq(back.progress, out.progress, "no crafting progress while cold")
  assert_eq(back.finished, out.finished, "no plates while cold")
  assert_true(u.finished > out.finished, "crafts again after the refuel")
  assert_eq(u.status, defines.entity_status.working, "working again: " .. status_name(u.status))
  assert_true(not u.disabled, "ungated")
end)

test("hearth: real ticks: inserters feed ore into the shell, coal through the fuel door, and take plates", function()
  local fx = fixture()
  local f, u = fx.snap.fed, fx.snap.units.fed
  assert_eq(f.coal_target, NAME .. "-proxy-fuel", "the coal inserter drops into the door, not the shell")
  assert_true(f.coal_left < 10, "coal taken from the chest: " .. tostring(f.coal_left))
  assert_true(f.ore_left < 20, "ore taken from the chest: " .. tostring(f.ore_left))
  assert_true(f.plates_out >= 1, "plates taken out of the shell: " .. tostring(f.plates_out))
  assert_eq(#u.log, 1, "one transition")
  assert_eq(u.log[1].powered, true, "came up when the first coal arrived")
  assert_eq(u.status, defines.entity_status.working, "status " .. status_name(u.status))
end)

test("hearth: real ticks: re-arm the fixture for the next run", function()
  assert_true(cl("hearth_arm_fixture"), "re-armed")
end)
