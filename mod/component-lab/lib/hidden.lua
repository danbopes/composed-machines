-- Boilerplate shared by every hidden part prototype. A part must be invisible to
-- the player (no selection, no map dot, no blueprint, no deconstruction), must not
-- block building (empty collision layers) and must never leave a ghost, because
-- the core owns its whole lifecycle.

local hidden = {}

hidden.empty_sprite = {filename = "__core__/graphics/empty.png", size = 1}

hidden.empty_sprite4 = {
  north = hidden.empty_sprite,
  east = hidden.empty_sprite,
  south = hidden.empty_sprite,
  west = hidden.empty_sprite,
}

hidden.flags = {
  "not-blueprintable",
  "not-deconstructable",
  "placeable-off-grid",
  "not-on-map",
  "not-repairable",
  "not-flammable",
  "no-copy-paste",
  "not-in-kill-statistics",
  "not-upgradable",
  "not-selectable-in-game",
}

-- Values the caller passes win, so a part can opt back into e.g. a collision box
-- (proxies need one for inserters to find them).
function hidden.entity(fields)
  local proto = {
    flags = table.deepcopy(hidden.flags),
    hidden = true,
    hidden_in_factoriopedia = true,
    collision_mask = {layers = {}},
    selectable_in_game = false,
    create_ghost_on_death = false,
    allow_copy_paste = false,
    is_military_target = false,
    alert_when_damaged = false,
    max_health = 1000,
    icon = "__base__/graphics/icons/wooden-chest.png",
    icon_size = 64,
  }
  for k, v in pairs(fields) do proto[k] = v end
  return proto
end

function hidden.container(name, icon, inventory)
  return hidden.entity{
    type = "container",
    name = name,
    icon = icon,
    inventory_size = inventory.size,
    inventory_type = (inventory.filters or inventory.filters_editable) and "with_filters_and_bar" or "with_bar",
    -- The proxy is the only door: a stray inserter must not reach the part directly.
    flags = (function()
      local f = table.deepcopy(hidden.flags)
      f[#f + 1] = "no-automated-item-removal"
      f[#f + 1] = "no-automated-item-insertion"
      return f
    end)(),
    picture = hidden.empty_sprite,
  }
end

function hidden.proxy(name, icon)
  return hidden.entity{
    type = "proxy-container",
    name = name,
    icon = icon,
    -- Inserters pick drop and pickup targets by collision box, not by mask.
    collision_box = {{-0.35, -0.35}, {0.35, 0.35}},
    picture = hidden.empty_sprite,
    draw_inventory_content = false,
  }
end

function hidden.eei(name, icon, energy_source, energy_usage)
  local source = table.deepcopy(energy_source)
  source.render_no_power_icon = false
  source.render_no_network_icon = false
  return hidden.entity{
    type = "electric-energy-interface",
    name = name,
    icon = icon,
    energy_source = source,
    energy_usage = energy_usage,
    gui_mode = "none",
    picture = hidden.empty_sprite,
  }
end

function hidden.reactor(name, icon, energy_source, energy_usage)
  local source = table.deepcopy(energy_source)
  source.render_no_power_icon = false
  return hidden.entity{
    type = "reactor",
    name = name,
    icon = icon,
    consumption = energy_usage,
    energy_source = source,
    -- The heat has nowhere to go; the reactor is only here because it burns fuel
    -- continuously while it holds some, which is what a burner watcher does.
    heat_buffer = {
      max_temperature = 1000,
      specific_heat = "1MJ",
      max_transfer = "1W",
      connections = {},
    },
    neighbour_bonus = 0,
    scale_energy_usage = false,
    picture = hidden.empty_sprite,
  }
end

-- The SPEC v2 generation part (V2-PARTS 1.1). energy_production stays 0: the
-- handler adds a cycle's energy to the buffer and the network drains it at up
-- to output_flow_limit, which is what an energy product would do.
function hidden.eei_producer(name, icon, energy_output)
  return hidden.entity{
    type = "electric-energy-interface",
    name = name,
    icon = icon,
    energy_source = {
      type = "electric",
      usage_priority = energy_output.usage_priority or "secondary-output",
      buffer_capacity = energy_output.buffer_capacity,
      output_flow_limit = energy_output.output_flow_limit,
      input_flow_limit = "0W",
      render_no_power_icon = false,
      render_no_network_icon = false,
    },
    energy_production = "0W",
    energy_usage = "0W",
    gui_mode = "none",
    picture = hidden.empty_sprite,
  }
end

-- The SPEC v2 heat output part (V2-PARTS 1.2). It takes the core's box because
-- heat connection positions must lie inside the owner's box, and the spec's
-- connections are written relative to the core's centre.
function hidden.heat_interface(name, icon, heat_buffer, collision_box)
  local buffer = table.deepcopy(heat_buffer)
  buffer.default_temperature = buffer.default_temperature or 15
  return hidden.entity{
    type = "heat-interface",
    name = name,
    icon = icon,
    collision_box = table.deepcopy(collision_box),
    heat_buffer = buffer,
    gui_mode = "none",
    picture = hidden.empty_sprite,
  }
end

function hidden.tank(name, icon, fluid_box)
  local box = table.deepcopy(fluid_box)
  box.production_type = nil
  box.pipe_covers = nil
  box.pipe_picture = nil
  return hidden.entity{
    type = "storage-tank",
    name = name,
    icon = icon,
    fluid_box = box,
    -- Pipe connections must lie inside the bounding box; empty layers keep it
    -- from blocking anything.
    collision_box = {{-0.4, -0.4}, {0.4, 0.4}},
    window_bounding_box = {{0, 0}, {0, 0}},
    flow_length_in_ticks = 360,
    pictures = {
      picture = hidden.empty_sprite4,
    },
    -- Rotating the core has to rotate the tank's connections, so it keeps four
    -- directions even though nothing draws it.
    two_direction_only = false,
  }
end

function hidden.combinator(name, icon)
  local base = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
  base.name = name
  base.icon = icon
  base.icons = nil
  base.minable = nil
  base.corpse = nil
  base.dying_explosion = nil
  base.fast_replaceable_group = nil
  base.next_upgrade = nil
  base.sprites = hidden.empty_sprite4
  base.activity_led_sprites = hidden.empty_sprite4
  base.draw_circuit_wires = false
  base.collision_box = nil
  base.selection_box = nil
  for k, v in pairs(hidden.entity{}) do
    if k ~= "icon" and k ~= "icon_size" then base[k] = v end
  end
  return base
end

return hidden
