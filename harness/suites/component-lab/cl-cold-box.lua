-- cl-cold-box suite. TEST-ENTITIES.md section 4.
--
-- The emulation keeps stacks on the 1x clock and pushes them back by
-- elapsed * (1 - 1/m) per powered pass (LuaItemStack.spoil_tick refuses any
-- value beyond full freshness, so the SPEC 1.3 stamp `remaining * m` cannot be
-- written). Time-dependent behaviour is observed through the scenario the mod
-- builds at on_init and drives at fixed ticks; see the entity script.

local CL = "component_lab"
local NAME = "cl-cold-box"
local M, INTERVAL = 8, 60

local function cl(fn, ...) return remote.call(CL, fn, ...) end

local function credit(elapsed) return math.floor(elapsed * (1 - 1 / M)) end

local row = require("_site").row{x = -1600, y = -1700, half = 3, tile = "grass-1"}
local function build(width)
  local s, pos = row:next(width or 6)
  local core = s.create_entity{name = NAME, position = pos, force = "player", raise_built = true}
  assert_not_nil(core, "create_entity " .. NAME)
  return core, s
end

local function eei_of(u) return cl("parts", u)["energy:energy"] end
local function chest(core) return core.get_inventory(defines.inventory.chest) end

local function scenario()
  local sc = cl("cold_box_scenario")
  assert_not_nil(sc, "scenario armed at on_init (run with --fresh)")
  assert_true(game.tick - sc.t0 > 265, "scenario finished (tick " .. (game.tick - sc.t0) .. " of 266)")
  return sc
end

local function count_items(s, position, name)
  local n = 0
  for _, e in pairs(s.find_entities_filtered{name = "item-on-ground", position = position, radius = 5}) do
    if e.stack.name == name then n = n + e.stack.count end
  end
  return n
end

-- ---- prototype ----------------------------------------------------------------

test("cl-cold-box: prototypes, shape S1 and the hidden EEI sized for one interval", function()
  local core = assert_prototype("entity", NAME)
  assert_eq(core.type, "container", "core type")
  assert_eq(core.get_inventory_size(defines.inventory.chest), 16, "16 slots")
  local eei = assert_prototype("entity", NAME .. "-eei")
  assert_eq(eei.type, "electric-energy-interface")
  assert_eq(eei.electric_energy_source_prototype.buffer_capacity, 10000, "10 kJ = 10 kW x 60 ticks")
  assert_eq(cl("shape", NAME), "S1", "shape")
  local def = prototypes.mod_data["component-lab--" .. NAME].data
  assert_eq(def.watch, "activity", "watcher")
  assert_eq(#def.parts, 1, "one hidden part")
  assert_eq(def.spec.inventories[1].spoil_modifier.multiplier, M, "m")
  assert_eq(def.spec.tick_interval, INTERVAL, "tick_interval")
end)

-- ---- lifecycle ----------------------------------------------------------------

test("cl-cold-box: build materialises the EEI; core is not updatable, EEI is", function()
  local core = build()
  local u = core.unit_number
  local eei = eei_of(u)
  assert_true(eei ~= nil and eei.valid, "EEI exists")
  assert_eq(eei.position.x, core.position.x, "EEI under the core")
  assert_eq(cl("owner_of", eei.unit_number), u, "owner")
  assert_true(core.is_updatable == false, "container core is not updatable")
  assert_true(eei.is_updatable == true, "EEI is updatable (the per-tick cost)")
  local rec = cl("record", u)
  assert_not_nil(rec.next_due, "first pass scheduled")
  assert_true(rec.next_due - game.tick <= INTERVAL, "within one interval")
  assert_eq(rec.next_due % INTERVAL, u % INTERVAL, "phased by unit_number")
  assert_true(chest(core).supports_bar(), "bar")
end)

test("cl-cold-box: empty box disables its EEI; reads normal when powered", function()
  local core = build()
  local u = core.unit_number
  cl("cold_box_pass", u)
  assert_true(eei_of(u).disabled_by_script, "EEI asleep while empty")
  assert_eq(cl("record", u).status, "no_power", "off any network the powered condition still fails")
  local sc = scenario()
  assert_eq(sc.snaps[5].b.status, "normal", "powered and empty")
  assert_eq(sc.snaps[5].b.diode, defines.entity_status_diode.green, "green")
  chest(core).insert{name = "raw-fish", count = 1}
  cl("cold_box_pass", u)
  assert_true(not eei_of(u).disabled_by_script, "EEI awake with contents")
end)

test("cl-cold-box: unpowered box with contents reads no_power red", function()
  local core = build()
  local u = core.unit_number
  chest(core).insert{name = "raw-fish", count = 1}
  cl("cold_box_pass", u)
  assert_eq(cl("record", u).status, "no_power")
  assert_eq(core.custom_status.label[1], "entity-status.no-power")
  assert_eq(core.custom_status.diode, defines.entity_status_diode.red)
end)

test("cl-cold-box: destroy with raise_destroy removes the EEI", function()
  local core = build()
  local u = core.unit_number
  local eei = eei_of(u)
  core.destroy{raise_destroy = true}
  assert_true(not eei.valid, "EEI gone")
  assert_nil(cl("record", u), "record gone")
end)

test("cl-cold-box: death removes the EEI", function()
  local core = build()
  local u = core.unit_number
  local eei = eei_of(u)
  core.die()
  assert_true(not eei.valid, "EEI gone")
  assert_nil(cl("record", u), "record gone")
end)

test("cl-cold-box: clone carries contents, ticks and pass state", function()
  local core, s = build(12)
  local u = core.unit_number
  chest(core).insert{name = "raw-fish", count = 7}
  cl("cold_box_pass", u)
  local tick = chest(core)[1].spoil_tick
  s.clone_entities{entities = {core}, destination_offset = {4, 0}}
  local copy = s.find_entity(NAME, {core.position.x + 4, core.position.y})
  assert_not_nil(copy, "clone exists")
  local eei = eei_of(copy.unit_number)
  assert_true(eei ~= nil and eei.valid, "clone has its EEI")
  assert_eq(eei.position.x, copy.position.x, "EEI at the clone")
  assert_eq(chest(copy)[1].spoil_tick, tick, "spoil tick cloned unchanged")
  local a, b = cl("record", u), cl("record", copy.unit_number)
  assert_eq(b.data.last_pass, a.data.last_pass, "last pass carried")
  assert_eq(b.status, a.status, "status carried")
  assert_not_nil(b.next_due, "clone scheduled")
  assert_eq(s.count_entities_filtered{name = NAME .. "-eei", position = copy.position}, 1, "exactly one EEI")
end)

test("cl-cold-box: blueprint has one entity and the bar; revive restores both", function()
  local core, s = build(12)
  chest(core).set_bar(5)
  local inv = game.create_inventory(1)
  inv.insert{name = "blueprint"}
  local bp = inv[1]
  local p = core.position
  local mapping = bp.create_blueprint{surface = s, force = "player", area = {{p.x - 1, p.y - 1}, {p.x + 1, p.y + 1}}}
  assert_eq(cl("tag_blueprint", bp, mapping), 1, "core tagged")
  local entities = bp.get_blueprint_entities()
  assert_eq(#entities, 1, "hidden EEI not blueprinted")
  assert_eq(entities[1].name, NAME)
  -- set_bar takes the first locked slot; the blueprint stores the open-slot count.
  assert_eq(entities[1].bar, 4, "bar in the blueprint")
  local ghosts = bp.build_blueprint{surface = s, force = "player", position = {p.x + 4, p.y},
    skip_fog_of_war = false, build_mode = defines.build_mode.forced}
  assert_eq(#ghosts, 1, "one ghost")
  local _, revived = ghosts[1].revive{raise_revive = true}
  assert_not_nil(revived, "revived")
  assert_not_nil(cl("record", revived.unit_number), "revived core registered")
  assert_true(eei_of(revived.unit_number).valid, "revived core has its EEI")
  assert_eq(chest(revived).get_bar(), 5, "bar restored")
  inv.destroy()
end)

-- ---- the native stamp cannot be written -----------------------------------------

test("cl-cold-box: KNOWN LIMIT spoil_tick cannot exceed full freshness, so SPEC 1.3's stamp is unwritable", function()
  local inv = game.create_inventory(1)
  inv.insert{name = "raw-fish", count = 1}
  local stack = inv[1]
  local fresh = stack.spoil_tick - game.tick
  local ok = pcall(function() stack.spoil_tick = game.tick + fresh * M end)
  inv.destroy()
  assert_true(not ok, "engine refuses remaining * m on a fresh stack; if this now passes, the emulation "
    .. "could stamp natively (remaining * m on insert, / m on removal) instead of ageing per pass")
end)

-- ---- scenario: real ticks ---------------------------------------------------------

test("cl-cold-box: powered pass slows ageing to 1/8 (emulation: +elapsed*7/8 per pass)", function()
  local sc = scenario()
  local s5, s65 = sc.snaps[5].a, sc.snaps[65].a
  assert_eq(s5.status, "working", "powered at the first pass")
  assert_eq(s5.diode, defines.entity_status_diode.green, "green")
  assert_eq(s65.tick - s5.tick, credit(60), "pushed back by 60 * 7/8 over one interval")
  -- The ageing rate the stack actually saw over the interval: 1/8, which is
  -- what the native stamp yields. The doc's `elapsed * (m - 1)` (= 420 here)
  -- would make a stack gain life; the native stamp moves spoil_tick by
  -- remaining * 7 at insert, which is not representable (see the KNOWN LIMIT).
  local remaining5 = s5.tick - (sc.t0 + 5)
  local remaining65 = s65.tick - (sc.t0 + 65)
  assert_true(math.abs((remaining5 - remaining65) - 60 / M) <= 1, "aged 7.5 ticks in 60, got " .. (remaining5 - remaining65))
end)

test("cl-cold-box: power cut -> no_power red and 1x within one pass; restore -> working and 1/8 again", function()
  local sc = scenario()
  local cut, back, again = sc.snaps[200].a, sc.snaps[205].a, sc.snaps[265].a
  local before = sc.snaps[125].a
  assert_eq(before.status, "working", "still working before the cut")
  assert_eq(cut.status, "no_power", "no_power after the buffer drained")
  assert_eq(cut.diode, defines.entity_status_diode.red, "red")
  assert_eq(cut.energy, 0, "hidden buffer empty")
  assert_eq(cut.tick, before.tick, "no credit across the unpowered interval (1x)")
  assert_eq(back.status, "working", "working once power returned")
  assert_eq(back.tick, cut.tick, "no credit for the transition interval")
  assert_eq(again.tick - back.tick, credit(60), "1/8 again after restore")
  local flips = {}
  for _, e in ipairs(sc.events) do
    if e.unit_number == sc.units.a then flips[#flips + 1] = tostring(e.powered) .. "@" .. (e.tick - sc.t0) end
  end
  assert_eq(table.concat(flips, ","), "true@5,false@200,true@205", "power_state_changed per transition")
end)

test("cl-cold-box: self-scheduled box passes on its own on a real server", function()
  local sc = scenario()
  local rec = cl("record", sc.units.s)
  assert_true(rec.data.last_pass ~= nil and rec.data.last_pass > sc.t0, "passed at least once")
  assert_true(game.tick - rec.data.last_pass <= INTERVAL, "passed within the last interval")
  assert_eq((rec.data.last_pass - sc.t0) % INTERVAL, sc.units.s % INTERVAL, "on its phase")
  assert_not_nil(rec.next_due, "still scheduled")
end)

test("cl-cold-box: draws 10 kW only while non-empty", function()
  local sc = scenario()
  local e5, e65, e125, e200 = sc.snaps[5].feed2, sc.snaps[65].feed2, sc.snaps[125].feed2, sc.snaps[200].feed2
  assert_true(sc.snaps[65].b.disabled, "EEI disabled while empty")
  assert_true(math.abs(e65 - e5) < 1, "no draw while empty (" .. (e5 - e65) .. " J)")
  assert_true(not sc.snaps[125].b.disabled, "EEI enabled once the fish arrived")
  local drawn = e125 - e200
  local expected = 10000 / 60 * 75
  assert_true(math.abs(drawn - expected) <= 10000 / 60 * 2,
    string.format("10 kW over 75 ticks = %.0f J, drew %.0f J", expected, drawn))
end)

test("cl-cold-box: KNOWN GAP inserter removal misses the partial-interval credit", function()
  local sc = scenario()
  local c65 = sc.snaps[65].c.tick
  local moved = sc.snaps[125].d
  assert_true(moved > 0, "the inserter moved the fish into the plain chest")
  assert_eq(sc.snaps[125].c.tick, 0, "box emptied")
  -- A seen removal at tick r would add floor((r - 65) * 7/8): up to 51 ticks.
  -- No container transfer event exists, so the inserter path keeps the
  -- last-pass value. The native part settles every transfer.
  assert_eq(moved, c65, "inserter-moved fish carries only the credit up to the last pass")
end)

test("cl-cold-box: remote take settles the partial interval", function()
  local sc = scenario()
  local u = sc.units.t
  local rec = cl("record", u)
  assert_true(rec.data.powered, "powered")
  local box = cl("call", u, "inventory", "cold")
  local before = box[1].spoil_tick
  local dest = game.create_inventory(4)
  assert_eq(cl("cold_box_take", u, dest, "raw-fish", 4), 4, "moved four")
  local expected = before + credit(game.tick - rec.data.last_pass)
  assert_eq(dest[1].spoil_tick, expected, "taken fish credited for the partial interval")
  assert_eq(box[1].spoil_tick, before, "fish left behind untouched until the next pass")
  assert_eq(box[1].count, 6, "six left")
  dest.destroy()
end)

test("cl-cold-box: KNOWN GAP removal by another script misses the credit", function()
  local sc = scenario()
  local box = cl("call", sc.units.t, "inventory", "cold")
  local before = box[1].spoil_tick
  local dest = game.create_inventory(1)
  dest[1].transfer_stack(box[1], 1)
  assert_eq(dest[1].spoil_tick, before, "plain transfer is not settled (no transfer event)")
  dest.destroy()
end)

test("cl-cold-box: mining settles the fish through the before_mine hook, plus the box", function()
  local sc = scenario()
  local u = sc.units.m
  local rec = cl("record", u)
  local core = rec and cl("call", u, "inventory", "cold")
  assert_not_nil(core, "box m exists")
  local before = core[1].spoil_tick
  local expected = before + credit(game.tick - rec.data.last_pass)
  local entity = cl("parts", u)["energy:energy"]
  local inv = game.create_inventory(8)
  assert_true(cl("mine", game.surfaces.nauvis.find_entity(NAME, entity.position), inv), "mined")
  assert_eq(inv.get_item_count("raw-fish"), 5, "fish returned")
  assert_eq(inv.get_item_count(NAME), 1, "box returned")
  assert_true(not entity.valid, "EEI gone")
  local idx = inv.find_item_stack("raw-fish")
  assert_eq(idx.spoil_tick, expected, "fish settled before leaving")
  inv.destroy()
end)

-- ---- review fixes (REVIEW.md H1, H2) -----------------------------------------

test("cl-cold-box: review H1 a destroyed EEI is rebuilt and the pass runs", function()
  local core = build()
  local u = core.unit_number
  chest(core).insert{name = "raw-fish", count = 5}
  local old = eei_of(u)
  old.damage(5000, "enemy")
  assert_true(old.valid, "damage does not reach the EEI")
  old.die()
  assert_true(old.valid, "die() does not kill it either")
  old.destroy()
  cl("dispatch", cl("record", u).next_due, u)
  local eei = eei_of(u)
  assert_true(eei.valid, "EEI rebuilt")
  assert_eq(eei.disabled_by_script, false, "pass ran on the rebuilt EEI (box not empty)")
  assert_not_nil(cl("record", u).next_due, "next pass scheduled")
end)

test("cl-cold-box: review H2 removing the box from power_state_changed", function()
  local core = build()
  local u = core.unit_number
  chest(core).insert{name = "raw-fish", count = 5}
  local id = cl("event_ids")[NAME].power_state_changed
  local fired = 0
  script.on_event(id, function(e)
    if e.unit_number ~= u then return end
    fired = fired + 1
    e.entity.destroy{raise_destroy = true}
  end)
  local ok, err = pcall(cl, "dispatch", cl("record", u).next_due, u)
  script.on_event(id, nil)
  assert_true(ok, tostring(err))
  assert_eq(fired, 1, "unpowered first pass raised power_state_changed")
  assert_true(not core.valid, "box removed")
  assert_nil(cl("record", u), "record dropped")
end)
