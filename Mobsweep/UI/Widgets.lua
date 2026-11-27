-- Shared UI pieces, in the game's own style (Blizzard templates and fonts), as in Jest and Needy.
local addonName, ns = ...

local Widgets = {}
ns.Widgets = Widgets

Widgets.ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\icon"
Widgets.GOLD_HEX = "ffffd100"
Widgets.GREY_HEX = "ff8c8c8c"

function Widgets.Text(parent, template, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY", template or "GameFontHighlight")
	fs:SetJustifyH("LEFT")
	return fs
end

function Widgets.Hairline(parent, layer)
	local t = parent:CreateTexture(nil, layer or "ARTWORK")
	t:SetColorTexture(1, 1, 1, 0.12)
	t:SetHeight(1)
	return t
end

-- Section title with a hairline running to the right edge of `parent`.
function Widgets.Header(parent, text)
	local fs = Widgets.Text(parent, "GameFontNormal")
	fs:SetText(text)
	local line = Widgets.Hairline(parent)
	line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
	line:SetPoint("RIGHT", parent, "RIGHT", -16, 0)
	fs.line = line
	return fs
end

function Widgets.Button(parent, text, width, height)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 100, height or 22)
	b:SetText(text or "")
	return b
end

-- A title-only tooltip, for icon buttons.
function Widgets.Tip(owner, title)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(title, 1, 1, 1)
	GameTooltip:Show()
end

function Widgets.Check(parent, text, get, set)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(26, 26)
	check.label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	check.label:SetPoint("LEFT", check, "RIGHT", 2, 1)
	check.label:SetText(text)
	check:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
	function check:Refresh() self:SetChecked(get() and true or false) end
	return check
end

-- Row of mutually exclusive options (as in Needy). items = { { value = ..., text = ... }, ... };
-- onSelect(value) fires on click. holder:SetValue(v) shows the current one.
function Widgets.Segmented(parent, items, width, onSelect)
	local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	holder:SetSize(width, 24)
	holder:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	holder:SetBackdropColor(0, 0, 0, 0.5)
	holder:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
	holder.buttons = {}
	local segW = width / #items
	for i, item in ipairs(items) do
		local b = CreateFrame("Button", nil, holder)
		b:SetPoint("TOPLEFT", (i - 1) * segW + 1, -1)
		b:SetSize(segW - 2, 22)
		b.bg = b:CreateTexture(nil, "BACKGROUND")
		b.bg:SetAllPoints()
		b.bg:SetColorTexture(1, 0.82, 0, 0.25)
		b.bg:Hide()
		local hover = b:CreateTexture(nil, "HIGHLIGHT")
		hover:SetAllPoints()
		hover:SetColorTexture(1, 1, 1, 0.08)
		if i > 1 then
			local div = b:CreateTexture(nil, "BORDER")
			div:SetColorTexture(0.4, 0.4, 0.4, 1)
			div:SetWidth(1)
			div:SetPoint("TOPLEFT", -1, 0)
			div:SetPoint("BOTTOMLEFT", -1, 0)
		end
		b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		b.text:SetPoint("CENTER")
		b.text:SetText(item.text)
		b.value = item.value
		b:SetScript("OnClick", function()
			onSelect(item.value)
			holder:SetValue(item.value)
		end)
		holder.buttons[i] = b
	end
	function holder:SetValue(value)
		for _, b in ipairs(self.buttons) do
			local on = b.value == value
			b.bg:SetShown(on)
			if on then
				b.text:SetTextColor(1, 1, 1)
			else
				b.text:SetTextColor(0.62, 0.62, 0.62)
			end
		end
	end
	return holder
end

-- Dropdowns (as in Jest) ---------------------------------------------------------------------------

-- A button drawn like the game's dropdowns (WowStyle1DropdownTemplate's art). b.Text holds the shown
-- value; the caller sets OnClick (usually to open a Widgets.ShowMenu list).
function Widgets.Dropdown(parent, width)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(width, 25)
	b.Background = b:CreateTexture(nil, "BACKGROUND")
	b.Background:SetAtlas("common-dropdown-textholder")
	b.Background:SetPoint("TOPLEFT", -8, 7)
	b.Background:SetPoint("BOTTOMRIGHT", 8, -9)
	b.Arrow = b:CreateTexture(nil, "ARTWORK")
	b.Arrow:SetAtlas("common-dropdown-a-button", true)
	b.Arrow:SetPoint("RIGHT", 1, -3)
	b.Text = b:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	b.Text:SetPoint("LEFT", 8, -1)
	b.Text:SetPoint("RIGHT", b.Arrow, "LEFT", -2, 0)
	b.Text:SetJustifyH("LEFT")
	b.Text:SetWordWrap(false)
	b:SetScript("OnEnter", function(self) self.Arrow:SetAtlas("common-dropdown-a-button-hover", true) end)
	b:SetScript("OnLeave", function(self) self.Arrow:SetAtlas("common-dropdown-a-button", true) end)
	b:SetScript("OnMouseDown", function(self) self.Arrow:SetAtlas("common-dropdown-a-button-pressedhover", true) end)
	b:SetScript("OnMouseUp", function(self) self.Arrow:SetAtlas("common-dropdown-a-button-hover", true) end)
	return b
end

-- A list of choices under `anchor`. items = { { text =, onClick = fn, checked = bool }, ... };
-- checked marks the current choice in gold. Closes on a pick, on Esc, or on a click anywhere else.
local menu
local MENU_ROW_H, MENU_MIN_W, MENU_PAD = 20, 140, 26

local function createMenu()
	menu = CreateFrame("Frame", "MobsweepMenu", UIParent, "BackdropTemplate")
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	menu:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
	menu:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
	menu:EnableMouse(true)
	menu:Hide()
	menu.rows = {}
	table.insert(UISpecialFrames, "MobsweepMenu") -- Esc closes it
	-- Close on a click outside. A click on the button that opened it is left to that button, which
	-- toggles: closing here first would make its click reopen the menu.
	menu:SetScript("OnEvent", function(self)
		if self:IsMouseOver() then return end
		if self.anchor and self.anchor:IsMouseOver() then return end
		self:Hide()
	end)
	menu:SetScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
	menu:SetScript("OnHide", function(self) pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
end

local function menuRow(i)
	local row = menu.rows[i]
	if row then return row end
	row = CreateFrame("Button", nil, menu)
	row:SetHeight(MENU_ROW_H)
	row:SetPoint("TOPLEFT", 5, -5 - (i - 1) * MENU_ROW_H)
	row:SetPoint("RIGHT", -5, 0)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", 8, 0)
	row.text:SetPoint("RIGHT", -8, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)
	local hover = row:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 0.82, 0, 0.18)
	row:SetScript("OnClick", function(self)
		menu:Hide()
		if self.onClick then self.onClick() end
	end)
	menu.rows[i] = row
	return row
end

function Widgets.ShowMenu(anchor, items)
	if not menu then createMenu() end
	local width = math.max(MENU_MIN_W, anchor:GetWidth() or 0)
	for i, item in ipairs(items) do
		local row = menuRow(i)
		row.text:SetText(item.text)
		row.onClick = item.onClick
		if item.checked then
			row.text:SetTextColor(1, 0.82, 0)
		else
			row.text:SetTextColor(1, 1, 1)
		end
		local textWidth = (row.text.GetUnboundedStringWidth and row.text:GetUnboundedStringWidth()) or row.text:GetStringWidth() or 0
		width = math.max(width, textWidth + MENU_PAD)
		row:Show()
	end
	for i = #items + 1, #menu.rows do menu.rows[i]:Hide() end
	menu:SetSize(width, #items * MENU_ROW_H + 10)
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	menu.anchor = anchor
	menu:Show()
	menu:Raise()
	return menu
end

function Widgets.CloseMenu()
	if menu then menu:Hide() end
end

function Widgets.MenuIsOpen()
	return menu ~= nil and menu:IsShown()
end

-- Key binding capture (as in Jest) ---------------------------------------------------------------
-- Click, then press a key (Esc cancels; middle and side mouse buttons work too). Right-click clears.
-- The binding is saved to the current binding set, the same as Key Bindings > AddOns.

local MODIFIER_KEYS = {
	LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
	LALT = true, RALT = true, LMETA = true, RMETA = true, UNKNOWN = true,
}
local MOUSE_KEYS = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

local function keyText(key)
	return (GetBindingText and GetBindingText(key)) or key
end

local function modifierPrefix()
	return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "") .. (IsShiftKeyDown() and "SHIFT-" or "")
end

local function clearBinding(command)
	local k1, k2 = GetBindingKey(command)
	if k1 then SetBinding(k1) end
	if k2 then SetBinding(k2) end
end

function Widgets.BindButton(parent, command, width)
	local b = Widgets.Button(parent, "", width or 150, 22)
	b:RegisterForClicks("AnyUp")

	function b:Refresh()
		if self.capturing then return end
		local key = GetBindingKey(command)
		self:SetText(key and keyText(key) or "|cff888888Not bound|r")
	end

	-- OnKeyDown is only set while capturing: a frame with one takes keyboard input from everything else.
	local onKeyDown

	local function stop(self)
		self.capturing = false
		self:SetScript("OnKeyDown", nil)
		self:EnableKeyboard(false)
		self:UnlockHighlight()
		self:Refresh()
	end

	function b:Cancel()
		if self.capturing then stop(self) end
	end

	local function assign(self, key)
		stop(self)
		if InCombatLockdown() then
			ns.Print("Key bindings can't be changed in combat.")
			return
		end
		local previous = GetBindingAction(key)
		clearBinding(command)
		if not SetBinding(key, command) then
			ns.Print("Couldn't bind " .. keyText(key) .. ".")
			self:Refresh()
			return
		end
		SaveBindings(GetCurrentBindingSet())
		self:Refresh()
		if previous and previous ~= "" and previous ~= command then
			local name = _G["BINDING_NAME_" .. previous] or previous
			ns.Print(("Bound %s. It was bound to \"%s\" before."):format(keyText(key), name))
		end
	end

	b:SetScript("OnClick", function(self, mouseButton)
		if self.capturing then
			local key = MOUSE_KEYS[mouseButton]
			if key then
				assign(self, modifierPrefix() .. key)
			else
				stop(self)
			end
			return
		end
		if InCombatLockdown() then
			ns.Print("Key bindings can't be changed in combat.")
			return
		end
		if mouseButton == "RightButton" then
			clearBinding(command)
			SaveBindings(GetCurrentBindingSet())
			self:Refresh()
			return
		end
		self.capturing = true
		self:LockHighlight()
		self:SetText("Press a key...")
		self:SetScript("OnKeyDown", onKeyDown)
		self:EnableKeyboard(true)
	end)

	onKeyDown = function(self, key)
		if not self.capturing or MODIFIER_KEYS[key] then return end
		if key == "ESCAPE" then
			stop(self)
			return
		end
		assign(self, modifierPrefix() .. key)
	end
	b:EnableKeyboard(false)
	return b
end

-- Windows ---------------------------------------------------------------------------------------------

local function child(frame, key)
	local v = rawget(frame, key)
	return type(v) == "table" and v or nil
end
Widgets.Child = child

-- A standard game window (ButtonFrameTemplate) with the addon icon in the portrait, a title and close
-- button. Movable by dragging; Esc closes it. Its Inset is hidden; callers add their own.
function Widgets.Window(name, title, width, height)
	local f = CreateFrame("Frame", name, UIParent, "ButtonFrameTemplate")
	f:SetSize(width, height)
	f:SetToplevel(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:SetMovable(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	if ButtonFrameTemplate_HideButtonBar then ButtonFrameTemplate_HideButtonBar(f) end
	local container = child(f, "PortraitContainer")
	local portrait = container and child(container, "portrait")
	if portrait then
		portrait:SetTexture(Widgets.ICON)
		-- The portrait is 62x62, but its circle mask covers x 2-60 and y 0-58 of it (SharedUIPanelTemplates.xml,
		-- CircleMask), so the circle sits 2px above the texture's centre. Map the icon onto the circle.
		portrait:SetTexCoord(-2 / 58, 60 / 58, 0, 62 / 58)
	end
	local inset = child(f, "Inset")
	if inset then inset:Hide() end
	if f.SetTitle then
		f:SetTitle(title)
	else
		local tc = child(f, "TitleContainer")
		if tc and child(tc, "TitleText") then tc.TitleText:SetText(title) end
	end
	-- The template's title bar runs from the portrait to the close button, which puts the title right of
	-- centre on a narrow window. Make it symmetric so the title centres on the whole window.
	local tc = child(f, "TitleContainer")
	if tc then
		local _, _, _, _, y = tc:GetPoint(1)
		tc:ClearAllPoints()
		tc:SetPoint("TOPLEFT", f, "TOPLEFT", 24, y or -1)
		tc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, y or -1)
	end
	f:Hide()
	table.insert(UISpecialFrames, name) -- Esc closes it
	return f
end

-- A recessed panel (InsetFrameTemplate) for lists.
function Widgets.Inset(parent)
	return CreateFrame("Frame", nil, parent, "InsetFrameTemplate")
end

-- A vertical scroll area with a slim indicator. Returns scrollFrame, content; size content's height.
function Widgets.ScrollArea(parent)
	local scroll = CreateFrame("ScrollFrame", nil, parent)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(1, 1)
	scroll:SetScrollChild(content)

	local thumb = scroll:CreateTexture(nil, "OVERLAY")
	thumb:SetWidth(4)
	thumb:SetColorTexture(1, 0.82, 0, 0.35)
	thumb:Hide()

	local function update()
		local view, total = scroll:GetHeight() or 0, content:GetHeight() or 0
		if total <= view + 1 or view <= 0 then
			thumb:Hide()
			return
		end
		local h = math.max(20, view * view / total)
		local y = (scroll:GetVerticalScroll() or 0) / (total - view) * (view - h)
		thumb:ClearAllPoints()
		thumb:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 8, -y)
		thumb:SetHeight(h)
		thumb:Show()
	end

	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local max = math.max(0, (content:GetHeight() or 0) - (self:GetHeight() or 0))
		local v = math.min(max, math.max(0, (self:GetVerticalScroll() or 0) - delta * 40))
		self:SetVerticalScroll(v)
		update()
	end)
	scroll:SetScript("OnSizeChanged", function(_, w)
		content:SetWidth(w)
		update()
	end)
	scroll.UpdateThumb = update
	return scroll, content
end

function Widgets.Version()
	local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
	local v = get and get(addonName, "Version")
	if not v or v:find("@") then return "dev" end
	return v
end
