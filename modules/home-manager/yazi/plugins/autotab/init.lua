--- @sync entry
local function entry(_, args)
for _ = #cx.tabs, args[1] do
ya.manager_emit("tab_create", { current = true })
end
ya.manager_emit("tab_switch", { args[1] })
end

return { entry = entry }
