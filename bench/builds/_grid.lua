-- Driver for the composed-vs-native cells; the variant file sets CELL first:
--   CELL = {w = tiles, h = tiles, place = function(s, slot, i) ... end}
-- slot = {left, top}; a cell owns [left, left + w) x [top, top + h).
BENCH.quiet_world()
local slots, subs, radius = BENCH.plan(ARGS.n, CELL.w, CELL.h)
local s = BENCH.make_surface(radius + 8)
local nets = BENCH.power(s, subs)
for i, slot in ipairs(slots) do CELL.place(s, slot, i) end
BENCH.report{
  variant = ARGS.variant, cells = #slots, substations = #subs, electric_networks = nets,
  entities = s.count_entities_filtered{},
}
