-- Tracking: while it's on, look at enemy nameplates (plus target and mouseover) about once a second for a
-- live mob from the quest's list. Addons can't target or mark on their own, so this only reports: the
-- Tracking panel's button glows and a short alert shows; the player's press does the targeting.
--   "nearby": a wanted mob came into view (not seen in the last ALERT_AGAIN seconds), with the chosen sound.
--   "marked": a live wanted mob now wears our marker. Once per mob.
-- It also says how near each wanted type is (Scanner.Nearby), so the Tag button tries the nearest type
-- first. Distance comes from CheckInteractDistance, which the game only answers for enemies out of combat;
-- in combat every type in view counts as just "in view" (and the button can't be changed then anyway).
local _, ns = ...

local Scanner = {}
ns.Scanner = Scanner

local INTERVAL = 1
local ALERT_AGAIN = 30

local ticker
local lastSeen = {} -- name -> GetTime() it was last in view
local markedSeen = {} -- GUID -> true once its "marked" alert has shown
local warnedPlates = false
local state = { tracking = false } -- see Scanner.State
local near = {} -- name -> NEAR_10 / NEAR_28 / IN_VIEW, from the last scan (see Scanner.Nearby)
local nearKey = "" -- near, flattened, to spot a change

local NEAR_10, NEAR_28, IN_VIEW = 1, 2, 3

-- CheckInteractDistance(unit, 3) is about 10 yards, (unit, 4) about 28. Out of combat only.
local function closeness(unit)
	if InCombatLockdown() or not CheckInteractDistance then return IN_VIEW end
	local function within(index)
		local ok, r = pcall(CheckInteractDistance, unit, index)
		return ok and not ns.IsSecret(r) and r == true
	end
	if within(3) then return NEAR_10 end
	if within(4) then return NEAR_28 end
	return IN_VIEW
end

local function alert(text, sound)
	if UIErrorsFrame and UIErrorsFrame.AddMessage then
		UIErrorsFrame:AddMessage(text, 1, 0.82, 0)
	end
	if sound then ns.PlayAlertSound() end
end

local function units()
	local list = {}
	if C_NamePlate and C_NamePlate.GetNamePlates then
		for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
			local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
			if unit then list[#list + 1] = unit end
		end
	end
	list[#list + 1] = "target"
	list[#list + 1] = "mouseover"
	return list
end

-- name, rank, marker, guid for a live, attackable mob on the list; nil otherwise.
local function check(unit, wanted)
	if not UnitExists(unit) or UnitIsDead(unit) or UnitIsPlayer(unit) then return end
	if UnitCanAttack and not UnitCanAttack("player", unit) then return end
	local name = UnitName(unit)
	if name == nil or ns.IsSecret(name) then return end
	local rank = wanted[name]
	if not rank then return end
	local marker = GetRaidTargetIndex and GetRaidTargetIndex(unit)
	if ns.IsSecret(marker) then marker = nil end
	local guid = UnitGUID and UnitGUID(unit)
	if ns.IsSecret(guid) then guid = nil end
	return name, rank, marker, guid
end

-- What Tracking sees: { tracking, found = the nearest wanted mob's name or nil, marked = it has our marker }.
function Scanner.State()
	return state
end

-- How near each wanted type is: name -> 1 (within about 10 yards), 2 (about 28), 3 (in view, or in
-- combat). Types not in view aren't listed. Empty while Tracking is off.
function Scanner.Nearby()
	return near
end

local function setNear(map)
	local keys = {}
	for name, d in pairs(map) do keys[#keys + 1] = name .. "=" .. d end
	table.sort(keys)
	local key = table.concat(keys, ";")
	near = map
	if key ~= nearKey then
		nearKey = key
		ns.Macro.Apply() -- reorders the Tag button (out of combat)
	end
end

function Scanner.Scan()
	if not ns.settings.tracking then return end
	local wanted = {}
	for i, t in ipairs(ns.Macro.Current()) do
		if wanted[t.name] == nil then wanted[t.name] = i end
	end
	local ourMarker = ns.settings.mark and ns.settings.marker
	local now = GetTime()
	local best, bestRank, bestNear, bestMarked
	local new, newMarked = nil, nil
	local seen, nearNow = {}, {}
	for _, unit in ipairs(units()) do
		local name, rank, marker, guid = check(unit, wanted)
		if name then
			local marked = ourMarker ~= nil and ourMarker ~= false and marker == ourMarker
			local d = closeness(unit)
			if not nearNow[name] or d < nearNow[name] then nearNow[name] = d end
			-- The nearest wins, then the better-ranked type, then one already marked.
			if not best or d < bestNear or (d == bestNear and (rank < bestRank
				or (rank == bestRank and marked and not bestMarked))) then
				best, bestRank, bestNear, bestMarked = name, rank, d, marked
			end
			if marked and guid and not markedSeen[guid] then
				markedSeen[guid] = true
				newMarked = newMarked or name
			end
			if not seen[name] then
				seen[name] = true
				if not new and (not lastSeen[name] or now - lastSeen[name] > ALERT_AGAIN) then new = name end
			end
		end
	end
	for name in pairs(seen) do lastSeen[name] = now end

	if newMarked then
		alert(newMarked .. " marked " .. ns.MarkerIcon(ourMarker, 16), false)
	elseif new then
		alert(new .. " nearby", true)
	end
	-- In combat distances are unknown and the button can't change, so keep the last out-of-combat order.
	if not InCombatLockdown() then setNear(nearNow) end
	state = { tracking = true, found = best, marked = bestMarked or false }
	ns.Fire("SCAN_UPDATE", state)
end

function Scanner.SetTracking(on)
	ns.settings.tracking = on and true or false
	if ticker then
		ticker:Cancel()
		ticker = nil
	end
	wipe(lastSeen)
	wipe(markedSeen)
	if ns.settings.tracking then
		ticker = C_Timer.NewTicker(INTERVAL, Scanner.Scan)
		if not warnedPlates and GetCVar and GetCVar("nameplateShowEnemies") == "0" then
			warnedPlates = true
			ns.Print("Enemy nameplates are off (V), so Tracking only sees your target and mouseover.")
		end
		Scanner.Scan()
	else
		setNear({})
		state = { tracking = false }
		ns.Fire("SCAN_UPDATE", state)
	end
end

function Scanner.Init()
	ns.On("NAME_PLATE_UNIT_ADDED", function() Scanner.Scan() end)
	ns.On("RAID_TARGET_UPDATE", function() Scanner.Scan() end)
	ns.Listen("TARGETS_CHANGED", function() Scanner.Scan() end)
	ns.On("PLAYER_LOGIN", function() Scanner.SetTracking(ns.settings.tracking) end)
end
