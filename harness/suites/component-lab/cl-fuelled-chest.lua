-- cl-fuelled-chest suite. TEST-ENTITIES.md section 3.
-- Same-tick behaviour is driven through the entity's poll (fuelled_poll) or a
-- synthetic scheduler dispatch; burning and flame-out over real ticks are read
-- from fixtures the mod arms at on_init (run with --fresh the first time).

local CL = "component_lab"
local NAME = "cl-fuelled-chest"
local WATTS = 20000
local POLL = 30

local function cl(fn, ...) return remote.call(CL, fn, ...) end

local row = require("_site").row{x = 300, y = -60}
local function site() return row:next(12) end

local function build()
  local s, pos = site()
  local core = s.create_entity{name = NAME, position = pos, force = "player", raise_built = true}
  assert_not_nil(core, "create_entity " .. NAME)
  return core, s, pos
end

local function parts_of(core)
  local out = {}
  for key, e in pairs(cl("parts", core.unit_number) or {}) do out[key] = e end
  return out
end

local function reactor_of(core) return parts_of(core)["energy:energy"] end
local function main_of(core) return core.get_inventory(defines.inventory.chest) end
local function poll(core) cl("fuelled_poll", core.unit_number) end
local function status_of(core) return cl("record", core.unit_number).status end

local function all_invalid(parts)
  for key, e in pairs(parts) do
    if e.valid then return false, key end
  end
  return true
end

test("fuelled-chest: prototype, shape S1 burner, one hidden reactor", function()
  assert_prototype("entity", NAME)
  assert_prototype("entity", NAME .. "-burner")
  assert_eq(cl("shape", NAME), "S1", "shape")
  local def = prototypes.mod_data["component-lab--" .. NAME].data
  assert_eq(def.watch, "burner", "watcher")
  assert_eq(def.core_type, "container", "core type")
  assert_eq(def.native_inventory, "main", "main is the container's own inventory")
  assert_eq(#def.parts, 1, "only the reactor is hidden")
  assert_eq(prototypes.entity[NAME].get_inventory_size(defines.inventory.chest), 16, "16 slots")
  assert_eq(prototypes.entity[NAME .. "-burner"].type, "reactor", "burner part is a reactor")
end)

test("fuelled-chest: build materialises the reactor; empty chest reads no_fuel", function()
  local core = build()
  local reactor = reactor_of(core)
  assert_not_nil(reactor, "reactor part")
  assert_true(reactor.valid, "reactor valid")
  assert_eq(cl("owner_of", reactor.unit_number), core.unit_number, "reactor owned by the core")
  assert_eq(reactor.position.x, core.position.x, "reactor under the core")
  assert_true(reactor.disabled_by_script, "empty chest keeps the reactor asleep")
  assert_eq(status_of(core), "no_fuel", "status")
  assert_eq(core.custom_status.label[1], "entity-status.no-fuel", "label")
  assert_eq(core.custom_status.diode, defines.entity_status_diode.red, "diode")
end)

test("fuelled-chest: core is not updatable, the reactor is (one ticking entity each)", function()
  local core = build()
  assert_true(not core.is_updatable, "container core is not updatable")
  assert_true(reactor_of(core).is_updatable, "hidden reactor is updatable")
end)

test("fuelled-chest: the poll is scheduled per entity every 30 ticks", function()
  local core = build()
  local u = core.unit_number
  local due = cl("record", u).next_due
  assert_eq(due, game.tick + POLL, "first poll one interval after build")
  local bucket = cl("bucket", due)
  local found = false
  for _, k in ipairs(bucket or {}) do if k == u then found = true end end
  assert_true(found, "unit in its bucket")
  main_of(core).insert{name = "iron-plate", count = 1}
  cl("call", u, "fuel_inventory").insert{name = "coal", count = 1}
  cl("dispatch", due, u)
  assert_true(not reactor_of(core).disabled_by_script, "synthetic dispatch ran the poll")
  assert_eq(status_of(core), "working", "status after the dispatched poll")
  assert_eq(cl("record", u).next_due, game.tick + POLL, "re-armed after the poll")
end)

test("fuelled-chest: fuel slot accepts chemical fuel and rejects non-fuel", function()
  local core = build()
  local fuel = cl("call", core.unit_number, "fuel_inventory")
  assert_eq(#fuel, 1, "one fuel slot")
  assert_true(not fuel.can_insert{name = "iron-plate"}, "iron plate rejected")
  assert_eq(fuel.insert{name = "iron-plate", count = 5}, 0, "insert of iron plate moved nothing")
  assert_true(fuel.can_insert{name = "wood"}, "wood accepted")
  assert_eq(fuel.insert{name = "coal", count = 5}, 5, "coal inserted")
end)

test("fuelled-chest: activity gate follows the main inventory within one poll", function()
  local core = build()
  local u = core.unit_number
  local reactor = reactor_of(core)
  cl("call", u, "fuel_inventory").insert{name = "coal", count = 3}
  poll(core)
  assert_true(reactor.disabled_by_script, "fuelled but empty: asleep")
  assert_nil(status_of(core), "idle S1 shows its default status")
  assert_nil(core.custom_status, "no custom status while idle")
  main_of(core).insert{name = "iron-plate", count = 4}
  poll(core)
  assert_true(not reactor.disabled_by_script, "insert wakes the reactor")
  assert_eq(status_of(core), "working", "working")
  assert_eq(core.custom_status.diode, defines.entity_status_diode.green, "green diode")
  main_of(core).clear()
  poll(core)
  assert_true(reactor.disabled_by_script, "emptied: asleep again")
  assert_nil(status_of(core), "idle again")
end)

test("fuelled-chest: flame-out reads no_fuel and raises power_state_changed", function()
  local core = build()
  local u = core.unit_number
  local reactor = reactor_of(core)
  main_of(core).insert{name = "iron-plate", count = 1}
  cl("call", u, "fuel_inventory").insert{name = "coal", count = 1}
  cl("set_event_log", true)
  poll(core)
  assert_eq(status_of(core), "working", "fuelled")
  cl("call", u, "fuel_inventory").clear()
  reactor.burner.currently_burning = nil
  poll(core)
  assert_eq(status_of(core), "no_fuel", "flame-out status")
  poll(core)
  cl("call", u, "fuel_inventory").insert{name = "coal", count = 1}
  poll(core)
  local log = cl("event_log", true)
  cl("set_event_log", false)
  local mine = {}
  for _, e in ipairs(log or {}) do
    if e.unit_number == u and e.flag == "power_state_changed" then mine[#mine + 1] = e end
  end
  assert_eq(#mine, 3, "one event per transition, none for a repeated poll")
  assert_eq(mine[1].powered, true, "fuelled")
  assert_eq(mine[2].powered, false, "flame-out")
  assert_eq(mine[3].powered, true, "refuelled")
  assert_eq(type(cl("event_ids")[NAME].power_state_changed), "number", "event id exposed")
end)

test("fuelled-chest: script mine returns remaining fuel with the contents", function()
  local core = build()
  local u = core.unit_number
  local parts = parts_of(core)
  main_of(core).insert{name = "iron-plate", count = 7}
  cl("call", u, "fuel_inventory").insert{name = "coal", count = 5}
  local inv = game.create_inventory(20)
  assert_true(cl("mine", core, inv), "mined")
  assert_true(not core.valid, "core gone")
  local ok, key = all_invalid(parts)
  assert_true(ok, "part left behind: " .. tostring(key))
  assert_nil(cl("record", u), "registry entry")
  assert_eq(inv.get_item_count("coal"), 5, "fuel returned")
  assert_eq(inv.get_item_count("iron-plate"), 7, "contents returned")
  assert_eq(inv.get_item_count(NAME), 1, "chest item returned")
  inv.destroy()
end)

test("fuelled-chest: destroy with raise_destroy removes the reactor", function()
  local core = build()
  local u = core.unit_number
  local parts = parts_of(core)
  core.destroy{raise_destroy = true}
  local ok, key = all_invalid(parts)
  assert_true(ok, "part left behind: " .. tostring(key))
  assert_nil(cl("record", u), "registry entry")
end)

test("fuelled-chest: death spills the fuel and removes the reactor", function()
  local core, s, pos = build()
  local parts = parts_of(core)
  cl("call", core.unit_number, "fuel_inventory").insert{name = "coal", count = 6}
  core.die()
  local ok, key = all_invalid(parts)
  assert_true(ok, "part left behind: " .. tostring(key))
  local spilled = 0
  for _, e in pairs(s.find_entities_filtered{name = "item-on-ground", position = pos, radius = 5}) do
    if e.stack.name == "coal" then spilled = spilled + e.stack.count end
  end
  assert_eq(spilled, 6, "spilled coal")
end)

test("fuelled-chest: clone carries the burning stack, fuel and contents", function()
  local core, s = build()
  local u = core.unit_number
  main_of(core).insert{name = "iron-plate", count = 3}
  cl("call", u, "fuel_inventory").insert{name = "coal", count = 2}
  local burner = reactor_of(core).burner
  burner.currently_burning = "wood"
  burner.remaining_burning_fuel = 123456
  poll(core)
  s.clone_entities{entities = {core}, destination_offset = {5, 0}}
  local copy = s.find_entity(NAME, {core.position.x + 5, core.position.y})
  assert_not_nil(copy, "clone exists")
  local reactor = reactor_of(copy)
  assert_true(reactor ~= nil and reactor.valid, "clone has its own reactor")
  assert_true(reactor ~= reactor_of(core), "not the source's reactor")
  assert_eq(reactor.position.x, copy.position.x, "reactor at the clone")
  local cb = reactor.burner.currently_burning
  assert_eq(cb and cb.name.name, "wood", "burning item cloned")
  assert_eq(reactor.burner.remaining_burning_fuel, 123456, "remaining burn cloned")
  assert_eq(cl("call", copy.unit_number, "fuel_inventory").get_item_count("coal"), 2, "fuel cloned")
  assert_eq(main_of(copy).get_item_count("iron-plate"), 3, "contents cloned")
  assert_true(not reactor.disabled_by_script, "clone of a working chest is awake")
  assert_eq(status_of(copy), "working", "status cloned")
  assert_not_nil(cl("record", copy.unit_number).next_due, "clone polls")
  assert_eq(s.count_entities_filtered{name = NAME .. "-burner", position = copy.position}, 1, "exactly one reactor")
end)

test("fuelled-chest: blueprint has one entity and a fuel request; the revived ghost requests it", function()
  local core, s, pos = build()
  main_of(core).insert{name = "iron-plate", count = 2}
  cl("call", core.unit_number, "fuel_inventory").insert{name = "coal", count = 4}
  local inv = game.create_inventory(1)
  inv.insert{name = "blueprint"}
  local bp = inv[1]
  local mapping = bp.create_blueprint{surface = s, force = "player",
    area = {{pos[1] - 1, pos[2] - 1}, {pos[1] + 1, pos[2] + 1}}}
  assert_eq(cl("tag_blueprint", bp, mapping), 1, "one core tagged")
  local entities = bp.get_blueprint_entities()
  assert_eq(#entities, 1, "the reactor is not blueprinted")
  assert_eq(entities[1].name, NAME)
  local plan = bp.get_blueprint_entity_tags(1).component_lab.extra.fuel_plan
  assert_not_nil(plan, "fuel request in tags")
  assert_eq(plan[1].id.name, "coal", "requested fuel")
  assert_eq(plan[1].items.in_inventory[1].count, 4, "requested count")

  local ghosts = bp.build_blueprint{surface = s, force = "player", position = {pos[1] + 6, pos[2]},
    skip_fog_of_war = false, build_mode = defines.build_mode.forced}
  assert_eq(#ghosts, 1, "one ghost")
  local _, revived = ghosts[1].revive{raise_revive = true}
  assert_not_nil(revived, "revived")
  assert_not_nil(cl("record", revived.unit_number), "revived core registered")
  local reactor = reactor_of(revived)
  local proxy = reactor.item_request_proxy
  assert_not_nil(proxy, "item-request-proxy on the new reactor")
  assert_eq(proxy.proxy_target, reactor, "proxy targets the hidden reactor")
  local req = proxy.insert_plan[1]
  assert_eq(req.id.name, "coal", "proxy requests coal")
  assert_eq(req.items.in_inventory[1].inventory, defines.inventory.fuel, "into the fuel slot")
  assert_eq(main_of(revived).get_item_count(), 0, "contents are not blueprinted")
  assert_eq(status_of(revived), "no_fuel", "unfuelled until robots deliver")
  inv.destroy()
end)

-- ---- real ticks --------------------------------------------------------------

local function fixtures()
  local fx = cl("fuelled_fixtures")
  assert_not_nil(fx, "fixtures armed at on_init (run with --fresh)")
  local elapsed = game.tick - fx.tick
  return fx, elapsed
end

test("fuelled-chest: real ticks: a chest holding items burns its fuel at 20 kW", function()
  local fx, elapsed = fixtures()
  assert_true(elapsed >= 10, "needs >= 10 ticks since the fixtures were armed, had " .. elapsed)
  local c = fx.chests.burning
  local burnt = c.energy_at_arm - c.energy_now
  local expected = WATTS / 60 * elapsed
  assert_true(burnt > 0, "fuel burnt down")
  assert_true(math.abs(burnt - expected) <= WATTS / 60 * 2,
    string.format("burnt %.0f J over %d ticks, expected %.0f J", burnt, elapsed, expected))
  assert_eq(cl("record", c.unit_number).status, "working", "status")
end)

test("fuelled-chest: real ticks: a fuelled chest with nothing in it does not burn", function()
  local fx, elapsed = fixtures()
  assert_true(elapsed >= 1, "a tick has passed")
  local c = fx.chests.idle
  assert_eq(c.energy_now, c.energy_at_arm, "no energy drawn while asleep")
  assert_nil(cl("record", c.unit_number).status, "idle")
end)

test("fuelled-chest: real ticks: flame-out reads no_fuel within one poll and logs the transition", function()
  local fx, elapsed = fixtures()
  local burn_ticks = math.ceil(fx.flameout_joules / (WATTS / 60))
  local first_poll = fx.flameout_first_poll
  assert_true(elapsed > first_poll and first_poll > burn_ticks,
    string.format("needs > %d ticks since the fixtures were armed, had %d", first_poll, elapsed))
  local c = fx.chests.flameout
  assert_true(not c.burning, "flame out: nothing burning")
  local rec = cl("record", c.unit_number)
  assert_eq(rec.status, "no_fuel", "status")
  local log = rec.data.power_log
  assert_eq(#log, 1, "one transition")
  assert_eq(log[1].powered, false, "went unpowered")
  assert_eq(log[1].tick, fx.tick + first_poll, "noticed at the first poll after the flame-out")
end)

test("fuelled-chest: real ticks: re-arm fixtures for the next run", function()
  assert_true(cl("fuelled_arm_fixtures"), "re-armed")
end)
