-- Mobsweep's targeting text, after RestedXP's targeting macro. The Tag button runs it (its macrotext):
--   /cleartarget
--   /targetexact [noexists][dead] Best Mob      one line per wanted mob, best first
--   /targetexact [noexists][dead] Next Mob
--   /cleartarget [dead]
--   /tm [harm,nodead] !8
-- Each /targetexact only runs while there's no live target yet, so the first live match wins, and a corpse
-- (often the nearest of a type you've just killed) falls through to the next type. Clearing first means it
-- never ends up on, or marks, whatever you had targeted before. "/tm !N" leaves a mob that already has that
-- marker alone instead of toggling it off.
-- While Tracking is on and you're out of combat, the types nearest you go first (Scanner.Nearby), so the
-- closest type wins rather than a fixed favourite.
-- The bar macro is just "/click MobsweepTrackerButton", so it never needs editing and the 255-character
-- macro limit doesn't apply. Secure attributes and macros can't be changed in combat; changes made then
-- wait for PLAYER_REGEN_ENABLED.
local _, ns = ...

local Macro = {}
ns.Macro = Macro

local current = {} -- the last Targets.Collect(), in its own order (.base), each entry with .inMacro
local quest -- the quest it came from (Targets.Quest())
local text -- the button's current text
local lastText -- what the button was last given
local macroOK = false -- the bar macro exists and holds MACRO_BODY
local ready = false -- macros are loaded; set shortly after the first loading screen
local queued = false
local warnedFull = false

Macro.EMPTY = "# Mobsweep: no quest mobs"

local HEAD = "/cleartarget"
local TARGET = "/targetexact [noexists][dead] "
local NOT_NEAR = 99

-- The text for `list` (best first), fitted to `limit` characters (ns.TEXT_LIMIT if not given). marker:
-- raid target index, or nil for no marking. Sets .inMacro on each entry. Returns the text and how many
-- mobs made it in.
function Macro.Body(list, marker, limit)
	limit = limit or ns.TEXT_LIMIT
	local tail = "/cleartarget [dead]"
	if marker then tail = tail .. "\n/tm [harm,nodead] !" .. marker end
	local lines, used = {}, #HEAD + 1 + #tail
	for _, t in ipairs(list) do
		local line = TARGET .. t.name
		t.inMacro = used + #line + 1 <= limit
		if t.inMacro then
			used = used + #line + 1
			table.insert(lines, line)
		end
	end
	local count = #lines
	if count == 0 then return Macro.EMPTY, 0 end
	table.insert(lines, 1, HEAD)
	table.insert(lines, tail)
	return table.concat(lines, "\n"), count
end

-- `current`, nearest types first (Scanner.Nearby), otherwise in its own order.
local function ordered()
	local near = ns.Scanner.Nearby()
	local list = {}
	for i, t in ipairs(current) do list[i] = t end
	table.sort(list, function(a, b)
		local na, nb = near[a.name] or NOT_NEAR, near[b.name] or NOT_NEAR
		if na ~= nb then return na < nb end
		return a.base < b.base
	end)
	return list
end

-- The bar macro ------------------------------------------------------------------------------------

local function room()
	local numAccount, numChar = GetNumMacros()
	local maxAccount, maxChar = MAX_ACCOUNT_MACROS or 120, MAX_CHARACTER_MACROS or 18
	if (numChar or 0) < maxChar then return true, true end
	return (numAccount or 0) < maxAccount, false
end

-- Makes sure the bar macro exists (per character if there's room) and holds MACRO_BODY.
-- Returns whether it does.
local function writeMacro()
	local index = GetMacroIndexByName(ns.MACRO_NAME)
	if index and index > 0 then
		local _, _, old = GetMacroInfo(index)
		if old ~= ns.MACRO_BODY then EditMacro(index, ns.MACRO_NAME, nil, ns.MACRO_BODY) end
		return true
	end
	local fits, perChar = room()
	if not fits then
		if not warnedFull then
			warnedFull = true
			ns.Print("Your macros are full. Delete one and Mobsweep will make its macro.")
		end
		return false
	end
	local ok, err = pcall(CreateMacro, ns.MACRO_NAME, ns.MACRO_ICON, ns.MACRO_BODY, perChar)
	if not ok then
		ns.Debug("CreateMacro failed:", err)
		return false
	end
	ns.Print("Made the |cffffd100Mobsweep|r macro. Put it on your bars from /mobsweep or /macro.")
	return true
end

-- Updating -------------------------------------------------------------------------------------------

-- Gives the Tag button its text for the current list, in the current order, if that changed.
-- Out of combat only; in combat it waits for the update PLAYER_REGEN_ENABLED queues.
function Macro.Apply()
	if not ready then return end
	text = Macro.Body(ordered(), ns.settings.mark and ns.settings.marker or nil)
	if text == lastText or InCombatLockdown() then return end
	ns.TrackerButton.SetMacroText(text)
	lastText = text
end

-- Rebuilds the list and updates the button and the bar macro.
function Macro.Update()
	queued = false
	if not ready then return end
	current, quest = ns.Targets.Collect()
	for i, t in ipairs(current) do t.base = i end
	Macro.Apply()
	if not macroOK and not InCombatLockdown() then macroOK = writeMacro() end
	ns.Fire("TARGETS_CHANGED", current)
end

-- Several quest events tend to arrive at once; rebuild once they settle.
function Macro.Queue(delay)
	if queued then return end
	queued = true
	C_Timer.After(delay or 0.5, Macro.Update)
end

-- After a settings change: rebuild now.
function Macro.Refresh()
	lastText = nil
	macroOK = false
	Macro.Update()
end

function Macro.Current()
	return current
end

-- The quest the list is for (Targets.Quest()), or nil.
function Macro.Quest()
	return quest
end

-- The Tag button's text.
function Macro.Text()
	return text
end

function Macro.Exists()
	local index = GetMacroIndexByName(ns.MACRO_NAME)
	return index ~= nil and index > 0
end

-- Puts the bar macro on the cursor, to drop on an action bar (making it first if need be).
function Macro.Pickup()
	if InCombatLockdown() then
		ns.Print("Not in combat.")
		return
	end
	if not Macro.Exists() then
		ready = true
		Macro.Refresh()
	end
	if Macro.Exists() then PickupMacro(ns.MACRO_NAME) end
end

function Macro.Init()
	for _, event in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "SUPER_TRACKING_CHANGED",
		"ZONE_CHANGED_NEW_AREA", "PLAYER_REGEN_ENABLED" }) do
		ns.On(event, function() Macro.Queue() end)
	end
	-- Edited or deleted in /macro: check it again on the next update.
	ns.On("UPDATE_MACROS", function() macroOK = false end)
	ns.On("PLAYER_ENTERING_WORLD", function()
		if ready then
			Macro.Queue()
			return
		end
		C_Timer.After(2, function()
			ready = true
			Macro.Update()
		end)
	end)
end
