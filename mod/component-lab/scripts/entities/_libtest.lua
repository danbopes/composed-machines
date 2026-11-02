-- Handlers for the library's own test entities. The probe proves the scheduler
-- fires on the right tick on a real, ticking server: it is armed at on_init
-- (map creation) and checked by the suite, which re-arms it for the next run.

local runtime = require("scripts.runtime")
local scheduler = require("scripts.scheduler")

local PROBE = "libtest_probe"

scheduler.on_named(PROBE, function(tick)
  local probe = storage.cl.probe
  if probe then
    probe.fired_at = tick
    probe.fired_count = (probe.fired_count or 0) + 1
  end
end)

local function arm(delay)
  local due = game.tick + (delay or 2)
  storage.cl.probe = {armed_at = game.tick, due = scheduler.schedule(PROBE, due)}
  return storage.cl.probe
end

-- The orphan probe proves on_object_destroyed is a working safety net: a core
-- removed with no event at all (destroy without raise_destroy) is cleaned up at
-- the end of the tick, which a single in-tick test call cannot observe.
local function orphan_probe()
  local surface = game.surfaces.nauvis
  surface.request_to_generate_chunks({-200, 0}, 1)
  surface.force_generate_chunk_requests()
  local core = surface.create_entity{name = "cl-libtest", position = {-200.5, 0.5}, force = "player"}
  -- Events raised from on_init are not delivered, so build the parts directly.
  local rec = runtime.lifecycle.materialise(core, nil, "probe")
  rec:inventory("extra").insert{name = "iron-plate", count = 7}
  local parts = {}
  for _, part in pairs(rec.parts) do parts[#parts + 1] = part end
  storage.cl.orphan_probe = {unit_number = core.unit_number, parts = parts, position = {-200.5, 0.5}, tick = game.tick}
  core.destroy()
end

runtime.init_hooks[#runtime.init_hooks + 1] = function()
  if not storage.cl.probe then arm() end
  if not storage.cl.orphan_probe then orphan_probe() end
end

runtime.expose("libtest_probe", function() return storage.cl.probe end)
runtime.expose("libtest_arm_probe", function(delay) return arm(delay) end)
runtime.expose("libtest_orphan_probe", function() return storage.cl.orphan_probe end)

local handlers = {}

handlers["cl-libtest"] = {
  on_created = function(rec, ctx)
    rec.data.created_by = ctx.cause
    rec.data.fired = {}
  end,
  on_tick = function(rec, tick)
    rec.data.fired[#rec.data.fired + 1] = tick
  end,
  blueprint_tags = function(rec) return {note = rec.data.note} end,
  apply_tags = function(rec, extra) rec.data.note = extra.note end,
}

handlers["cl-libtest-machine"] = {
  on_cycle_finished = function(rec)
    rec.data.cycles = (rec.data.cycles or 0) + 1
  end,
}

handlers["cl-libtest-burner"] = {}
handlers["cl-libtest-rotor"] = {
  on_rotated = function(rec, previous) rec.data.rotated_from = previous end,
}

return handlers
