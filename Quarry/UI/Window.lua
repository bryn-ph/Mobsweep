-- Quarry's window: its few settings, the tracked quest's mobs and a button to put the macro on your bars.
-- Opened from the minimap icon, /quarry, or the launcher in the game's Settings > AddOns.
local _, ns = ...

local Window = {}
ns.Window = Window

local W = ns.Widgets

local WIDTH, HEIGHT = 340, 560
local HEADER_MAX = 250 -- the quest title's room before the header's hairline
local CONTROL_X, CONTROL_W = 136, 150 -- where a labelled row's control starts, and its width
local ROW_H = 20
local MARKER_SIZE = 18

local win
local controls = {}
local rows = {}

local function setting(key)
	return function() return ns.settings[key] end, function(v)
		ns.settings[key] = v
		ns.Macro.Refresh()
	end
end

local function addCheck(label, key, y, after)
	local get, set = setting(key)
	if after then
		local plain = set
		set = function(v) plain(v); after(v) end
	end
	local c = W.Check(win, label, get, set)
	c:SetPoint("TOPLEFT", 14, y)
	table.insert(controls, c)
	return c
end

local function section(text, y)
	local h = W.Header(win, text)
	h:SetPoint("TOPLEFT", 16, y)
	h.line:SetPoint("RIGHT", win, "RIGHT", -14, 0)
	return h
end

-- A label on the left of a row; its control goes CONTROL_X to the right of it.
local function rowLabel(text, y)
	local l = W.Text(win, "GameFontHighlight")
	l:SetPoint("TOPLEFT", 18, y)
	l:SetText(text)
	return l
end

-- Alert sound picker: choosing one plays it.
local function soundDropdown()
	local d = W.Dropdown(win, CONTROL_W - 4)
	function d:Refresh()
		local s = ns.Sound(ns.settings.alertSound)
		self.Text:SetText(s and s.name or "")
	end
	d:SetScript("OnClick", function(self)
		if W.MenuIsOpen() then
			W.CloseMenu()
			return
		end
		local items = {}
		for _, s in ipairs(ns.SOUNDS) do
			table.insert(items, { text = s.name, checked = s.key == ns.settings.alertSound, onClick = function()
				ns.settings.alertSound = s.key
				ns.PlayAlertSound(s.key)
				self:Refresh()
			end })
		end
		W.ShowMenu(self, items)
	end)
	table.insert(controls, d)
	return d
end

-- Raid marker picker -----------------------------------------------------------------------------

local function markerPicker(anchor)
	local holder = CreateFrame("Frame", nil, win)
	holder:SetSize(8 * (MARKER_SIZE + 2), MARKER_SIZE + 2)
	holder:SetPoint("LEFT", anchor, "RIGHT", 12, 0)
	holder.buttons = {}
	for i = 1, 8 do
		local b = CreateFrame("Button", nil, holder)
		b:SetSize(MARKER_SIZE + 2, MARKER_SIZE + 2)
		b:SetPoint("LEFT", (i - 1) * (MARKER_SIZE + 2), 0)
		b.selected = b:CreateTexture(nil, "BACKGROUND")
		b.selected:SetAllPoints()
		b.selected:SetColorTexture(1, 0.82, 0, 0.3)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetSize(MARKER_SIZE, MARKER_SIZE)
		b.icon:SetPoint("CENTER")
		b.icon:SetTexture(ns.MarkerTexture(i))
		b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		b:SetScript("OnClick", function()
			ns.settings.marker = i
			ns.settings.mark = true
			ns.Macro.Refresh()
			Window.Refresh()
		end)
		b:SetScript("OnEnter", function(self) W.Tip(self, ns.MarkerName(i)) end)
		b:SetScript("OnLeave", function() GameTooltip:Hide() end)
		holder.buttons[i] = b
	end
	function holder:Refresh()
		for i, b in ipairs(self.buttons) do
			local on = ns.settings.mark and ns.settings.marker == i
			b.selected:SetShown(on)
			b.icon:SetAlpha(on and 1 or 0.35)
		end
	end
	table.insert(controls, holder)
	return holder
end

-- Target list ------------------------------------------------------------------------------------

local function row(i)
	local r = rows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, win.content)
	r:SetHeight(ROW_H)
	r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
	r:SetPoint("RIGHT", win.content, "RIGHT", 0, 0)
	r.name = W.Text(r, "GameFontHighlight")
	r.name:SetPoint("LEFT", 6, 0)
	r.name:SetWidth(150)
	r.name:SetWordWrap(false)
	r.quest = W.Text(r, "GameFontDisableSmall")
	r.quest:SetPoint("RIGHT", -6, 0)
	r.quest:SetWidth(126)
	r.quest:SetJustifyH("RIGHT")
	r.quest:SetWordWrap(false)
	if i % 2 == 0 then
		local stripe = r:CreateTexture(nil, "BACKGROUND")
		stripe:SetAllPoints()
		stripe:SetColorTexture(1, 1, 1, 0.03)
	end
	rows[i] = r
	return r
end

local function fillList()
	local list = ns.Macro.Current()
	local inMacro = 0
	for i, t in ipairs(list) do
		local r = row(i)
		r.name:SetText(t.name)
		if t.inMacro then
			inMacro = inMacro + 1
			r.name:SetTextColor(1, 1, 1)
		else
			r.name:SetTextColor(0.5, 0.5, 0.5)
		end
		r.quest:SetText((t.kind == "loot" and "Loot" or "Kill") .. (t.here == false and "  ·  other zone" or ""))
		r:Show()
	end
	for i = #list + 1, #rows do rows[i]:Hide() end
	win.content:SetHeight(math.max(1, #list * ROW_H))
	if win.scroll.UpdateThumb then win.scroll.UpdateThumb() end

	local quest = ns.Macro.Quest()
	win.header:SetWidth(0)
	win.header:SetText(quest and quest.title or "Targets")
	win.header:SetWidth(math.min(HEADER_MAX, math.max(1, (win.header.GetUnboundedStringWidth and win.header:GetUnboundedStringWidth())
		or win.header:GetStringWidth() or HEADER_MAX)))

	if not quest then
		win.empty:SetText("No tracked quest")
	elseif #list == 0 then
		win.empty:SetText("No quest mobs")
	end
	win.empty:SetShown(#list == 0)
	win.count:SetText(#list > 0 and ("%d of %d in the macro"):format(inMacro, #list) or "")
end

-- Window -----------------------------------------------------------------------------------------

local function create()
	win = W.Window("QuarryWindow", "Quarry", WIDTH, HEIGHT)
	win:SetPoint("CENTER")

	local version = W.Text(win, "GameFontDisableSmall")
	version:SetPoint("TOPRIGHT", -14, -34)
	version:SetJustifyH("RIGHT")
	version:SetText("Quarry " .. W.Version())

	-- Targeting
	section("Targeting", -62)
	local mark = addCheck("Mark targets", "mark", -78)
	markerPicker(mark.label)
	win.bind = W.BindButton(win, ns.TAG_BINDING, CONTROL_W)
	win.bind:SetPoint("LEFT", rowLabel("Tag key", -114), "LEFT", CONTROL_X, 0)
	table.insert(controls, win.bind)

	-- Tracking panel
	section("Tracking", -146)
	addCheck("Show panel", "showButton", -162, function() ns.TrackerButton.Update() end)
	win.style = W.Segmented(win, { { value = "full", text = "Full" }, { value = "minimal", text = "Minimal" } },
		CONTROL_W, function(v)
			ns.settings.panelStyle = v
			ns.TrackerButton.Update()
		end)
	win.style:SetPoint("LEFT", rowLabel("Style", -196), "LEFT", CONTROL_X, 0)
	function win.style:Refresh() self:SetValue(ns.settings.panelStyle) end
	table.insert(controls, win.style)
	win.sound = soundDropdown()
	win.sound:SetPoint("LEFT", rowLabel("Alert sound", -228), "LEFT", CONTROL_X + 4, 0)

	-- General
	section("General", -258)
	addCheck("Minimap icon", "minimapShow", -274, function() ns.MinimapButton.Update() end)

	win.header = W.Header(win, "")
	win.header:SetPoint("TOPLEFT", 16, -312)
	win.header:SetWordWrap(false)
	win.header.line:SetPoint("RIGHT", win, "RIGHT", -14, 0)

	local inset = W.Inset(win)
	inset:SetPoint("TOPLEFT", 10, -330)
	inset:SetPoint("BOTTOMRIGHT", -10, 40)
	win.scroll, win.content = W.ScrollArea(inset)
	win.scroll:SetPoint("TOPLEFT", 4, -4)
	win.scroll:SetPoint("BOTTOMRIGHT", -12, 4)

	win.empty = W.Text(inset, "GameFontDisable")
	win.empty:SetPoint("CENTER")
	win.empty:SetJustifyH("CENTER")

	local pickup = W.Button(win, "Pick up macro", 130, 22)
	pickup:SetPoint("BOTTOMLEFT", 10, 10)
	pickup:SetScript("OnClick", function() ns.Macro.Pickup() end)

	win.count = W.Text(win, "GameFontDisableSmall")
	win.count:SetPoint("BOTTOMRIGHT", -14, 16)
	win.count:SetJustifyH("RIGHT")

	win:HookScript("OnShow", function() Window.Refresh() end)
	win:HookScript("OnHide", function()
		win.bind:Cancel()
		W.CloseMenu()
	end)
	ns.On("UPDATE_BINDINGS", function() win.bind:Refresh() end)
	ns.Listen("TARGETS_CHANGED", function()
		if win:IsShown() then fillList() end
	end)
end

function Window.Refresh()
	if not win then return end
	for _, c in ipairs(controls) do c:Refresh() end
	fillList()
end

function Window.Show()
	if not win then create() end
	if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then
		HideUIPanel(SettingsPanel)
	end
	win:Show()
	win:Raise()
	Window.Refresh()
end

function Window.Toggle()
	if win and win:IsShown() then win:Hide() else Window.Show() end
end

function Window.IsShown()
	return win ~= nil and win:IsShown()
end

-- The game's Settings > AddOns page only holds a button that opens our own window (as in Jest and Needy).
function Window.Register()
	if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
	local launcher = CreateFrame("Frame")
	local title = launcher:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("Quarry")
	local open = W.Button(launcher, "Open Quarry", 180, 24)
	open:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	open:SetScript("OnClick", function() Window.Show() end)
	local category = Settings.RegisterCanvasLayoutCategory(launcher, "Quarry")
	Settings.RegisterAddOnCategory(category)
end
