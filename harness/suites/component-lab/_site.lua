-- Shared test sites for the component-lab suites.
--
-- Every suite builds on its own row of the map. A site is generated, cleared of
-- trees, rocks and nests and paved before use, because fresh maps get new seeds
-- and water or a tree under a site silently breaks build_blueprint and revive.
-- After each test the whole stretch of the row that test touched is cleared
-- again (cores first, with raise_destroy, so the runtime drops their records),
-- so no test leaves entities behind for a later one to trip over. Clones and
-- blueprint pastes land a few tiles past their site, which the margins cover.
--
-- Map fixtures armed at on_init live away from every row; zz-leftovers.lua
-- checks that the record count is back to the fixture-only baseline.

local M = {}

local CL = "component_lab"
-- Clones and blueprint pastes in the suites land at most 8 tiles off their site.
local MARGIN_X, MARGIN_Y = 16, 6

local rows = {}
local touched = {}
local temp_surfaces = {}

local core_names = {}
local function is_core(name)
  local known = core_names[name]
  if known == nil then
    known = remote.call(CL, "shape", name) ~= nil
    core_names[name] = known
  end
  return known
end

-- area = nil scans the whole surface: a huge explicit area is not a shortcut,
-- the engine walks every chunk coordinate inside it (about 30 s for +-1e6).
local function clear(surface, area)
  local found = surface.find_entities_filtered{area = area}
  for _, e in pairs(found) do
    if e.valid and e.type ~= "character" and is_core(e.name) then e.destroy{raise_destroy = true} end
  end
  for _, e in pairs(found) do
    if e.valid and e.type ~= "character" then e.destroy() end
  end
end

local Row = {}
Row.__index = Row

--- A row of sites: x0 is the first site's x, y the row's centre line, half the
--- paved half-height, tile what to pave with.
function M.row(opts)
  local row = setmetatable({
    x0 = opts.x, cursor = opts.x, y = opts.y, half = opts.half or 6,
    tile = opts.tile or "refined-concrete", surface = opts.surface or "nauvis",
  }, Row)
  rows[#rows + 1] = row
  return row
end

--- Claim the next `width` tiles of the row. Returns surface, {x + 0.5, y + 0.5}.
function Row:next(width)
  width = width or 10
  local s = game.surfaces[self.surface]
  local x = self.cursor
  self.cursor = x + width
  s.request_to_generate_chunks({x, self.y}, 2)
  s.force_generate_chunk_requests()
  local area = {{x - 3, self.y - self.half}, {x + width + 3, self.y + self.half}}
  clear(s, area)
  local tiles = {}
  for tx = area[1][1], area[2][1] do
    for ty = area[1][2], area[2][2] do tiles[#tiles + 1] = {name = self.tile, position = {tx, ty}} end
  end
  s.set_tiles(tiles, true, true)
  touched[self] = true
  return s, {x + 0.5, self.y + 0.5}
end

function Row:area()
  return {{self.x0 - MARGIN_X, self.y - self.half - MARGIN_Y}, {self.cursor + MARGIN_X, self.y + self.half + MARGIN_Y}}
end

--- A scratch surface, emptied (and deleted) after the test.
function M.temp_surface(name)
  local s = game.surfaces[name] or game.create_surface(name)
  temp_surfaces[name] = true
  return s
end

function M.clean()
  for row in pairs(touched) do
    local s = game.surfaces[row.surface]
    if s then clear(s, row:area()) end
  end
  touched = {}
  for name in pairs(temp_surfaces) do
    local s = game.surfaces[name]
    if s then
      clear(s, nil)
      game.delete_surface(s)
    end
  end
  temp_surfaces = {}
end

local baseline = nil
function M.baseline() return baseline end

before_each(function()
  if baseline == nil then baseline = remote.call(CL, "census") end
end)
after_each(M.clean)

return M
