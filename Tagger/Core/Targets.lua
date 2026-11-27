-- Which mobs your quests still want you to kill or loot, best first.
--
-- With QuestieDB installed, each quest's kill objectives and the NPCs that drop its items come from
-- LibQuestieDB, its public library (read only; contract below). Without it, kill objectives are read off the
-- quest log's objective text, and loot quests are skipped: the game doesn't say what drops a quest item.
local _, ns = ...

local Targets = {}
ns.Targets = Targets

local CONTRACT = 4 -- LibQuestieDB contract this was written against (QuestieDB/src/api.lua)

local function questieDB()
	local db = LibQuestieDB
	if type(db) ~= "table" or type(db.Quest) ~= "table" or type(db.Npc) ~= "table" or type(db.Item) ~= "table" then
		return nil
	end
	if type(db.RequireContract) == "function" then
		local ok, fits = pcall(db.RequireContract, CONTRACT)
		if not (ok and fits) then return nil end
	end
	return db
end

function Targets.HasQuestieDB()
	return questieDB() ~= nil
end

local function get(entity, id, key)
	if type(entity.Get) ~= "function" or id == nil then return nil end
	local ok, v = pcall(entity.Get, id, key)
	if ok then return v end
end

-- Zones ------------------------------------------------------------------------------

local areaNames = {}

local function areaName(areaID)
	local n = areaNames[areaID]
	if n == nil then
		n = (C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(areaID)) or false
		areaNames[areaID] = n
	end
	return n or nil
end

-- true: the NPC spawns in this zone; false: only elsewhere; nil: no spawn data to go on.
local function spawnsHere(db, npcID, zone)
	if not zone or zone == "" then return nil end
	local spawns = get(db.Npc, npcID, "spawns")
	if type(spawns) ~= "table" or next(spawns) == nil then return nil end
	for areaID in pairs(spawns) do
		if areaName(areaID) == zone then return true end
	end
	return false
end

-- Quest log --------------------------------------------------------------------------

-- The quest Tagger works on: the focused (super-tracked) one, or failing that the first unfinished quest
-- on the objective tracker. Returns { id, title, complete } or nil.
function Targets.Quest()
	local QL = C_QuestLog
	if not (QL and QL.GetNumQuestLogEntries and QL.GetInfo) then return nil end
	local byID, firstWatched = {}, nil
	for i = 1, QL.GetNumQuestLogEntries() or 0 do
		local info = QL.GetInfo(i)
		local id = info and info.questID
		if id and id > 0 and not info.isHeader and not info.isHidden then
			local q = { id = id, title = info.title or "?", complete = QL.IsComplete and QL.IsComplete(id) or false }
			byID[id] = q
			if not firstWatched and not q.complete and QL.GetQuestWatchType and QL.GetQuestWatchType(id) ~= nil then
				firstWatched = q
			end
		end
	end
	local super = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
	if super and byID[super] then return byID[super] end
	-- The tracker's own order, where the client gives it.
	if QL.GetNumQuestWatches and QL.GetQuestIDForQuestWatchIndex then
		for w = 1, QL.GetNumQuestWatches() or 0 do
			local q = byID[QL.GetQuestIDForQuestWatchIndex(w)]
			if q and not q.complete then return q end
		end
	end
	return firstWatched
end

-- Is the objective called `label` still to do, going by the quest log's lines? An unfinished line that
-- mentions it wins, so a done "Young Wolf slain" doesn't tick off "Wolf". No mention at all: still to do.
local function needed(objectives, label)
	if type(label) ~= "string" or label == "" then return true end
	label = label:lower()
	local done = false
	for _, o in ipairs(objectives) do
		local text = type(o.text) == "string" and o.text:lower() or ""
		if text:find(label, 1, true) then
			if not o.finished then return true end
			done = true
		end
	end
	return not done
end

local SLAIN = (type(QUEST_MONSTERS_KILLED) == "string" and QUEST_MONSTERS_KILLED:match("^%%s(.-):")) or " slain"

-- "Kobold Vermin slain: 3/10" or "3/10 Kobold Vermin slain" -> "Kobold Vermin".
function Targets.NameFromObjective(text)
	if type(text) ~= "string" then return nil end
	local name = text:gsub("^%s*%d+%s*/%s*%d+%s*", ""):gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "")
	if SLAIN ~= "" and #name > #SLAIN and name:sub(-#SLAIN) == SLAIN then
		name = name:sub(1, -#SLAIN - 1)
	end
	name = name:match("^%s*(.-)%s*$")
	if name == "" then return nil end
	return name
end

-- Collecting --------------------------------------------------------------------------

local HERE_ORDER = { [true] = 1, none = 2, [false] = 3 }

-- The mobs Targets.Quest() still wants, one entry per name: { name, quest, questID, kind = "kill"|"loot",
-- here }. Mobs in your zone come first, then in objective order. Returns the list and the quest (or nil).
function Targets.Collect()
	local db = questieDB()
	local zone = GetRealZoneText and GetRealZoneText()
	local out, byName = {}, {}
	local quest = Targets.Quest()

	local function add(name, kind, npcID)
		if type(name) ~= "string" or name == "" then return end
		local here = nil
		if db and npcID then here = spawnsHere(db, npcID, zone) end
		local t = byName[name]
		if t then
			if here == true then t.here = true end -- a namesake spawns here
			return
		end
		t = { name = name, quest = quest.title, questID = quest.id, kind = kind, here = here, order = #out + 1 }
		byName[name] = t
		table.insert(out, t)
	end

	if quest and not quest.complete then
		local objectives = (C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(quest.id)) or {}
		local data = db and get(db.Quest, quest.id, "objectives")
		if type(data) == "table" then
			for _, o in ipairs(data[1] or {}) do -- creatures to kill
				local npcName = get(db.Npc, o[1], "name")
				if needed(objectives, o[2] or npcName) then add(npcName, "kill", o[1]) end
			end
			for _, o in ipairs(data[5] or {}) do -- kill credit: any of several creatures counts
				if needed(objectives, o[3] or get(db.Npc, o[2], "name")) then
					for _, id in ipairs(o[1] or {}) do add(get(db.Npc, id, "name"), "kill", id) end
				end
			end
			for _, o in ipairs(data[3] or {}) do -- items, from whatever drops them
				if needed(objectives, o[2] or get(db.Item, o[1], "name")) then
					for _, id in ipairs(get(db.Item, o[1], "npcDrops") or {}) do
						add(get(db.Npc, id, "name"), "loot", id)
					end
				end
			end
		else
			for _, o in ipairs(objectives) do
				if o.type == "monster" and not o.finished then
					add(Targets.NameFromObjective(o.text), "kill")
				end
			end
		end
	end

	table.sort(out, function(a, b)
		local ha, hb = HERE_ORDER[a.here == nil and "none" or a.here], HERE_ORDER[b.here == nil and "none" or b.here]
		if ha ~= hb then return ha < hb end
		return a.order < b.order
	end)
	return out, quest
end
