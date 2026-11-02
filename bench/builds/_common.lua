-- Prepended to every build file by make_save.py, after the ARGS table.
-- Everything goes on a dedicated flat surface so the baseline is not mixed
-- with nauvis terrain, resources or biters.

local SURFACE = ARGS.surface or "bench"
local BLOCK = 18          -- substation supply area is 18x18, wire reach 18

local function quiet_world()
  game.map_settings.enemy_expansion.enabled = false
  game.map_settings.enemy_evolution.enabled = false
  game.map_settings.pollution.enabled = ARGS.pollution == true
  for _, s in pairs(game.surfaces) do
    for _, e in pairs(s.find_entities_filtered{force = "enemy"}) do e.destroy() end
  end
end

local function make_surface(radius_tiles)
  local s = game.surfaces[SURFACE]
  -- delete_surface takes effect on the next tick, so the name would still be
  -- taken by the create below; move the old surface out of the way first.
  if s then
    s.name = SURFACE .. "-old-" .. game.tick .. "-" .. s.index
    game.delete_surface(s)
  end
  s = game.create_surface(SURFACE, {
    default_enable_all_autoplace_controls = false,
    autoplace_settings = {
      tile = {treat_missing_as_default = false, settings = {["lab-dark-1"] = {}}},
      entity = {treat_missing_as_default = false, settings = {}},
      decorative = {treat_missing_as_default = false, settings = {}},
    },
    cliff_settings = {richness = 0},
    no_enemies_mode = true,
    starting_area = "none",
  })
  s.always_day = true
  local chunks = math.ceil(radius_tiles / 32) + 1
  s.request_to_generate_chunks({0, 0}, chunks)
  s.force_generate_chunk_requests()
  -- Autoplace with an empty tile set can still leave water/out-of-map; pave it.
  local tiles = {}
  local r = chunks * 32
  for x = -r, r - 1 do
    for y = -r, r - 1 do tiles[#tiles + 1] = {name = "lab-dark-1", position = {x, y}} end
  end
  s.set_tiles(tiles, false)
  return s
end

local function must(s, spec)
  spec.force = spec.force or "player"
  local e = s.create_entity(spec)
  if not e then error("create_entity failed: " .. spec.name .. " at " .. serpent.line(spec.position)) end
  return e
end

-- Layout: blocks of 18x18 centred on a substation (supply area 18x18, wire
-- reach 18, so neighbouring substations auto-connect). Each side of the centre
-- column holds cells of w x h tiles in the 7-tile band x -9..-2 / x 2..9, rows
-- of h from y -9. For the original 7x3 cell that is 12 cells per block.
local function plan(n_cells, w, h)
  w, h = w or 7, h or 3
  local per_side, rows = math.floor(7 / w), math.floor(18 / h)
  assert(per_side >= 1 and rows >= 1, "cell too large for a block")
  local blocks = math.ceil(n_cells / (2 * per_side * rows))
  local side = math.ceil(math.sqrt(math.max(blocks, 1)))
  local origin = -(side * BLOCK) / 2
  local slots, subs = {}, {}
  local b = 0
  for by = 0, side - 1 do
    for bx = 0, side - 1 do
      if b >= blocks then break end
      b = b + 1
      local cx = origin + bx * BLOCK + BLOCK / 2
      local cy = origin + by * BLOCK + BLOCK / 2
      subs[#subs + 1] = {cx, cy}
      for row = 0, rows - 1 do
        for _, base in ipairs({cx - 9, cx + 2}) do
          for k = 0, per_side - 1 do
            if #slots < n_cells then slots[#slots + 1] = {left = base + k * w, top = cy - 9 + row * h} end
          end
        end
      end
    end
  end
  return slots, subs, side * BLOCK / 2
end

local function power(s, subs)
  for _, p in ipairs(subs) do must(s, {name = "substation", position = p}) end
  -- A few interfaces, each beside a substation so it lands in the one network.
  local count = math.min(ARGS.eei or 4, #subs)
  for i = 1, count do
    local p = subs[math.floor((i - 1) * #subs / count) + 1]
    local e = must(s, {name = "electric-energy-interface", position = {p[1], p[2] - 2}})
    e.electric_buffer_size = 1e12
    e.power_production = 1e10
    e.power_usage = 0
  end
  -- Report network count so a broken layout cannot pass silently.
  local nets = {}
  for _, p in pairs(s.find_entities_filtered{type = "electric-pole"}) do
    nets[p.electric_network_id or -1] = true
  end
  local n = 0
  for _ in pairs(nets) do n = n + 1 end
  return n
end

-- An electric-energy-interface that only consumes, e.g. a native stand-in for
-- an always-on electric updatable. watts -> J/tick.
local function eei_consumer(s, pos, watts)
  local e = must(s, {name = "electric-energy-interface", position = pos})
  e.power_production = 0
  e.power_usage = watts / 60
  e.electric_buffer_size = 2 * watts / 60
  return e
end

local function infinity_pipe(s, pos, fluid, amount)
  local p = must(s, {name = "infinity-pipe", position = pos})
  p.set_infinity_pipe_filter(fluid and {name = fluid, percentage = amount or 1, mode = "exactly"} or nil)
  return p
end

-- Inserter at pos that moves items from x-1 to x+1 (or reverse).
local function inserter(s, name, pos, eastward)
  local e = must(s, {name = name, position = pos, direction = eastward == false and defines.direction.east or defines.direction.west})
  return e
end

local function infinity_source(chest, items)
  for i, item in ipairs(items) do
    chest.set_infinity_container_filter(i, {name = item, count = prototypes.item[item].stack_size, mode = "exactly"})
  end
end

local function infinity_sink(chest)
  chest.remove_unfiltered_items = true
end

-- source -> inserter -> machine -> inserter -> sink, laid out west to east on
-- the slot's middle row. size is the machine footprint (2 or 3).
local function cell(s, slot, opts)
  local y = slot.top + 1.5
  local L = slot.left
  local src = must(s, {name = "infinity-chest", position = {L + 0.5, y}})
  local i1 = must(s, {name = opts.inserter, position = {L + 1.5, y}, direction = opts.dir})
  local m
  if opts.size == 3 then
    m = must(s, {name = opts.machine, position = {L + 3.5, y}})
  else
    m = must(s, {name = opts.machine, position = {L + 3, slot.top + 2}})
  end
  local xo = L + 1 + opts.size + 0.5
  local i2 = must(s, {name = opts.inserter, position = {xo, y}, direction = opts.dir})
  local dst = must(s, {name = "infinity-chest", position = {xo + 1, y}})
  if opts.recipe then m.set_recipe(opts.recipe) end
  if opts.inputs then infinity_source(src, opts.inputs) end
  infinity_sink(dst)
  return m
end

local function report(t)
  rcon.print(helpers.table_to_json(t))
end

BENCH = {
  quiet_world = quiet_world, make_surface = make_surface, plan = plan, power = power,
  cell = cell, must = must, report = report, eei_consumer = eei_consumer,
  infinity_pipe = infinity_pipe, inserter = inserter, infinity_source = infinity_source,
  infinity_sink = infinity_sink,
  -- Measured on 2.1.24: direction=west picks up from the west and drops east.
  EAST_FLOW = defines.direction.west,
}
