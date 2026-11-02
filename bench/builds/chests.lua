-- (a) Passive baseline: N wooden chests and nothing else.
BENCH.quiet_world()
local n = ARGS.n
local side = math.ceil(math.sqrt(n))
local pitch = 2
local s = BENCH.make_surface(side * pitch / 2 + 8)
local origin = -(side * pitch) / 2
local placed = 0
for y = 0, side - 1 do
  for x = 0, side - 1 do
    if placed >= n then break end
    BENCH.must(s, {name = "wooden-chest", position = {origin + x * pitch + 0.5, origin + y * pitch + 0.5}})
    placed = placed + 1
  end
end
BENCH.report{variant = "chests", cells = placed, entities = s.count_entities_filtered{}}
