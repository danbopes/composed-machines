-- Run after the world has ticked for a while: status histograms, crafts,
-- fluid fill and composed-record census, so a starved, unpowered or unfed
-- layout is caught before benchmarking.
local s = game.surfaces[ARGS.surface or "bench"]
local status_name = {}
for k, v in pairs(defines.entity_status) do status_name[v] = k end
local out = {tick = game.tick, by_type = {}, names = {}}
for _, e in pairs(s.find_entities_filtered{}) do
  out.names[e.name] = (out.names[e.name] or 0) + 1
end
for _, t in ipairs({"furnace", "assembling-machine", "inserter", "reactor", "constant-combinator"}) do
  local hist, n = {}, 0
  for _, e in pairs(s.find_entities_filtered{type = t}) do
    local st = status_name[e.status] or tostring(e.status)
    if e.custom_status then st = st .. "/custom" end
    hist[st] = (hist[st] or 0) + 1
    n = n + 1
  end
  if n > 0 then out.by_type[t] = hist end
end
local products = 0
for _, e in pairs(s.find_entities_filtered{type = {"furnace", "assembling-machine"}}) do
  products = products + e.products_finished
end
out.products_finished = products
local tanks, filled = 0, 0
for _, e in pairs(s.find_entities_filtered{type = "storage-tank"}) do
  tanks = tanks + 1
  local f = e.get_fluid(1)
  if f and f.amount > 0 then filled = filled + 1 end
end
if tanks > 0 then out.tanks = {total = tanks, with_fluid = filled} end
local burning = 0
for _, e in pairs(s.find_entities_filtered{type = "reactor"}) do
  if e.burner and e.burner.currently_burning then burning = burning + 1 end
end
out.reactors_burning = burning
if remote.interfaces["component_lab"] then
  local ok, census = pcall(remote.call, "component_lab", "census")
  if ok then out.census = census end
end
rcon.print(helpers.table_to_json(out))
