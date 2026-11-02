-- cl-creep-collector: energy per unit of script-chosen work (TEST-ENTITIES-2.md
-- section 3). The shell idles disabled_by_script, so it draws nothing and leaves
-- the active list. When the script finds a tree or rock in range it enables the
-- shell for one 2 s cycle, so the engine charges 800 kJ at 400 kW with no Lua
-- energy arithmetic; the finished cycle removes the target and yields its items.

local runtime = require("scripts.runtime")
local scheduler = require("scripts.scheduler")
local defs = require("scripts.defs")

local NAME = "cl-creep-collector"
local RANGE = 8
-- Nothing raises an event when a tree grows or a rock is placed by another mod,
-- so an idle collector has to look again; one second is Rampant's own cadence.
local IDLE_POLL = 60

local function is_target(e)
  if e.type == "tree" then return true end
  return e.type == "simple-entity" and e.prototype.count_as_rock_for_filtered_deconstruction
end

local function find_target(surface, position)
  local best, best_d
  for _, e in pairs(surface.find_entities_filtered{position = position, radius = RANGE, type = {"tree", "simple-entity"}}) do
    if is_target(e) then
      local dx, dy = e.position.x - position.x, e.position.y - position.y
      local d = dx * dx + dy * dy
      if not best_d or d < best_d then best, best_d = e, d end
    end
  end
  return best
end

-- Mining results with a random amount would make the yield, and so the tests and
-- the bench, depend on a generator; the midpoint keeps it deterministic.
local function yield_of(prototype)
  local out = {}
  local props = prototype.mineable_properties
  for _, p in ipairs(props and props.products or {}) do
    if p.type == "item" and (p.probability or 1) >= 1 then
      local count = p.amount or math.floor(((p.amount_min or 0) + (p.amount_max or 0)) / 2)
      if count > 0 then out[#out + 1] = {name = p.name, count = count} end
    end
  end
  return out
end

local function fits(inv, items)
  for _, item in ipairs(items) do
    if inv.get_insertable_count(item.name) < item.count then return false end
  end
  return true
end

local function harvest(target, renewable)
  local items = yield_of(target.prototype)
  if not renewable then target.destroy{raise_destroy = true} end
  return items
end

local function deliver(inv, items, entity)
  for _, item in ipairs(items) do
    local moved = inv.insert(item)
    -- The space was checked when the cycle started; only a hand insert in the
    -- meantime can overflow it, and then the rest lands on the ground.
    if moved < item.count then
      entity.surface.spill_item_stack{position = entity.position,
        stack = {name = item.name, count = item.count - moved}, force = entity.force}
    end
  end
end

local function try_start(rec)
  local core = rec.entity
  if not core.disabled_by_script then return end
  local failing = rec:check_conditions()
  if failing then
    rec:set_status(failing.status, {diode = failing.diode})
    rec:schedule(IDLE_POLL)
    return
  end
  local target = find_target(core.surface, core.position)
  if not target then
    rec:set_status("waiting_for_script")
    rec:schedule(IDLE_POLL)
    return
  end
  if not fits(rec:inventory("spoils"), yield_of(target.prototype)) then
    rec:set_status("full_output", {diode = "yellow"})
    rec:schedule(IDLE_POLL)
    return
  end
  rec.data.target = target
  if rec:start_cycle() then
    -- While the shell runs the engine's own status (working, low power, no
    -- power) is the truth; a custom "working" would hide a brownout.
    rec:set_status(nil)
    rec:unschedule()
  else
    rec.data.target = nil
    rec:schedule(IDLE_POLL)
  end
end

local function finish(rec)
  local target = rec.data.target
  rec.data.target = nil
  -- Another collector, a player or a biter may have taken it mid-cycle; the
  -- energy is spent either way, as it would be for the native type.
  if not (target and target.valid) then return end
  local items = harvest(target, rec.data.renewable)
  rec.data.harvested = (rec.data.harvested or 0) + 1
  deliver(rec:inventory("spoils"), items, rec.entity)
end

local handlers = {
  on_created = function(rec) rec:schedule(1) end,
  on_tick = function(rec) try_start(rec) end,
  on_cycle_finished = function(rec)
    finish(rec)
    try_start(rec)
  end,
}

-- Bench cells keep their tree so the collector works at steady state; the
-- search, yield and insert are still paid every cycle, and the poll column does
-- the same.
runtime.expose("creep_collector_renewable", function(entity, value)
  local rec = runtime.get(entity)
  if not rec then error("not a " .. NAME) end
  rec.data.renewable = value ~= false
end)

-- ---- poll-creep-collector: the Rampant pattern, for the third bench column ----
-- One shared 60-tick walk over every polled cell, as Rampant does: a consumer
-- EEI holds one unit of work (800 kJ, charged at 400 kW) and Lua deducts it
-- when it removes a target.

local POLL = "cl-creep-collector-poll"
local UNIT = 800000

local function poll_cells() return storage.cl.creep_poll end

scheduler.on_named(POLL, function(tick)
  local cells = poll_cells()
  if not cells then return end
  local live = 0
  for i, cell in pairs(cells) do
    local eei, chest = cell.eei, cell.chest
    if eei.valid and chest.valid then
      live = live + 1
      if eei.energy >= UNIT then
        local target = find_target(eei.surface, eei.position)
        if target then
          local inv = chest.get_inventory(defines.inventory.chest)
          if fits(inv, yield_of(target.prototype)) then
            eei.energy = eei.energy - UNIT
            deliver(inv, harvest(target, cell.renewable), chest)
            cell.harvested = (cell.harvested or 0) + 1
          end
        end
      end
    else
      cells[i] = nil
    end
  end
  if live > 0 then scheduler.schedule(POLL, tick + IDLE_POLL) end
end)

local function poll_add(eei, chest, renewable)
  local first = storage.cl.creep_poll == nil or next(storage.cl.creep_poll) == nil
  storage.cl.creep_poll = storage.cl.creep_poll or {}
  table.insert(storage.cl.creep_poll, {eei = eei, chest = chest, renewable = renewable == true})
  if first then scheduler.schedule(POLL, game.tick + IDLE_POLL) end
  return #storage.cl.creep_poll
end
runtime.expose("creep_poll_add", poll_add)

runtime.expose("creep_poll_cells", function() return storage.cl.creep_poll end)

-- ---- timed scenario, for the suite ---------------------------------------------
-- Cycles take 120 ticks, so the energy and idle fixtures are built at map
-- creation and observed while the server runs; the suite only reads them. Each
-- cell sits on its own electric network fed by one tertiary interface holding a
-- known charge, so the charge it loses is exactly what the cell drew.

local ORIGIN = {x = -2600, y = 2720}
local SPACING = 64
local CHARGE = 10e6
local DONE_AT = 720

local function sc() return storage.cl.creep_scenario end

local function prepare_area(surface)
  local area = {{ORIGIN.x - 16, ORIGIN.y - 16}, {ORIGIN.x + SPACING * 5 + 16, ORIGIN.y + 16}}
  surface.request_to_generate_chunks({ORIGIN.x + SPACING * 2.5, ORIGIN.y}, 6)
  surface.force_generate_chunk_requests()
  for _, e in pairs(surface.find_entities_filtered{area = area}) do
    if e.type ~= "character" then e.destroy() end
  end
  local tiles = {}
  for x = area[1][1], area[2][1] do
    for y = area[1][2], area[2][2] do tiles[#tiles + 1] = {name = "refined-concrete", position = {x, y}} end
  end
  surface.set_tiles(tiles)
end

local function network(surface, centre)
  local source = surface.create_entity{name = "hidden-electric-energy-interface",
    position = {centre.x - 6, centre.y - 6}, force = "player"}
  source.power_production = 0
  source.power_usage = 0
  source.energy = CHARGE
  surface.create_entity{name = "substation", position = {centre.x - 5, centre.y - 5}, force = "player"}
  return source
end

local function place(surface, slot, trees, rocks)
  local centre = {x = ORIGIN.x + slot * SPACING + 0.5, y = ORIGIN.y + 0.5}
  local source = network(surface, centre)
  local core = surface.create_entity{name = NAME, position = centre, force = "player"}
  -- Events raised during on_init are not delivered, so build the parts directly.
  local rec = runtime.lifecycle.materialise(core, nil, "scenario")
  for _, off in ipairs(trees or {}) do
    surface.create_entity{name = "tree-01", position = {centre.x + off[1], centre.y + off[2]}}
  end
  for _, off in ipairs(rocks or {}) do
    surface.create_entity{name = "big-rock", position = {centre.x + off[1], centre.y + off[2]}}
  end
  return rec, source, centre
end

local function count_targets(surface, centre)
  local n = 0
  for _, e in pairs(surface.find_entities_filtered{position = centre, radius = RANGE + 2, type = {"tree", "simple-entity"}}) do
    if is_target(e) then n = n + 1 end
  end
  return n
end

local function sample(s, key)
  local cell = s.cells[key]
  local core = cell.core
  return {
    tick = game.tick, energy = cell.source.energy, disabled = core.disabled_by_script,
    updatable = core.is_updatable, status = core.status, crafting = core.is_crafting(),
    products = core.products_finished, progress = core.crafting_progress, buffer = core.electric_buffer_size, stored = core.energy,
    spoils_wood = runtime.get(core):inventory("spoils").get_item_count("wood"),
    chest_wood = cell.chest and cell.chest.get_item_count("wood") or 0,
    held_wood = cell.inserter and cell.inserter.held_stack.valid_for_read and cell.inserter.held_stack.count or 0,
    custom = core.custom_status and core.custom_status.label[1] or nil,
    targets = count_targets(core.surface, cell.centre),
  }
end

scheduler.on_named("cl_creep_probe", function(tick)
  local s = sc()
  if not s then return end
  local at = tick - s.t0
  if at == 300 then
    s.full_mid = sample(s, "full")
    s.idle_mid = sample(s, "idle")
  elseif at == DONE_AT then
    for key in pairs(s.cells) do s.final[key] = sample(s, key) end
    local poll = storage.cl.creep_poll and storage.cl.creep_poll[s.poll_index]
    s.poll_final = poll and {harvested = poll.harvested or 0,
      wood = poll.chest.get_item_count("wood"), energy = poll.eei.energy,
      targets = count_targets(poll.eei.surface, poll.eei.position)}
    s.done_tick = tick
  end
end)

local function on_finished(event)
  local s = sc()
  if not s then return end
  for key, cell in pairs(s.cells) do
    if cell.unit == event.unit_number then
      local list = s.finished[key]
      list[#list + 1] = {tick = event.tick, energy = cell.source.energy, products = cell.core.products_finished,
        targets = count_targets(cell.core.surface, cell.centre)}
    end
  end
end
runtime.subscribe(defs.events[NAME].cycle_finished, on_finished)

local function arm()
  local surface = game.surfaces.nauvis
  prepare_area(surface)
  local s = {t0 = game.tick, cells = {}, finished = {}, final = {}}
  storage.cl.creep_scenario = s
  -- Three trees at distinct distances so the order is fixed.
  local layout = {
    trio = {trees = {{-3, 3}, {4, 3}, {0, -6}}, sink = true},
    idle = {},
    full = {trees = {{3, 3}}, fill = 200},
    rock = {rocks = {{4, -4}}},
  }
  local slot = 0
  for _, key in ipairs({"trio", "idle", "full", "rock"}) do
    local spec = layout[key]
    local rec, source, centre = place(surface, slot, spec.trees, spec.rocks)
    if spec.fill then rec:inventory("spoils").insert{name = "wood", count = spec.fill} end
    s.cells[key] = {unit = rec.unit_number, core = rec.entity, source = source, centre = centre, energy0 = source.energy}
    if spec.sink then
      -- A real inserter on the proxy, so the suite sees spoils leave through it;
      -- a burner one, so it takes nothing from the network being measured.
      local inserter = surface.create_entity{name = "burner-inserter", position = {centre.x + 3, centre.y},
        force = "player", direction = defines.direction.west}
      inserter.get_fuel_inventory().insert{name = "coal", count = 5}
      s.cells[key].inserter = inserter
      s.cells[key].chest = surface.create_entity{name = "wooden-chest", position = {centre.x + 4, centre.y}, force = "player"}
    end
    s.finished[key] = {}
    slot = slot + 1
  end

  local centre = {x = ORIGIN.x + slot * SPACING, y = ORIGIN.y}
  local source = network(surface, centre)
  local eei = surface.create_entity{name = "cl-creep-collector-poll-eei", position = centre, force = "player"}
  local chest = surface.create_entity{name = "steel-chest", position = {centre.x + 2.5, centre.y + 0.5}, force = "player"}
  for _, off in ipairs({{-3, 3}, {4, 3}, {0, -6}}) do
    surface.create_entity{name = "tree-01", position = {centre.x + off[1], centre.y + off[2]}}
  end
  s.poll_source = source
  s.poll_index = poll_add(eei, chest, false)

  scheduler.schedule("cl_creep_probe", s.t0 + 300)
  scheduler.schedule("cl_creep_probe", s.t0 + DONE_AT)
  runtime.fixtures.hold_until(s.t0 + DONE_AT)
end

runtime.init_hooks[#runtime.init_hooks + 1] = function()
  if not storage.cl.creep_scenario then arm() end
end

runtime.expose("creep_scenario", function() return storage.cl.creep_scenario end)

return handlers
