-- cl-fuelled-chest: a chest that burns fuel while it holds anything (S1, burner).
-- TEST-ENTITIES.md section 3. The core is a wooden-chest container; the burner
-- becomes a hidden reactor, gated by the script on the main inventory.

local component = require("lib.component")

component.define{
  name = "cl-fuelled-chest",
  emulation = {like = "wooden-chest"},
  inventories = {{name = "main", role = "storage", size = 16}},
  energy_source = {
    type = "burner",
    fuel_categories = {"chemical"},
    effectivity = 1,
    fuel_inventory_size = 1,
    burnt_inventory_size = 0,
  },
  energy_usage = "20kW",
  activity = "inventory_not_empty",
  activity_inventories = {"main"},
  events = {power_state_changed = true},
}
