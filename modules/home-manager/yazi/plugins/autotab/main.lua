--- @sync entry
local function entry(_, job)
  local input = job.args[1] - 1
  for _ = #cx.tabs, input do
    ya.emit("tab_create", { current = true })
  end
  ya.emit("tab_switch", { input })
end

return { entry = entry }
