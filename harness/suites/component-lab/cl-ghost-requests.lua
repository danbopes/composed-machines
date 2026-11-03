-- Ghost item requests (insert plans) on vanilla entities. Review item C16: the
-- claim that every inventory an entity owns is addressable by the existing
-- BlueprintInsertPlan. Robot delivery takes real ticks, so the mod arms a map
-- fixture at on_init (scripts/ghost-requests.lua) and these tests read it.

local CL = "component_lab"
local function cl(fn, ...) return remote.call(CL, fn, ...) end

local function fixture()
  local fx = cl("ghost_requests_fixture")
  assert_not_nil(fx, "fixture armed at on_init (run with --fresh)")
  return fx
end

local function requested(list, name)
  for _, r in pairs(list or {}) do
    if r.name == name then return r.count end
  end
  return 0
end

local function planned(plan, name, inventory)
  local n = 0
  for _, p in pairs(plan or {}) do
    if p.id.name == name then
      for _, at in pairs(p.items.in_inventory or {}) do
        if at.inventory == inventory then n = n + (at.count or 1) end
      end
    end
  end
  return n
end

test("ghost-requests: a script revive does not fulfil an insert plan; it leaves a proxy for robots", function()
  local fx = fixture()
  local r = fx.at_revive
  assert_eq(requested(r.chest_requests, "iron-plate"), fx.chest_plates, "container ghost requests its plates")
  assert_eq(requested(r.tower_requests, "coal"), fx.tower_coal, "reactor ghost requests its fuel")
  assert_eq(r.chest_contents, 0, "revived container is empty")
  assert_eq(r.tower_fuel, 0, "revived reactor has no fuel")
  assert_not_nil(r.chest_proxy, "container revive left an item-request-proxy")
  assert_not_nil(r.tower_proxy, "reactor revive left an item-request-proxy")
  assert_true(r.chest_proxy.target and r.tower_proxy.target, "each proxy targets its revived entity")
  assert_eq(planned(r.chest_proxy.plan, "iron-plate", defines.inventory.chest), fx.chest_plates,
    "proxy carries the plan into the chest inventory")
  assert_eq(planned(r.tower_proxy.plan, "coal", defines.inventory.fuel), fx.tower_coal,
    "proxy carries the plan into the fuel inventory")
end)

test("ghost-requests: construction robots deliver an insert plan to a container and to a burner reactor's fuel", function()
  local fx = fixture()
  local s = fx.snap
  assert_not_nil(s, string.format("fixture incomplete (needs tick %d): the server did not run long enough", fx.snap_at))
  assert_eq(s.chest_contents, fx.chest_plates, "plates delivered into the container")
  assert_eq(s.tower_fuel, fx.tower_coal, "coal delivered into the reactor's fuel inventory")
  assert_true(not s.chest_proxy_left and not s.tower_proxy_left, "both proxies fulfilled and gone")
  assert_eq(s.store_plates, 50 - fx.chest_plates, "plates came from the logistic network")
  assert_eq(s.store_coal, 20 - fx.tower_coal, "coal came from the logistic network")
end)
