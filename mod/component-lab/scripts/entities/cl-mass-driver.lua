-- cl-mass-driver: charges, then fires a plate along its facing
-- (TEST-ENTITIES-2.md section 7). The shell's fixed recipe eats one plate per
-- 10 s cycle at 4 MW, so energy per shot is the engine's own arithmetic; the
-- only Lua is the cycle_finished handler standing in for the proposed
-- cycle_finished_trigger. Nothing is scheduled per instance.

local runtime = require("scripts.runtime")
local scheduler = require("scripts.scheduler")

local NAME = "cl-mass-driver"
local SLUG = "cl-mass-driver-slug"
local SPEED = 1
-- The slug leaves from the shell's edge, not its centre, so it is visible
-- from the first tick instead of being drawn under the machine.
local MUZZLE = 1.5

local d = defines.direction
local VECTORS = {
  [d.north] = {0, -1},
  [d.east] = {1, 0},
  [d.south] = {0, 1},
  [d.west] = {-1, 0},
}

local function launch(surface, force, source, position, direction, range)
  local v = VECTORS[direction] or VECTORS[d.north]
  local target = {x = position.x + v[1] * range, y = position.y + v[2] * range}
  surface.create_entity{
    name = SLUG,
    position = {position.x + v[1] * MUZZLE, position.y + v[2] * MUZZLE},
    target = target,
    speed = SPEED,
    force = force,
    source = source,
  }
  return target
end

local function fire(rec)
  local e = rec.entity
  local target = launch(e.surface, e.force, e, e.position, e.direction, rec.settings.range)
  rec.data.shots = (rec.data.shots or 0) + 1
  rec.data.last_shot = {tick = game.tick, x = target.x, y = target.y, direction = e.direction}
end

local function on_gui(rec, _, frame)
  local spec = rec:spec().settings[1]
  frame.add{type = "label", caption = {"cl-mass-driver.range", rec.settings.range}}
  frame.add{
    type = "slider", name = "cl_mass_driver_range",
    minimum_value = spec.min, maximum_value = spec.max, value = rec.settings.range, value_step = 1,
    tags = {unit_number = rec.unit_number},
  }
  local source = rec.entity.electric_buffer_size or 0
  frame.add{type = "label", caption = {"cl-mass-driver.charge",
    string.format("%.1f", rec.entity.energy / 1e6), string.format("%.0f", source / 1e6)}}
end

runtime.subscribe(defines.events.on_gui_value_changed, function(event)
  local element = event.element
  if not (element.valid and element.name == "cl_mass_driver_range") then return end
  local rec = storage.cl.records[element.tags.unit_number or 0]
  if not rec or rec.name ~= NAME then return end
  rec:set_setting("range", math.floor(element.slider_value + 0.5), event.player_index)
  local label = element.parent.children[1]
  if label and label.valid then label.caption = {"cl-mass-driver.range", rec.settings.range} end
end)

local handlers = {
  on_cycle_finished = fire,
  on_gui = on_gui,
}

runtime.expose("mass_driver_fire", function(unit_number)
  local rec = storage.cl.records[unit_number]
  if not rec or rec.name ~= NAME then error("not a " .. NAME .. ": " .. tostring(unit_number)) end
  fire(rec)
  return rec.data.last_shot
end)

-- ---- poll-mass-driver bench cell: Renai's dispatcher -------------------------
-- An EEI buffer and a chest per cannon, and one shared walk every 15 ticks
-- asking "buffer full and a plate present?". One walk over a list is what
-- Renai does (one on_nth_tick), so the column measures that pattern rather
-- than this library's per-record scheduler.

local POLL = "cl-mass-driver-poll"
local POLL_EVERY = 15
local POLL_RANGE = 20
local POLL_BUFFER = 40e6

scheduler.on_named(POLL, function(tick)
  local cells = storage.cl.mass_driver_poll
  if not cells then return end
  local n, kept = #cells, 0
  for i = 1, n do
    local cell = cells[i]
    local eei, chest = cell.eei, cell.chest
    if eei.valid and chest.valid then
      kept = kept + 1
      cells[kept] = cell
      if eei.energy >= POLL_BUFFER - 1 and chest.remove_item{name = "iron-plate", count = 1} > 0 then
        eei.energy = 0
        launch(chest.surface, chest.force, chest, chest.position, d.north, POLL_RANGE)
        cell.shots = (cell.shots or 0) + 1
      end
    end
  end
  for i = n, kept + 1, -1 do cells[i] = nil end
  if kept > 0 then scheduler.schedule(POLL, tick + POLL_EVERY) end
end)

runtime.expose("mass_driver_poll_add", function(eei, chest)
  local cells = storage.cl.mass_driver_poll
  if not cells then
    cells = {}
    storage.cl.mass_driver_poll = cells
  end
  cells[#cells + 1] = {eei = eei, chest = chest}
  if #cells == 1 then scheduler.schedule(POLL, game.tick + POLL_EVERY) end
  return #cells
end)

runtime.expose("mass_driver_poll_shots", function()
  local total, cells = 0, storage.cl.mass_driver_poll or {}
  for _, cell in ipairs(cells) do total = total + (cell.shots or 0) end
  return {cells = #cells, shots = total}
end)

-- ---- timed scenario, for the suite --------------------------------------------
-- A cycle takes 600 ticks and the suite runs inside one, so the drivers that
-- must actually fire are built at map creation and watched every tick; the
-- suite only reads what was recorded.

local WATCH = "cl_md_watch"
local PROBE = "cl_md_probe"
local ORIGIN = {x = -2000, y = 1600}
local SPACING = 48
local DONE_AT = 720

local function sc() return storage.cl.md_scenario end

local function prepare_area(surface)
  local area = {{ORIGIN.x - 40, ORIGIN.y - 40}, {ORIGIN.x + SPACING * 6 + 40, ORIGIN.y + 40}}
  for x = area[1][1], area[2][1], 32 do
    surface.request_to_generate_chunks({x, ORIGIN.y}, 2)
  end
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

local function place(surface, slot, opts)
  local x, y = ORIGIN.x + slot * SPACING + 0.5, ORIGIN.y + 0.5
  local core = surface.create_entity{name = NAME, position = {x, y}, direction = opts.direction, force = "player"}
  -- Events raised during on_init are not delivered, so build the record directly.
  local rec = runtime.lifecycle.materialise(core, nil, "scenario")
  if opts.powered then
    surface.create_entity{name = "substation", position = {x + 2.5, y + 3.5}, force = "player"}
    local eei = surface.create_entity{name = "electric-energy-interface", position = {x + 2.5, y + 6.5}, force = "player"}
    eei.electric_buffer_size = 1e10
    eei.power_production = 1e9
    eei.power_usage = 0
  end
  if opts.energy then core.energy = opts.energy == "full" and core.electric_buffer_size or opts.energy end
  if opts.range then rec:set_setting("range", opts.range) end
  if opts.plates then core.insert{name = "iron-plate", count = opts.plates} end
  return rec
end

-- A lane along the facing only, so a neighbour's slug (or the clone's, five
-- tiles beside its source) is never counted as this driver's.
local function slug_area(rec)
  local e = rec.entity
  local p, v = e.position, VECTORS[e.direction] or VECTORS[d.north]
  local along, across = 40, 2
  local hx = math.abs(v[1]) * along + math.abs(v[2]) * across
  local hy = math.abs(v[2]) * along + math.abs(v[1]) * across
  return {{p.x - hx, p.y - hy}, {p.x + hx, p.y + hy}}
end

local function input_count(entity)
  return entity.get_inventory(defines.inventory.crafter_input).get_item_count("iron-plate")
end

scheduler.on_named(WATCH, function(tick)
  local s = sc()
  if not s then return end
  for key, rec in pairs(s.recs) do
    if rec.entity.valid then
      local w = s.watch[key]
      local slugs = rec.entity.surface.find_entities_filtered{name = SLUG, area = slug_area(rec)}
      if #slugs > 0 then
        local pos = slugs[1].position
        if not w.first then w.first = {tick = tick, x = pos.x, y = pos.y} end
        w.last = {tick = tick, x = pos.x, y = pos.y}
        if #slugs > w.max then w.max = #slugs end
      end
    end
  end
  if tick - s.t0 < DONE_AT then scheduler.schedule(WATCH, tick + 1) end
end)

local actions = {}

actions[300] = function(s)
  local powered = s.recs.powered.entity
  s.mid = {
    input = input_count(powered),
    crafting = powered.is_crafting(),
    progress = powered.crafting_progress,
    status = powered.status,
    energy = powered.energy,
    buffer_energy = s.recs.buffer.entity.energy,
  }

  local victim = s.recs.mine
  local inv = game.create_inventory(8)
  local mined_progress = victim.entity.crafting_progress
  local ok = runtime.mine(victim.entity, inv)
  s.mined = {ok = ok, progress = mined_progress, plates = inv.get_item_count("iron-plate"),
    drivers = inv.get_item_count(NAME)}
  inv.destroy()
  s.recs.mine = nil

  local source = s.recs.clone.entity
  local surface = source.surface
  surface.clone_entities{entities = {source}, destination_offset = {-5, 0}}
  local copy = surface.find_entity(NAME, {source.position.x - 5, source.position.y})
  local crec = copy and storage.cl.records[copy.unit_number]
  s.clone = {
    source_progress = source.crafting_progress,
    copy_progress = copy and copy.crafting_progress,
    copy_unit = copy and copy.unit_number,
    copy_direction = copy and copy.direction,
    copy_range = crec and crec.settings.range,
  }
  if crec then
    s.recs.copy = crec
    s.watch.copy = {max = 0}
  end
end

actions[DONE_AT] = function(s)
  s.final = {}
  for key, rec in pairs(s.recs) do
    local e = rec.entity
    if e.valid then
      s.final[key] = {
        status = e.status,
        input = input_count(e),
        energy = e.energy,
        shots = rec.data.shots or 0,
        last_shot = rec.data.last_shot,
        products = e.products_finished,
        position = e.position,
        buffer_size = e.electric_buffer_size,
      }
    end
  end
  s.done_tick = game.tick
end

scheduler.on_named(PROBE, function(tick)
  local s = sc()
  if not s then return end
  local fn = actions[tick - s.t0]
  if fn then fn(s) end
end)

local function arm()
  local surface = game.surfaces.nauvis
  prepare_area(surface)
  local s = {t0 = game.tick, recs = {}, watch = {}, units = {}}
  storage.cl.md_scenario = s
  local specs = {
    powered = {slot = 0, direction = d.east, powered = true, energy = "full", plates = 1},
    buffer = {slot = 1, direction = d.east, energy = 40e6, plates = 1},
    idle = {slot = 2, powered = true},
    range = {slot = 3, powered = true, range = 8, plates = 1},
    mine = {slot = 4, powered = true, plates = 1},
    clone = {slot = 5, direction = d.south, powered = true, range = 30, plates = 1},
  }
  for key, opts in pairs(specs) do
    local rec = place(surface, opts.slot, opts)
    s.recs[key] = rec
    s.units[key] = rec.unit_number
    s.watch[key] = {max = 0}
  end
  s.buffer_start = s.recs.buffer.entity.energy
  s.buffer_size = s.recs.buffer.entity.electric_buffer_size
  for offset in pairs(actions) do scheduler.schedule(PROBE, s.t0 + offset) end
  scheduler.schedule(WATCH, s.t0 + 1)
  runtime.fixtures.hold_until(s.t0 + DONE_AT)
end

runtime.init_hooks[#runtime.init_hooks + 1] = function()
  if not storage.cl.md_scenario then arm() end
end

runtime.expose("md_scenario", function()
  local s = storage.cl.md_scenario
  if not s then return nil end
  -- Records hold functions via their metatable; the suite needs plain data.
  return {t0 = s.t0, units = s.units, watch = s.watch, mid = s.mid, mined = s.mined, clone = s.clone,
    final = s.final, done_tick = s.done_tick, buffer_start = s.buffer_start, buffer_size = s.buffer_size}
end)

return handlers
