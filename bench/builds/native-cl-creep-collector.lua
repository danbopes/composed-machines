-- Native for cl-creep-collector: an electric furnace smelting iron ore, the
-- engine's own S3 electric machine (energy charged per crafting cycle, no
-- script), fed from an infinity chest and emptied into a sink.
CELL = {w = 7, h = 3, place = function(s, slot)
  BENCH.cell(s, slot, {machine = "electric-furnace", size = 3, inserter = "fast-inserter",
    dir = BENCH.EAST_FLOW, inputs = {"iron-ore"}})
end}
