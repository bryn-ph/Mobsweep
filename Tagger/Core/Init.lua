local addonName, ns = ...

ns.name = addonName
ns.debug = false

function ns.Print(...)
	print("|cffffd100Tagger|r", ...)
end

function ns.Debug(...)
	if ns.debug then
		print("|cff888888Tagger debug|r", ...)
	end
end

-- Midnight-style secret values (unit names and markers in instances): can be passed along but not
-- compared, indexed or concatenated.
function ns.IsSecret(value)
	return issecretvalue ~= nil and issecretvalue(value) == true
end

-- Key Bindings > AddOns (Bindings.xml).
BINDING_HEADER_TAGGER = "Tagger"
_G["BINDING_NAME_CLICK TaggerTrackerButton:LeftButton"] = "Tag quest mob"
BINDING_NAME_TAGGER_TOGGLE_TRACKING = "Tracking on/off"

-- Game events -----------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		eventFrame:RegisterEvent(event)
	end
	table.insert(handlers[event], fn)
end

function ns.Off(event)
	handlers[event] = nil
	eventFrame:UnregisterEvent(event)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	if not list then return end
	for _, fn in ipairs(list) do
		fn(event, ...)
	end
end)

-- Internal messages -------------------------------------------------------------
--   TARGETS_CHANGED(list)   the macro was rebuilt; list is Macro.Current()
--   SCAN_UPDATE(state)      Tracking looked around; state is Scanner.State()

local listeners = {}

function ns.Listen(message, fn)
	listeners[message] = listeners[message] or {}
	table.insert(listeners[message], fn)
end

function ns.Fire(message, ...)
	local list = listeners[message]
	if not list then return end
	for _, fn in ipairs(list) do
		local ok, err = pcall(fn, ...)
		if not ok then
			geterrorhandler()(err)
		end
	end
end

-- Startup -------------------------------------------------------------------------

ns.On("ADDON_LOADED", function(_, name)
	if name ~= addonName then return end
	ns.Off("ADDON_LOADED")
	ns.DB.Init()
	ns.Window.Register()
	ns.MinimapButton.Init()
	ns.TrackerButton.Init()
	ns.Macro.Init()
	ns.Scanner.Init()
end)

-- Referenced by the TOC's AddonCompartmentFunc.
function Tagger_OnAddonCompartmentClick()
	ns.Window.Toggle()
end

-- Referenced by Bindings.xml.
function Tagger_ToggleTracking()
	ns.Scanner.SetTracking(not ns.settings.tracking)
end
