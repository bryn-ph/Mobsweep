"""Load the addon in TOC order against a mocked WoW API and exercise the main paths: building the target
list from the quest log (with and without QuestieDB), fitting and writing the macro, combat deferral,
the window and the slash commands."""
import pathlib, sys
from lupa import lua51

root = pathlib.Path(__file__).resolve().parents[1]
addon = root / "Tagger"
lua = lua51.LuaRuntime(unpack_returned_tuples=True)


MOCK = r"""
local printed = {}
__printed = printed
function print(...)
  local t = {}
  for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
  printed[#printed + 1] = table.concat(t, " ")
end
local now = 1000
function GetTime() return now end

-- Timers run when __flush() is called, in due-time order.
local timers = {}
C_Timer = { After = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end }
__tickers = 0
C_Timer.NewTicker = function(_, fn)
  __tickers = __tickers + 1
  return { Cancel = function() __tickers = __tickers - 1 end }
end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function __flush(seconds)
  local stop = now + (seconds or 1000)
  while true do
    table.sort(timers, function(a, b) return a.at < b.at end)
    local t = timers[1]
    if not t or t.at > stop then break end
    table.remove(timers, 1)
    if t.at > now then now = t.at end
    t.fn()
  end
  if now < stop then now = stop end
end

-- Frames: any unknown method is a no-op returning nil; a few track state.
local Obj = {}
local function newObj(kind)
  return setmetatable({ __kind = kind, __shown = true, __scripts = {}, __text = "" }, Obj)
end
Obj.__index = function(self, key)
  local m = rawget(Obj, key)
  if m then return m end
  if type(key) == "string" and key:match("^Create") then
    return function() return newObj(key) end
  end
  if type(key) == "string" and key:match("^%u") then
    return function() return nil end
  end
end
function Obj:Show() self.__shown = true; local f = self.__scripts.OnShow; if f then f(self) end end
function Obj:Hide() self.__shown = false; local f = self.__scripts.OnHide; if f then f(self) end end
function Obj:SetShown(v) if v then self:Show() else self:Hide() end end
function Obj:IsShown() return self.__shown end
function Obj:SetScript(name, fn) self.__scripts[name] = fn end
function Obj:HookScript(name, fn) self.__scripts[name] = fn end
function Obj:SetText(t) self.__text = t end
function Obj:GetText() return self.__text end
function Obj:SetTextColor(r, g, b) self.__color = { r, g, b } end
function Obj:CreateTexture() return newObj("Texture") end
function Obj:CreateFontString() return newObj("FontString") end
function Obj:GetHeight() return 0 end
function Obj:GetWidth() return 0 end
function Obj:GetVerticalScroll() return 0 end
function Obj:SetChecked(v) self.__checked = v end
function Obj:GetChecked() return self.__checked end
function Obj:Click(button) local f = self.__scripts.OnClick; if f then f(self, button or "LeftButton") end end
function Obj:SetAttribute(k, v) self.__attrs = self.__attrs or {}; self.__attrs[k] = v end
function Obj:GetAttribute(k) return self.__attrs and self.__attrs[k] end
function Obj:SetTexture(t) self.__texture = t end
function Obj:SetDesaturated(v) self.__desat = v end
function Obj:SetBackdropColor(r, g, b, a) self.__bg = { r, g, b, a } end
function Obj:SetBackdropBorderColor(r, g, b, a) self.__edge = { r, g, b, a } end

__frames = {}
function CreateFrame(kind, name, parent, template)
  local o = newObj(kind)
  o.__template = template
  if template and template:find("ButtonFrameTemplate") then o.__shown = false end
  if name then _G[name] = o end
  __frames[#__frames + 1] = o
  return o
end
UIParent = newObj("Frame")
Minimap = newObj("Minimap")
function GetCursorPosition() return 0, 0 end
UISpecialFrames = {}
SlashCmdList = {}
GameTooltip = newObj("GameTooltip")
function geterrorhandler() return function(e) error(e, 0) end end
RAID_TARGET_8 = "Skull"
QUEST_MONSTERS_KILLED = "%s slain: %d/%d"

-- Units the scanner can see: token -> { name, guid, dead, player, friendly, mark }
__units = {}
__plates = {}
C_NamePlate = { GetNamePlates = function()
  local t = {}
  for _, token in ipairs(__plates) do t[#t + 1] = { namePlateUnitToken = token } end
  return t
end }
function UnitExists(u) return __units[u] ~= nil end
function UnitIsDead(u) return __units[u] and __units[u].dead or false end
function UnitIsPlayer(u) return __units[u] and __units[u].player or false end
function UnitCanAttack(_, u) return __units[u] ~= nil and not __units[u].friendly end
function UnitName(u) return __units[u] and __units[u].name end
function UnitGUID(u) return __units[u] and __units[u].guid end
function GetRaidTargetIndex(u) return __units[u] and __units[u].mark end
__cvars = { nameplateShowEnemies = "1" }
function GetCVar(k) return __cvars[k] end
__alerts = {}
UIErrorsFrame = { AddMessage = function(_, text) __alerts[#__alerts + 1] = text end }
__sounds = 0
SOUNDKIT = { MAP_PING = 3175 }
function PlaySound(id) __sounds = __sounds + 1; __lastSound = id end

-- Key bindings
__bindings = {}
function GetBindingKey(cmd)
  local keys = {}
  for k, c in pairs(__bindings) do if c == cmd then keys[#keys + 1] = k end end
  table.sort(keys)
  return keys[1], keys[2]
end
function GetBindingAction(key) return __bindings[key] or "" end
function SetBinding(key, cmd) __bindings[key] = cmd; return true end
function GetBindingText(key) return key end
function GetCurrentBindingSet() return 1 end
__saved = 0
function SaveBindings() __saved = __saved + 1 end
function IsAltKeyDown() return false end
function IsControlKeyDown() return false end
function IsShiftKeyDown() return __shift end

-- Combat
__combat = false
function InCombatLockdown() return __combat end

-- Macros
__macros = {}
__numChar = 0
MAX_ACCOUNT_MACROS, MAX_CHARACTER_MACROS = 120, 18
function GetNumMacros() return 0, __numChar end
function GetMacroIndexByName(name)
  for i, m in ipairs(__macros) do if m.name == name then return i end end
  return 0
end
function GetMacroInfo(i) local m = __macros[i]; if m then return m.name, m.icon, m.body end end
function CreateMacro(name, icon, body, perChar)
  assert(not __combat, "CreateMacro in combat")
  assert(#body <= 255, "macro body too long: " .. #body)
  __macros[#__macros + 1] = { name = name, icon = icon, body = body, perChar = perChar }
  __numChar = __numChar + (perChar and 1 or 0)
  return #__macros
end
__edits = 0
function EditMacro(i, name, icon, body)
  assert(not __combat, "EditMacro in combat")
  assert(#body <= 255, "macro body too long: " .. #body)
  __edits = __edits + 1
  __macros[i].body = body
end
function PickupMacro(name) __picked = name end

-- Zones: area 12 is Elwynn Forest, 40 is Westfall.
__zone = "Elwynn Forest"
function GetRealZoneText() return __zone end
C_Map = { GetAreaInfo = function(id) return ({ [12] = "Elwynn Forest", [40] = "Westfall" })[id] end }

-- Quest log
__quests = {}
__watched = {}
__super = 0
C_QuestLog = {
  GetNumQuestLogEntries = function() return #__quests end,
  GetInfo = function(i) return __quests[i] end,
  IsComplete = function(id) for _, q in ipairs(__quests) do if q.questID == id then return q.complete end end end,
  GetQuestWatchType = function(id) if __watched[id] then return 0 end end,
  GetQuestObjectives = function(id) for _, q in ipairs(__quests) do if q.questID == id then return q.objectives end end end,
  GetNumQuestWatches = function() return #__watchOrder end,
  GetQuestIDForQuestWatchIndex = function(i) return __watchOrder[i] end,
}
__watchOrder = {}
C_SuperTrack = { GetSuperTrackedQuestID = function() return __super end }

-- LibQuestieDB (only some tests turn it on)
local npcs = {
  [1] = { name = "Kobold Vermin", spawns = { [12] = {} } },
  [2] = { name = "Kobold Worker", spawns = { [12] = {} } },
  [3] = { name = "Defias Bandit", spawns = { [40] = {} } },
  [4] = { name = "Young Wolf", spawns = { [12] = {} } },
  [5] = { name = "Prowler", spawns = { [12] = {} } },
}
local items = { [100] = { name = "Gold Dust", npcDrops = { 2, 3 } }, [101] = { name = "Wolf Meat", npcDrops = { 4, 5 } } }
local quests = {
  [10] = { objectives = { { { 1, nil, 10 } } } },
  [11] = { objectives = { nil, nil, { { 100, nil, 10 } } } },
  [12] = { objectives = { nil, nil, { { 101, nil, 8 } } } },
}
__QuestieDB = {
  RequireContract = function(n) return n <= 4 end,
  Quest = { Get = function(id, key) local q = quests[id]; return q and q[key] end },
  Npc = { Get = function(id, key) local n = npcs[id]; return n and n[key] end },
  Item = { Get = function(id, key) local n = items[id]; return n and n[key] end },
}
"""

lua.execute(MOCK)
toc = (addon / "Tagger.toc").read_text(encoding="utf-8")
files = [l.strip() for l in toc.splitlines() if l.strip() and not l.startswith("#")]
ns = lua.eval("{}")
for f in files:
    path = addon / f.replace("\\", "/")
    chunk = lua.eval("function(src, name) return assert(loadstring(src, name)) end")(path.read_text(encoding="utf-8"), "@" + f)
    chunk("Tagger", ns)

run = lua.eval(r"""function(ns)
  local ef = __frames[1]
  local function fire(event, ...) ef.__scripts.OnEvent(ef, event, ...) end
  local function body() local m = __macros[GetMacroIndexByName("Tagger")]; return m and m.body end
  local function printedSince(n, pattern)
    for i = n + 1, #__printed do if __printed[i]:find(pattern, 1, true) then return true end end
  end
  local function names()
    local t = {}
    for _, x in ipairs(ns.Macro.Current()) do t[#t + 1] = x.name end
    return table.concat(t, ",")
  end
  local function settle() __flush(1) end
  local TAIL = "\n/cleartarget [dead]\n/tm [harm,nodead] !8"

  TaggerDB = { settings = { enabled = false, announce = true, trackedOnly = true, marker = 8, alertSound = false } } -- from an older version
  fire("ADDON_LOADED", "Tagger")
  assert(ns.settings.enabled == nil and ns.settings.announce == nil and ns.settings.trackedOnly == nil, "old settings dropped")
  assert(ns.settings.alertSound == "none" and ns.settings.panelStyle == "full", "sound off carried over; full panel")
  ns.settings.alertSound = "ping"
  fire("PLAYER_LOGIN")
  assert(ns.settings.marker == 8 and not ns.settings.tracking, "settings loaded")
  local button, panel = _G.TaggerTrackerButton, _G.TaggerTracker
  assert(button and button.__template == "SecureActionButtonTemplate" and button:GetAttribute("type") == "macro", "secure button")
  assert(panel:IsShown(), "Tracking panel shown")

  -- Objective text parsing, both formats.
  assert(ns.Targets.NameFromObjective("Kobold Vermin slain: 3/10") == "Kobold Vermin", "classic format")
  assert(ns.Targets.NameFromObjective("3/10 Kobold Vermin slain") == "Kobold Vermin", "retail format")
  assert(ns.Targets.NameFromObjective("Kill Hogger") == "Kill Hogger", "no counts")

  -- Nothing is written before the first loading screen settles (macros may not be loaded yet).
  __quests = {
    { questID = 10, title = "Kobold Camp Cleanup", objectives = { { text = "Kobold Vermin slain: 2/10", type = "monster", finished = false } } },
    { questID = 11, title = "Gold Dust Exchange", objectives = { { text = "Gold Dust: 0/10", type = "item", finished = false } } },
    { questID = 12, title = "Wolves Across the Border", objectives = { { text = "Wolf Meat: 0/8", type = "item", finished = false } } },
  }
  fire("QUEST_LOG_UPDATE")
  settle()
  assert(#__macros == 0, "no macro before the world loads")
  fire("PLAYER_ENTERING_WORLD")
  __flush(3)

  -- Nothing tracked: no quest, empty macro.
  assert(ns.Macro.Quest() == nil and body() == ns.Macro.EMPTY, "nothing tracked")
  assert(__macros[1].perChar, "macro made per character")

  -- A tracked quest, without QuestieDB: its kill objectives, from the log text.
  __watched[10] = true
  __watchOrder = { 10 }
  fire("QUEST_WATCH_LIST_CHANGED")
  settle()
  assert(ns.Macro.Quest().id == 10, "the tracked quest")
  assert(body() == "/cleartarget\n/targetexact Kobold Vermin" .. TAIL, "kill-only body: " .. tostring(body()))
  assert(button:GetAttribute("macrotext") == body(), "button runs the same text")

  -- The focused quest wins, and with QuestieDB its loot drops count; this zone first, most wanted last.
  LibQuestieDB = __QuestieDB
  __super = 11
  fire("SUPER_TRACKING_CHANGED")
  settle()
  assert(ns.Macro.Quest().id == 11, "focused quest")
  assert(names() == "Kobold Worker,Defias Bandit", "only the focused quest's mobs: " .. names())
  assert(ns.Macro.Current()[1].kind == "loot" and ns.Macro.Current()[2].here == false, "kinds and zones")
  assert(body() == "/cleartarget\n/targetexact Defias Bandit\n/targetexact Kobold Worker" .. TAIL, "body: " .. body())

  -- No focus: the first unfinished quest in tracker order.
  __super = 0
  __watched[12] = true
  __watchOrder = { 12, 10 }
  __quests[3].complete = true
  fire("SUPER_TRACKING_CHANGED")
  settle()
  assert(ns.Macro.Quest().id == 10 and names() == "Kobold Vermin", "skips the finished tracked quest")
  __quests[3].complete = false
  fire("QUEST_LOG_UPDATE")
  settle()
  assert(ns.Macro.Quest().id == 12 and names() == "Young Wolf,Prowler", "tracker order: " .. names())

  -- A focused quest that's complete has nothing left.
  __super = 11
  __quests[2].complete = true
  fire("QUEST_LOG_UPDATE")
  settle()
  assert(ns.Macro.Quest().id == 11 and body() == ns.Macro.EMPTY, "complete focused quest: " .. body())
  __quests[2].complete = false

  -- Finished objectives drop out.
  __quests[2].objectives[1].finished = true
  fire("QUEST_LOG_UPDATE")
  settle()
  assert(body() == ns.Macro.EMPTY, "finished objective")
  __quests[2].objectives[1].finished = false

  -- Combat: the edit waits until it ends, for the macro and the button alike.
  __combat = true
  fire("QUEST_LOG_UPDATE")
  settle()
  assert(body() == ns.Macro.EMPTY and button:GetAttribute("macrotext") == ns.Macro.EMPTY, "no edits in combat")
  __combat = false
  fire("PLAYER_REGEN_ENABLED")
  settle()
  assert(body():find("Kobold Worker", 1, true) and button:GetAttribute("macrotext") == body(), "edited after combat")

  -- No needless edits.
  local edits = __edits
  fire("QUEST_LOG_UPDATE")
  settle()
  assert(__edits == edits, "unchanged list doesn't rewrite the macro")

  -- Marker choice and off.
  SlashCmdList.TAGGER("mark 7")
  assert(body():find("!7$"), "cross marker")
  SlashCmdList.TAGGER("mark off")
  assert(not body():find("/tm", 1, true) and body():find("/cleartarget [dead]", 1, true), "no marking")
  SlashCmdList.TAGGER("mark 8")

  -- Fitting: long lists are cut to 255 characters, best first and last.
  local list = {}
  for i = 1, 20 do list[i] = { name = ("Mob Number %02d With A Long Name"):format(i) } end
  local b, count = ns.Macro.Body(list, 8)
  assert(#b <= 255 and count > 0 and count < 20, "fits: " .. #b .. " chars, " .. count .. " mobs")
  assert(list[1].inMacro and not list[20].inMacro, "best ones kept")
  assert(b:match("^/cleartarget\n"), "clears the old target first")
  assert(b:match("([^\n]*)\n/cleartarget %[dead%]") == "/targetexact " .. list[1].name, "the best is last")

  -- Tracking: nameplates, alerts, glow, the marked alert.
  __cvars.nameplateShowEnemies = "0"
  local before = #__printed
  __units = {
    nameplate1 = { name = "Kobold Worker", guid = "g1" },
    nameplate2 = { name = "Hogger", guid = "g2" },
    nameplate3 = { name = "Defias Bandit", guid = "g3", friendly = true },
  }
  __plates = { "nameplate1", "nameplate2", "nameplate3" }
  SlashCmdList.TAGGER("track")
  assert(ns.settings.tracking and __tickers == 1, "tracking ticks")
  assert(printedSince(before, "nameplates are off"), "warns about nameplates")
  local st = ns.Scanner.State()
  assert(st.found == "Kobold Worker" and not st.marked, "found the quest mob, not the others")
  assert(__alerts[#__alerts] == "Kobold Worker nearby" and __sounds == 1 and __lastSound == 3175, "nearby alert with a ping")
  assert(button.glow:IsShown(), "button glows")
  local alerts = #__alerts
  ns.Scanner.Scan()
  assert(#__alerts == alerts, "no repeat while it stays in view")
  __units.nameplate1.mark = 8
  fire("RAID_TARGET_UPDATE")
  assert(__alerts[#__alerts]:find("^Kobold Worker marked") and __sounds == 1, "quiet marked alert")
  assert(ns.Scanner.State().marked and not button.glow:IsShown() and button.marker:IsShown(), "marked: no glow, marker badge")
  alerts = #__alerts
  ns.Scanner.Scan()
  assert(#__alerts == alerts, "marked alert once per mob")
  __units.nameplate1.dead = true
  ns.Scanner.Scan()
  assert(ns.Scanner.State().found == nil and not button.glow:IsShown(), "dead mobs don't count")
  __units.nameplate1 = { name = "Kobold Worker", guid = "g4" }
  ns.Scanner.Scan()
  assert(ns.Scanner.State().found == "Kobold Worker" and #__alerts == alerts, "seen again within 30s: no new alert")
  ns.settings.alertSound = "none"
  __units.nameplate1 = nil
  __flush(40)
  ns.Scanner.Scan()
  __units.nameplate1 = { name = "Kobold Worker", guid = "g5" }
  ns.Scanner.Scan()
  assert(#__alerts == alerts + 1 and __sounds == 1, "alerts again after a while; sound off")
  ns.settings.alertSound = "ping"

  -- Minimal panel: just the button. Hovering it fades in a card with the full panel's information.
  local toggleBox
  for _, f in ipairs(__frames) do
    if f.label and f.label:GetText() == "Tracking" then toggleBox = f end
  end
  SlashCmdList.TAGGER("style")
  assert(ns.settings.panelStyle == "minimal" and not toggleBox:IsShown(), "minimal hides the toggle")
  assert(panel.__bg[4] == 0 and panel.__edge[4] == 0, "no box")
  button.__scripts.OnEnter(button)
  local card = _G.TaggerTrackerCard
  assert(card and card:IsShown(), "hover opens the card")
  assert(card.state:GetText() == "On" and card.status:GetText() == "Kobold Worker nearby", "card: " .. card.status:GetText())
  assert(card.quest:GetText() == "Gold Dust Exchange", "card names the quest")
  __units.nameplate1 = nil
  ns.Scanner.Scan()
  assert(card.status:GetText() == "Searching..." and not button.glow:IsShown(), "open card follows the scan")
  button:tracking()
  assert(card.state:GetText() == "Off" and card.status:GetText() == "Off", "and Tracking off")
  button:tracking()
  button.__scripts.OnLeave(button)
  assert(not card:IsShown(), "closes when the mouse leaves")
  __units.nameplate1 = { name = "Kobold Worker", guid = "g6" }
  ns.Scanner.Scan()

  -- Dragging the button moves the panel (not in combat) and saves where it went.
  local moved = 0
  panel.StartMoving = function() moved = moved + 1 end
  panel.GetPoint = function() return "TOPLEFT", UIParent, "TOPLEFT", 40, -60 end
  button.__scripts.OnEnter(button)
  button.__scripts.OnDragStart(button)
  assert(moved == 1 and not card:IsShown(), "drag moves it and closes the card")
  button.__scripts.OnDragStop(button)
  assert(ns.settings.buttonPosition[1] == "TOPLEFT" and ns.settings.buttonPosition[4] == -60, "position saved")
  __combat = true
  button.__scripts.OnDragStart(button)
  assert(moved == 1, "can't move in combat")
  __combat = false
  panel.StartMoving, panel.GetPoint = nil, nil
  ns.TrackerButton.ResetPosition()

  __combat = true
  SlashCmdList.TAGGER("style")
  assert(not toggleBox:IsShown(), "style waits for combat to end")
  __combat = false
  fire("PLAYER_REGEN_ENABLED")
  assert(ns.settings.panelStyle == "full" and toggleBox:IsShown() and panel.__bg[4] > 0, "full again")
  button.__scripts.OnEnter(button)
  assert(not card:IsShown(), "full has no card")
  button.__scripts.OnLeave(button)

  -- Right-clicking the Tag button (its custom "tracking" type) toggles Tracking.
  assert(button:GetAttribute("type2") == "tracking", "right-click type")
  button:tracking()
  assert(not ns.settings.tracking and button.icon.__desat, "off; icon greyed")
  button:tracking()
  assert(ns.settings.tracking and not button.icon.__desat, "on again")

  -- Minimap right-click and the binding toggle Tracking.
  _G.TaggerMinimapButton.__scripts.OnClick(_G.TaggerMinimapButton, "RightButton")
  assert(not ns.settings.tracking and __tickers == 0 and not ns.Scanner.State().tracking, "right-click stops tracking")
  Tagger_ToggleTracking()
  assert(ns.settings.tracking and __tickers == 1, "binding starts it")
  Tagger_ToggleTracking()

  -- The panel can't be hidden in combat.
  __combat = true
  SlashCmdList.TAGGER("button")
  assert(panel:IsShown(), "panel waits for combat to end")
  __combat = false
  fire("PLAYER_REGEN_ENABLED")
  assert(not panel:IsShown(), "then hides")
  SlashCmdList.TAGGER("button")
  assert(panel:IsShown(), "and comes back")

  -- Deleted in /macro: made again on the next change.
  __macros = {}
  __numChar = 0
  fire("UPDATE_MACROS")
  fire("QUEST_LOG_UPDATE")
  settle()
  assert(#__macros == 1, "macro made again")

  -- No room anywhere: one warning, no error, and the button still works.
  __macros = {}
  local oldNum = GetNumMacros
  GetNumMacros = function() return 120, 18 end
  fire("UPDATE_MACROS")
  before = #__printed
  ns.Macro.Refresh()
  assert(#__macros == 0 and printedSince(before, "macros are full"), "full macros warn")
  assert(button:GetAttribute("macrotext"):find("/targetexact", 1, true), "button doesn't need a macro slot")
  GetNumMacros = oldNum
  __numChar = 18
  ns.Macro.Refresh()
  assert(#__macros == 1 and not __macros[1].perChar, "falls back to an account macro")

  -- Window.
  SlashCmdList.TAGGER("")
  assert(_G.TaggerWindow:IsShown(), "window opens")
  local shown = 0
  for _, f in ipairs(__frames) do
    if f.name and f.quest and f:IsShown() then shown = shown + 1 end
  end
  assert(shown == #ns.Macro.Current() and shown > 0, "a row per target")
  -- Alert sound dropdown: lists the sounds, picking one saves and plays it.
  local sound = _G.TaggerWindow.sound
  assert(sound.Text:GetText() == "Map ping", "shows the current sound")
  sound:Click()
  local menu = _G.TaggerMenu
  assert(menu:IsShown(), "menu opens")
  local pick
  for _, row in ipairs(menu.rows) do
    if row:IsShown() and row.text:GetText() == "Raid warning" then pick = row end
  end
  assert(pick and #menu.rows == #ns.SOUNDS, "a row per sound")
  pick:Click()
  assert(ns.settings.alertSound == "raidwarning" and __lastSound == 8959 and not menu:IsShown(), "picked, previewed, closed")
  assert(sound.Text:GetText() == "Raid warning", "shows the new sound")
  sound:Click()
  sound:Click()
  assert(not menu:IsShown(), "second click closes it")
  sound:Click()
  _G.TaggerWindow:Hide()
  assert(not menu:IsShown(), "closing the window closes the menu")
  SlashCmdList.TAGGER("")
  _G.TaggerWindow.style.buttons[2]:Click()
  assert(ns.settings.panelStyle == "minimal", "style from the window")
  _G.TaggerWindow.style.buttons[1]:Click()

  -- The Tag key: click, press a key; Esc cancels; right-click clears; a key's old action is reported.
  local bind = _G.TaggerWindow.bind
  assert(bind:GetText():find("Not bound", 1, true), "starts unbound")
  bind:Click()
  assert(bind.capturing and bind:GetText() == "Press a key...", "capturing")
  bind.__scripts.OnKeyDown(bind, "LSHIFT")
  assert(bind.capturing, "modifiers alone don't bind")
  __shift = true
  __bindings["SHIFT-F"] = "TOGGLEAUTORUN"
  before = #__printed
  bind.__scripts.OnKeyDown(bind, "F")
  __shift = false
  assert(__bindings["SHIFT-F"] == ns.TAG_BINDING and __saved == 1 and not bind.capturing, "bound and saved")
  assert(bind:GetText() == "SHIFT-F" and bind.__scripts.OnKeyDown == nil, "shows the key, stops listening")
  assert(printedSince(before, "TOGGLEAUTORUN"), "says what the key did before")
  bind:Click()
  bind.__scripts.OnKeyDown(bind, "G")
  assert(__bindings["G"] == ns.TAG_BINDING and __bindings["SHIFT-F"] == nil, "a new key replaces the old one")
  bind:Click()
  bind.__scripts.OnKeyDown(bind, "ESCAPE")
  assert(__bindings["G"] == ns.TAG_BINDING and not bind.capturing, "Esc cancels")
  bind:Click("RightButton")
  assert(GetBindingKey(ns.TAG_BINDING) == nil and bind:GetText():find("Not bound", 1, true), "right-click clears")
  __combat = true
  bind:Click()
  assert(not bind.capturing, "not in combat")
  __combat = false
  bind:Click()
  _G.TaggerWindow:Hide()
  assert(not bind.capturing, "closing the window stops capturing")
  SlashCmdList.TAGGER("")

  SlashCmdList.TAGGER("pickup")
  assert(__picked == "Tagger", "pickup puts the macro on the cursor")
  SlashCmdList.TAGGER("minimap")
  assert(not _G.TaggerMinimapButton:IsShown(), "/tagger minimap hides it")
  SlashCmdList.TAGGER("list")
  SlashCmdList.TAGGER("help")
  SlashCmdList.TAGGER("reset")
  assert(ns.settings.minimapShow and ns.settings.showButton and not ns.settings.tracking, "reset restores defaults")
end""")

try:
    run(ns)
except Exception as e:
    print("FAIL", e)
    sys.exit(1)
print("Smoke test passed")
