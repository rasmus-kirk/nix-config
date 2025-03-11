--- @sync entry
local function entry(_, args)
  input = args.args[1] - 1
  for _ = #cx.tabs, input do
    ya.manager_emit("tab_create", { current = true })
  end
  ya.manager_emit("tab_switch", { input })
end

return { entry = entry }
