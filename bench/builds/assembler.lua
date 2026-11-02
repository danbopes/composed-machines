-- (d) assembling-machine-2 on iron-gear-wheel. A gear every 0.67 s eats 3 plates/s,
-- which a fast inserter cannot feed, so the input side uses a bulk inserter.
CELL = {machine = "assembling-machine-2", size = 3, inserter = "bulk-inserter", dir = BENCH.EAST_FLOW,
        recipe = "iron-gear-wheel", inputs = {"iron-plate"}}
