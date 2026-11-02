-- Empty bench surface: the fixed cost every variant pays (harness fixtures,
-- nauvis, an empty surface), subtracted for per-instance figures.
BENCH.quiet_world()
local s = BENCH.make_surface(8)
BENCH.report{variant = "empty", cells = 0, entities = s.count_entities_filtered{}}
