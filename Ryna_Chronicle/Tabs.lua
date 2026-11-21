-- Tabs: Chronicle's two tabs in the core's panel (Ryna.Panel.AddTab), Recording and Census, built
-- with the core's widgets (Ryna.Panel.Widgets). The combat-log controls are the core's (its
-- Advanced tab). Recording also has the merchants switch (Merchants.lua), the tooltip line naming
-- the characters that hold an item (Items.lua), the session strip's settings, dungeon runs (Runs.lua:
-- recording them, the live display, the summary on leaving and its damage and healing), and opens
-- Ryna's window (Window.lua; not there with a core too old for it).

local _, ns = ...
if ns.off then return end
local L = ns.L

local W = ns.API.Panel.Widgets
local WIDTH = W.WIDTH
local text, button, checkbox, toggle = W.text, W.button, W.checkbox, W.toggle

-- The live run display's three-way choice: the game's dropdown (11.x Menu API) where the client has
-- it, else a button that steps through the three, as the core's combat-log mode does.
local function displayControl(parent)
  local D = ns.RunDisplay
  local function set(mode) ns.Run("run display", D.SetDisplay, mode) end
  local dd = W.create and W.create("DropdownButton", parent, { "WowStyle1DropdownTemplate" })
  if dd and dd.SetupMenu then
    local ok = pcall(dd.SetupMenu, dd, function(_, root)
      for _, mode in ipairs(D.MODES) do
        root:CreateRadio(D.Label(mode), function(m) return ns.Runs.Display() == m end, set, mode)
      end
    end)
    if ok then
      dd:SetWidth(200)
      function dd.sync() if dd.GenerateMenu then pcall(dd.GenerateMenu, dd) end end
      return dd
    end
    dd:Hide()
  end
  local b = button(parent, nil, 240, 22)
  if not b then return nil end
  b:SetScript("OnClick", function()
    local current = ns.Runs.Display()
    for i, m in ipairs(D.MODES) do
      if m == current then return set(D.MODES[i % #D.MODES + 1]) end
    end
    set(D.MODES[1])
  end)
  function b.sync() b:SetText(string.format(L["%s (click to change)"], D.Label(ns.Runs.Display()))) end
  return b
end

-- The tabs' controls.
local P = {}
P.Refresh = function() ns.API.Panel.Refresh() end

local build, layout = {}, {}

-- Dungeon runs: recording them, the live display, the summary on leaving and its damage and healing.
function build.runs(f)
  P.runsHeader = text(f, "GameFontNormal")
  P.runsHeader:SetText(L["Dungeon runs"])
  P.runs = checkbox(f, L["Record dungeon runs"],
    L["Each time you enter a dungeon or raid: the time inside, experience, kills, bosses, loot and what it "
    .. "was worth, deaths and wear, kept per character for Dungeons in Ryna's window. Needs kills and loot on."])
  toggle(P.runs, "runs", function() ns.RunDisplay.Refresh() end)
  P.runDisplayLabel = text(f, "GameFontHighlight")
  P.runDisplayLabel:SetText(L["While inside, show the run as:"])
  P.runDisplay = displayControl(f)
  P.runDisplayHint = text(f, "GameFontDisableSmall", 10)
  P.runDisplayHint:SetText(L["Drag it where you want it. /ryna runs test shows it with example numbers, to "
    .. "place it outside a dungeon."])
  P.runSummary = checkbox(f, L["Show a summary when I leave"],
    L["Each time you walk out of the instance, the run so far against your earlier runs there. It goes "
    .. "when you go back in."])
  toggle(P.runSummary, "runSummary")
  P.runSummaryMeter = checkbox(f, L["My damage and healing on the summary"],
    L["Your own damage done and healing done over the run, from the game's damage meter."])
  toggle(P.runSummaryMeter, "runSummaryMeter")
end

function build.recording(f)
  P.recordingIntro = text(f, "GameFontHighlightSmall", 11)
  P.recordingIntro:SetText(L["About your own characters, Ryna records their gear, bags and bank, quests, "
    .. "professions, reputations, gold and played time, your guild's roster, and a 30-day journal of what "
    .. "you do. Other players are the Census tab's."])
  P.chronicle = checkbox(f, L["Record kills and loot"],
    L["Counts the creatures you and your group kill, the experience they give and what you loot from them, "
    .. "as running totals on the character (not journal events). Off: nothing is counted, and the totals so "
    .. "far are kept."])
  toggle(P.chronicle, "chronicle")
  P.tooltips = checkbox(f, L["Show my numbers on tooltips"],
    L["Adds your own kills and drops to creature and item tooltips: how many you killed, what they dropped "
    .. "for you and how often."])
  toggle(P.tooltips, "tooltips")
  P.holders = checkbox(f, L["Show which of my characters hold an item"],
    L["One more line on item tooltips naming your other characters that hold it, and how many, in their "
    .. "bags or the bank, from your saved file: \"Alyra: 120 in the bank · Brennic: 34\"."])
  toggle(P.holders, "tooltipHolders")
  P.merchants = checkbox(f, L["Record the merchants I visit"],
    L["When you open a merchant, records what that NPC sells and for how much, once per NPC each time you "
    .. "log in, for vendor prices on ryna.io. Merchants are NPCs: nothing here is about a player."])
  toggle(P.merchants, "merchants")
  -- In game: the session strip (Strip.lua) and Ryna's window (Window.lua).
  P.liveHeader = text(f, "GameFontNormal")
  P.liveHeader:SetText(L["In game"])
  P.strip = checkbox(f, L["Show the session strip"],
    L["One line on screen with this session's kills, experience and money per hour, quests and time. "
    .. "Hover it for more; click it for Ryna's window."])
  toggle(P.strip, "sessionStrip", function() ns.Strip.Apply() end)
  P.stripLock = checkbox(f, L["Lock the strip"],
    L["Unlocked, Shift-drag moves it. Right-clicking the strip locks or unlocks it too."])
  toggle(P.stripLock, "sessionStripLocked", function() ns.Strip.Apply() end)
  P.stripReset = button(f, L["Reset position"], 140, 22)
  if P.stripReset then
    P.stripReset:SetScript("OnClick", function() ns.Run("session strip", ns.Strip.ResetPosition) end)
  end
  -- Dungeon runs (Runs.lua, RunDisplay.lua, RunSummary.lua), when they loaded.
  if ns.Runs and ns.RunDisplay then build.runs(f) end
  if ns.Window and ns.Window.available then
    P.openWindow = button(f, L["Open Ryna's window"], 220, 22)
    if P.openWindow then
      P.openWindow:SetScript("OnClick", function() ns.Run("ryna window", ns.Window.Open) end)
    end
    P.windowHint = text(f, "GameFontDisableSmall", 10)
    P.windowHint:SetText(L["Also /chronicle. Your session, your characters, everything in their bags and banks, "
      .. "your kills with their drops, your loot and your levels."])
  end
end

function layout.recording(s, settings)
  s.text(P.recordingIntro, 0, 12)
  P.chronicle:SetChecked(settings.chronicle)
  P.chronicle.place(s, 4)
  P.tooltips:SetChecked(settings.tooltips)
  P.tooltips.place(s, 4)
  P.holders:SetChecked(settings.tooltipHolders)
  P.holders.setActive(settings.tooltips)
  P.holders.place(s, 30)
  P.merchants:SetChecked(settings.merchants)
  P.merchants.place(s, 4)
  s.text(P.liveHeader, 0, 6)
  P.strip:SetChecked(settings.sessionStrip)
  P.strip.place(s, 4)
  P.stripLock:SetChecked(settings.sessionStripLocked)
  P.stripLock.setActive(settings.sessionStrip)
  P.stripLock.place(s, 30)
  if P.stripReset then s.add(P.stripReset, 22, 8, 8) end
  if P.openWindow then
    P.openWindow:ClearAllPoints()
    if P.stripReset then
      P.openWindow:SetPoint("LEFT", P.stripReset, "RIGHT", 8, 0)
    else
      s.add(P.openWindow, 22, 8, 8)
    end
  end
  if P.windowHint then s.text(P.windowHint, 8, 6) end
  if P.runs then layout.runs(s, settings) end
end

function layout.runs(s, settings)
  s.text(P.runsHeader, 0, 6)
  P.runs:SetChecked(settings.runs)
  P.runs.setActive(settings.chronicle)
  P.runs.place(s, 4)
  local recording = settings.chronicle and settings.runs and true or false
  P.runDisplayLabel:SetAlpha(recording and 1 or 0.5)
  s.text(P.runDisplayLabel, 30, 4)
  if P.runDisplay then
    P.runDisplay.sync()
    if recording then P.runDisplay:Enable() else P.runDisplay:Disable() end
    s.add(P.runDisplay, 22, 30, 4)
  end
  s.text(P.runDisplayHint, 30, 8)
  P.runSummary:SetChecked(settings.runSummary)
  P.runSummary.setActive(recording)
  P.runSummary.place(s, 30)
  P.runSummaryMeter:SetChecked(settings.runSummaryMeter)
  P.runSummaryMeter.setActive(recording and settings.runSummary)
  P.runSummaryMeter.place(s, 56)
end

function build.census(f)
  P.censusIntro = text(f, "GameFontHighlightSmall", 11)
  P.censusIntro:SetText(L["Ryna never sends /who itself. When you type /who, the results are recorded as "
    .. "sightings, like players you see on nameplates or in chat."])
  P.census = checkbox(f, L["Take part in the census"],
    L["Records other players you see (nearby, in chat, your group and your guild). "
    .. "Off: Ryna records only your own characters."])
  P.chat = checkbox(f, L["Record who I see in chat"],
    L["Only who spoke, never what they said or in which channel."])
  P.group = checkbox(f, L["Record other players in my group"],
    L["Who was in your groups."])
  P.nearby = checkbox(f, L["Record players I see nearby"],
    L["Players whose nameplates, target or mouseover you see: their level, class and guild, and where."])
  P.nameplateHint = text(f, "GameFontDisableSmall", 10)
  P.nameplateHint:SetWidth(WIDTH - 100)
  P.nameplateHint:SetText(L["The game shows nameplates for enemies only unless friendly nameplates are on "
    .. "(Shift+V). Ryna only sees nameplates the game draws."])
  -- Sets the game's nameplateShowFriends only when clicked; the addon never changes it by itself.
  P.friendly = button(f, L["Turn friendly nameplates on"], 240, 22)
  if P.friendly then
    P.friendly:SetScript("OnClick", function()
      ns.Run("friendly nameplates", function()
        ns.Sightings.ShowFriendlyNameplates()
        P.Refresh()
      end)
    end)
  end
  toggle(P.census, "census")
  toggle(P.chat, "chatSightings")
  toggle(P.group, "groupMembers")
  toggle(P.nearby, "nearbyPlayers")
  P.privacy = text(f, "GameFontDisableSmall", 10)
  P.privacy:SetText(L["The census keeps who was seen, never what they said. "
    .. "Its data is never sold or used for advertising."])
end

function layout.census(s, settings)
  s.text(P.censusIntro, 0, 12)
  P.census:SetChecked(settings.census)
  P.chat:SetChecked(settings.chatSightings)
  P.group:SetChecked(settings.groupMembers)
  P.nearby:SetChecked(settings.nearbyPlayers)
  P.census.place(s, 4)
  for _, cb in ipairs({ P.chat, P.group, P.nearby }) do
    cb.setActive(settings.census)
    cb.place(s, 30)
    if cb == P.nearby then
      P.nameplateHint:SetAlpha(settings.census and 1 or 0.5)
      s.text(P.nameplateHint, 60, 4)
      if P.friendly then
        local on = ns.Sightings.FriendlyNameplatesOn()
        P.friendly:SetText(on and L["Friendly nameplates are on"] or L["Turn friendly nameplates on"])
        if settings.census and not on then P.friendly:Enable() else P.friendly:Disable() end
        s.add(P.friendly, 22, 60, 12)
      end
    end
  end
  s.text(P.privacy, 4, 6)
end

ns.API.Panel.AddTab({ key = "recording", label = L["Recording"], order = 20,
  build = build.recording, layout = layout.recording })
ns.API.Panel.AddTab({ key = "census", label = L["Census"], order = 30, build = build.census, layout = layout.census })
