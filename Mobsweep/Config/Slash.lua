local _, ns = ...

local commands = {}
local order = {}

local function add(name, usage, fn)
	commands[name] = fn
	table.insert(order, { name = name, usage = usage })
end

local function help()
	ns.Print("commands:")
	for _, c in ipairs(order) do
		print(("  |cffffd100/mobsweep %s|r - %s"):format(c.name, c.usage))
	end
end

add("list", "print what the macro targets", function()
	ns.Macro.Update()
	local names = {}
	for _, t in ipairs(ns.Macro.Current()) do
		if t.inMacro then table.insert(names, t.name) end
	end
	local quest = ns.Macro.Quest()
	if not quest then
		ns.Print("No tracked quest.")
	else
		ns.Print(quest.title .. ": " .. (#names > 0 and table.concat(names, ", ") or "no quest mobs."))
	end
end)

add("mark", "[1-8 | off] which raid marker the macro puts on targets", function(arg)
	local n = tonumber(arg)
	if arg == "off" then
		ns.settings.mark = false
	elseif n and n >= 1 and n <= 8 then
		ns.settings.mark = true
		ns.settings.marker = math.floor(n)
	else
		ns.Print("/mobsweep mark 1-8 (8 is skull), or /mobsweep mark off")
		return
	end
	ns.Macro.Refresh()
	ns.Window.Refresh()
	ns.Print(ns.settings.mark and ("Marking with " .. ns.MarkerIcon(ns.settings.marker) .. " " .. ns.MarkerName(ns.settings.marker) .. ".")
		or "Not marking.")
end)

add("track", "turn Tracking on or off", function()
	ns.Scanner.SetTracking(not ns.settings.tracking)
	ns.Print("Tracking " .. (ns.settings.tracking and "on." or "off."))
end)

add("button", "show or hide the Tracking panel", function()
	ns.settings.showButton = not ns.settings.showButton
	ns.TrackerButton.Update()
	ns.Window.Refresh()
	ns.Print("Tracking panel " .. (ns.settings.showButton and "shown." or "hidden. /mobsweep button brings it back."))
end)

add("style", "switch the Tracking panel between full and minimal", function()
	ns.settings.panelStyle = ns.settings.panelStyle == "minimal" and "full" or "minimal"
	ns.TrackerButton.Update()
	ns.Window.Refresh()
	ns.Print("Tracking panel: " .. ns.settings.panelStyle .. ".")
end)

add("pickup", "put the macro on your cursor", function()
	ns.Macro.Pickup()
end)

add("minimap", "show or hide the minimap icon", function()
	ns.settings.minimapShow = not ns.settings.minimapShow
	ns.MinimapButton.Update()
	ns.Window.Refresh()
	ns.Print("Minimap icon " .. (ns.settings.minimapShow and "shown." or "hidden. /mobsweep minimap brings it back."))
end)

add("debug", "toggle debug output", function()
	ns.debug = not ns.debug
	ns.Print("debug " .. (ns.debug and "on" or "off"))
end)

add("reset", "reset settings and the panel's position", function()
	ns.DB.Reset()
	ns.Scanner.SetTracking(ns.settings.tracking)
	ns.TrackerButton.ResetPosition()
	ns.TrackerButton.Update()
	ns.MinimapButton.Update()
	ns.Macro.Refresh()
	ns.Window.Refresh()
	ns.Print("Settings reset.")
end)

add("help", "this list", help)

SLASH_MOBSWEEP1 = "/mobsweep"
SlashCmdList.MOBSWEEP = function(msg)
	local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
	cmd = cmd:lower()
	if cmd == "" then
		ns.Window.Toggle()
		return
	end
	local fn = commands[cmd]
	if fn then
		fn(rest:lower())
	else
		help()
	end
end
