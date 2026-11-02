-- Composed: cl-slag-generator (burner assembler shell, water -> stone every 4 s,
-- crafted handler adds 6 MJ to the hidden secondary-output EEI). Water from an
-- infinity pipe, coal inserted from an infinity chest into the shell's fuel slot,
-- stone taken out to a sink, and a 2 MW consumer EEI so the generator is drained
-- (1.5 MW average output) and never blocks. h = 6 leaves a gap row.
CELL = {w = 7, h = 6, place = function(s, slot)
  local L, T = slot.left, slot.top
  local y = T + 2.5
  BENCH.infinity_pipe(s, {L + 3.5, T + 0.5}, "water", 1)
  BENCH.infinity_source(BENCH.must(s, {name = "infinity-chest", position = {L + 0.5, y}}), {"coal"})
  BENCH.inserter(s, "fast-inserter", {L + 1.5, y})
  BENCH.must(s, {name = "cl-slag-generator", position = {L + 3.5, y}, raise_built = true})
  BENCH.inserter(s, "fast-inserter", {L + 5.5, y})
  BENCH.infinity_sink(BENCH.must(s, {name = "infinity-chest", position = {L + 6.5, y}}))
  BENCH.eei_consumer(s, {L + 1, T + 5}, 2e6)
end}
