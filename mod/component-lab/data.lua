data:extend({
  {
    type = "item",
    name = "component-lab-marker",
    icon = "__base__/graphics/icons/wooden-chest.png",
    subgroup = "storage",
    order = "z[component-lab]",
    stack_size = 1,
    hidden = true,
  },
})

require("prototypes._libtest")

require("prototypes.entities.cl-fluid-chest")
require("prototypes.entities.cl-signal-chest")
require("prototypes.entities.cl-fuelled-chest")
require("prototypes.entities.cl-cold-box")
require("prototypes.entities.cl-timed-converter")
require("prototypes.entities.cl-seep-derrick")
require("prototypes.entities.cl-dig-site")
require("prototypes.entities.cl-signal-endpoint")
require("prototypes.entities.cl-rotating-chest")
require("prototypes.entities.cl-brazier")
require("prototypes.entities.cl-hearth")
require("prototypes.entities.cl-creep-collector")
require("prototypes.entities.cl-tuned-furnace")
require("prototypes.entities.cl-mass-driver")
require("prototypes.entities.cl-slag-generator")
require("prototypes.entities.cl-waste-heat-smelter")
