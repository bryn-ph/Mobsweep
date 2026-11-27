-- SavedVariables: settings only.
local _, ns = ...

local DB = {}
ns.DB = DB

local CURRENT_VERSION = 1

local function clamp(key, v)
	local lim = ns.Limits[key]
	if not lim then return v end
	if v < lim[1] then return lim[1] end
	if v > lim[2] then return lim[2] end
	return v
end

local function cleanSettings(saved)
	saved = type(saved) == "table" and saved or {}
	local out = {}
	for key, default in pairs(ns.Defaults) do
		local v = saved[key]
		if type(v) == type(default) and not (type(v) == "number" and v ~= v) then
			out[key] = type(v) == "number" and clamp(key, v) or v
		else
			out[key] = default
		end
	end
	out.marker = math.floor(out.marker)
	if saved.alertSound == false then out.alertSound = "none" end -- was an on/off setting
	if not ns.Sound(out.alertSound) then out.alertSound = ns.Defaults.alertSound end
	if not ns.PANEL_STYLES[out.panelStyle] then out.panelStyle = ns.Defaults.panelStyle end
	local pos = saved.buttonPosition
	if type(pos) == "table" and type(pos[1]) == "string" and type(pos[2]) == "string"
		and type(pos[3]) == "number" and type(pos[4]) == "number" then
		out.buttonPosition = { pos[1], pos[2], pos[3], pos[4] }
	end
	return out
end

function DB.Init()
	if type(TaggerDB) ~= "table" then
		TaggerDB = {}
	end
	local db = TaggerDB
	db.version = CURRENT_VERSION
	db.settings = cleanSettings(db.settings)
	ns.db = db
	ns.settings = db.settings
end

function DB.Reset()
	ns.db.settings = cleanSettings(nil)
	ns.settings = ns.db.settings
end
