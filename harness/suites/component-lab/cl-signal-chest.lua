-- cl-signal-chest suite. TEST-ENTITIES.md section 2.

local CL = "component_lab"
local NAME = "cl-signal-chest"
local RED = defines.wire_connector_id.circuit_red
local GREEN = defines.wire_connector_id.circuit_green

local function cl(fn, ...) return remote.call(CL, fn, ...) end

local row = require("_site").row{x = 1200, y = 0}
local function site(width) return row:next(width) end

local function build(width)
  local s, pos = site(width)
  local core = s.create_entity{name = NAME, position = pos, force = "player", raise_built = true}
  assert_not_nil(core, "create_entity " .. NAME)
  return core, s, pos
end

local function cc_of(core) return cl("parts", core.unit_number)["combinator:signals"] end

-- {name -> count} of the hidden combinator's first section, as the engine holds it
local function section(cc)
  local cb = cc.get_control_behavior()
  if not cb then return {} end
  local out = {}
  local sec = cb.get_section(1)
  for _, f in pairs(sec and sec.filters or {}) do
    if f.value and f.value.name then
      out[f.value.name] = f.min
      assert_eq(f.value.quality, "normal", "filter quality pinned for " .. f.value.name)
    end
  end
  return out
end

local function wired(a, b, id)
  local ca = a.get_wire_connector(id, false)
  if not ca then return false end
  for _, c in pairs(ca.connections) do
    if c.target.owner == b then return true end
  end
  return false
end

local function all_invalid(parts)
  for key, e in pairs(parts) do if e.valid then return false, key end end
  return true
end

test("cl-signal-chest: prototype is an S0 container with one hidden combinator", function()
  assert_prototype("entity", NAME)
  assert_prototype("entity", NAME .. "-cc")
  assert_eq(cl("shape", NAME), "S0", "shape")
  local def = prototypes.mod_data["component-lab--" .. NAME].data
  assert_eq(def.core_type, "container", "core type")
  assert_eq(def.native_inventory, "main", "native inventory")
  assert_eq(#def.parts, 1, "one hidden part")
  assert_eq(def.parts[1].kind, "combinator", "the part is the script output")
  assert_eq(prototypes.entity[NAME].get_inventory_size(defines.inventory.chest), 16, "16 slots")
  assert_true(type(cl("event_ids")[NAME].inventory_changed) == "number", "inventory_changed id generated")
end)

test("cl-signal-chest: build wires the combinator to both colours; nothing is updatable", function()
  local core = build()
  local cc = cc_of(core)
  assert_true(cc ~= nil and cc.valid, "combinator part")
  assert_eq(cl("owner_of", cc.unit_number), core.unit_number, "owner")
  assert_true(wired(core, cc, RED), "red wire core<->combinator")
  assert_true(wired(core, cc, GREEN), "green wire core<->combinator")
  assert_eq(core.is_updatable, false, "core (container) is not an UpdatableEntity")
  assert_eq(cc.is_updatable, false, "combinator idle: not updatable")
  cl("signal_chest_publish", core.unit_number, {["iron-plate"] = 5})
  assert_eq(cc.is_updatable, false, "combinator publishing: still not updatable")
  assert_eq(core.is_updatable, false, "core still not updatable while publishing")
  assert_true(cl("record", core.unit_number).next_due ~= nil, "inventory_changed poll is scheduled")
end)

test("cl-signal-chest: publish writes the combinator section; empty disables it; capped at max_output_signals", function()
  local core = build()
  local u = core.unit_number
  local cc = cc_of(core)
  assert_eq(cl("signal_chest_publish", u, {["iron-plate"] = 5}), 1, "one signal kept")
  local sec = section(cc)
  assert_eq(sec["iron-plate"], 5, "iron-plate in section")
  assert_true(cc.get_control_behavior().enabled, "enabled while publishing")
  assert_eq(cl("signal_chest_signals", u)[1].count, 5, "record keeps the published list")
  cl("signal_chest_publish", u, {{type = "virtual", name = "signal-A", count = -3}, {name = "copper-plate", count = 2}})
  sec = section(cc)
  assert_nil(sec["iron-plate"], "publish replaces, not merges")
  assert_eq(sec["signal-A"], -3, "virtual signal")
  assert_eq(sec["copper-plate"], 2, "item signal")
  assert_eq(cl("signal_chest_publish", u, {}), 0, "empty publish")
  assert_true(not cc.get_control_behavior().enabled, "disabled while nothing is published")
  local many = {}
  local items = {}
  for name, proto in pairs(prototypes.item) do
    if not proto.hidden and not proto.parameter then items[#items + 1] = name end
  end
  table.sort(items)
  for i = 1, 25 do many[items[i]] = i end
  assert_eq(cl("signal_chest_publish", u, many), 20, "capped at max_output_signals = 20")
  local n = 0
  for _ in pairs(section(cc)) do n = n + 1 end
  assert_eq(n, 20, "section holds 20 filters")
end)

test("cl-signal-chest: lamp on the core reads contents + published signals the tick after, across save/load", function()
  local f = cl("signal_chest_fixture")
  assert_not_nil(f, "fixture armed at on_init (run with --fresh)")
  assert_not_nil(f.wire_t1, "fixture step 1 ran")
  assert_eq(f.wire_t1_tick, f.armed_tick + 1, "read on the tick after the publish")
  assert_eq(f.wire_t1["iron-plate"], 5, "published iron-plate=5 on the lamp's wire")
  assert_eq(f.wire_t1["copper-plate"], 7, "native read-contents copper-plate=7 on the same wire")
  assert_true(f.lamp.valid and f.a.valid, "fixture entities still exist")
  local now = {}
  for _, s in pairs(f.lamp.get_signals(RED) or {}) do now[s.signal.name] = s.count end
  assert_eq(now["iron-plate"], 5, "still published now (map was saved at creation and loaded by the server)")
  assert_eq(section(cc_of(f.a))["iron-plate"], 5, "section survived the save")
end)

test("cl-signal-chest: inventory_changed poll raises once per change per poll, never while untouched", function()
  local f = cl("signal_chest_fixture")
  assert_not_nil(f, "fixture armed at on_init (run with --fresh)")
  assert_true(f.done, "fixture finished (server ran " .. tostring(game.tick - f.armed_tick) .. " ticks; needs 84)")
  local before, one, burst = f.events_before_mutation, f.events_after_one, f.events_after_burst
  assert_eq(before.a, 0, "no event before the first poll")
  assert_eq(one.a, 1, "chest A: insert before the first poll -> one event")
  assert_eq(one.b, 1, "chest B: one transfer -> one event")
  assert_eq(one.c, 0, "chest C: untouched (publish only) -> no event")
  assert_eq(burst.a, 1, "chest A: untouched since -> no more events")
  assert_eq(burst.b, 2, "chest B: two transfers inside one poll window -> one event")
  assert_eq(burst.c, 0, "chest C: still none")
  assert_eq(f.wire_end["copper-plate"], 7, "wire still reads contents at the end")
end)

test("cl-signal-chest: poll through the scheduler (read_contents off forces the contents diff)", function()
  local core = build()
  local u = core.unit_number
  core.get_or_create_control_behavior().read_contents = false
  cl("set_event_log", true)
  local t = game.tick + 7771
  cl("schedule", u, t)
  cl("dispatch", t, u)
  assert_eq(#cl("event_log", false), 0, "untouched chest: no event")
  local inv = core.get_inventory(defines.inventory.chest)
  inv.insert{name = "iron-plate", count = 10}
  inv.insert{name = "copper-plate", count = 10}
  t = game.tick + 7781
  cl("schedule", u, t)
  cl("dispatch", t, u)
  local log = cl("event_log", true)
  assert_eq(#log, 1, "two transfers before a poll: one event")
  assert_eq(log[1].flag, "inventory_changed")
  assert_eq(log[1].inventory_name, "main")
  assert_eq(log[1].unit_number, u)
  t = game.tick + 7791
  cl("schedule", u, t)
  cl("dispatch", t, u)
  assert_eq(#cl("event_log", true), 0, "no event on the next untouched poll")
  cl("signal_chest_publish", u, {["iron-plate"] = 1})
  t = game.tick + 7801
  cl("schedule", u, t)
  cl("dispatch", t, u)
  assert_eq(#cl("event_log", true), 0, "publishing is not an inventory change")
  cl("set_event_log", false)
  assert_true(cl("record", u).next_due ~= nil, "poll re-armed itself")
end)

test("cl-signal-chest: script mine returns contents and removes the combinator", function()
  local core = build()
  local u = core.unit_number
  local parts = cl("parts", u)
  local keep = {}
  for k, e in pairs(parts) do keep[k] = e end
  cl("signal_chest_publish", u, {["iron-plate"] = 5})
  core.get_inventory(defines.inventory.chest).insert{name = "copper-plate", count = 3}
  local inv = game.create_inventory(8)
  assert_true(cl("mine", core, inv), "mined")
  assert_true(not core.valid, "core gone")
  local ok, key = all_invalid(keep)
  assert_true(ok, "part left behind: " .. tostring(key))
  assert_nil(cl("record", u), "registry entry")
  assert_eq(inv.get_item_count("copper-plate"), 3, "contents returned")
  assert_eq(inv.get_item_count(NAME), 1, "chest item returned")
  assert_eq(inv.get_item_count("constant-combinator"), 0, "no hidden-part item leaks")
  inv.destroy()
end)

test("cl-signal-chest: destroy and death remove the combinator", function()
  for _, how in ipairs({"destroy", "die"}) do
    local core = build()
    local u = core.unit_number
    local cc = cc_of(core)
    if how == "destroy" then core.destroy{raise_destroy = true} else core.die() end
    assert_true(not cc.valid, how .. ": combinator gone")
    assert_nil(cl("record", u), how .. ": registry entry")
  end
end)

test("cl-signal-chest: clone carries published signals and re-wires", function()
  local core, s = build(20)
  local u = core.unit_number
  cl("signal_chest_publish", u, {["iron-plate"] = 5, ["copper-plate"] = 9})
  core.get_inventory(defines.inventory.chest).insert{name = "coal", count = 4}
  s.clone_entities{entities = {core}, destination_offset = {5, 0}}
  local copy = s.find_entity(NAME, {core.position.x + 5, core.position.y})
  assert_not_nil(copy, "clone exists")
  local cc = cc_of(copy)
  assert_true(cc ~= nil and cc.valid, "cloned combinator")
  assert_eq(cc.position.x, copy.position.x, "combinator at the clone")
  assert_true(wired(copy, cc, RED) and wired(copy, cc, GREEN), "clone wired to its own combinator")
  assert_true(not wired(copy, cc_of(core), RED), "clone not wired to the source's combinator")
  local sec = section(cc)
  assert_eq(sec["iron-plate"], 5, "iron-plate cloned")
  assert_eq(sec["copper-plate"], 9, "copper-plate cloned")
  assert_eq(#cl("signal_chest_signals", copy.unit_number), 2, "record data cloned")
  assert_eq(copy.get_inventory(defines.inventory.chest).get_item_count("coal"), 4, "contents cloned natively")
  assert_eq(section(cc_of(core))["iron-plate"], 5, "source untouched")
  assert_true(cl("record", copy.unit_number).next_due ~= nil, "clone polls")
end)

test("cl-signal-chest: blueprint is one entity; signals survive blueprint -> ghost -> revive", function()
  local core, s, pos = build(20)
  local u = core.unit_number
  cl("signal_chest_publish", u, {["iron-plate"] = 5})
  local inv = game.create_inventory(1)
  inv.insert{name = "blueprint"}
  local bp = inv[1]
  local mapping = bp.create_blueprint{surface = s, force = "player",
    area = {{pos[1] - 1, pos[2] - 1}, {pos[1] + 1, pos[2] + 1}}}
  assert_eq(cl("tag_blueprint", bp, mapping), 1, "one core tagged")
  local entities = bp.get_blueprint_entities()
  assert_eq(#entities, 1, "the hidden combinator is not blueprinted")
  assert_eq(entities[1].name, NAME)
  assert_nil(entities[1].wires, "script wires to the hidden combinator are not blueprinted")
  local tags = bp.get_blueprint_entity_tags(1).component_lab
  assert_eq(tags.extra.signals[1].name, "iron-plate", "signals in tags")
  assert_eq(tags.extra.signals[1].count, 5)
  local ghosts = bp.build_blueprint{surface = s, force = "player", position = {pos[1] + 6, pos[2]},
    skip_fog_of_war = false, build_mode = defines.build_mode.forced}
  assert_eq(#ghosts, 1, "one ghost")
  local _, revived = ghosts[1].revive{raise_revive = true}
  assert_not_nil(revived, "revived")
  assert_eq(section(cc_of(revived))["iron-plate"], 5, "section restored from tags")
  assert_true(cc_of(revived).get_control_behavior().enabled, "output enabled after revive")
  inv.destroy()
end)

test("cl-signal-chest: copy-paste between two signal chests carries the sections", function()
  local a = build()
  local b = build()
  cl("signal_chest_publish", a.unit_number, {["iron-plate"] = 5, ["stone"] = 11})
  cl("signal_chest_publish", b.unit_number, {["coal"] = 1})
  assert_true(cl("paste", a, b), "pasted")
  local sec = section(cc_of(b))
  assert_eq(sec["iron-plate"], 5, "iron-plate pasted")
  assert_eq(sec["stone"], 11, "stone pasted")
  assert_nil(sec["coal"], "destination's old signals replaced")
  assert_eq(section(cc_of(a))["stone"], 11, "source untouched")
end)

test("cl-signal-chest: native comparison (wooden-chest + constant-combinator) is not updatable either", function()
  local s, pos = site()
  local chest = s.create_entity{name = "wooden-chest", position = pos, force = "player"}
  local combi = s.create_entity{name = "constant-combinator", position = {pos[1] + 2, pos[2]}, force = "player"}
  chest.get_wire_connector(RED, true).connect_to(combi.get_wire_connector(RED, true), false)
  local cb = combi.get_or_create_control_behavior()
  cb.get_section(1).filters = {{value = {type = "item", name = "iron-plate", quality = "normal", comparator = "="}, min = 5}}
  assert_eq(chest.is_updatable, false, "native chest")
  assert_eq(combi.is_updatable, false, "native constant combinator")
  chest.destroy()
  combi.destroy()
end)

