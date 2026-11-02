-- cl-dig-site: the pY dino-dig-site pattern on the composed-machine emulation.
-- The shell is an automatic assembler whose cycle the script gates: a cycle may
-- only begin from try_start(), which consumes one food and raises cycle_started, so
-- the shell is kept disabled whenever it is idle. Idle shells poll at the pY
-- interval (61); running shells cost nothing until the crafted event.

local runtime = require("scripts.runtime")

local PASS_INTERVAL = 61
local SCAN_RADIUS = 12.5
local YIELD = {["raw-fish"] = 8, ["cl-ration"] = 16}
local LABELS = {no_modules = {"cl-dig-site.no-creature"}}

local function scan(rec)
  local e = rec.entity
  rec.data.ores = e.surface.find_entities_filtered{type = "resource", position = e.position, radius = SCAN_RADIUS}
  rec.data.next_ore = 1
end

-- Round robin over the build-time scan, pruning depleted patches as they are met.
local function next_ore(rec, advance)
  local ores = rec.data.ores or {}
  while #ores > 0 do
    local i = rec.data.next_ore or 1
    if i > #ores then i = 1 end
    local ore = ores[i]
    if ore.valid then
      if advance then rec.data.next_ore = i + 1 end
      return ore
    end
    table.remove(ores, i)
    rec.data.next_ore = i
  end
  return nil
end

local function ore_item(ore)
  for _, p in ipairs(ore.prototype.mineable_properties.products or {}) do
    if p.type == "item" then return p.name end
  end
  return nil
end

-- Written slot by slot because the ore inventory's bar is closed (it is what
-- keeps inserters from dropping into an output), and LuaInventory.insert
-- honours the bar.
local function put(inv, name, count)
  local stack_size = prototypes.item[name].stack_size
  for round = 1, 2 do
    for i = 1, #inv do
      if count <= 0 then return 0 end
      local stack = inv[i]
      if round == 1 and stack.valid_for_read and stack.name == name and stack.quality.name == "normal" then
        local n = math.min(count, stack_size - stack.count)
        stack.count = stack.count + n
        count = count - n
      elseif round == 2 and not stack.valid_for_read then
        local n = math.min(count, stack_size)
        stack.set_stack{name = name, count = n}
        count = count - n
      end
    end
  end
  return count
end

local function space_for(inv, name, count)
  local stack_size = prototypes.item[name].stack_size
  local free = 0
  for i = 1, #inv do
    local stack = inv[i]
    if not stack.valid_for_read then
      free = free + stack_size
    elseif stack.name == name then
      free = free + stack_size - stack.count
    end
    if free >= count then return true end
  end
  return false
end

local function take_food(rec)
  local inv = rec:inventory("food")
  for i = 1, #inv do
    local stack = inv[i]
    if stack.valid_for_read then
      local name = stack.name
      stack.count = stack.count - 1
      return name
    end
  end
  return nil
end

local function stop(rec, status, diode)
  rec.entity.disabled_by_script = true
  rec:set_status(status, {diode = diode, label = LABELS[status]})
  rec:schedule(PASS_INTERVAL)
end

-- SPEC section 4 step 4 with the section 5 priority: the script's blocked
-- status (5) outranks the declared conditions (7).
local function try_start(rec)
  local ore = next_ore(rec, false)
  if not ore then return stop(rec, "no_minable_resources") end
  local failing = rec:check_conditions()
  if failing then return stop(rec, failing.status, failing.diode) end
  local item = ore_item(ore)
  if item and not space_for(rec:inventory("ore"), item, YIELD["cl-ration"]) then
    return stop(rec, "full_output", "yellow")
  end
  local food = take_food(rec)
  rec.data.active = true
  rec.data.fed = food
  rec:unschedule()
  rec.entity.disabled_by_script = false
  rec:raise("cycle_started", {food = food})
  -- Cleared rather than set to working, so the engine's own no_power /
  -- low_power still shows while the cycle runs.
  rec:set_status(nil)
end

local function dig(rec)
  local ore = next_ore(rec, true)
  local amount = YIELD[rec.data.fed] or 0
  rec.data.fed = nil
  if not ore or amount == 0 then return end
  local item = ore_item(ore)
  if not item then return end
  if ore.amount <= amount then
    amount = ore.amount
    ore.deplete()
  else
    ore.amount = ore.amount - amount
  end
  put(rec:inventory("ore"), item, amount)
  rec.data.dug = (rec.data.dug or 0) + amount
end

local function pass(rec)
  if rec.data.active then return end
  try_start(rec)
end

runtime.expose("dig_site_pass", function(unit_number)
  local rec = storage.cl.records[unit_number]
  if rec then pass(rec) end
end)

-- ---- test rigs ---------------------------------------------------------------
-- A suite runs inside one tick, so behaviour that needs the engine to tick (a
-- real cycle, real inserters) is set up at map creation and read by the suite
-- once the server has run. Each rig sits on its own lab-tile pad, far enough
-- from the others that no scan radius overlaps.

local RIG_Y = -400

local function pad(surface, cx, cy)
  surface.request_to_generate_chunks({cx, cy}, 2)
  surface.force_generate_chunk_requests()
  local area = {{cx - 16, cy - 16}, {cx + 16, cy + 16}}
  local tiles = {}
  for x = cx - 16, cx + 15 do
    for y = cy - 16, cy + 15 do tiles[#tiles + 1] = {name = "lab-dark-1", position = {x, y}} end
  end
  surface.set_tiles(tiles)
  for _, e in pairs(surface.find_entities_filtered{area = area}) do
    if e.valid and e.type ~= "character" then e.destroy() end
  end
end

local function power(surface, cx, cy)
  surface.create_entity{name = "electric-energy-interface", position = {cx + 6, cy + 4}, force = "player"}
  surface.create_entity{name = "substation", position = {cx + 3, cy + 3}, force = "player"}
end

local function ore_patch(surface, cx, cy, amount)
  local out = {}
  for dx = -1, 1 do
    out[#out + 1] = surface.create_entity{name = "iron-ore", position = {cx + dx, cy - 5}, amount = amount}
  end
  return out
end

-- Base inserters have no custom vectors, so the facing is found by asking.
local function inserter(surface, at, to)
  local e = surface.create_entity{name = "fast-inserter", position = at, force = "player",
    direction = defines.direction.east}
  local dx = e.drop_position.x - e.position.x
  local want = to[1] - at[1]
  if (dx > 0) ~= (want > 0) then e.direction = defines.direction.west end
  return e
end

local function rig_site(index, opts)
  local surface = game.surfaces.nauvis
  local cx, cy = 400 + index * 48 + 0.5, RIG_Y + 0.5
  pad(surface, cx, cy)
  power(surface, cx, cy)
  local ores = opts.ore and ore_patch(surface, math.floor(cx), math.floor(cy), opts.ore) or {}
  local core = surface.create_entity{name = "cl-dig-site", position = {cx, cy}, force = "player"}
  -- Events raised during on_init are not delivered.
  local rec = runtime.lifecycle.materialise(core, nil, "rig")
  if opts.module then core.get_module_inventory().insert{name = opts.module, count = 1} end
  if opts.fish then rec:inventory("food").insert{name = "raw-fish", count = opts.fish} end
  local info = {unit_number = core.unit_number, core = core, ores = ores}
  -- Time compression: the server runs ~30 ticks before the suite, so the
  -- finish rig starts 99% through its 1200-tick cycle and the crafted event
  -- comes from the engine within that window.
  if opts.progress then
    core.disabled_by_script = false
    core.crafting_progress = opts.progress
  end
  pass(rec)
  info.food_after_start = rec:inventory("food").get_item_count()
  if opts.inserter then
    local side = opts.inserter.side
    local proxy_x = cx + side
    local ins_x, chest_x = cx + side * 2, cx + side * 3
    local chest = surface.create_entity{name = "iron-chest", position = {chest_x, cy}, force = "player"}
    if opts.inserter.chest_items then chest.insert(opts.inserter.chest_items) end
    local to = opts.inserter.into_site and {proxy_x, cy} or {chest_x, cy}
    local ins = inserter(surface, {ins_x, cy}, to)
    local proxy = rec.parts["proxy:" .. opts.inserter.inventory]
    if opts.inserter.into_site then ins.drop_target = proxy else ins.pickup_target = proxy end
    -- Saves the pickup leg, so the drop lands inside the ~20 ticks a fast
    -- boot leaves before the suite runs.
    if opts.inserter.preload then ins.held_stack.set_stack(opts.inserter.preload) end
    local items = opts.inserter.site_items
    if items then put(rec:inventory(opts.inserter.inventory), items.name, items.count) end
    info.chest = chest
    info.inserter = ins
  end
  return info
end

local function build_rigs()
  storage.cl.dig_rigs = {
    slow = rig_site(0, {module = "cl-creature-slow", fish = 10, ore = 1000}),
    fast = rig_site(1, {module = "cl-creature-fast", fish = 10, ore = 1000}),
    finish = rig_site(2, {module = "cl-creature-fast", fish = 10, ore = 1000, progress = 0.99}),
    food_in = rig_site(3, {module = "cl-creature-slow", fish = 10, ore = 1000,
      inserter = {side = -1, inventory = "food", into_site = true, chest_items = {name = "raw-fish", count = 20},
        preload = {name = "raw-fish", count = 1}}}),
    ore_in = rig_site(4, {module = "cl-creature-slow", fish = 10, ore = 1000,
      inserter = {side = 1, inventory = "ore", into_site = true, chest_items = {name = "raw-fish", count = 20}}}),
    ore_out = rig_site(5, {module = "cl-creature-slow", ore = 1000,
      inserter = {side = 1, inventory = "ore", into_site = false, site_items = {name = "iron-ore", count = 20}}}),
    food_out = rig_site(6, {ore = 1000,
      inserter = {side = -1, inventory = "food", into_site = false, site_items = {name = "raw-fish", count = 20}}}),
  }
end

runtime.init_hooks[#runtime.init_hooks + 1] = function()
  if not storage.cl.dig_rigs then build_rigs() end
end

runtime.expose("dig_site_rigs", function() return storage.cl.dig_rigs end)

return {
  on_created = function(rec, ctx)
    rec:inventory("ore").set_bar(1)
    -- Rescanned on clone too: the copied scan lists the source's patches.
    scan(rec)
    if ctx.cause == "clone" and rec.data.active then return end
    rec.data.active = false
    pass(rec)
  end,

  on_tick = function(rec) pass(rec) end,

  on_cycle_finished = function(rec)
    dig(rec)
    rec.data.active = false
    rec.data.cycles = (rec.data.cycles or 0) + 1
    try_start(rec)
  end,
}
