-- Ghost item requests on vanilla entities, delivered by construction robots.
-- Evidence for the claim that an insert plan can address any inventory an
-- entity owns: a container's chest inventory and a burner reactor's fuel
-- inventory. Robot delivery takes real ticks, so this is a map fixture armed at
-- on_init and snapshotted later; the suite (cl-ghost-requests.lua) reads it.

local runtime = require("scripts.runtime")
local scheduler = require("scripts.scheduler")

local ORIGIN = {x = 2400.5, y = 2400.5}
local SNAP_AT = 900
local SNAP = "cl_ghost_requests_snap"
local CHEST_PLATES, TOWER_COAL = 20, 5

local function fixture() return storage.cl.ghost_requests end

local function arm()
  local s = game.surfaces.nauvis
  s.request_to_generate_chunks(ORIGIN, 1)
  s.force_generate_chunk_requests()
  local area = {{ORIGIN.x - 12, ORIGIN.y - 12}, {ORIGIN.x + 12, ORIGIN.y + 12}}
  local tiles = {}
  for x = area[1][1], area[2][1] do
    for y = area[1][2], area[2][2] do tiles[#tiles + 1] = {name = "refined-concrete", position = {x, y}} end
  end
  s.set_tiles(tiles, true, true)
  for _, e in pairs(s.find_entities_filtered{area = area}) do
    if e.valid and e.type ~= "character" then e.destroy() end
  end
  local function put(name, dx, dy)
    return s.create_entity{name = name, position = {ORIGIN.x + dx, ORIGIN.y + dy}, force = "player"}
  end
  put("electric-energy-interface", -4, 0)
  put("medium-electric-pole", -2, -2)
  local roboport = put("roboport", 0, 0)
  roboport.get_inventory(defines.inventory.roboport_robot).insert{name = "construction-robot", count = 10}
  local store = put("storage-chest", 3, -3)
  store.insert{name = "iron-plate", count = 50}
  store.insert{name = "coal", count = 20}

  local function ghost(inner, dx, dy, item, inventory, count)
    local g = s.create_entity{name = "entity-ghost", inner_name = inner,
      position = {ORIGIN.x + dx, ORIGIN.y + dy}, force = "player"}
    g.insert_plan = {{id = {name = item}, items = {in_inventory = {{inventory = inventory, stack = 0, count = count}}}}}
    local requests = g.item_requests
    local _, entity, proxy = g.revive{raise_revive = true, return_item_request_proxy = true}
    return entity, requests, proxy
  end
  local chest, chest_requests, chest_proxy = ghost("iron-chest", 5, 3, "iron-plate", defines.inventory.chest,
    CHEST_PLATES)
  local tower, tower_requests, tower_proxy = ghost("heating-tower", -5, 6, "coal", defines.inventory.fuel,
    TOWER_COAL)
  -- A burning tower would eat the delivery before the snapshot; disabled, the
  -- coal stays in the fuel slot where the plan put it.
  tower.disabled_by_script = true

  storage.cl.ghost_requests = {
    tick = game.tick, snap_at = game.tick + SNAP_AT, chest = chest, tower = tower, store = store,
    chest_plates = CHEST_PLATES, tower_coal = TOWER_COAL,
    at_revive = {
      chest_requests = chest_requests, tower_requests = tower_requests,
      chest_contents = chest.get_item_count("iron-plate"),
      tower_fuel = tower.get_fuel_inventory().get_item_count("coal"),
      chest_proxy = chest_proxy and chest_proxy.valid and {target = chest_proxy.proxy_target == chest,
        plan = chest_proxy.insert_plan} or nil,
      tower_proxy = tower_proxy and tower_proxy.valid and {target = tower_proxy.proxy_target == tower,
        plan = tower_proxy.insert_plan} or nil,
    },
  }
  scheduler.schedule(SNAP, game.tick + SNAP_AT)
  runtime.fixtures.hold_until(game.tick + SNAP_AT)
end

scheduler.on_named(SNAP, function(tick)
  local fx = fixture()
  if not fx then return end
  fx.snap = {
    tick = tick,
    chest_contents = fx.chest.get_item_count("iron-plate"),
    tower_fuel = fx.tower.get_fuel_inventory().get_item_count("coal"),
    chest_proxy_left = fx.chest.item_request_proxy ~= nil,
    tower_proxy_left = fx.tower.item_request_proxy ~= nil,
    store_plates = fx.store.get_item_count("iron-plate"),
    store_coal = fx.store.get_item_count("coal"),
  }
end)

runtime.init_hooks[#runtime.init_hooks + 1] = function()
  if not fixture() then arm() end
end

runtime.expose("ghost_requests_fixture", function()
  local fx = fixture()
  return fx and {tick = fx.tick, snap_at = fx.snap_at, chest_plates = fx.chest_plates, tower_coal = fx.tower_coal,
    at_revive = fx.at_revive, snap = fx.snap}
end)
