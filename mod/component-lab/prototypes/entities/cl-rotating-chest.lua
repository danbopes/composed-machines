-- cl-rotating-chest: a storehouse that rotates (S0). TEST-ENTITIES-2.md section 4.
--
-- A passive assembler shell (the only cheap native type that rotates and has a
-- 6x3 box) over one hidden 240-slot container. A proxy sits on every edge tile
-- of the footprint, because an inserter reaches exactly the tile in front of it
-- and the composed type would accept an inserter on any side.

local component = require("lib.component")

local W, H = 6, 3

local function edge_offsets()
  local out = {}
  for ix = 0, W - 1 do
    for iy = 0, H - 1 do
      if ix == 0 or ix == W - 1 or iy == 0 or iy == H - 1 then
        out[#out + 1] = {ix - (W - 1) / 2, iy - (H - 1) / 2}
      end
    end
  end
  return out
end

-- The storehouse is drawn as a grid of steel chests, one per tile, so its
-- footprint reads at a glance in both orientations.
local function chest_grid(cols, rows)
  local layers = {}
  for ix = 0, cols - 1 do
    for iy = 0, rows - 1 do
      local dx, dy = ix - (cols - 1) / 2, iy - (rows - 1) / 2
      layers[#layers + 1] = {
        filename = "__base__/graphics/entity/steel-chest/steel-chest.png",
        priority = "extra-high", width = 64, height = 80, scale = 0.5,
        shift = {dx - 0.25 / 32, dy - 0.5 / 32},
      }
    end
  end
  layers[#layers + 1] = {
    filename = "__base__/graphics/entity/steel-chest/steel-chest-shadow.png",
    priority = "extra-high", width = 110, height = 46, scale = 0.5 * math.max(cols, rows) / 2,
    shift = {(cols - 1) / 2 + 0.4, (rows - 1) / 2 + 0.2}, draw_as_shadow = true,
  }
  return {layers = layers}
end

local wide, tall = chest_grid(W, H), chest_grid(H, W)

component.define{
  name = "cl-rotating-chest",
  direction_count = 4,
  inventories = {
    {name = "main", role = "storage", size = 240, with_bar = true, proxy_offsets = edge_offsets()},
  },
  emulation = {
    like = "assembling-machine-2",
    core = "assembling-machine",
    prototype = {
      icon = "__base__/graphics/icons/steel-chest.png",
      collision_box = {{-2.9, -1.4}, {2.9, 1.4}},
      selection_box = {{-3, -1.5}, {3, 1.5}},
      graphics_set = {animation = {north = wide, east = tall, south = wide, west = tall}},
      corpse = "medium-remnants",
      open_sound = {filename = "__base__/sound/metallic-chest-open.ogg", volume = 0.43},
      close_sound = {filename = "__base__/sound/metallic-chest-close.ogg", volume = 0.43},
      -- The deep-copied assembler would otherwise keep its mirrored graphics,
      -- its circuit connector and its icon list.
      icons = component.CLEAR,
      graphics_set_flipped = component.CLEAR,
      circuit_connector = component.CLEAR,
      circuit_connector_flipped = component.CLEAR,
      icon_draw_specification = component.CLEAR,
      icons_positioning = component.CLEAR,
      use_mirroring = false,
    },
    item = {icon = "__base__/graphics/icons/steel-chest.png", icons = component.CLEAR},
  },
}
