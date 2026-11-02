-- Bucketed scheduler: storage.cl.due[tick] holds the keys due that tick. on_tick is
-- registered only while some bucket exists, so a world with nothing scheduled pays
-- no per-tick Lua at all, and a tick with nothing due pays one table lookup.
--
-- A key is a core unit_number or a string naming a callback registered with
-- scheduler.on_named. Rescheduling does not search old buckets: the record keeps
-- next_due and stale bucket entries are skipped when their tick comes.

local scheduler = {}

local dispatch_key = nil
local named = {}
local armed = false

local function state() return storage.cl end

local function on_tick(event)
  scheduler.dispatch(event.tick)
end

local function arm()
  if armed then return end
  armed = true
  script.on_event(defines.events.on_tick, on_tick)
end

local function disarm_if_idle()
  if armed and next(state().due) == nil then
    armed = false
    script.on_event(defines.events.on_tick, nil)
  end
end

--- fn(key, tick) is called for numeric keys whose record still wants this tick.
function scheduler.set_dispatcher(fn) dispatch_key = fn end

--- Register a named callback at script load (main chunk), never later.
function scheduler.on_named(name, fn) named[name] = fn end

--- Put key in the bucket for tick. A tick at or before now runs next tick.
function scheduler.schedule(key, tick)
  local now = game.tick
  if tick <= now then tick = now + 1 end
  local due = state().due
  local bucket = due[tick]
  if bucket then
    bucket[#bucket + 1] = key
  else
    due[tick] = {key}
  end
  arm()
  return tick
end

function scheduler.bucket(tick)
  return state().due[tick]
end

function scheduler.dispatch(tick)
  local due = state().due
  local bucket = due[tick]
  if bucket then
    due[tick] = nil
    for i = 1, #bucket do
      local key = bucket[i]
      if type(key) == "string" then
        local fn = named[key]
        if fn then fn(tick) end
      elseif dispatch_key then
        dispatch_key(key, tick)
      end
    end
  end
  disarm_if_idle()
end

--- Synthetic dispatch for the suites: runs the records due at tick (only `only`
--- when given) and leaves everything else in the bucket for the real tick.
--- Named callbacks drive real-tick fixtures (snapshots, game.speed), and other
--- records in the same bucket may be fixtures with a phase to keep; running
--- either early from a suite corrupts every test that reads it.
function scheduler.dispatch_records(tick, only)
  local due = state().due
  local bucket = due[tick]
  if not bucket then return end
  local kept = {}
  due[tick] = nil
  for i = 1, #bucket do
    local key = bucket[i]
    if type(key) == "string" or (only ~= nil and key ~= only) then
      kept[#kept + 1] = key
    elseif dispatch_key then
      dispatch_key(key, tick)
    end
  end
  if #kept > 0 then
    local now = due[tick]
    if now then
      for i = 1, #kept do now[#now + 1] = kept[i] end
    else
      due[tick] = kept
    end
  end
  disarm_if_idle()
end

function scheduler.on_load()
  if storage.cl and next(storage.cl.due) ~= nil then arm() end
end

return scheduler
