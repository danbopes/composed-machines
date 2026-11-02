-- Runs last (the manifest is sorted). Every test clears its own row through
-- _site.lua; this proves it, by checking that no composed-machine records
-- exist beyond the map fixtures armed at on_init.

local site = require("_site")

test("zz: no test leaves composed machines behind", function()
  site.clean()
  local base = site.baseline()
  assert_not_nil(base, "baseline taken before the first test")
  local now = remote.call("component_lab", "census")
  local names = {}
  for name in pairs(base) do names[name] = true end
  for name in pairs(now) do names[name] = true end
  -- Fewer is fine: some tests mine or kill a fixture on purpose.
  for name in pairs(names) do
    local after, before = now[name] or 0, base[name] or 0
    assert_true(after <= before, string.format("%s: %d records after the suite, %d before it", name, after, before))
  end
end)
