-- The Tagger macro, after RestedXP's targeting macro: clear the target, a /targetexact line for each
-- wanted mob (the most wanted last, so it wins when several are in range), drop a corpse, then mark what
-- it found. Clearing first means it never ends up on (or marks) whatever you had targeted before.
-- "/tm !N" leaves a mob that already has that marker alone instead of toggling it off.
-- The same text drives the Tracking panel's button. Macros and secure attributes can't be changed in
-- combat, so changes made then wait for PLAYER_REGEN_ENABLED.
local _, ns = ...

local Macro = {}
ns.Macro = Macro

local current = {} -- the last Targets.Collect(), each entry with .inMacro
local quest -- the quest it came from (Targets.Quest())
local body = nil -- the current text
local lastBody -- what we last wrote (or found there)
local ready = false -- macros are loaded; set shortly after the first loading screen
local queued = false
local warnedFull = false

Macro.EMPTY = "# Tagger: no quest mobs"

-- The macro text for `list` (best first), fitted to the macro limit. marker: raid target index, or nil
-- for no marking. Sets .inMacro on each entry. Returns the body and how many mobs made it in.
local HEAD = "/cleartarget"

function Macro.Body(list, marker)
	local tail = "/cleartarget [dead]"
	if marker then tail = tail .. "\n/tm [harm,nodead] !" .. marker end
	local lines, used = {}, #HEAD + 1 + #tail
	for _, t in ipairs(list) do
		local line = "/targetexact " .. t.name
		t.inMacro = used + #line + 1 <= ns.MACRO_LIMIT
		if t.inMacro then
			used = used + #line + 1
			table.insert(lines, 1, line)
		end
	end
	local count = #lines
	if count == 0 then return Macro.EMPTY, 0 end
	table.insert(lines, 1, HEAD)
	table.insert(lines, tail)
	return table.concat(lines, "\n"), count
end

-- Writing --------------------------------------------------------------------------------------

local function room()
	local numAccount, numChar = GetNumMacros()
	local maxAccount, maxChar = MAX_ACCOUNT_MACROS or 120, MAX_CHARACTER_MACROS or 18
	if (numChar or 0) < maxChar then return true, true end
	return (numAccount or 0) < maxAccount, false
end

-- Puts `body` in the macro, making it first (per character if there's room) if it's missing.
-- Returns whether the macro now holds it.
local function write(body)
	local index = GetMacroIndexByName(ns.MACRO_NAME)
	if index and index > 0 then
		local _, _, old = GetMacroInfo(index)
		if old ~= body then EditMacro(index, ns.MACRO_NAME, nil, body) end
		return true
	end
	local fits, perChar = room()
	if not fits then
		if not warnedFull then
			warnedFull = true
			ns.Print("Your macros are full. Delete one and Tagger will make its macro.")
		end
		return false
	end
	local ok, err = pcall(CreateMacro, ns.MACRO_NAME, ns.MACRO_ICON, body, perChar)
	if not ok then
		ns.Debug("CreateMacro failed:", err)
		return false
	end
	ns.Print("Made the |cffffd100Tagger|r macro. Put it on your bars from /tagger or /macro.")
	return true
end

-- Rebuilds the list and writes the macro (and the Tracking button) if it changed.
function Macro.Update()
	queued = false
	if not ready then return end
	current, quest = ns.Targets.Collect()
	body = Macro.Body(current, ns.settings.mark and ns.settings.marker or nil)
	if body ~= lastBody then
		if InCombatLockdown() then
			ns.Debug("in combat; macro update waits")
		else
			write(body)
			ns.TrackerButton.SetMacroText(body)
			lastBody = body
		end
	end
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
	lastBody = nil
	Macro.Update()
end

function Macro.Current()
	return current
end

-- The quest the list is for (Targets.Quest()), or nil.
function Macro.Quest()
	return quest
end

function Macro.Text()
	return body
end

function Macro.Exists()
	local index = GetMacroIndexByName(ns.MACRO_NAME)
	return index ~= nil and index > 0
end

-- Puts the macro on the cursor, to drop on an action bar (making it first if need be).
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
	-- Edited or deleted in /macro: compare with what's really there next time.
	ns.On("UPDATE_MACROS", function() lastBody = nil end)
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
