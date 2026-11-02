-- cl-timed-converter suite (TEST-ENTITIES.md section 5). Synchronous tests drive
-- the poll through the scheduler's synthetic dispatch; anything that needs real
-- cycles reads the scenario the mod armed at map creation (run with --fresh).

local CL = "component_lab"
local NAME = "cl-timed-converter"
local CYCLE_TICKS = 300

local function cl(fn, ...) return remote.call(CL, fn, ...) end

local row = require("_site").row{x = 2000, y = 640, half = 12}
local function site() return row:next(12) end

local function build()
  local s, pos = site()
  local core = s.create_entity{name = NAME, position = pos, force = "player", raise_built = true}
  assert_not_nil(core, "create_entity " .. NAME)
  return core, s, pos
end

local function parts(u) return cl("parts", u) or {} end
local function input(u) return cl("call", u, "inventory", "input") end
local function output(u) return cl("call", u, "inventory", "output") end
local function fuel(u) return cl("call", u, "fuel_inventory") end

-- Runs the record's pending poll now instead of waiting for its tick.
local function poll(u)
  local due = cl("record", u).next_due
  assert_not_nil(due, "a poll is scheduled")
  cl("dispatch", due, u)
end

-- The event log is shared with the scenario's converters, which raise on
-- their own real-tick passes, so only this unit's events count.
local function own(log, u)
  local out = {}
  for _, e in ipairs(log or {}) do
    if e.unit_number == u then out[#out + 1] = e end
  end
  return out
end

local function flags(log, u)
  local out = {}
  for _, e in ipairs(own(log, u)) do out[#out + 1] = e.flag end
  return table.concat(out, ",")
end

local function scenario()
  local s = cl("tc_scenario")
  assert_not_nil(s, "timed scenario armed at on_init (run with --fresh)")
  assert_not_nil(s.done_tick, "timed scenario finished (game.tick " .. game.tick .. ")")
  return s
end

-- ---- prototypes -------------------------------------------------------------

test("cl-timed-converter: prototypes and shape S3", function()
  local p = assert_prototype("entity", NAME)
  assert_eq(p.type, "assembling-machine", "shell type")
  assert_eq(p.module_inventory_size, 2, "module slots")
  assert_eq(p.burner_prototype.fuel_categories["chemical"], true, "chemical burner")
  assert_eq(cl("shape", NAME), "S3", "shape")
  local recipe = assert_prototype("recipe", NAME .. "-cycle")
  assert_eq(recipe.energy, 5, "cycle_time")
  assert_eq(#recipe.ingredients, 0, "consume_at script: no engine ingredients")
  assert_eq(#recipe.products, 0, "no engine products (the cycle token is not needed)")
  assert_eq(assert_prototype("item", "cl-tagged-sample").type, "item-with-tags")
  local def = prototypes.mod_data["component-lab--" .. NAME].data
  local names = {}
  for _, part in ipairs(def.parts) do names[#names + 1] = part.kind .. ":" .. part.key end
  assert_eq(table.concat(names, ","), "inventory:input,proxy:input,inventory:output,proxy:output", "part plan")
end)

-- ---- lifecycle --------------------------------------------------------------

test("cl-timed-converter: build creates containers and edge proxies", function()
  local core = build()
  local u = core.unit_number
  local p = parts(u)
  for _, key in ipairs({"inventory:input", "proxy:input", "inventory:output", "proxy:output"}) do
    assert_true(p[key] ~= nil and p[key].valid, "part " .. key)
    assert_eq(cl("owner_of", p[key].unit_number), u, key .. " owner")
  end
  assert_eq(p["proxy:input"].proxy_target_entity, p["inventory:input"], "input proxy target")
  assert_eq(p["proxy:output"].proxy_target_entity, p["inventory:output"], "output proxy target")
  assert_eq(p["proxy:input"].position.x, core.position.x - 1, "input proxy on the west edge")
  assert_eq(p["proxy:output"].position.x, core.position.x + 1, "output proxy on the east edge")
  local inv = input(u)
  assert_eq(#inv, 4, "input size")
  assert_eq(#output(u), 2, "output size")
  assert_eq(inv.get_filter(1).name, "iron-ore", "slot filter 1")
  assert_eq(inv.get_filter(4).name, "cl-tagged-sample", "slot filter 4")
  assert_eq(inv.insert{name = "coal", count = 1}, 0, "unlisted item rejected")
end)

test("cl-timed-converter: shell updatable, hidden parts are not", function()
  local core = build()
  assert_true(core.is_updatable, "shell is updatable")
  for key, part in pairs(parts(core.unit_number)) do
    assert_true(not part.is_updatable, key .. " is_updatable")
  end
end)

test("cl-timed-converter: idle shell is disabled, not crafting, waiting_for_script", function()
  local core = build()
  assert_true(not core.is_crafting(), "not crafting")
  assert_true(core.disabled_by_script, "disabled_by_script")
  assert_eq(core.custom_status.label[1], "cl-status.waiting-for-script", "custom_status")
  poll(core.unit_number)
  assert_true(core.disabled_by_script, "an empty poll does not start it")
end)

test("cl-timed-converter: poll sees input, raises inventory_changed then cycle_started", function()
  local core = build()
  local u = core.unit_number
  poll(u)
  fuel(u).insert{name = "coal", count = 2}
  cl("set_event_log", true)
  input(u).insert{name = "iron-ore", count = 1}
  poll(u)
  local log = own(cl("event_log", true), u)
  cl("set_event_log", false)
  assert_eq(flags(log, u), "inventory_changed,cycle_started", "events in order")
  assert_eq(log[1].inventory, "input", "inventory_changed payload")
  assert_true(not core.disabled_by_script, "shell enabled")
  assert_nil(core.custom_status, "engine status shows while running")
  assert_eq(cl("record", u).data.current.name, "iron-ore", "stack chosen")
  assert_eq(input(u).get_item_count("iron-ore"), 1, "consume_at script: not consumed at start")
  cl("set_event_log", true)
  poll(u)
  assert_eq(flags(cl("event_log", true), u), "", "no event while nothing changed")
  cl("set_event_log", false)
end)

test("cl-timed-converter: no fuel holds the cycle and shows no_fuel", function()
  local core = build()
  local u = core.unit_number
  input(u).insert{name = "iron-ore", count = 1}
  poll(u)
  assert_true(core.disabled_by_script, "not started without fuel")
  assert_eq(core.custom_status.label[1], "entity-status.no-fuel", "no_fuel status")
  fuel(u).insert{name = "coal", count = 1}
  poll(u)
  assert_true(not core.disabled_by_script, "started once fuelled")
end)

test("cl-timed-converter: full output holds the cycle", function()
  local core = build()
  local u = core.unit_number
  fuel(u).insert{name = "coal", count = 1}
  output(u).insert{name = "iron-plate", count = 200}
  input(u).insert{name = "iron-ore", count = 1}
  poll(u)
  assert_true(core.disabled_by_script, "not started into a full output")
  assert_eq(core.custom_status.label[1], "entity-status.full-output", "full_output status")
end)

test("cl-timed-converter: script mine returns input, output, fuel, burnt result and modules", function()
  local core = build()
  local u = core.unit_number
  fuel(u).insert{name = "coal", count = 3}
  core.get_module_inventory().insert{name = "speed-module", count = 2}
  input(u).insert{name = "iron-ore", count = 4}
  output(u).insert{name = "iron-plate", count = 2}
  local burnt = core.burner.burnt_result_inventory
  local burnt_in = burnt.insert{name = "iron-gear-wheel", count = 1}
  poll(u)
  assert_true(not core.disabled_by_script, "mined mid-cycle")
  local inv = game.create_inventory(32)
  local p = parts(u)
  assert_true(cl("mine", core, inv), "mined")
  assert_true(not core.valid, "core gone")
  for key, part in pairs(p) do assert_true(not part.valid, key .. " removed") end
  assert_nil(cl("record", u), "record removed")
  assert_eq(inv.get_item_count("iron-ore"), 4, "input (the in-cycle ore too)")
  assert_eq(inv.get_item_count("iron-plate"), 2, "output")
  assert_eq(inv.get_item_count("coal"), 3, "fuel")
  assert_eq(inv.get_item_count("speed-module"), 2, "modules")
  assert_eq(inv.get_item_count(NAME), 1, "the converter")
  assert_eq(inv.get_item_count("iron-gear-wheel"), burnt_in,
    "burnt result inventory (insert accepted " .. burnt_in .. ")")
  inv.destroy()
end)

test("cl-timed-converter: destroy and death remove every part; death spills input", function()
  local core = build()
  local p = parts(core.unit_number)
  core.destroy{raise_destroy = true}
  for key, part in pairs(p) do assert_true(not part.valid, "destroy left " .. key) end

  local victim, s, pos = build()
  local u = victim.unit_number
  p = parts(u)
  input(u).insert{name = "stone", count = 6}
  victim.die()
  for key, part in pairs(p) do assert_true(not part.valid, "death left " .. key) end
  assert_nil(cl("record", u), "record removed")
  local spilled = 0
  for _, e in pairs(s.find_entities_filtered{name = "item-on-ground", position = pos, radius = 5}) do
    if e.stack.name == "stone" then spilled = spilled + e.stack.count end
  end
  assert_eq(spilled, 6, "spilled input")
end)

test("cl-timed-converter: clone copies parts, contents, filters and the running cycle", function()
  local core, s = build()
  local u = core.unit_number
  fuel(u).insert{name = "coal", count = 2}
  input(u).insert{name = "copper-ore", count = 3}
  poll(u)
  s.clone_entities{entities = {core}, destination_offset = {0, 5}}
  local copy = s.find_entity(NAME, {core.position.x, core.position.y + 5})
  assert_not_nil(copy, "clone exists")
  local cu = copy.unit_number
  local p = parts(cu)
  for _, key in ipairs({"inventory:input", "proxy:input", "inventory:output", "proxy:output"}) do
    assert_true(p[key] ~= nil and p[key].valid, "cloned part " .. key)
    assert_eq(p[key].position.y, copy.position.y, key .. " at the clone")
  end
  assert_eq(p["proxy:input"].proxy_target_entity, p["inventory:input"], "clone's proxy targets the clone's container")
  assert_eq(input(cu).get_item_count("copper-ore"), 3, "input cloned")
  assert_eq(input(cu).get_filter(2).name, "copper-ore", "filters cloned")
  assert_eq(fuel(cu).get_item_count("coal"), fuel(u).get_item_count("coal"), "fuel cloned")
  assert_eq(copy.disabled_by_script, false, "running state cloned")
  assert_eq(cl("record", cu).data.current.name, "copper-ore", "chosen stack cloned")
  assert_not_nil(cl("record", cu).next_due, "clone polls")
end)

test("cl-timed-converter: blueprint holds one entity with the module request", function()
  local core, s, pos = build()
  core.get_module_inventory().insert{name = "speed-module", count = 1}
  local inv = game.create_inventory(1)
  inv.insert{name = "blueprint"}
  local bp = inv[1]
  local mapping = bp.create_blueprint{surface = s, force = "player",
    area = {{pos[1] - 2, pos[2] - 2}, {pos[1] + 2, pos[2] + 2}}}
  cl("tag_blueprint", bp, mapping)
  local entities = bp.get_blueprint_entities()
  assert_eq(#entities, 1, "no containers or proxies in the blueprint")
  assert_eq(entities[1].name, NAME)
  local requested = 0
  for _, plan in ipairs(entities[1].items or {}) do
    if plan.id.name == "speed-module" then
      for _, at in ipairs(plan.items.in_inventory or {}) do requested = requested + (at.count or 1) end
    end
  end
  assert_eq(requested, 1, "module request")

  local ghosts = bp.build_blueprint{surface = s, force = "player", position = {pos[1], pos[2] + 6},
    skip_fog_of_war = false, build_mode = defines.build_mode.forced}
  assert_eq(#ghosts, 1, "one ghost")
  local _, revived = ghosts[1].revive{raise_revive = true}
  assert_not_nil(revived, "revived")
  assert_not_nil(cl("record", revived.unit_number), "revived core registered")
  assert_true(revived.disabled_by_script, "revived core idles")
  assert_eq(input(revived.unit_number).get_filter(1).name, "iron-ore", "revived input filtered")
  inv.destroy()
end)

-- ---- timed behaviour (scenario armed at on_init) ----------------------------

test("cl-timed-converter: idle shell burns no fuel over 300 ticks", function()
  local s = scenario()
  local before, after = s.idle_before, s.idle_after
  assert_not_nil(after, "idle sample taken")
  assert_eq(after.fuel, before.fuel, "fuel items")
  assert_eq(after.remaining, before.remaining, "remaining_burning_fuel")
  local core = s.entities.idle
  assert_true(core.disabled_by_script and not core.is_crafting(), "still idle")
end)

test("cl-timed-converter: inserter through the proxy starts a cycle within one poll", function()
  local s = scenario()
  assert_not_nil(s.ore_arrived, "the inserter delivered ore into the hidden input")
  assert_eq(s.feed_chest.get_item_count("iron-ore"), 0, "source chest emptied")
  local started = s.started[s.units.inserter]
  assert_not_nil(started, "cycle_started raised")
  local latency = started[1].tick - s.ore_arrived
  assert_true(latency >= 0 and latency <= 10,
    "started within one 10-tick poll of arrival (latency " .. latency .. "; native: same tick)")
  local finished = s.finished[s.units.inserter]
  assert_not_nil(finished, "cycle_finished raised")
  -- A cycle enabled from on_tick first advances in the next entity update.
  assert_eq(finished[1].tick - started[1].tick, CYCLE_TICKS + 1, "5 s cycle at speed 1, plus the start tick")
  local u = s.units.inserter
  assert_eq(output(u).get_item_count("iron-plate"), 1, "one plate in output")
  assert_eq(input(u).get_item_count("iron-ore"), 0, "ore consumed")
  assert_true(s.changed[u] ~= nil and #s.changed[u] >= 2, "inventory_changed on arrival and on consumption")
end)

-- TEST-ENTITIES.md expects >= 301 (a forced tick between crafts). SPEC 1.4 puts
-- that minimum on automatic start only (restart_delay); a script start issued from
-- the cycle_finished handler is back-to-back, and the emulation shows exactly that.
test("cl-timed-converter: two items give two back-to-back cycles", function()
  local s = scenario()
  local u = s.units.twice
  local finished = s.finished[u]
  assert_true(finished ~= nil and #finished == 2, "two cycle_finished events")
  assert_eq(finished[2].products - finished[1].products, 1, "products_finished increments per cycle")
  local spacing = finished[2].tick - finished[1].tick
  assert_eq(spacing, CYCLE_TICKS, "restart from the cycle_finished handler loses no tick")
  assert_eq(output(u).get_item_count("iron-plate"), 2, "two plates")
  assert_eq(input(u).get_item_count("iron-ore"), 0, "both ores consumed")
  local last = 0
  for _, sample in ipairs(s.progress) do
    assert_true(sample.value > last, "crafting_progress rising at tick " .. sample.tick .. " (" .. sample.value .. ")")
    last = sample.value
  end
  assert_true(last > 0.9 and last < 1, "progress near 1 before the finish (" .. last .. ")")
  local core = s.entities.twice
  assert_true(core.disabled_by_script, "idle again once the input is empty")
  assert_eq(core.custom_status.label[1], "cl-status.waiting-for-script", "waiting_for_script again")
end)

test("cl-timed-converter: a speed module shortens the cycle by its effect", function()
  local s = scenario()
  local u = s.units.speed
  local core = s.entities.speed
  local started, finished = s.started[u], s.finished[u]
  assert_true(started ~= nil and finished ~= nil, "cycle ran")
  local duration = finished[1].tick - started[1].tick
  local speed = core.crafting_speed
  assert_true(speed > 1, "module raised crafting_speed (" .. speed .. ")")
  local expected = CYCLE_TICKS / speed
  assert_true(duration >= expected and duration <= expected + 1.5,
    "duration " .. duration .. " ~ " .. expected .. " (+1 start tick)")
end)

test("cl-timed-converter: tagged input yields a result whose tag derives from it", function()
  local s = scenario()
  local out = output(s.units.tagged)
  assert_eq(out.get_item_count("cl-tagged-sample"), 1, "one tagged result")
  local stack = out.find_item_stack("cl-tagged-sample")
  assert_eq(stack.get_tag("seed"), 7, "seed carried")
  assert_eq(stack.get_tag("derived"), 22, "derived from seed 7")
  assert_eq(stack.get_tag("generation"), 1, "one generation")
  assert_eq(input(s.units.tagged).get_item_count("cl-tagged-sample"), 0, "input consumed")
end)

test("cl-timed-converter: clone carries a mid-cycle crafting_progress", function()
  local s = scenario()
  local c = s.clone
  assert_not_nil(c, "clone taken")
  assert_true(c.source_progress > 0.3 and c.source_progress < 0.7, "source mid-cycle (" .. c.source_progress .. ")")
  assert_eq(c.copy_progress, c.source_progress, "crafting_progress cloned")
  assert_eq(c.copy_disabled, false, "clone keeps running")
  assert_eq(c.copy_current, "iron-ore", "clone knows its chosen stack")
  local finished = s.finished[c.copy_unit]
  assert_not_nil(finished, "clone finished its cycle")
  assert_eq(output(c.copy_unit).get_item_count("iron-plate"), 1, "clone produced its plate")
  assert_eq(output(s.units.clone).get_item_count("iron-plate"), 1, "source produced its plate")
end)

-- ---- review fixes (REVIEW.md H2) ---------------------------------------------

test("cl-timed-converter: review H2 removing the converter from inventory_changed", function()
  local core = build()
  local u = core.unit_number
  fuel(u).insert{name = "coal", count = 5}
  local id = cl("event_ids")[NAME].inventory_changed
  local fired = 0
  script.on_event(id, function(e)
    if e.unit_number ~= u then return end
    fired = fired + 1
    e.entity.destroy{raise_destroy = true}
  end)
  local ok, err = pcall(function()
    input(u).insert{name = "iron-ore", count = 1}
    poll(u)
  end)
  script.on_event(id, nil)
  assert_true(ok, tostring(err))
  assert_eq(fired, 1, "inventory_changed raised once")
  assert_true(not core.valid, "converter removed")
  assert_nil(cl("record", u), "record dropped")
end)
