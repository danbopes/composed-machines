-- cl-waste-heat-smelter: a crafter that heats a heat-pipe network while it works
-- (TEST-ENTITIES-2.md section 6). The shell crafts natively; the only Lua is one
-- add_heat per crafted event, so an idle or unpowered smelter costs no script.

local util = require("util")
local runtime = require("scripts.runtime")
local scheduler = require("scripts.scheduler")

local NAME = "cl-waste-heat-smelter"

local heat_joules = nil
local function heat_per_cycle(rec)
  heat_joules = heat_joules or util.parse_energy(rec:spec().emulation.heat_product)
  return heat_joules
end

local handlers = {
  on_cycle_finished = function(rec)
    rec.data.lost = (rec.data.lost or 0) + heat_per_cycle(rec) - rec:add_heat(heat_per_cycle(rec))
  end,
}

-- ---- timed fixture, for the suite ---------------------------------------------
-- The harness calls the suite after roughly 3700 ticks, so 50 cycles in a row
-- (9600 ticks) cannot finish first. Five smelters craft ten plates each instead:
-- the same 50 crafted events and 20 MJ, in a fifth of the time. Each has its own
-- heat pipe, so every rig is checked on its own. The suite reads the samples.

local PROBE = "cl_whs_probe"
local ORIGIN = {x = -2400, y = 1840}
local CYCLE_TICKS = 192
local RIGS = 5
local ORE = 10
local CRAFT_DONE = ORE * CYCLE_TICKS + 120
local IDLE_AT = CRAFT_DONE + 600

local function fx() return storage.cl.whs_fixture end

local function prepare(surface)
  local area = {{ORIGIN.x - 8, ORIGIN.y - 8}, {ORIGIN.x + 8 * (RIGS + 1) + 8, ORIGIN.y + 10}}
  surface.request_to_generate_chunks({ORIGIN.x + 24, ORIGIN.y}, 2)
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

local function powered_smelter(surface, x)
  local pos = {ORIGIN.x + x + 0.5, ORIGIN.y + 0.5}
  local core = surface.create_entity{name = NAME, position = pos, force = "player"}
  -- Events raised during on_init are not delivered, so build the parts directly.
  local rec = runtime.lifecycle.materialise(core, nil, "fixture")
  local eei = surface.create_entity{name = "electric-energy-interface", position = {pos[1] - 3.5, pos[2] - 3.5}, force = "player"}
  eei.power_production = 1e6
  eei.electric_buffer_size = 1e8
  surface.create_entity{name = "substation", position = {pos[1] - 3.5, pos[2] - 1.5}, force = "player"}
  local pipe = surface.create_entity{name = "heat-pipe", position = {pos[1], pos[2] + 2}, force = "player"}
  return {core = rec.entity, unit_number = rec.unit_number, pipe = pipe,
    pipe_before = pipe.temperature, interface_before = rec.parts["heat:heat"].temperature}
end

local function sample(s, key)
  local out = {tick = game.tick, rigs = {}}
  for i, rig in ipairs(s.rigs) do
    local rec = storage.cl.records[rig.unit_number]
    out.rigs[i] = {
      pipe = rig.pipe.temperature,
      interface = rec.parts["heat:heat"].temperature,
      products = rig.core.products_finished,
      plates = rig.core.get_inventory(defines.inventory.crafter_output).get_item_count("copper-plate"),
      status = rig.core.status,
      lost = rec.data.lost or 0,
    }
  end
  out.starved_status = s.starved.core.status
  out.starved_pipe = s.starved.pipe.temperature
  s.samples[key] = out
end

local actions = {
  [CYCLE_TICKS * 3 + 60] = function(s) sample(s, "mid") end,
  -- Plates left in the output make the engine report full_output, so the
  -- crafted plates are counted and then taken out, as an output inserter would.
  [CRAFT_DONE] = function(s)
    sample(s, "crafted")
    for _, rig in ipairs(s.rigs) do rig.core.get_inventory(defines.inventory.crafter_output).clear() end
  end,
  [IDLE_AT] = function(s) sample(s, "idle") end,
}

scheduler.on_named(PROBE, function(tick)
  local s = fx()
  if not s then return end
  local fn = actions[tick - s.t0]
  if fn then fn(s) end
end)

local function arm()
  local surface = game.surfaces.nauvis
  prepare(surface)
  local s = {t0 = game.tick, samples = {}, ore = ORE, rigs = {}}
  storage.cl.whs_fixture = s
  for i = 1, RIGS do
    local rig = powered_smelter(surface, 8 * (i - 1))
    rig.core.get_inventory(defines.inventory.crafter_input).insert{name = "copper-ore", count = ORE}
    s.rigs[i] = rig
  end
  s.starved = powered_smelter(surface, 8 * RIGS)
  for offset in pairs(actions) do scheduler.schedule(PROBE, s.t0 + offset) end
  runtime.fixtures.hold_until(s.t0 + IDLE_AT + 1)
end

runtime.init_hooks[#runtime.init_hooks + 1] = function()
  if not storage.cl.whs_fixture then arm() end
end

runtime.expose("whs_fixture", function()
  local s = fx()
  if not s then return nil end
  return s
end)

return handlers
