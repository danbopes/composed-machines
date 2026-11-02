-- Added to a save's isolated mod set for one --benchmark tick; on_init fires
-- because the mod is new to the save. Nothing is ever saved.
local function census()
  local out = {tick = game.tick, surfaces = {}, totals = {}, types = {}}
  for name, proto in pairs(prototypes.entity) do out.types[name] = proto.type end
  for _, s in pairs(game.surfaces) do
    local per = {}
    for name in pairs(prototypes.entity) do
      local n = s.count_entities_filtered{name = name}
      if n > 0 then
        per[name] = n
        out.totals[name] = (out.totals[name] or 0) + n
      end
    end
    out.surfaces[s.name] = per
  end
  for name in pairs(out.types) do
    if not out.totals[name] then out.types[name] = nil end
  end
  helpers.write_file("bench-census.json", helpers.table_to_json(out), false)
end

script.on_init(census)
