local _, ns = ...

ns.Defaults = {
	mark = true, -- the macro puts a raid marker on what it targets
	marker = 8, -- raid target index: 1 star ... 8 skull
	tracking = false, -- scan nameplates for the quest's mobs and alert when one is near
	alertSound = "ping", -- played with the "nearby" alert; a key of ns.SOUNDS ("none" for silence)
	showButton = true, -- the on-screen Tracking panel
	panelStyle = "full", -- "full" (box, toggle, status) or "minimal" (just the button)
	minimapShow = true,
	minimapAngle = 200,
}

ns.Limits = {
	marker = { 1, 8 },
	minimapAngle = { 0, 360 },
}

ns.MACRO_NAME = "Mobsweep"
ns.MACRO_ICON = "Ability_Hunter_SniperShot"
-- The bar macro just clicks the Tag button, which holds the real text (Core/Macro.lua), so a macro's
-- 255-character limit doesn't cut the mob list.
ns.MACRO_BODY = "/click MobsweepTrackerButton"
-- The Tag button's text (its macrotext, run by C_Macro.RunMacroText) can be longer than a macro; this keeps
-- it within a sane size. Each line stays well under the 255 a single line can hold.
ns.TEXT_LIMIT = 1023
ns.TAG_BINDING = "CLICK MobsweepTrackerButton:LeftButton" -- Bindings.xml

ns.PANEL_STYLES = { full = true, minimal = true }

-- Alert sounds ----------------------------------------------------------------------
-- kit: the SOUNDKIT key; id: its value, for a client without that key.

ns.SOUNDS = {
	{ key = "none", name = "None" },
	{ key = "ping", name = "Map ping", kit = "MAP_PING", id = 3175 },
	{ key = "raidwarning", name = "Raid warning", kit = "RAID_WARNING", id = 8959 },
	{ key = "readycheck", name = "Ready check", kit = "READY_CHECK", id = 8960 },
	{ key = "whisper", name = "Whisper", kit = "TELL_MESSAGE", id = 3081 },
	{ key = "quest", name = "Quest complete", kit = "IG_QUEST_LIST_COMPLETE", id = 878 },
	{ key = "alarm", name = "Alarm clock", kit = "ALARM_CLOCK_WARNING_3", id = 12889 },
}

function ns.Sound(key)
	for _, s in ipairs(ns.SOUNDS) do
		if s.key == key then return s end
	end
end

-- Plays an alert sound (the chosen one if key is nil). "none" plays nothing.
function ns.PlayAlertSound(key)
	local s = ns.Sound(key or ns.settings.alertSound)
	if not (s and s.id and PlaySound) then return end
	PlaySound((SOUNDKIT and SOUNDKIT[s.kit]) or s.id)
end

-- Raid markers ----------------------------------------------------------------------

function ns.MarkerTexture(index)
	return "Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. index
end

function ns.MarkerName(index)
	return _G["RAID_TARGET_" .. index] or ("Marker " .. index)
end

function ns.MarkerIcon(index, size)
	size = size or 14
	return ("|T%s:%d:%d|t"):format(ns.MarkerTexture(index), size, size)
end
