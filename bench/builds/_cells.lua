-- Shared driver for the cell variants; the variant file sets CELL first.
BENCH.quiet_world()
local slots, subs, radius = BENCH.plan(ARGS.n)
local s = BENCH.make_surface(radius + 8)
local nets = BENCH.power(s, subs)
for _, slot in ipairs(slots) do BENCH.cell(s, slot, CELL) end
BENCH.report{
  variant = ARGS.variant, cells = #slots, substations = #subs, electric_networks = nets,
  entities = s.count_entities_filtered{},
}
