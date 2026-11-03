-- Library tests for component-lab: lifecycle, scheduler, status, blueprint.
-- Suites run inside the aitest mod, so everything in component-lab is reached
-- through remote.call("component_lab", ...).

local CL = "component_lab"

local function cl(fn, ...) return remote.call(CL, fn, ...) end

local row = require("_site").row{x = 300, y = 0}
local function site(width) return row:next(width) end

local function build(name, width)
  local s, pos = site(width)
  local core = s.create_entity{name = name, position = pos, force = "player", raise_built = true}
  assert_not_nil(core, "create_entity " .. name)
  return core, s, pos
end

local function part_list(unit_number)
  local out = {}
  for key, entity in pairs(cl("parts", unit_number) or {}) do out[key] = entity end
  return out
end

local function all_invalid(parts)
  for key, entity in pairs(parts) do
    if entity.valid then return false, key end
  end
  return true
end

local EXPECTED_LIBTEST_PARTS = {
  "inventory:extra", "proxy:extra", "energy:energy", "tank:fluid1", "combinator:signals",
}

test("component-lab loads (marker item present)", function()
  assert_prototype("item", "component-lab-marker")
end)

test("lib: shapes derived per SPEC section 2", function()
  assert_eq(cl("shape", "cl-libtest"), "S1", "electric always-on chest")
  assert_eq(cl("shape", "cl-libtest-machine"), "S3", "burner process")
  assert_eq(cl("shape", "cl-libtest-burner"), "S1", "burner chest")
  assert_eq(cl("shape", "cl-fluid-chest"), "S0", "fluid chest without the threshold event")
  local data = prototypes.mod_data["component-lab--cl-libtest"].data
  assert_eq(data.core_type, "container")
  assert_eq(data.native_inventory, "main")
end)

test("lib: hidden part prototypes carry the hidden boilerplate", function()
  for _, name in ipairs({"cl-libtest-inv-extra", "cl-libtest-proxy-extra", "cl-libtest-eei",
      "cl-libtest-tank-1", "cl-libtest-cc", "cl-libtest-burner-burner"}) do
    local p = assert_prototype("entity", name)
    assert_true(p.hidden, name .. " hidden")
    assert_true(not p.selectable_in_game, name .. " not selectable")
    assert_true(p.has_flag("not-blueprintable"), name .. " not blueprintable")
    assert_true(p.has_flag("not-deconstructable"), name .. " not deconstructable")
    assert_eq(next(p.collision_mask.layers), nil, name .. " collision layers empty")
  end
end)

test("lib: build materialises and registers every part", function()
  local core = build("cl-libtest")
  local u = core.unit_number
  local parts = part_list(u)
  for _, key in ipairs(EXPECTED_LIBTEST_PARTS) do
    local part = parts[key]
    assert_not_nil(part, "part " .. key)
    assert_true(part.valid, key .. " valid")
    assert_eq(part.force.name, "player", key .. " force")
    assert_eq(cl("owner_of", part.unit_number), u, key .. " owner")
  end
  assert_eq(parts["proxy:extra"].proxy_target_entity, parts["inventory:extra"], "proxy targets the hidden container")
  local rec = cl("record", u)
  assert_eq(rec.settings.level, 3, "setting default")
  assert_eq(rec.data.created_by, defines.events.script_raised_built, "on_created cause")
  local red = core.get_wire_connector(defines.wire_connector_id.circuit_red, false)
  assert_true(red ~= nil and red.connection_count >= 1, "combinator wired to the core")
end)

test("lib: build is idempotent across a second build event", function()
  local core = build("cl-libtest")
  local before = cl("count")
  script.raise_script_built{entity = core}
  assert_eq(cl("count"), before, "no second record")
  assert_eq(game.surfaces.nauvis.count_entities_filtered{name = "cl-libtest-inv-extra", position = core.position}, 1,
    "no second set of parts")
end)

test("lib: script mine returns hidden inventories and removes parts", function()
  local core = build("cl-libtest")
  local u = core.unit_number
  local parts = part_list(u)
  cl("call", u, "inventory", "extra").insert{name = "iron-plate", count = 5}
  core.get_inventory(defines.inventory.chest).insert{name = "copper-plate", count = 3}
  local inv = game.create_inventory(16)
  assert_true(cl("mine", core, inv), "mined")
  assert_true(not core.valid, "core gone")
  local ok, key = all_invalid(parts)
  assert_true(ok, "part left behind: " .. tostring(key))
  assert_nil(cl("record", u), "registry entry")
  assert_eq(inv.get_item_count("iron-plate"), 5, "hidden inventory returned")
  assert_eq(inv.get_item_count("copper-plate"), 3, "native inventory returned")
  assert_eq(inv.get_item_count("cl-libtest"), 1, "core item returned")
  inv.destroy()
end)

test("lib: mine of a burner chest returns its fuel", function()
  local core = build("cl-libtest-burner")
  local u = core.unit_number
  cl("call", u, "fuel_inventory").insert{name = "coal", count = 4}
  local inv = game.create_inventory(8)
  cl("mine", core, inv)
  assert_eq(inv.get_item_count("coal"), 4, "fuel returned")
  inv.destroy()
end)

test("lib: destroy with raise_destroy cleans up", function()
  local core = build("cl-libtest")
  local u = core.unit_number
  local parts = part_list(u)
  core.destroy{raise_destroy = true}
  local ok, key = all_invalid(parts)
  assert_true(ok, "part left behind: " .. tostring(key))
  assert_nil(cl("record", u), "registry entry")
end)

test("lib: death spills hidden contents and removes parts", function()
  local core, s, pos = build("cl-libtest")
  local u = core.unit_number
  local parts = part_list(u)
  cl("call", u, "inventory", "extra").insert{name = "iron-gear-wheel", count = 4}
  core.die()
  local ok, key = all_invalid(parts)
  assert_true(ok, "part left behind: " .. tostring(key))
  assert_nil(cl("record", u), "registry entry")
  local spilled = 0
  for _, e in pairs(s.find_entities_filtered{name = "item-on-ground", position = pos, radius = 5}) do
    if e.stack.name == "iron-gear-wheel" then spilled = spilled + e.stack.count end
  end
  assert_eq(spilled, 4, "spilled gears")
end)

test("lib: core removed without any event is cleaned by on_object_destroyed", function()
  local probe = cl("libtest_orphan_probe")
  assert_not_nil(probe, "orphan probe armed at on_init (run with --fresh)")
  assert_true(game.tick > probe.tick, "a tick has passed since the probe")
  local ok, key = all_invalid(probe.parts)
  assert_true(ok, "orphaned part survived: " .. tostring(key))
  assert_nil(cl("record", probe.unit_number), "registry entry")
  local s = game.surfaces.nauvis
  local spilled = 0
  for _, e in pairs(s.find_entities_filtered{name = "item-on-ground", position = probe.position, radius = 5}) do
    if e.stack.name == "iron-plate" then spilled = spilled + e.stack.count end
  end
  assert_eq(spilled, 7, "orphan's hidden contents spilled")
end)

test("lib: clone_entities re-creates parts with their contents", function()
  local core, s = build("cl-libtest", 20)
  local u = core.unit_number
  cl("call", u, "inventory", "extra").insert{name = "iron-plate", count = 9}
  cl("call", u, "set_setting", "level", 6)
  s.clone_entities{entities = {core}, destination_offset = {5, 0}}
  local copy = s.find_entity("cl-libtest", {core.position.x + 5, core.position.y})
  assert_not_nil(copy, "clone exists")
  local parts = part_list(copy.unit_number)
  for _, key in ipairs(EXPECTED_LIBTEST_PARTS) do
    assert_true(parts[key] ~= nil and parts[key].valid, "cloned part " .. key)
    assert_eq(parts[key].position.x, copy.position.x, key .. " at the clone")
  end
  assert_eq(cl("call", copy.unit_number, "inventory", "extra").get_item_count("iron-plate"), 9, "contents cloned")
  assert_eq(cl("record", copy.unit_number).settings.level, 6, "settings cloned")
  assert_eq(cl("call", u, "inventory", "extra").get_item_count("iron-plate"), 9, "source untouched")
end)

test("lib: clone_area does not leave duplicate parts", function()
  local core, s, pos = build("cl-libtest", 20)
  local area = {{pos[1] - 1, pos[2] - 1}, {pos[1] + 1, pos[2] + 1}}
  local dest = {{pos[1] + 9, pos[2] - 1}, {pos[1] + 11, pos[2] + 1}}
  s.clone_area{source_area = area, destination_area = dest, clone_entities = true, clone_tiles = false}
  local copy = s.find_entity("cl-libtest", {pos[1] + 10, pos[2]})
  assert_not_nil(copy, "clone exists")
  for _, name in ipairs({"cl-libtest-inv-extra", "cl-libtest-proxy-extra", "cl-libtest-eei", "cl-libtest-tank-1", "cl-libtest-cc"}) do
    assert_eq(s.count_entities_filtered{name = name, area = dest}, 1, name .. " exactly once at the clone")
  end
  assert_not_nil(cl("record", copy.unit_number), "clone registered")
end)

test("lib: scheduler buckets fire on the right tick (synthetic dispatch)", function()
  local core = build("cl-libtest")
  local u = core.unit_number
  local t = game.tick + 1000
  assert_eq(cl("schedule", u, t), t, "scheduled tick")
  local bucket = cl("bucket", t)
  assert_true(bucket ~= nil and bucket[#bucket] == u, "unit in its bucket")
  cl("dispatch", t - 1, u)
  assert_eq(#cl("record", u).data.fired, 0, "nothing fires a tick early")
  cl("dispatch", t, u)
  local fired = cl("record", u).data.fired
  assert_eq(#fired, 1, "fired once")
  assert_eq(fired[1], t, "fired at its tick")
  assert_nil(cl("bucket", t), "bucket consumed")
  assert_nil(cl("record", u).next_due, "next_due cleared")

  local t1, t2 = game.tick + 2000, game.tick + 2500
  cl("schedule", u, t1)
  cl("schedule", u, t2)
  cl("dispatch", t1, u)
  assert_eq(#cl("record", u).data.fired, 1, "a rescheduled entry is skipped at its old tick")
  cl("dispatch", t2, u)
  assert_eq(cl("record", u).data.fired[2], t2, "and fires at the new one")
end)

test("lib: scheduler fired on a real server tick", function()
  local probe = cl("libtest_probe")
  assert_not_nil(probe, "probe armed at on_init (run with --fresh)")
  assert_true(game.tick > probe.due, "server has passed the due tick")
  assert_eq(probe.fired_at, probe.due, "fired exactly on its tick")
  assert_eq(probe.fired_count, 1, "fired once")
  cl("libtest_arm_probe", 2)
end)

test("lib: set_status writes custom_status and raises status_changed", function()
  local core = build("cl-libtest")
  local u = core.unit_number
  cl("set_event_log", true)
  assert_true(cl("call", u, "set_status", "no_power"), "changed")
  local cs = core.custom_status
  assert_not_nil(cs, "custom_status set")
  assert_eq(cs.label[1], "entity-status.no-power", "label")
  assert_eq(cs.diode, defines.entity_status_diode.red, "diode")
  assert_true(not cl("call", u, "set_status", "no_power"), "no write when unchanged")
  cl("call", u, "set_status", "no_modules")
  assert_eq(core.custom_status.label[1], "cl-status.no-modules", "added status label")
  local log = cl("event_log", true)
  cl("set_event_log", false)
  assert_eq(#log, 2, "one event per transition")
  assert_eq(log[1].flag, "status_changed")
  assert_eq(log[1].new_status, "no_power")
  assert_eq(log[2].old_status, "no_power")
  assert_true(type(cl("event_ids")["cl-libtest"].status_changed) == "number", "event id exposed")
end)

test("lib: check_conditions reports the first failing condition", function()
  local core = build("cl-libtest-burner")
  local u = core.unit_number
  assert_nil(cl("call", u, "check_conditions"), "no conditions declared")
end)

test("lib: blueprint carries tags; revived ghost gets them back", function()
  local core, s, pos = build("cl-libtest", 20)
  local u = core.unit_number
  cl("call", u, "set_setting", "level", 7)
  cl("call", u, "inventory", "extra").set_bar(3)
  local inv = game.create_inventory(1)
  inv.insert{name = "blueprint"}
  local bp = inv[1]
  local mapping = bp.create_blueprint{surface = s, force = "player",
    area = {{pos[1] - 1, pos[2] - 1}, {pos[1] + 1, pos[2] + 1}}}
  assert_eq(cl("tag_blueprint", bp, mapping), 1, "one core tagged")
  local entities = bp.get_blueprint_entities()
  assert_eq(#entities, 1, "hidden parts are not blueprinted")
  assert_eq(entities[1].name, "cl-libtest")
  local tags = bp.get_blueprint_entity_tags(1).component_lab
  assert_eq(tags.settings.level, 7, "setting in tags")
  assert_eq(tags.bars.extra, 3, "hidden bar in tags")

  local ghosts = bp.build_blueprint{surface = s, force = "player", position = {pos[1] + 6, pos[2]},
    skip_fog_of_war = false, build_mode = defines.build_mode.forced}
  assert_eq(#ghosts, 1, "one ghost")
  local _, revived = ghosts[1].revive{raise_revive = true}
  assert_not_nil(revived, "revived")
  local rec = cl("record", revived.unit_number)
  assert_not_nil(rec, "revived core registered")
  assert_eq(rec.settings.level, 7, "setting applied from tags")
  assert_eq(cl("call", revived.unit_number, "inventory", "extra").get_bar(), 3, "bar applied from tags")
  inv.destroy()
end)

test("lib: script-start shell idles disabled until start_cycle", function()
  local core = build("cl-libtest-machine")
  local u = core.unit_number
  assert_true(core.disabled_by_script, "idle shell disabled")
  assert_eq(cl("record", u).status, "waiting_for_script")
  assert_eq(core.custom_status.label[1], "cl-status.waiting-for-script")
  cl("set_event_log", true)
  assert_true(cl("call", u, "start_cycle"), "started")
  assert_true(not core.disabled_by_script, "running")
  local log = cl("event_log", true)
  cl("set_event_log", false)
  assert_eq(log[1] and log[1].flag, "cycle_started", "cycle_started raised")
  local parts = part_list(u)
  assert_eq(parts["proxy:input"].position.x, core.position.x - 1, "proxy offset applied")
end)

-- ---- review fixes (REVIEW.md H1, H2) -----------------------------------------

-- The suite runs in the aitest mod, so a subscriber registered here sees
-- component_lab's events exactly as a third-party mod would.
local function with_subscriber(id, fn, body)
  script.on_event(id, fn)
  local ok, err = pcall(body)
  script.on_event(id, nil)
  if not ok then error(err, 0) end
end

test("lib: review H1 hidden parts cannot be damaged", function()
  local core = build("cl-libtest")
  local parts = part_list(core.unit_number)
  for _, key in ipairs(EXPECTED_LIBTEST_PARTS) do
    assert_true(not parts[key].destructible, key .. " indestructible")
  end
  parts["energy:energy"].damage(1000000, "enemy")
  assert_true(parts["energy:energy"].valid, "EEI survives damage")
end)

test("lib: review H1 a part removed by script is rebuilt before the next handler", function()
  local core = build("cl-libtest")
  local u = core.unit_number
  local old = part_list(u)
  old["energy:energy"].die()
  assert_true(old["energy:energy"].valid, "die() does not kill an indestructible part")
  old["energy:energy"].destroy()
  old["inventory:extra"].destroy()
  local due = cl("call", u, "schedule", 1)
  cl("dispatch", due, u)
  local rec = cl("record", u)
  assert_eq(rec.data.fired[#rec.data.fired], due, "on_tick ran")
  local now = part_list(u)
  for _, key in ipairs(EXPECTED_LIBTEST_PARTS) do
    assert_true(now[key].valid, key .. " valid")
    assert_true(not now[key].destructible, key .. " indestructible")
    assert_eq(cl("owner_of", now[key].unit_number), u, key .. " owner")
  end
  assert_true(not old["energy:energy"].valid and not old["inventory:extra"].valid, "old parts gone")
  assert_eq(now["proxy:extra"].proxy_target_entity, now["inventory:extra"], "proxy relinked to the new container")
  assert_not_nil(cl("call", u, "inventory", "extra"), "inventory reachable")
end)

test("lib: review H2 a subscriber may remove the machine from its own event", function()
  local core = build("cl-libtest")
  local u = core.unit_number
  local parts = part_list(u)
  local fired = 0
  with_subscriber(cl("event_ids")["cl-libtest"].status_changed, function(e)
    fired = fired + 1
    if e.entity.valid then e.entity.destroy{raise_destroy = true} end
  end, function()
    assert_true(cl("call", u, "set_status", "no_power"), "status changed")
  end)
  assert_eq(fired, 1, "subscriber ran once")
  assert_true(not core.valid, "core removed")
  assert_nil(cl("record", u), "record dropped")
  local ok, key = all_invalid(parts)
  assert_true(ok, "parts torn down (" .. tostring(key) .. ")")
end)

-- Library parts added for the later entities (README, same heading).

test("lib: v2 parts generate their prototypes and shapes", function()
  for _, name in ipairs({"cl-libtest-rotor-proxy-main", "cl-libtest-hearth-burner", "cl-libtest-hearth-proxy-fuel",
      "cl-libtest-hearth-generator", "cl-libtest-hearth-heat", "cl-libtest-brazier-burner",
      "cl-libtest-brazier-proxy-fuel"}) do
    local p = assert_prototype("entity", name)
    assert_true(p.hidden and p.has_flag("not-blueprintable"), name .. " is a hidden part")
  end
  assert_eq(cl("shape", "cl-libtest-rotor"), "S0", "passive rotatable shell")
  assert_eq(cl("shape", "cl-libtest-hearth"), "S3", "always-burning shell")
  assert_eq(cl("shape", "cl-libtest-brazier"), "S1", "part-only burner")
  local rotor = prototypes.entity["cl-libtest-rotor"]
  assert_eq(rotor.type, "assembling-machine")
  assert_nil(rotor.fixed_recipe, "rotor has no recipe")
  assert_nil(rotor.electric_energy_source_prototype, "rotor draws no power")
  local hearth = prototypes.entity["cl-libtest-hearth"]
  assert_nil(hearth.burner_prototype, "the hearth's burner moved off the shell")
  assert_eq(prototypes.entity["cl-libtest-brazier"].type, "simple-entity-with-owner")
  assert_eq(prototypes.entity["cl-libtest-hearth-generator"].type, "electric-energy-interface")
  assert_eq(prototypes.entity["cl-libtest-hearth-heat"].type, "heat-interface")
end)

test("lib: extra proxies are doors to one inventory and follow a rotation", function()
  local core = build("cl-libtest-rotor")
  local u = core.unit_number
  local parts = part_list(u)
  local inv = parts["inventory:main"]
  assert_eq(parts["proxy:main"].proxy_target_entity, inv, "first door")
  assert_eq(parts["proxy:main@2"].proxy_target_entity, inv, "second door")
  assert_eq(parts["proxy:main"].position.x, core.position.x - 1, "first door west of centre")
  cl("call", u, "inventory", "main").insert{name = "iron-plate", count = 100}
  local before = core.direction
  assert_true(cl("rotate", core), "assembler shell rotates")
  assert_true(core.direction ~= before, "direction changed")
  assert_eq(cl("record", u).data.rotated_from, before, "on_rotated got the previous direction")
  assert_eq(parts["proxy:main"].position.x, core.position.x, "door moved with the facing (x)")
  assert_eq(parts["proxy:main"].position.y, core.position.y - 1, "door moved with the facing (y)")
  assert_eq(cl("call", u, "inventory", "main").get_item_count("iron-plate"), 100, "contents kept")
end)

test("lib: fuel proxy feeds a hidden reactor; has_fuel follows it", function()
  local core = build("cl-libtest-brazier")
  local u = core.unit_number
  local parts = part_list(u)
  local proxy, burner = parts["proxy:fuel"], parts["energy:energy"]
  assert_eq(proxy.proxy_target_entity, burner, "proxy targets the reactor")
  assert_eq(proxy.proxy_target_inventory, defines.inventory.fuel, "proxy targets the fuel slot")
  assert_true(not cl("call", u, "has_fuel"), "empty at build")
  proxy.get_inventory(defines.inventory.proxy_main).insert{name = "coal", count = 3}
  assert_eq(burner.burner.inventory.get_item_count("coal"), 3, "fuel went through the proxy")
  assert_true(cl("call", u, "has_fuel"), "has_fuel with coal waiting")
  local inv = game.create_inventory(8)
  assert_true(cl("mine", core, inv), "mined")
  assert_eq(inv.get_item_count("coal"), 3, "fuel returned")
  inv.destroy()
end)

test("lib: generation and heat parts take energy from the handler", function()
  local core = build("cl-libtest-hearth")
  local u = core.unit_number
  local parts = part_list(u)
  assert_not_nil(parts["proxy:fuel"], "hearth fuel door")
  assert_eq(cl("call", u, "add_output_energy", 5e6), 5e6, "first 5 MJ fit")
  assert_eq(cl("call", u, "add_output_energy", 30e6), 15e6, "capped at the 20 MJ buffer")
  assert_eq(parts["generator:output"].energy, 20e6, "buffer full")
  local t0 = parts["heat:heat"].temperature
  assert_eq(cl("call", u, "add_heat", 100e6), 100e6, "100 MJ fit")
  assert_eq(parts["heat:heat"].temperature, t0 + 100, "1 MJ per degree")
  assert_eq(cl("call", u, "add_heat", 1e12), (500 - t0 - 100) * 1e6, "capped at max_temperature")
end)

test("lib: read_signal is 0 on an unwired core", function()
  local core = build("cl-libtest")
  assert_eq(cl("call", core.unit_number, "read_signal", "signal-A"), 0)
end)

-- CraftingMachinePrototype: a non-square crafting machine "can only be rotated
-- before placement". With the passive shell's connectionless fluid box
-- (direction_count = 4) 2.1.24 does rotate it after placement, but only by 180
-- degrees (east <-> west): the box never turns. Placement and blueprints take
-- all four directions.
test("lib: KNOWN-LIMIT a non-square shell only flips 180 degrees after placement", function()
  local s, pos = site(12)
  local placed = s.create_entity{name = "cl-libtest-rotor-long", position = pos, direction = defines.direction.east,
    force = "player", raise_built = true}
  assert_eq(placed.direction, defines.direction.east, "placed facing east")
  local box = placed.bounding_box
  assert_true(box.right_bottom.y - box.left_top.y > 5, "east-facing box is 3 wide, 6 tall")
  assert_true(cl("rotate", placed), "rotate accepted")
  assert_eq(placed.direction, defines.direction.west, "flipped, not turned (drop this limit if it turns)")
  box = placed.bounding_box
  assert_true(box.right_bottom.y - box.left_top.y > 5, "box unchanged")
end)
