-- cl-dig-site suite. TEST-ENTITIES.md section 7.
-- In-tick tests drive the idle pass synchronously through dig_site_pass; the
-- behaviours that need the engine to tick (a real crafted event, real
-- inserters, module speed on progress) read the rigs the entity script builds
-- at map creation, so run with --fresh after any prototype change.

local NAME = "cl-dig-site"
local PART_NAMES = {NAME .. "-inv-food", NAME .. "-proxy-food", NAME .. "-inv-ore", NAME .. "-proxy-ore"}

local function cl(fn, ...) return remote.call("component_lab", fn, ...) end

-- Sites are 48 apart so the 12.5-tile ore scan of one never sees another's ore.
local row = require("_site").row{x = -900, y = 700, half = 16, tile = "lab-dark-1"}
local function pad(with_ore)
  local s, pos = row:next(48)
  local cx, cy = pos[1], pos[2]
  local ores = {}
  if with_ore then
    for dx = -1, 1 do
      ores[#ores + 1] = s.create_entity{name = "iron-ore", position = {cx + dx, cy - 5}, amount = 500}
    end
  end
  return s, {cx, cy}, ores
end

local function build(opts)
  opts = opts or {}
  local s, pos, ores = pad(opts.ore ~= false)
  local core = s.create_entity{name = NAME, position = pos, force = "player", raise_built = true}
  assert_not_nil(core, "create_entity " .. NAME)
  local u = core.unit_number
  if opts.modules then core.get_module_inventory().insert{name = opts.modules, count = opts.module_count or 1} end
  if opts.fish then cl("call", u, "inventory", "food").insert{name = "raw-fish", count = opts.fish} end
  return core, u, s, pos, ores
end

local function pass(u) cl("dig_site_pass", u) end
local function food(u) return cl("call", u, "inventory", "food") end
local function ore_inv(u) return cl("call", u, "inventory", "ore") end

local function parts(u)
  local out = {}
  for key, e in pairs(cl("parts", u) or {}) do out[key] = e end
  return out
end

local function count_parts_near(s, pos)
  local area = {{pos[1] - 1.5, pos[2] - 1.5}, {pos[1] + 1.5, pos[2] + 1.5}}
  local names = {NAME}
  for _, n in ipairs(PART_NAMES) do names[#names + 1] = n end
  return s.count_entities_filtered{area = area, name = names}
end

local function rig(name)
  local rigs = cl("dig_site_rigs")
  assert_not_nil(rigs, "dig site rigs are built at on_init (run with --fresh)")
  local r = rigs[name]
  assert_true(r.core.valid, name .. " rig core valid")
  return r
end

-- ---- prototypes and parts -------------------------------------------------

test("cl-dig-site: prototypes, shape S3, assembler shell with 4 hidden parts", function()
  local p = assert_prototype("entity", NAME)
  assert_eq(p.type, "assembling-machine", "core type")
  assert_eq(p.module_inventory_size, 4, "module slots")
  assert_eq(cl("shape", NAME), "S3", "shape")
  local def = prototypes.mod_data["component-lab--" .. NAME].data
  assert_eq(table.concat(def.part_names, ","), table.concat(PART_NAMES, ","), "hidden part list")
  assert_eq(assert_prototype("item", "cl-creature-fast").module_effects.speed, 1, "fast creature speed")
  assert_eq(assert_prototype("item", "cl-creature-slow").category, "cl-creature", "creature category")
  assert_true(p.allowed_module_categories and p.allowed_module_categories["cl-creature"], "shell accepts creatures")
  local ids = cl("event_ids")[NAME]
  assert_true(type(ids.cycle_started) == "number" and type(ids.cycle_finished) == "number", "event ids")
end)

test("cl-dig-site: build gives 1 core + 4 hidden; only the shell is updatable", function()
  local core, u, s, pos = build()
  assert_eq(count_parts_near(s, pos), 5, "entities per dig site (native: 1)")
  assert_true(core.is_updatable, "shell is updatable")
  local ps = parts(u)
  for _, key in ipairs({"inventory:food", "proxy:food", "inventory:ore", "proxy:ore"}) do
    assert_not_nil(ps[key], "part " .. key)
    assert_true(not ps[key].is_updatable, key .. " not updatable")
  end
  assert_eq(ps["proxy:food"].proxy_target_entity, ps["inventory:food"], "food proxy target")
  assert_eq(ps["proxy:food"].position.x, pos[1] - 1, "food proxy on the west column")
  assert_eq(ps["proxy:ore"].position.x, pos[1] + 1, "ore proxy on the east column")
  assert_true(core.get_module_inventory().can_insert{name = "cl-creature-fast"}, "creature module fits")
  assert_true(not core.get_module_inventory().can_insert{name = "speed-module"}, "other categories refused")
end)

-- ---- conditions and blocked status ------------------------------------------

test("cl-dig-site: no module -> disabled, red 'No creature'", function()
  local core, u = build({fish = 5})
  assert_true(core.disabled_by_script, "disabled")
  local rec = cl("record", u)
  assert_eq(rec.status, "no_modules", "status")
  assert_eq(core.custom_status.label[1], "cl-dig-site.no-creature", "label")
  assert_eq(core.custom_status.diode, defines.entity_status_diode.red, "diode")
  assert_eq(food(u).get_item_count("raw-fish"), 5, "no food consumed")
  assert_true(rec.next_due ~= nil and rec.next_due > game.tick, "idle shell polls")
  assert_true(rec.next_due <= game.tick + 61, "at the 61-tick interval")
end)

test("cl-dig-site: module + food but no ore in range -> blocked no_minable_resources", function()
  local core, u = build({ore = false, modules = "cl-creature-slow", fish = 5})
  pass(u)
  assert_true(core.disabled_by_script, "disabled")
  assert_eq(cl("record", u).status, "no_minable_resources", "blocked status")
  assert_eq(core.custom_status.label[1], "entity-status.no-minable-resources", "label")
  assert_eq(core.custom_status.diode, defines.entity_status_diode.red, "diode")
  assert_eq(food(u).get_item_count(), 5, "no food consumed while blocked")
end)

test("cl-dig-site: blocked outranks conditions (SPEC section 5 order)", function()
  local _, u = build({ore = false})
  assert_eq(cl("record", u).status, "no_minable_resources", "no ore and no module")
end)

test("cl-dig-site: module, no food -> yellow no_ingredients", function()
  local core, u = build({modules = "cl-creature-slow"})
  pass(u)
  assert_true(core.disabled_by_script, "disabled")
  assert_eq(cl("record", u).status, "no_ingredients", "status")
  assert_eq(core.custom_status.diode, defines.entity_status_diode.yellow, "diode")
end)

test("cl-dig-site: module + food + ore -> cycle starts in one pass, one food consumed", function()
  local core, u = build({modules = "cl-creature-slow", fish = 5})
  cl("set_event_log", true)
  pass(u)
  local log = cl("event_log", true)
  cl("set_event_log", false)
  assert_true(not core.disabled_by_script, "running")
  assert_eq(food(u).get_item_count("raw-fish"), 4, "one food consumed at start")
  assert_eq(#log, 1, "one event")
  assert_eq(log[1].flag, "cycle_started", "cycle_started raised")
  assert_eq(log[1].food, "raw-fish", "payload names the food")
  local rec = cl("record", u)
  assert_true(rec.data.active, "cycle active")
  assert_nil(rec.next_due, "running shell is not polled")
  assert_nil(core.custom_status, "engine status shown while running")
  pass(u)
  assert_eq(food(u).get_item_count("raw-fish"), 4, "a pass during a cycle consumes nothing")
end)

test("cl-dig-site: food filters pin fish and ration", function()
  local _, u = build()
  local inv = food(u)
  assert_eq(inv.get_filter(1).name, "raw-fish", "slot 1")
  assert_eq(inv.get_filter(2).name, "cl-ration", "slot 2")
  assert_eq(inv.insert{name = "iron-plate", count = 1}, 0, "non-food refused")
  assert_eq(inv.insert{name = "cl-ration", count = 3}, 3, "ration accepted")
end)

test("cl-dig-site: full ore output -> disabled with full_output", function()
  local core, u = build({modules = "cl-creature-slow", fish = 5})
  local inv = ore_inv(u)
  for i = 1, #inv do inv[i].set_stack{name = "iron-ore", count = 50} end
  pass(u)
  assert_true(core.disabled_by_script, "disabled")
  assert_eq(cl("record", u).status, "full_output", "status")
  assert_eq(core.custom_status.diode, defines.entity_status_diode.yellow, "diode")
  assert_eq(food(u).get_item_count(), 5, "no food consumed")
end)

-- The spec's `inventory_below{max_count = 1000}` cannot fail on a 4-slot
-- inventory of a 50-stack ore; the script adds a no-space-for-a-yield check.
test("cl-dig-site: inventory_below 1000 is unreachable with 4 ore slots (spec note)", function()
  local _, u = build({modules = "cl-creature-slow", fish = 5})
  local inv = ore_inv(u)
  for i = 1, #inv do inv[i].set_stack{name = "iron-ore", count = 50} end
  assert_eq(inv.get_item_count(), 200, "4 slots of iron ore hold 200")
  assert_nil(cl("call", u, "check_conditions"), "the declared conditions still all hold")
end)

-- ---- real ticks (rigs built at on_init) -----------------------------------

-- Written for any number of elapsed ticks: other fixtures in the full suite
-- may run the server longer (or faster) before the suite is called.
test("cl-dig-site: rig: a real cycle finishes, yields ore and depletes the patch", function()
  local r = rig("finish")
  local rec = cl("record", r.unit_number)
  local cycles = rec.data.cycles or 0
  assert_true(cycles >= 1, "crafted event handled (cycles " .. cycles .. ", tick " .. game.tick .. ")")
  assert_eq(rec.data.dug, 8 * cycles, "one fish yield (8) per cycle")
  assert_eq(ore_inv(r.unit_number).get_item_count("iron-ore"), rec.data.dug, "yield in ore")
  local left = 0
  for _, o in ipairs(r.ores) do left = left + o.amount end
  assert_eq(left, 3000 - rec.data.dug, "ore entity amount decreased by the yield")
  assert_eq(r.food_after_start, 9, "one food at the first start")
  assert_eq(food(r.unit_number).get_item_count(), 9 - cycles, "and one more as each next cycle starts")
  assert_true(not r.core.disabled_by_script, "next cycle running")
end)

local function total_progress(r)
  return (cl("record", r.unit_number).data.cycles or 0) + r.core.crafting_progress
end

test("cl-dig-site: rig: fast creature doubles crafting speed and progress", function()
  local slow, fast = rig("slow"), rig("fast")
  assert_eq(slow.core.crafting_speed, 1, "slow creature speed")
  assert_eq(fast.core.crafting_speed, 2, "fast creature speed")
  local ps, pf = total_progress(slow), total_progress(fast)
  assert_true(ps > 0, "slow rig progressing (tick " .. game.tick .. ")")
  assert_true(math.abs(pf - 2 * ps) < 1.5 / 1200, string.format("fast progress %.4f = 2 x slow %.4f", pf, ps))
  assert_eq(slow.food_after_start, 9, "one food consumed at start")
end)

local function moved(r)
  local held = r.inserter.held_stack.valid_for_read and r.inserter.held_stack.count or 0
  return r.chest.get_inventory(defines.inventory.chest).get_item_count(), held
end

test("cl-dig-site: rig: an inserter drops fish into food through the proxy", function()
  local r = rig("food_in")
  local in_chest, held = moved(r)
  local in_food = food(r.unit_number).get_item_count("raw-fish")
  -- Each later cycle start eats one fish, so the count has to add them back.
  local eaten = cl("record", r.unit_number).data.cycles or 0
  assert_true(in_food + eaten > r.food_after_start, "fish arrived in food (tick " .. game.tick .. ")")
  assert_eq(in_chest + held + in_food + eaten, 20 + 1 + r.food_after_start, "conserved")
end)

test("cl-dig-site: rig: an inserter cannot drop into ore", function()
  local r = rig("ore_in")
  local in_chest, held = moved(r)
  assert_eq(in_chest + held, 20, "nothing taken for the ore proxy")
  local dug = cl("record", r.unit_number).data.dug or 0
  assert_eq(ore_inv(r.unit_number).get_item_count(), dug, "ore holds only the rig's own yield")
end)

test("cl-dig-site: rig: an inserter picks from ore through the proxy", function()
  local r = rig("ore_out")
  local in_chest, held = moved(r)
  assert_true(in_chest + held > 0, "ore picked (tick " .. game.tick .. ")")
  local dug = cl("record", r.unit_number).data.dug or 0
  assert_eq(ore_inv(r.unit_number).get_item_count() + in_chest + held, 20 + dug, "conserved")
end)

test("cl-dig-site: KNOWN-LIMIT rig: an inserter must not pick from food (inserter_access = insert)", function()
  local r = rig("food_out")
  local in_chest, held = moved(r)
  assert_eq(in_chest + held, 0,
    "EMULATION LIMIT: a proxy-container exposes its target both ways, and the 2.1 inventory bar only gates " ..
    "insertion, so an insert-only inventory cannot refuse inserter pickup; the native type answers " ..
    "validMachinePickupTargetInternal per inventory (fish taken: " .. (in_chest + held) .. ")")
end)

test("cl-dig-site: KNOWN-LIMIT wires cannot read the food (it lives in a hidden container)", function()
  for _, n in ipairs({NAME .. "-inv-food", NAME .. "-proxy-food"}) do
    local p = prototypes.entity[n]
    assert_true(p.selectable_in_game == false and p.flags["not-selectable-in-game"],
      n .. " is not selectable, so a player cannot wire the food directly")
  end
  local r = rig("wired")
  local u = r.unit_number
  assert_true(r.core.get_control_behavior().circuit_read_contents, "shell reads contents")
  assert_eq(food(u).get_item_count("raw-fish"), 6, "food holds 6 fish")
  local net = {}
  for _, sig in pairs(r.pole.get_signals(defines.wire_connector_id.circuit_red) or {}) do
    net[sig.signal.name] = sig.count
  end
  assert_eq(net["copper-plate"], 7, "the wire has propagated: the native chest on it reads 7 copper (tick " .. game.tick .. ")")
  assert_eq(net["raw-fish"], 6,
    "EMULATION LIMIT: the shell's read-contents sees only the assembler's own inventories and the food sits in a " ..
    "hidden, unselectable container, so no wire can read it; the native type's circuit_outputs = \"contents\" " ..
    "would put the food on the network (raw-fish on the wire: " .. tostring(net["raw-fish"]) .. ")")
end)

test("cl-dig-site: KNOWN-LIMIT status follows the parts only at the next pass (up to 61 ticks late)", function()
  local core, u = build({modules = "cl-creature-slow", fish = 5})
  local inv = ore_inv(u)
  for i = 1, #inv do inv[i].set_stack{name = "iron-ore", count = 50} end
  pass(u)
  assert_eq(cl("record", u).status, "full_output", "idle on a full output")
  food(u).clear()
  local failing = cl("call", u, "check_conditions")
  assert_eq(failing and failing.status, "no_ingredients", "the conditions already say no_ingredients this tick")
  local rec = cl("record", u)
  assert_true(rec.next_due > game.tick and rec.next_due <= game.tick + 61,
    "the next pass is due within 61 ticks (in " .. (rec.next_due - game.tick) .. ")")
  assert_eq(rec.status, "no_ingredients",
    "EMULATION LIMIT: custom_status is written only by the 61-tick pass, so the shell still shows " ..
    tostring(rec.status) .. " (" .. tostring(core.custom_status and core.custom_status.label[1]) .. ") after the " ..
    "food is gone; the native type evaluates its conditions in its own update and reports no_ingredients at once")
end)

-- ---- blueprint, ghost requests, removal, clone ----------------------------

local function blueprint_of(s, pos)
  local inv = game.create_inventory(1)
  inv.insert{name = "blueprint"}
  local bp = inv[1]
  local mapping = bp.create_blueprint{surface = s, force = "player",
    area = {{pos[1] - 1.5, pos[2] - 1.5}, {pos[1] + 1.5, pos[2] + 1.5}}}
  cl("tag_blueprint", bp, mapping)
  return bp, inv
end

local function requested(list, name)
  local n = 0
  for _, plan in pairs(list or {}) do
    if plan.id.name == name then
      for _, at in pairs(plan.items.in_inventory or {}) do n = n + (at.count or 1) end
    end
  end
  return n
end

test("cl-dig-site: blueprint carries the module request, not the hidden food", function()
  local _, _, s, pos = build({modules = "cl-creature-fast", module_count = 2, fish = 5})
  local bp, inv = blueprint_of(s, pos)
  local entities = bp.get_blueprint_entities()
  assert_eq(#entities, 1, "hidden parts are not blueprinted")
  assert_eq(entities[1].name, NAME)
  assert_eq(requested(entities[1].items, "cl-creature-fast"), 2, "module request on the shell")
  assert_eq(requested(entities[1].items, "raw-fish"), 0, "food behind a proxy is not part of the blueprint")

  local ghosts = bp.build_blueprint{surface = s, force = "player", position = {pos[1] + 6, pos[2]},
    skip_fog_of_war = false, build_mode = defines.build_mode.forced}
  assert_eq(#ghosts, 1, "one ghost")
  local ghost_requests = 0
  for _, r in pairs(ghosts[1].item_requests) do
    if r.name == "cl-creature-fast" then ghost_requests = ghost_requests + r.count end
  end
  assert_eq(ghost_requests, 2, "ghost requests the modules")
  local _, revived, proxy = ghosts[1].revive{raise_revive = true, return_item_request_proxy = true}
  assert_not_nil(revived, "revived")
  assert_not_nil(cl("record", revived.unit_number), "revived core registered")
  assert_eq(#cl("call", revived.unit_number, "inventory", "food"), 2, "revived food part exists")
  assert_not_nil(proxy or revived.item_request_proxy, "module request proxy left for robots")
  assert_eq(cl("record", revived.unit_number).status, "no_modules", "revived site waits for its creature")
  inv.destroy()
end)

test("cl-dig-site: a ghost's food request is not fulfilled (no declared-inventory requests)", function()
  local s, pos = pad(true)
  local ghost = s.create_entity{name = "entity-ghost", inner_name = NAME, position = pos, force = "player"}
  -- The only inventories a ghost can name are the shell's; the closest is the
  -- 0-slot crafter input that a consume_at = "script" cycle leaves behind.
  local ok, err = pcall(function()
    ghost.insert_plan = {{id = {name = "raw-fish"},
      items = {in_inventory = {{inventory = defines.inventory.crafter_input, stack = 0, count = 5}}}}}
  end)
  assert_true(ok, "insert_plan accepted: " .. tostring(err))
  local _, revived, proxy = ghost.revive{raise_revive = true, return_item_request_proxy = true}
  assert_not_nil(revived, "revived")
  assert_eq(food(revived.unit_number).get_item_count(), 0, "food stays empty")
  if proxy and proxy.valid then
    assert_eq(proxy.proxy_target, revived, "the request targets the shell, never the hidden food container")
    assert_eq(#revived.get_inventory(defines.inventory.crafter_input), 0, "and the shell input has no slot to fill")
  end
end)

test("cl-dig-site: mining returns food, ore and the creature modules", function()
  local core, u = build({modules = "cl-creature-fast", module_count = 2, fish = 5})
  local ps = parts(u)
  ore_inv(u)[1].set_stack{name = "iron-ore", count = 7}
  local buffer = game.create_inventory(16)
  assert_true(cl("mine", core, buffer), "mined")
  assert_eq(buffer.get_item_count("raw-fish"), 5, "food returned")
  assert_eq(buffer.get_item_count("iron-ore"), 7, "ore returned")
  assert_eq(buffer.get_item_count("cl-creature-fast"), 2, "modules returned")
  assert_eq(buffer.get_item_count(NAME), 1, "dig site item returned")
  for key, e in pairs(ps) do assert_true(not e.valid, key .. " removed") end
  assert_nil(cl("record", u), "record gone")
  buffer.destroy()
end)

test("cl-dig-site: destroy with raise_destroy removes the parts", function()
  local core, u = build({fish = 3})
  local ps = parts(u)
  core.destroy{raise_destroy = true}
  for key, e in pairs(ps) do assert_true(not e.valid, key .. " removed") end
  assert_nil(cl("record", u), "record gone")
end)

test("cl-dig-site: death spills food and removes the parts", function()
  local core, u, s, pos = build({fish = 3})
  local ps = parts(u)
  core.die()
  for key, e in pairs(ps) do assert_true(not e.valid, key .. " removed") end
  local spilled = 0
  for _, e in pairs(s.find_entities_filtered{name = "item-on-ground", position = pos, radius = 5}) do
    if e.stack.name == "raw-fish" then spilled = spilled + e.stack.count end
  end
  assert_eq(spilled, 3, "food spilled")
end)

test("cl-dig-site: clone keeps contents and rescans ore at the destination", function()
  local core, u, s, pos = build({modules = "cl-creature-slow", fish = 6})
  -- Hold the source idle so the clone is judged by its own surroundings.
  cl("call", u, "inventory", "food").clear()
  pass(u)
  food(u).insert{name = "raw-fish", count = 6}
  local _, dest = pad(false)
  s.clone_entities{entities = {core}, destination_offset = {dest[1] - pos[1], dest[2] - pos[2]}}
  local copy = s.find_entity(NAME, dest)
  assert_not_nil(copy, "clone exists")
  local cu = copy.unit_number
  assert_eq(count_parts_near(s, dest), 5, "clone has its own 4 parts")
  assert_eq(food(cu).get_item_count("raw-fish"), 6, "food cloned")
  assert_eq(copy.get_module_inventory().get_item_count("cl-creature-slow"), 1, "module cloned")
  assert_eq(#cl("record", cu).data.ores, 0, "rescanned: no ore near the clone")
  assert_eq(cl("record", cu).status, "no_minable_resources", "clone blocked by its own surroundings")
  assert_eq(food(u).get_item_count("raw-fish"), 6, "source untouched")
end)
