-- The Tracking panel: the Tag button, a secure button that runs the macro text (click it, or bind it in
-- the settings or Key Bindings > AddOns), plus a Tracking toggle and a status line. Right-click the Tag
-- button to turn Tracking on or off; drag it (or the full panel's box) to move it. It glows while a
-- wanted mob is in view and not yet marked.
-- Two styles: "full" (a box with the toggle and status) and "minimal" (just the button; hovering it fades
-- in a card with the same information, on whichever side has more room).
-- The button acts on mouse up, and a press that turns into a drag never clicks, so dragging doesn't fire it.
-- The panel holds a secure button, so it can't be moved, resized, shown or hidden in combat; those wait.
-- The hover card isn't protected and can show in combat.
local _, ns = ...

local TrackerButton = {}
ns.TrackerButton = TrackerButton

local W = ns.Widgets

local FULL_W, FULL_H = 210, 50
local ICON = 36
local CARD_W, CARD_H = 210, 64
local GREY = { 0.6, 0.6, 0.6 }
local GOLD = { 1, 0.82, 0 }
local GREEN = { 0.25, 1, 0.25 }

local panel, button, toggle, status, card
local pendingText -- macro text that arrived before the button existed
local pending = false -- a style or visibility change waiting for combat to end

local function savePosition()
	local point, _, relPoint, x, y = panel:GetPoint()
	if point then ns.settings.buttonPosition = { point, relPoint or point, x or 0, y or 0 } end
end

local function place()
	panel:ClearAllPoints()
	local pos = ns.settings.buttonPosition
	if pos then
		panel:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		panel:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
	end
end

local function startMoving()
	if InCombatLockdown() then return end
	if card then card:Hide() end
	panel:StartMoving()
end

local function stopMoving()
	panel:StopMovingOrSizing()
	savePosition()
end

-- What the panel says: text and colour of the status line, and the button's look.
local function describe()
	local state = ns.Scanner.State()
	local d = { color = GREY, active = false, marked = false, glow = false }
	if not ns.Macro.Quest() then
		d.text = "No tracked quest"
	elseif #ns.Macro.Current() == 0 then
		d.text = "No quest mobs"
	elseif not ns.settings.tracking then
		d.text = "Off"
	elseif state.found then
		d.active, d.marked = true, state.marked
		d.text, d.color = state.found .. (d.marked and "" or " nearby"), GOLD
		d.glow = not d.marked
	else
		d.active = true
		d.text = "Searching..."
	end
	return d
end

local function makeGlow()
	local glow = button:CreateTexture(nil, "OVERLAY")
	glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	glow:SetBlendMode("ADD")
	glow:SetVertexColor(1, 0.82, 0)
	glow:SetSize(ICON * 1.9, ICON * 1.9)
	glow:SetPoint("CENTER")
	glow:Hide()
	local pulse = glow:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.3)
	fade:SetDuration(0.6)
	glow.pulse = pulse
	return glow
end

local function setBox(frame, alpha)
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(0, 0, 0, alpha)
	frame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
end

-- Hover card (minimal) --------------------------------------------------------------------------

local function createCard()
	card = CreateFrame("Frame", "QuarryTrackerCard", panel, "BackdropTemplate")
	card:SetSize(CARD_W, CARD_H)
	card:SetFrameStrata("TOOLTIP")
	setBox(card, 0.85)
	card:Hide()

	card.title = W.Text(card, "GameFontNormal")
	card.title:SetPoint("TOPLEFT", 10, -9)
	card.title:SetText("Tracking")
	card.state = W.Text(card, "GameFontHighlightSmall")
	card.state:SetPoint("TOPRIGHT", -10, -11)
	card.state:SetJustifyH("RIGHT")
	card.status = W.Text(card, "GameFontHighlightSmall")
	card.status:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -6)
	card.status:SetWidth(CARD_W - 20)
	card.status:SetWordWrap(false)
	card.quest = W.Text(card, "GameFontDisableSmall")
	card.quest:SetPoint("TOPLEFT", card.status, "BOTTOMLEFT", 0, -4)
	card.quest:SetWidth(CARD_W - 20)
	card.quest:SetWordWrap(false)

	card.fade = card:CreateAnimationGroup()
	local alpha = card.fade:CreateAnimation("Alpha")
	alpha:SetFromAlpha(0)
	alpha:SetToAlpha(1)
	alpha:SetDuration(0.15)
	card.fade:SetToFinalAlpha(true)
end

local function fillCard(d)
	if not card then return end
	local on = ns.settings.tracking
	card.state:SetText(on and "On" or "Off")
	local c = on and GREEN or GREY
	card.state:SetTextColor(c[1], c[2], c[3])
	card.status:SetText(d.text)
	card.status:SetTextColor(d.color[1], d.color[2], d.color[3])
	local quest = ns.Macro.Quest()
	card.quest:SetText(quest and quest.title or "")
end

local function showCard()
	if not panel.minimal then return end
	if not card then createCard() end
	-- Open towards the middle of the screen.
	local x = panel:GetCenter()
	local width = UIParent:GetWidth()
	card:ClearAllPoints()
	if x and width and x > width / 2 then
		card:SetPoint("RIGHT", button, "LEFT", -6, 0)
	else
		card:SetPoint("LEFT", button, "RIGHT", 6, 0)
	end
	fillCard(describe())
	card:Show()
	card.fade:Stop()
	card.fade:Play()
end

local function hideCard()
	if card then
		card.fade:Stop()
		card:Hide()
	end
end

-- Building ---------------------------------------------------------------------------------------

local function create()
	panel = CreateFrame("Frame", "QuarryTracker", UIParent, "BackdropTemplate")
	panel:SetSize(FULL_W, FULL_H)
	panel:SetClampedToScreen(true)
	panel:SetFrameStrata("MEDIUM")
	panel:EnableMouse(true)
	panel:SetMovable(true)
	panel:RegisterForDrag("LeftButton")
	setBox(panel, 0.8)
	panel:SetScript("OnDragStart", startMoving)
	panel:SetScript("OnDragStop", stopMoving)

	-- Acts on key up, like Jest's wheel button; a CLICK binding sends both down and up.
	-- Left: the macro text. Right: the custom "tracking" type, which the template runs as this method.
	button = CreateFrame("Button", "QuarryTrackerButton", panel, "SecureActionButtonTemplate")
	button:SetSize(ICON, ICON)
	button:RegisterForClicks("AnyDown", "AnyUp")
	button:RegisterForDrag("LeftButton")
	button:SetAttribute("useOnKeyDown", false)
	button:SetAttribute("type", "macro")
	button:SetAttribute("type2", "tracking")
	button:SetAttribute("macrotext", pendingText or "")
	function button:tracking()
		ns.Scanner.SetTracking(not ns.settings.tracking)
	end
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexture(W.ICON)
	button.icon = icon
	local marker = button:CreateTexture(nil, "OVERLAY")
	marker:SetSize(16, 16)
	marker:SetPoint("BOTTOMRIGHT", 3, -3)
	button.marker = marker
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	button.glow = makeGlow()
	button:SetScript("OnDragStart", startMoving)
	button:SetScript("OnDragStop", stopMoving)
	button:SetScript("OnEnter", function(self)
		if panel.minimal then
			showCard()
		else
			W.Tip(self, "Quarry")
		end
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
		hideCard()
	end)

	toggle = W.Check(panel, "Tracking",
		function() return ns.settings.tracking end,
		function(v) ns.Scanner.SetTracking(v) end)
	toggle:SetPoint("TOPLEFT", button, "TOPRIGHT", 4, 4)

	status = W.Text(panel, "GameFontHighlightSmall")
	status:SetPoint("BOTTOMLEFT", button, "BOTTOMRIGHT", 8, 2)
	status:SetWidth(FULL_W - ICON - 24)
	status:SetWordWrap(false)

	ns.Listen("SCAN_UPDATE", function() TrackerButton.Refresh() end)
	ns.Listen("TARGETS_CHANGED", function() TrackerButton.Refresh() end)
end

-- Lays the panel out for the chosen style. Out of combat only.
local function applyStyle()
	local minimal = ns.settings.panelStyle == "minimal"
	panel.minimal = minimal
	button:ClearAllPoints()
	if minimal then
		panel:SetSize(ICON, ICON)
		button:SetPoint("CENTER")
		panel:SetBackdropColor(0, 0, 0, 0)
		panel:SetBackdropBorderColor(0, 0, 0, 0)
	else
		panel:SetSize(FULL_W, FULL_H)
		button:SetPoint("LEFT", 7, 0)
		panel:SetBackdropColor(0, 0, 0, 0.8)
		panel:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
		hideCard()
	end
	toggle:SetShown(not minimal)
	status:SetShown(not minimal)
end

-- The status line (or hover card), glow, marker badge and icon, from the scanner and the target list.
function TrackerButton.Refresh()
	if not panel then return end
	toggle:Refresh()
	local d = describe()
	status:SetText(d.text)
	status:SetTextColor(d.color[1], d.color[2], d.color[3])
	if card and card:IsShown() then fillCard(d) end
	button.icon:SetDesaturated(not d.active)
	if d.marked and ns.settings.mark then
		button.marker:SetTexture(ns.MarkerTexture(ns.settings.marker))
		button.marker:Show()
	else
		button.marker:Hide()
	end
	if d.glow then
		if not button.glow:IsShown() then
			button.glow:Show()
			button.glow.pulse:Play()
		end
	elseif button.glow:IsShown() then
		button.glow.pulse:Stop()
		button.glow:Hide()
	end
end

-- Applies the style and shows or hides the panel to match the settings (after combat, if need be).
function TrackerButton.Update()
	if not panel then return end
	if InCombatLockdown() then
		pending = true
		return
	end
	pending = false
	applyStyle()
	panel:SetShown(ns.settings.showButton)
	TrackerButton.Refresh()
end

-- Called by Macro (out of combat) whenever the macro text changes.
function TrackerButton.SetMacroText(text)
	if button then
		button:SetAttribute("macrotext", text)
	else
		pendingText = text
	end
end

function TrackerButton.ResetPosition()
	ns.settings.buttonPosition = nil
	if panel and not InCombatLockdown() then place() end
end

function TrackerButton.Init()
	create()
	place()
	TrackerButton.Update()
	ns.On("PLAYER_REGEN_ENABLED", function()
		if pending then TrackerButton.Update() end
	end)
end
