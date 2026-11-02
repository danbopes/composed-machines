local runtime = require("scripts.runtime")

for name, handlers in pairs(require("scripts.entities._libtest")) do
  runtime.register(name, handlers)
end

-- prototype name -> entity script; one script may serve several prototypes.
for _, entry in ipairs({
  {"cl-fluid-chest", "cl-fluid-chest"},
  {"cl-fluid-chest-watch", "cl-fluid-chest"},
  {"cl-signal-chest", "cl-signal-chest"},
  {"cl-fuelled-chest", "cl-fuelled-chest"},
  {"cl-cold-box", "cl-cold-box"},
  {"cl-timed-converter", "cl-timed-converter"},
  {"cl-seep-derrick", "cl-seep-derrick"},
  {"cl-dig-site", "cl-dig-site"},
  {"cl-signal-endpoint", "cl-signal-endpoint"},
  {"cl-rotating-chest", "cl-rotating-chest"},
  {"cl-brazier", "cl-brazier"},
  {"cl-hearth", "cl-hearth"},
  {"cl-creep-collector", "cl-creep-collector"},
  {"cl-tuned-furnace", "cl-tuned-furnace"},
  {"cl-mass-driver", "cl-mass-driver"},
  {"cl-slag-generator", "cl-slag-generator"},
  {"cl-waste-heat-smelter", "cl-waste-heat-smelter"},
}) do
  runtime.register(entry[1], require("scripts.entities." .. entry[2]))
end

runtime.install()
