-- cl-signal-endpoint suite. TEST-ENTITIES.md section 8.
--
-- Power transitions need real ticks, which a one-tick suite cannot wait for, so
-- they are recorded by the rig the entity script arms at on_init and read here
-- through endpoint_rig. Everything else is built and asserted in this tick.

local CL = "component_lab"
local NAME = "cl-signal-endpoint"
local EEI = "cl-signal-endpoint-eei"
local RED = defines.wire_connector_id.circuit_red
local GREEN = defines.wire_connector_id.circuit_green

local function cl(fn, ...) return remote.call(CL, fn, ...) end

local row = require("_site").row{x = -520, y = 260}
local function site() return row:next(8) end

local function build(direction)
  local s, pos = site()
  local core = s.create_entity{name = NAME, position = pos, force = "player", direction = direction, raise_built = true}
  assert_not_nil(core, "create_entity " .. NAME)
  return core, s, pos
end

local function eei_of(core) return cl("parts", core.unit_number)["energy:energy"] end

local function signals(n)
  local items = {"iron-plate", "copper-plate", "steel-plate", "stone", "coal", "wood", "iron-ore", "copper-ore",
    "iron-gear-wheel", "electronic-circuit", "advanced-circuit", "processing-unit", "plastic-bar", "sulfur",
    "battery", "explosives", "copper-cable", "iron-stick", "stone-brick", "concrete", "landfill", "pipe",
    "engine-unit", "low-density-structure", "rocket-fuel"}
  local out = {}
  for i = 1, n do out[i] = {type = "item", name = items[i], count = i} end
  return out
end

local function section_filters(core)
  local section = core.get_or_create_control_behavior().get_section(1)
  return section and section.filters or {}
end

local function rig()
  local r = cl("endpoint_rig")
  assert_not_nil(r, "rig armed at on_init (run with --fresh)")
  assert_not_nil(r.done_tick, string.format(
    "rig scenario not finished at tick %d (step %d); the suite ran too early", game.tick, r.step or -1))
  return r
end

local function events_between(r, from_label, to_label)
  local lo, hi = r.obs[from_label].events, r.obs[to_label].events
  local out = {}
  for i = lo + 1, hi do out[#out + 1] = r.events[i] end
  return out
end

local function count_flag(list, flag)
  local n = 0
  for _, e in ipairs(list) do if e.flag == flag then n = n + 1 end end
  return n
end

-- ---- prototype --------------------------------------------------------------

test("cl-signal-endpoint: shape S1, constant-combinator core, one hidden EEI", function()
  assert_eq(cl("shape", NAME), "S1", "shape")
  local data = prototypes.mod_data["component-lab--" .. NAME].data
  assert_eq(data.core_type, "constant-combinator", "core type")
  assert_eq(data.watch, "activity", "always-on electric watcher")
  assert_eq(#data.parts, 1, "one hidden part")
  assert_eq(data.parts[1].prototype, EEI, "the EEI")
  assert_eq(data.spec.tick_interval, 60, "tick_interval")
  assert_eq(data.spec.max_output_signals, 20, "max_output_signals")
  local eei = assert_prototype("entity", EEI)
  assert_eq(eei.type, "electric-energy-interface")
  assert_eq(eei.electric_energy_source_prototype.buffer_capacity, 1e6, "1MJ buffer")
  assert_eq(eei.electric_energy_source_prototype.usage_priority, "secondary-input")
  assert_true(math.abs(eei.get_max_energy_usage() * 60 - 50e3) < 1, "50kW draw, got " .. eei.get_max_energy_usage() * 60)
  local ids = cl("event_ids")[NAME]
  assert_true(type(ids.status_changed) == "number", "status_changed id")
  assert_true(type(ids.power_state_changed) == "number", "power_state_changed id")
end)

-- ---- lifecycle ----------------------------------------------------------------

test("cl-signal-endpoint: build creates the EEI under the core and schedules the phase poll", function()
  local core = build()
  local u = core.unit_number
  local eei = eei_of(core)
  assert_true(eei ~= nil and eei.valid, "EEI exists")
  assert_eq(eei.position.x, core.position.x, "EEI under the core (x)")
  assert_eq(eei.position.y, core.position.y, "EEI under the core (y)")
  assert_eq(cl("owner_of", eei.unit_number), u, "EEI owned by the core")
  assert_true(not core.is_updatable, "constant-combinator core is not updatable")
  assert_true(eei.is_updatable, "EEI is updatable (the per-tick cost the native S1 replaces)")
  local rec = cl("record", u)
  assert_not_nil(rec.next_due, "poll scheduled")
  assert_eq(rec.next_due % 60, u % 60, "phase unit_number % tick_interval")
  assert_true(rec.next_due > game.tick and rec.next_due <= game.tick + 60, "within one interval")
  assert_true(not core.get_or_create_control_behavior().enabled, "output gated off until a poll proves power")
end)

test("cl-signal-endpoint: four directions, each with red and green connectors", function()
  for _, dir in ipairs({defines.direction.north, defines.direction.east, defines.direction.south, defines.direction.west}) do
    local core, s, pos = build(dir)
    assert_eq(core.direction, dir, "direction kept")
    local chest = s.create_entity{name = "wooden-chest", position = {pos[1] + 2, pos[2]}, force = "player"}
    for _, id in ipairs({RED, GREEN}) do
      local a = core.get_wire_connector(id, true)
      assert_not_nil(a, "connector " .. id .. " in direction " .. dir)
      assert_true(a.connect_to(chest.get_wire_connector(id, true), false, defines.wire_origin.player), "wire connects")
      assert_eq(a.connection_count, 1, "one wire")
    end
  end
end)

test("cl-signal-endpoint: mining returns the core item only and removes the EEI", function()
  local core = build()
  local u = core.unit_number
  local eei = eei_of(core)
  cl("endpoint_publish", u, signals(3))
  local inv = game.create_inventory(8)
  assert_true(cl("mine", core, inv), "mined")
  assert_true(not core.valid, "core gone")
  assert_true(not eei.valid, "EEI gone")
  assert_nil(cl("record", u), "record gone")
  assert_eq(inv.get_item_count(NAME), 1, "core item")
  assert_eq(inv.get_item_count(), 1, "nothing else")
  inv.destroy()
end)

test("cl-signal-endpoint: destroy and death remove the EEI", function()
  local a = build()
  local ea = eei_of(a)
  local ua = a.unit_number
  a.destroy{raise_destroy = true}
  assert_true(not ea.valid, "EEI gone after destroy")
  assert_nil(cl("record", ua), "record gone after destroy")
  local b = build()
  local eb = eei_of(b)
  local ub = b.unit_number
  b.die()
  assert_true(not eb.valid, "EEI gone after death")
  assert_nil(cl("record", ub), "record gone after death")
end)

test("cl-signal-endpoint: clone carries sections, buffer, status and its own poll", function()
  local core, s = build()
  local u = core.unit_number
  cl("endpoint_publish", u, signals(2))
  eei_of(core).energy = 400000
  cl("call", u, "set_status", "working")
  s.clone_entities{entities = {core}, destination_offset = {4, 0}}
  local copy = s.find_entity(NAME, {core.position.x + 4, core.position.y})
  assert_not_nil(copy, "clone exists")
  local ce = eei_of(copy)
  assert_true(ce ~= nil and ce.valid, "clone has its own EEI")
  assert_true(ce ~= eei_of(core), "not the source's EEI")
  assert_eq(ce.position.x, copy.position.x, "EEI moved with the clone")
  assert_true(math.abs(ce.energy - 400000) < 1, "buffer energy cloned, got " .. ce.energy)
  local f = section_filters(copy)
  assert_eq(#f, 2, "sections cloned")
  assert_eq(f[2].value.name, "copper-plate")
  local rec = cl("record", copy.unit_number)
  assert_eq(rec.status, "working", "status cloned")
  assert_eq(rec.next_due % 60, copy.unit_number % 60, "clone polls on its own phase")
  assert_eq(s.count_entities_filtered{name = EEI, position = copy.position}, 1, "exactly one EEI at the clone")
end)

-- ---- output -------------------------------------------------------------------

test("cl-signal-endpoint: publish writes a native section, clamped to max_output_signals", function()
  local core = build()
  local u = core.unit_number
  cl("endpoint_publish", u, signals(3))
  local f = section_filters(core)
  assert_eq(#f, 3, "three signals")
  assert_eq(f[1].value.name, "iron-plate")
  assert_eq(f[1].value.quality, "normal", "quality set explicitly")
  assert_eq(f[3].min, 3, "count")
  cl("endpoint_publish", u, signals(25))
  assert_eq(#section_filters(core), 20, "clamped to 20")
end)

test("cl-signal-endpoint: an unplugged endpoint polls to not_plugged_in, output stays off", function()
  local core = build()
  local u = core.unit_number
  cl("set_event_log", true)
  assert_eq(cl("endpoint_poll", u), "not_plugged_in_electric_network")
  local log = cl("event_log", true)
  cl("set_event_log", false)
  assert_eq(core.custom_status.label[1], "entity-status.not-plugged-in-electric-network", "custom_status label")
  assert_eq(core.custom_status.diode, defines.entity_status_diode.red, "red diode")
  assert_true(not core.get_or_create_control_behavior().enabled, "output off")
  assert_eq(count_flag(log, "status_changed"), 1, "status_changed raised")
  assert_eq(count_flag(log, "power_state_changed"), 0, "was never powered: no power flip")
  cl("set_event_log", true)
  cl("endpoint_poll", u)
  assert_eq(#cl("event_log", true), 0, "a steady poll raises nothing")
  cl("set_event_log", false)
end)

-- ---- real-tick rig ----------------------------------------------------------

test("cl-signal-endpoint: powered endpoint works, draws 50kW and shows in electric statistics", function()
  local r = rig()
  local o = r.obs.steady
  assert_eq(o.status, "working", "status")
  assert_true(o.enabled, "output on")
  assert_true(o.energy > 1e6 - 2000, "buffer kept full (refilled each tick), got " .. o.energy)
  local core = r.core
  assert_eq(core.custom_status.label[1], "entity-status.working", "custom_status on the core")
  local a, b = r.obs.steady, r.obs.restored
  assert_true((a.stats_in or 0) > 0, "network consumption statistics list " .. EEI)
  -- The buffer is full at both samples, so the network supplied exactly the draw.
  assert_true(math.abs(a.energy - b.energy) < 1, "buffer full at both samples")
  local watts = (b.stats_in - a.stats_in) / (b.tick - a.tick) * 60
  assert_true(math.abs(watts - 50e3) < 50, string.format("network supplied 50kW over the window, got %.1f W", watts))
  local eei = eei_of(core)
  assert_true(eei.energy > 1e6 - 2000, "still full now")
end)

test("cl-signal-endpoint: published signals appear on a wire from the core", function()
  local o = rig().obs.steady
  assert_eq(o.wire["iron-plate"], 10, "iron-plate on the wire")
  assert_eq(o.wire["copper-plate"], 20, "copper-plate on the wire")
end)

test("cl-signal-endpoint: cut network -> no_power within one poll, output off, wire empty", function()
  local r = rig()
  local o = r.obs.cut
  assert_eq(o.status, "no_power", "status after the cut")
  assert_true(not o.enabled, "cb.enabled == false")
  assert_eq(next(o.wire), nil, "wire reads nothing")
  assert_true(o.energy > 0, "buffer not yet empty: status follows supply, not the buffer")
end)

test("cl-signal-endpoint: restore -> working and the signals return", function()
  local o = rig().obs.restored
  assert_eq(o.status, "working", "status after restore")
  assert_true(o.enabled, "output on")
  assert_eq(o.wire["iron-plate"], 10, "iron-plate back")
  assert_eq(o.wire["copper-plate"], 20, "copper-plate back")
end)

test("cl-signal-endpoint: exactly one transition event per cut and per restore, none while steady", function()
  local r = rig()
  local steady = events_between(r, "steady", "steady2")
  assert_eq(#steady, 0, "no event while powered and steady")
  local cut = events_between(r, "steady2", "cut")
  assert_eq(count_flag(cut, "status_changed"), 1, "one status_changed on cut")
  assert_eq(count_flag(cut, "power_state_changed"), 1, "one power_state_changed on cut")
  assert_eq(cut[#cut].powered, false, "powered = false")
  assert_eq(#events_between(r, "cut", "cut2"), 0, "no event while unpowered and steady")
  local restore = events_between(r, "cut2", "restored")
  assert_eq(count_flag(restore, "status_changed"), 1, "one status_changed on restore")
  assert_eq(count_flag(restore, "power_state_changed"), 1, "one power_state_changed on restore")
  assert_eq(restore[#restore].powered, true, "powered = true")
end)

test("cl-signal-endpoint: unplug -> not_plugged_in; brownout -> low_power, still powered", function()
  local r = rig()
  assert_eq(r.obs.unplugged.status, "not_plugged_in_electric_network", "pole removed")
  assert_true(not r.obs.unplugged.enabled, "output off unplugged")
  assert_eq(r.obs.replugged.status, "working", "pole back")
  assert_eq(r.obs.brownout.status, "low_power", "25kW for a 50kW draw")
  assert_true(r.obs.brownout.enabled, "low power still publishes")
  local brown = events_between(r, "replugged", "brownout")
  assert_eq(count_flag(brown, "status_changed"), 1, "status_changed into low_power")
  assert_eq(count_flag(brown, "power_state_changed"), 0, "low_power is still powered")
  assert_eq(r.obs.final.status, "working", "back to working")
end)

-- ---- blueprint and copy-paste ------------------------------------------------

test("cl-signal-endpoint: blueprint has one entity with its sections and no EEI; ghost revives with them", function()
  local core, s, pos = build()
  local u = core.unit_number
  cl("endpoint_publish", u, signals(4))
  local inv = game.create_inventory(1)
  inv.insert{name = "blueprint"}
  local bp = inv[1]
  local mapping = bp.create_blueprint{surface = s, force = "player",
    area = {{pos[1] - 1, pos[2] - 1}, {pos[1] + 1, pos[2] + 1}}}
  cl("tag_blueprint", bp, mapping)
  local entities = bp.get_blueprint_entities()
  assert_eq(#entities, 1, "one entity, no EEI")
  assert_eq(entities[1].name, NAME)
  local cb = entities[1].control_behavior
  assert_not_nil(cb, "control behaviour in the blueprint")
  local filters = cb.sections and cb.sections.sections and cb.sections.sections[1].filters
  assert_true(filters ~= nil and #filters == 4, "four filters in the blueprint section")

  local ghosts = bp.build_blueprint{surface = s, force = "player", position = {pos[1] + 4, pos[2]},
    skip_fog_of_war = false, build_mode = defines.build_mode.forced}
  assert_eq(#ghosts, 1, "one ghost")
  local _, revived = ghosts[1].revive{raise_revive = true}
  assert_not_nil(revived, "revived")
  assert_not_nil(cl("record", revived.unit_number), "revived core registered")
  local e = eei_of(revived)
  assert_true(e ~= nil and e.valid, "revived core got its EEI")
  assert_eq(#section_filters(revived), 4, "sections came back")
  inv.destroy()
end)

test("cl-signal-endpoint: copy-paste carries the sections; the power gate is re-asserted at the next poll", function()
  local src = build()
  cl("endpoint_publish", src.unit_number, signals(5))
  local r = rig()
  local dst = r.core
  assert_true(dst.get_or_create_control_behavior().enabled, "rig endpoint powered and on before paste")
  dst.copy_settings(src)
  assert_eq(#section_filters(dst), 5, "sections pasted")
  assert_eq(section_filters(dst)[5].value.name, "coal")
  assert_true(not dst.get_or_create_control_behavior().enabled, "paste copied the unpowered source's off switch")
  assert_eq(cl("endpoint_poll", dst.unit_number), "working")
  assert_true(dst.get_or_create_control_behavior().enabled, "poll re-enabled the powered endpoint")
end)
