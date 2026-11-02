-- Real-tick test fixtures. A suite runs inside a single tick, so anything that
-- has to be watched over time is built at on_init and observed while the server
-- runs; the suite only reads what was recorded. The harness calls the suite as
-- soon as the server answers, so every fixture holds game.speed up until its
-- last observation, and only the last one to finish may drop it back to 1:
-- separate fixtures each writing game.speed cut each other short.

local scheduler = require("scripts.scheduler")

local fixtures = {}

local SPEED = 1000
local RELEASE = "cl_fixtures_release"
local SPEEDUP = "cl_fixtures_speedup"

--- Keep the game at fixture speed until `tick` (absolute). Call from on_init,
--- or from a suite re-arming a fixture for the next --keep run.
--- The speed-up lands on the next tick: a suite re-arming a fixture mid-run
--- must not leave the rest of that run at fixture speed.
function fixtures.hold_until(tick)
  local st = storage.cl
  if not st.fixtures_until or tick > st.fixtures_until then
    st.fixtures_until = tick
    scheduler.schedule(RELEASE, tick)
  end
  scheduler.schedule(SPEEDUP, game.tick + 1)
end

--- The tick every fixture has finished by, or nil when none is held.
function fixtures.done_at() return storage.cl.fixtures_until end

scheduler.on_named(SPEEDUP, function(tick)
  local until_tick = storage.cl.fixtures_until
  if until_tick and tick < until_tick then game.speed = SPEED end
end)

scheduler.on_named(RELEASE, function(tick)
  local until_tick = storage.cl.fixtures_until
  if until_tick and tick >= until_tick then game.speed = 1 end
end)

return fixtures
