-- cl-signal-chest: a chest whose circuit output is written by script (S0).
-- The native read-contents mode is the container's own; script output lives in
-- the hidden constant combinator's first section; inventory_changed is a poll.

local runtime = require("scripts.runtime")
local scheduler = require("scripts.scheduler")

local NAME = "cl-signal-chest"
local POLL = 10
local RED = defines.wire_connector_id.circuit_red

-- ---- script output -------------------------------------------------------------

local function normalise(signals)
  local list = {}
  if signals[1] == nil then
    for name, count in pairs(signals) do
      list[#list + 1] = {type = "item", name = name, quality = "normal", count = count}
    end
  else
    for _, s in ipairs(signals) do
      list[#list + 1] = {type = s.type or "item", name = s.name, quality = s.quality or "normal", count = s.count}
    end
  end
  table.sort(list, function(a, b)
    if a.type ~= b.type then return a.type < b.type end
    if a.name ~= b.name then return a.name < b.name end
    return a.quality < b.quality
  end)
  return list
end

-- Disabled when empty so the combinator, like the native type's behaviour, does
-- no circuit work while nothing is published.
local function write(rec, list)
  local limit = rec:spec().max_output_signals or 20
  local kept = {}
  for i = 1, math.min(#list, limit) do kept[i] = list[i] end
  rec.data.signals = kept
  rec:set_signals(kept)
  rec:combinator().get_or_create_control_behavior().enabled = #kept > 0
  return #kept
end

local function publish(rec, signals) return write(rec, normalise(signals or {})) end

-- ---- inventory_changed poll ----------------------------------------------------

-- get_signals_changed is the cheap native pre-check: false means the wire (and
-- so the contents, while read_contents is on) is untouched since the last poll.
-- A true can be spurious (our own publish, external signals), so the contents
-- diff decides. With read_contents off the wire says nothing about the chest.
local function wire_quiet(rec)
  local core = rec.entity
  local cb = core.get_control_behavior()
  if cb and not cb.read_contents then return false end
  local since = rec.data.checked and math.max(0, rec.data.checked - 1) or nil
  return core.get_signals_changed(RED, since) == false
end

local function poll(rec)
  local quiet = wire_quiet(rec)
  rec.data.polls = (rec.data.polls or 0) + 1
  if not quiet and rec:contents_changed("main") then
    rec:raise("inventory_changed", {inventory = defines.inventory.chest, inventory_name = "main"})
  end
  rec.data.checked = game.tick
end

local function record(unit_number)
  local rec = storage.cl.records[unit_number]
  if not rec or rec.name ~= NAME then error(NAME .. ": no record " .. tostring(unit_number), 2) end
  return rec
end

runtime.expose("signal_chest_publish", function(unit_number, signals)
  return publish(record(unit_number), signals)
end)

runtime.expose("signal_chest_signals", function(unit_number)
  return record(unit_number).data.signals
end)


-- ---- tick fixture (suite support) -------------------------------------------------
-- A suite runs inside one tick, so wire timing, the poll and save/load can only be
-- observed by a fixture that is armed at map creation and read by the suite later.

local FIXTURE = "cl_signal_chest_fixture"
local FIXTURE_X = -400

local fixture = {}

local function fx() return storage.cl.signal_chest_fixture end

local function lamp_read(lamp)
  local out = {}
  for _, s in ipairs(lamp.get_signals(RED) or {}) do out[s.signal.name] = s.count end
  return out
end

local function count_events(unit_number)
  return (fx().events or {})[unit_number] or 0
end

fixture.steps = {
  [1] = function(f)
    f.wire_t1 = lamp_read(f.lamp)
    f.wire_t1_tick = game.tick
    f.events_before_mutation = {a = count_events(f.a.unit_number), b = count_events(f.b.unit_number),
      c = count_events(f.c.unit_number)}
    f.b.get_inventory(defines.inventory.chest).insert{name = "iron-gear-wheel", count = 3}
    -- a publish changes the wire but not the contents, so it must not raise
    publish(runtime.get(f.c), {wood = 2})
    return 40
  end,
  [2] = function(f)
    f.events_after_one = {a = count_events(f.a.unit_number), b = count_events(f.b.unit_number),
      c = count_events(f.c.unit_number)}
    -- two transfers inside one poll window must still be one event
    f.b.get_inventory(defines.inventory.chest).insert{name = "iron-gear-wheel", count = 1}
    return 2
  end,
  [3] = function(f)
    f.b.get_inventory(defines.inventory.chest).insert{name = "copper-cable", count = 4}
    return 40
  end,
  [4] = function(f)
    f.events_after_burst = {a = count_events(f.a.unit_number), b = count_events(f.b.unit_number),
      c = count_events(f.c.unit_number)}
    f.wire_end = lamp_read(f.lamp)
    f.done_tick = game.tick
    f.done = true
  end,
}

scheduler.on_named(FIXTURE, function(tick)
  local f = fx()
  if not f or f.done then return end
  f.step = f.step + 1
  local delay = fixture.steps[f.step](f)
  if delay then scheduler.schedule(FIXTURE, tick + delay) end
end)

local function build(surface, x, materialise)
  local core = surface.create_entity{name = NAME, position = {x + 0.5, 0.5}, force = "player"}
  if materialise then runtime.lifecycle.materialise(core, nil, "fixture") else
    script.raise_script_built{entity = core}
  end
  return core
end

function fixture.arm(in_init)
  local old = fx()
  if old then
    for _, key in ipairs({"a", "b", "c", "lamp"}) do
      local e = old[key]
      if e and e.valid then e.destroy{raise_destroy = true} end
    end
  end
  local surface = game.surfaces.nauvis
  surface.request_to_generate_chunks({FIXTURE_X, 0}, 1)
  surface.force_generate_chunk_requests()
  local f = {step = 0, armed_tick = game.tick, events = {}}
  storage.cl.signal_chest_fixture = f
  -- Events raised during on_init are not delivered, so build the parts directly there.
  f.a = build(surface, FIXTURE_X, in_init)
  f.b = build(surface, FIXTURE_X + 4, in_init)
  f.c = build(surface, FIXTURE_X + 8, in_init)
  f.lamp = surface.create_entity{name = "small-lamp", position = {FIXTURE_X + 0.5, 2.5}, force = "player"}
  f.lamp.get_wire_connector(RED, true).connect_to(f.a.get_wire_connector(RED, true), false)
  f.a.get_inventory(defines.inventory.chest).insert{name = "copper-plate", count = 7}
  publish(runtime.get(f.a), {["iron-plate"] = 5})
  scheduler.schedule(FIXTURE, game.tick + 1)
  return f
end

runtime.init_hooks[#runtime.init_hooks + 1] = function()
  if not fx() then fixture.arm(true) end
end

runtime.subscribe(runtime.defs.events[NAME].inventory_changed, function(event)
  local f = fx()
  if f then f.events[event.unit_number] = (f.events[event.unit_number] or 0) + 1 end
end)

runtime.expose("signal_chest_fixture", function() return fx() end)
runtime.expose("signal_chest_fixture_arm", function() return fixture.arm(false) end)

-- ---- handlers --------------------------------------------------------------------

return {
  on_created = function(rec, ctx)
    local data = rec.data
    data.signals = data.signals or {}
    if ctx.cause ~= "clone" then write(rec, data.signals) end
    rec:contents_changed("main")
    data.checked = game.tick
    rec:schedule(POLL)
  end,

  on_tick = function(rec)
    poll(rec)
    rec:schedule(POLL)
  end,

  -- The library copied the combinator's sections; data.signals is what later
  -- publishes, blueprints and the GUI read, so it has to follow.
  on_pasted = function(to, from) write(to, from.data.signals or {}) end,

  blueprint_tags = function(rec) return {signals = rec.data.signals} end,

  apply_tags = function(rec, extra)
    if type(extra) == "table" and extra.signals then write(rec, extra.signals) end
  end,

  on_gui = function(rec, _, frame)
    local signals = rec.data.signals or {}
    if #signals == 0 then return end
    frame.add{type = "label", caption = {"cl-gui.published-signals"}}
    local grid = frame.add{type = "table", column_count = 10}
    for _, s in ipairs(signals) do
      grid.add{type = "sprite-button", sprite = s.type .. "/" .. s.name, number = s.count,
        style = "slot_button", enabled = false}
    end
  end,
}
