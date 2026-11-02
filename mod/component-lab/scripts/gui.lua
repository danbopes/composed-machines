-- A frame anchored to the core's own GUI, for parts the engine GUI cannot show
-- (hidden inventories, a hidden reactor's fuel slot). An entity script can build
-- its own content with on_gui(rec, player, frame); without one the frame lists
-- every hidden inventory as a live `inventory` element (2.1.7).

local defs = require("scripts.defs")

local gui = {}

local FRAME = "component_lab_parts"

local ANCHORS = {
  ["container"] = defines.relative_gui_type.container_gui,
  ["assembling-machine"] = defines.relative_gui_type.assembling_machine_gui,
  ["constant-combinator"] = defines.relative_gui_type.constant_combinator_gui,
}

function gui.anchor_for(core_type) return ANCHORS[core_type] end

function gui.close(player)
  local frame = player.gui.relative[FRAME]
  if frame then frame.destroy() end
end

function gui.default_content(rec, frame)
  local def = rec:def()
  for _, inv_spec in ipairs(rec:spec().inventories or {}) do
    if def.native_inventory ~= inv_spec.name and inv_spec.show_in_gui ~= false then
      frame.add{type = "label", caption = {"?", {"composed-inventory-name." .. inv_spec.name}, inv_spec.name}}
      local slots = frame.add{type = "inventory", slots_per_row = 10}
      slots.inventory = rec:inventory(inv_spec.name)
    end
  end
  local energy = rec.parts["energy:energy"]
  if energy and energy.burner then
    frame.add{type = "label", caption = {"cl-gui.fuel"}}
    local slots = frame.add{type = "inventory", slots_per_row = 10}
    slots.inventory = energy.burner.inventory
  end
end

--- Open the relative frame for rec. Returns the frame or nil when nothing to show.
function gui.open(player, rec, build)
  gui.close(player)
  local anchor = ANCHORS[rec:def().core_type]
  if not anchor then return nil end
  local frame = player.gui.relative.add{
    type = "frame",
    name = FRAME,
    direction = "vertical",
    caption = {"cl-gui.parts"},
    anchor = {gui = anchor, position = defines.relative_gui_position.right, names = {rec.name}},
    tags = {unit_number = rec.unit_number},
  }
  if build then build(rec, player, frame) else gui.default_content(rec, frame) end
  if #frame.children == 0 then
    frame.destroy()
    return nil
  end
  return frame
end

gui.FRAME = FRAME

return gui
