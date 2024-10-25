return {
	entry = function(self, _)
		local dir, event = ya.input {
			title = "Directory name:",
			position = { "top-center", y = 2, w = 50 },
		}

		if event ~= 1 then
			return
		end

		local args = { "-p", dir }
		if ya.target_family() == "windows" then
			args = { dir }
		end

		local child = Command("mkdir")
			:args(args)
			:stderr(Command.PIPED)
			:spawn()

		local status, _ = child:wait()
		if not status.success then
			ya.notify {
				title = "Error creating directory",
				content = child:read_line(),
				timeout = 5,
				level = "error",
			}
		end
	end
}
