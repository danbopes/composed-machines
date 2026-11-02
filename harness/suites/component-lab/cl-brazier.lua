-- cl-brazier suite. TEST-ENTITIES-2.md section 2.
-- Same-tick behaviour is driven through the entity's pass (brazier_poll) or a
-- synthetic scheduler dispatch; burning and flame-out over real ticks are read
-- from fixtures the mod arms at on_init (run with --fresh the first time).

local CL = "component_lab"
local NAME = "cl-brazier"
local WATTS = 30000
local POLL = 30

local function cl(fn, ...) return remote.call(CL, fn, ...) end

-- This suite's own row: no other suite builds on y = 1120.
local row = require("_site").row{x = 0, y = 1120}
local function site(width) return row:next(width or 12) end

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
local function fuel_of(core) return cl("call", core.unit_number, "fuel_inventory") end
local function poll(core) cl("brazier_poll", core.unit_number) end
local function status_of(core) return cl("record", core.unit_number).status end
local function light_of(core) return cl("brazier_light", core.unit_number) end

local function all_invalid(parts)
  for key, e in pairs(parts) do
    if e.valid then return false, key end
  end
  return true
end

local function power_events(log, u)
  local mine = {}
  for _, e in ipairs(log or {}) do
    if e.unit_number == u and e.flag == "power_state_changed" then mine[#mine + 1] = e end
  end
  return mine
end

local function lights_on(core)
  local n = 0
  for _, obj in pairs(rendering.get_all_objects("component-lab")) do
    if obj.type == "light" and obj.target and obj.target.entity == core then n = n + 1 end
  end
  return n
end

test("cl-brazier: prototype, shape S1, simple-entity core with a hidden reactor and fuel door", function()
  assert_prototype("entity", NAME)
  local burner = assert_prototype("entity", NAME .. "-burner")
  local door = assert_prototype("entity", NAME .. "-proxy-fuel")
  assert_eq(cl("shape", NAME), "S1", "shape")
  local def = prototypes.mod_data["component-lab--" .. NAME].data
  assert_eq(def.core_type, "simple-entity-with-owner", "core type")
  assert_eq(prototypes.entity[NAME].type, "simple-entity-with-owner", "engine type")
  assert_eq(#def.parts, 2, "reactor + fuel proxy, nothing else")
  assert_eq(burner.type, "reactor", "burner part is a reactor")
  assert_eq(door.type, "proxy-container", "fuel door")
  assert_true(burner.hidden and door.hidden, "parts are hidden")
  assert_eq(burner.burner_prototype.fuel_inventory_size, 1, "one fuel slot")
  assert_eq(burner.get_max_energy_usage() * 60, WATTS, "30 kW")
  assert_eq(type(cl("event_ids")[NAME].power_state_changed), "number", "event id exposed")
end)

test("cl-brazier: build materialises the parts; unfuelled reads no_fuel with the light off", function()
  local core = build()
  local u = core.unit_number
  local parts = parts_of(core)
  local reactor, door = parts["energy:energy"], parts["proxy:fuel"]
  assert_true(reactor and reactor.valid, "reactor part")
  assert_true(door and door.valid, "fuel door part")
  assert_eq(cl("owner_of", reactor.unit_number), u, "reactor owned by the core")
  assert_eq(reactor.position.x, core.position.x, "reactor under the core")
  assert_eq(door.proxy_target_entity, reactor, "door opens on the reactor")
  assert_eq(door.proxy_target_inventory, defines.inventory.fuel, "door opens on the fuel slot")
  assert_true(not reactor.disabled_by_script, "activity = always: the reactor is never gated")
  assert_eq(status_of(core), "no_fuel", "status")
  assert_eq(core.custom_status.label[1], "entity-status.no-fuel", "label")
  assert_eq(core.custom_status.diode, defines.entity_status_diode.red, "red diode")
  local light = light_of(core)
  assert_not_nil(light, "light drawn")
  assert_true(not light.visible, "light off while unfuelled")
  assert_eq(light.target, core, "light follows the core")
  assert_eq(lights_on(core), 1, "exactly one light")
end)

test("cl-brazier: only the reactor ticks; the core is not updatable", function()
  local core = build()
  assert_true(not core.is_updatable, "simple-entity core is not updatable")
  assert_true(reactor_of(core).is_updatable, "hidden reactor is updatable")
end)

test("cl-brazier: the pass is scheduled per entity every 30 ticks", function()
  local core = build()
  local u = core.unit_number
  local due = cl("record", u).next_due
  assert_eq(due, game.tick + POLL, "first pass one interval after build")
  local found = false
  for _, k in ipairs(cl("bucket", due) or {}) do if k == u then found = true end end
  assert_true(found, "unit in its bucket")
  fuel_of(core).insert{name = "coal", count = 1}
  cl("dispatch", due, u)
  assert_eq(status_of(core), "working", "synthetic dispatch ran the pass")
  assert_true(light_of(core).visible, "light on after the dispatched pass")
  assert_eq(cl("record", u).next_due, game.tick + POLL, "re-armed after the pass")
end)

test("cl-brazier: fuel slot takes chemical fuel only, also through the door", function()
  local core = build()
  local fuel = fuel_of(core)
  assert_eq(#fuel, 1, "one fuel slot")
  assert_eq(fuel.insert{name = "iron-plate", count = 5}, 0, "iron plate rejected")
  local door = parts_of(core)["proxy:fuel"].get_inventory(defines.inventory.proxy_main)
  assert_eq(door.insert{name = "iron-plate", count = 5}, 0, "door rejects iron plate")
  assert_eq(door.insert{name = "wood", count = 4}, 4, "door takes wood")
  assert_eq(fuel.get_item_count("wood"), 4, "wood landed in the reactor")
  assert_true(cl("call", core.unit_number, "has_fuel"), "has_fuel")
end)

test("cl-brazier: power_state_changed fires once per transition and toggles the light", function()
  local core = build()
  local u = core.unit_number
  local reactor = reactor_of(core)
  cl("set_event_log", true)
  poll(core)
  fuel_of(core).insert{name = "wood", count = 1}
  poll(core)
  assert_eq(status_of(core), "working", "fuelled")
  assert_eq(core.custom_status.diode, defines.entity_status_diode.green, "green diode")
  assert_true(light_of(core).visible, "light on")
  poll(core)
  poll(core)
  fuel_of(core).clear()
  reactor.burner.currently_burning = nil
  assert_true(not cl("call", u, "has_fuel"), "nothing left to burn")
  poll(core)
  assert_eq(status_of(core), "no_fuel", "flame-out status")
  assert_true(not light_of(core).visible, "light off")
  poll(core)
  fuel_of(core).insert{name = "coal", count = 1}
  poll(core)
  local mine = power_events(cl("event_log", true), u)
  cl("set_event_log", false)
  assert_eq(#mine, 3, "one event per transition, none for a repeated pass")
  assert_eq(mine[1].powered, true, "fuelled")
  assert_eq(mine[2].powered, false, "flame-out")
  assert_eq(mine[3].powered, true, "refuelled")
  assert_true(light_of(core).visible, "light back on")
  assert_eq(lights_on(core), 1, "still one light, toggled rather than redrawn")
end)

test("cl-brazier: mid-burn with an empty slot still counts as powered", function()
  local core = build()
  local burner = reactor_of(core).burner
  burner.currently_burning = "wood"
  burner.remaining_burning_fuel = 100000
  poll(core)
  assert_eq(status_of(core), "working", "burning the last item")
  assert_true(light_of(core).visible, "light on")
end)

test("cl-brazier: script mine returns the remaining fuel and the brazier", function()
  local core = build()
  local u = core.unit_number
  local parts = parts_of(core)
  fuel_of(core).insert{name = "coal", count = 5}
  poll(core)
  local inv = game.create_inventory(8)
  assert_true(cl("mine", core, inv), "mined")
  assert_true(not core.valid, "core gone")
  local ok, key = all_invalid(parts)
  assert_true(ok, "part left behind: " .. tostring(key))
  assert_nil(cl("record", u), "registry entry")
  assert_eq(inv.get_item_count("coal"), 5, "fuel returned")
  assert_eq(inv.get_item_count(NAME), 1, "brazier item returned")
  inv.destroy()
end)

test("cl-brazier: destroy with raise_destroy removes the parts and the light", function()
  local core = build()
  local u = core.unit_number
  local parts = parts_of(core)
  local before = #rendering.get_all_objects("component-lab")
  core.destroy{raise_destroy = true}
  local ok, key = all_invalid(parts)
  assert_true(ok, "part left behind: " .. tostring(key))
  assert_nil(cl("record", u), "registry entry")
  assert_eq(#rendering.get_all_objects("component-lab"), before - 1, "the light went with the core")
end)

test("cl-brazier: death spills the fuel and removes the parts", function()
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

test("cl-brazier: clone carries the burn and fuel and draws its own light", function()
  local core, s = build()
  fuel_of(core).insert{name = "coal", count = 2}
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
  local cb = reactor.burner.currently_burning
  assert_eq(cb and cb.name.name, "wood", "burning item cloned")
  assert_eq(reactor.burner.remaining_burning_fuel, 123456, "remaining burn cloned")
  assert_eq(fuel_of(copy).get_item_count("coal"), 2, "fuel cloned")
  assert_eq(parts_of(copy)["proxy:fuel"].proxy_target_entity, reactor, "door re-linked to the clone's reactor")
  assert_eq(status_of(copy), "working", "status")
  local light = light_of(copy)
  assert_true(light ~= nil and light.visible, "clone's light on")
  assert_eq(light.target, copy, "clone's light follows the clone")
  assert_eq(lights_on(core), 1, "source keeps exactly one light")
  assert_eq(lights_on(copy), 1, "clone has exactly one light")
  assert_not_nil(cl("record", copy.unit_number).next_due, "clone polls")
  assert_eq(s.count_entities_filtered{name = NAME .. "-burner", position = copy.position}, 1, "exactly one reactor")
end)

test("cl-brazier: blueprint has one entity and a fuel request; the revived ghost requests it", function()
  local core, s, pos = build()
  fuel_of(core).insert{name = "coal", count = 4}
  local inv = game.create_inventory(1)
  inv.insert{name = "blueprint"}
  local bp = inv[1]
  local mapping = bp.create_blueprint{surface = s, force = "player",
    area = {{pos[1] - 1, pos[2] - 1}, {pos[1] + 1, pos[2] + 1}}}
  assert_eq(cl("tag_blueprint", bp, mapping), 1, "one core tagged")
  local entities = bp.get_blueprint_entities()
  assert_eq(#entities, 1, "the parts are not blueprinted")
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
  assert_eq(proxy.insert_plan[1].id.name, "coal", "proxy requests coal")
  assert_eq(proxy.insert_plan[1].items.in_inventory[1].inventory, defines.inventory.fuel, "into the fuel slot")
  assert_eq(status_of(revived), "no_fuel", "unfuelled until robots deliver")
  assert_true(not light_of(revived).visible, "dark until fuelled")
  inv.destroy()
end)

test("cl-brazier: KNOWN-LIMIT flame-out is only noticed at the next pass (up to 30 ticks late)", function()
  local core = build()
  local reactor = reactor_of(core)
  fuel_of(core).insert{name = "wood", count = 1}
  poll(core)
  fuel_of(core).clear()
  reactor.burner.currently_burning = nil
  assert_true(not cl("call", core.unit_number, "has_fuel"), "the burner is out")
  assert_true(status_of(core) == "no_fuel" and not light_of(core).visible,
    "KNOWN-LIMIT: the burner ran dry but the status still reads '" .. tostring(status_of(core))
    .. "' and the light is on until the next pass (" .. POLL .. " ticks). A native burner would raise "
    .. "power_state_changed the tick it runs dry, with no poll")
end)

-- ---- real ticks --------------------------------------------------------------

local function fixtures()
  local fx = cl("brazier_fixtures")
  assert_not_nil(fx, "fixtures armed at on_init (run with --fresh)")
  return fx, game.tick - fx.tick
end

test("cl-brazier: real ticks: a fuelled brazier burns at 30 kW, lit, with no events while steady", function()
  local fx, elapsed = fixtures()
  assert_true(elapsed >= 10, "needs >= 10 ticks since the fixtures were armed, had " .. elapsed)
  local b = fx.braziers.steady
  local burnt = b.energy_at_arm - b.energy_now
  local expected = WATTS / 60 * elapsed
  assert_true(math.abs(burnt - expected) <= WATTS / 60 * 2,
    string.format("burnt %.0f J over %d ticks, expected %.0f J", burnt, elapsed, expected))
  local rec = cl("record", b.unit_number)
  assert_eq(rec.status, "working", "status")
  assert_eq(#rec.data.power_log, 0, "no transitions while steady")
  assert_true(b.light.visible, "light on")
end)

test("cl-brazier: real ticks: flame-out raises one powered=false at the first pass after it", function()
  local fx, elapsed = fixtures()
  local burn_ticks = math.ceil(fx.flameout_joules / (WATTS / 60))
  local first_poll = fx.flameout_first_poll
  assert_true(elapsed > first_poll and first_poll > burn_ticks,
    string.format("needs > %d ticks since the fixtures were armed, had %d", first_poll, elapsed))
  local b = fx.braziers.flameout
  assert_true(not b.burning, "flamed out")
  local rec = cl("record", b.unit_number)
  assert_eq(rec.status, "no_fuel", "status")
  local log = rec.data.power_log
  assert_eq(#log, 1, "one transition")
  assert_eq(log[1].powered, false, "went unpowered")
  assert_eq(log[1].tick, fx.tick + first_poll, "noticed at the first pass after the flame-out")
  assert_true(not b.light.visible, "light off")
end)

test("cl-brazier: real ticks: an inserter refuels it through the fuel door and lights it", function()
  local fx, elapsed = fixtures()
  assert_true(elapsed >= fx.inserter_ticks,
    string.format("fixture incomplete: needs %d ticks since arming, had %d", fx.inserter_ticks, elapsed))
  local b = fx.braziers.fed
  assert_eq(fx.inserter_drop_target, b.door, "the inserter's drop target is the fuel door, not the core")
  assert_true(b.fuel_count > 0 or b.burning, "coal reached the reactor")
  local rec = cl("record", b.unit_number)
  assert_eq(rec.status, "working", "status")
  assert_eq(#rec.data.power_log, 1, "one transition")
  assert_eq(rec.data.power_log[1].powered, true, "lit by the delivery")
  assert_true(b.light.visible, "light on")
end)

test("cl-brazier: real ticks: an inserter picking from the brazier tile cannot drain the fuel", function()
  local fx, elapsed = fixtures()
  assert_true(elapsed >= fx.inserter_ticks,
    string.format("fixture incomplete: needs %d ticks since arming, had %d", fx.inserter_ticks, elapsed))
  assert_not_nil(fx.pulled_coal, "fixture predates the drain check; run with --fresh")
  local b = fx.braziers.pulled
  assert_eq(fx.pull_sink_count, 0, "nothing reached the chest behind the inserter")
  -- One coal may be burning by now; the rest must still be in the slot.
  assert_true(b.fuel_count >= fx.pulled_coal - 1,
    string.format("fuel slot holds %d of %d coal", b.fuel_count, fx.pulled_coal))
  assert_true(b.burning, "still burning")
  local rec = cl("record", b.unit_number)
  assert_eq(rec.status, "working", "status")
  assert_eq(#rec.data.power_log, 0, "no false flame-out")
end)

test("cl-brazier: real ticks: re-arm fixtures for the next run", function()
  assert_true(cl("brazier_arm_fixtures"), "re-armed")
end)
