-- RunDisplay: the live dungeon run on screen, as a strip or a card, the player's choice (runDisplay,
-- Runs.Display(); ryna_agent docs/ryna-agent-cores-mods.md 7.7 "In game"). Shown only while a run is
-- open, a paused one included (in its paused state); never outside a run.
--
--   strip  one thin bar: the dungeon, the timer, experience an hour, kills, bosses and worth so far
--          (at the level cap, bosses, drops and worth); outside, the timer stops and the bar says how
--          long the run waits. Hovering it shows the card's detail as a tooltip.
--   card   the same, larger: the experience bar, the run's numbers and each boss's split against the
--          fastest run here, with the items rolled for under the boss that dropped them and who won each.
--
-- One frame (RynaChronicleRun), dragged with the left button, held by its top left corner so the card
-- grows downwards, its place kept in RynaDB.settings.runDisplayPos { x, y } (the corner, from the
-- screen's bottom left). The words are RunView.lua's; this file only draws them. The timer ticks once a
-- second while it is shown (an OnUpdate, throttled); everything else is read again when Runs.lua says
-- something changed. /ryna runs test shows it with example numbers, to place it outside a dungeon.
-- Every frame call is made under pcall: a client without one leaves the display absent, never an error.

local _, ns = ...
if ns.off then return end
local L = ns.L

local D = {}
ns.RunDisplay = D

local V = ns.RunView
local CARD_W = 260
local PAD = 6
local LINE = 15
local BAR_H = 14
local MAX_LINES = 40
local GOLD = { 1, 0.82, 0 }
local DIM = { 0.62, 0.62, 0.62 }
local EDGE = { 0.23, 0.21, 0.28 }

-- A setting as it is stored (the core's Settings.Get answers booleans only).
function D.SettingValue(key)
  local all = ns.API.Settings.All and ns.API.Settings.All()
  if type(all) == "table" then return all[key] end
  return nil
end

-- What the client says --------------------------------------------------------------------------

local function plainNum(v)
  if v == nil or ns.IsSecret(v) or type(v) ~= "number" then return nil end
  return v
end

-- The character's experience now: { cur, max, level }, or nil.
function D.Xp()
  local cur = plainNum(ns.Try(ns.Fn("UnitXP"), "player"))
  local max = plainNum(ns.Try(ns.Fn("UnitXPMax"), "player"))
  local level = plainNum(ns.Try(ns.Fn("UnitLevel"), "player"))
  if not cur or not max then return nil end
  return { cur = cur, max = max, level = level or 0 }
end

-- Whether no experience can be had: the level cap (GetMaxPlayerLevel, else MAX_PLAYER_LEVEL).
function D.Capped()
  local level = plainNum(ns.Try(ns.Fn("UnitLevel"), "player"))
  local max = plainNum(ns.Try(ns.Fn("GetMaxPlayerLevel")))
  if not max then max = plainNum(_G.MAX_PLAYER_LEVEL) end
  return V.Capped(level, max, plainNum(ns.Try(ns.Fn("UnitXPMax"), "player")))
end

-- The fastest earlier run of a run's dungeon, from the list (for the names of the bosses to come).
function D.FastestRun(cmp)
  local id = type(cmp) == "table" and type(cmp.fastest) == "table" and cmp.fastest.id
  if not id then return nil end
  for _, r in ipairs(ns.Runs.List()) do
    if r.id == id then return r end
  end
  return nil
end

-- What it shows: the example while placing it, else the open run (nil: nothing to show).
local function source()
  if D.example then return D.example.view, D.example.mode end
  if not ns.Runs.On() then return nil end
  local mode = ns.Runs.Display()
  if mode == "off" then return nil end
  return ns.Runs.Current(), mode
end

function D.CardModel(view)
  if D.example then return D.example.card end
  local cmp = ns.Runs.Compare(view)
  return V.Card(view, { capped = D.Capped(), xp = D.Xp(), compare = cmp, fastestRun = D.FastestRun(cmp),
    itemInfo = ns.RunSummary and ns.RunSummary.ItemInfo })
end

-- The frame ---------------------------------------------------------------------------------------

local function fontString(parent, font, justify)
  local ok, fs = pcall(parent.CreateFontString, parent, nil, "OVERLAY", font or "GameFontHighlightSmall")
  if not ok or not fs then fs = parent:CreateFontString(nil, "OVERLAY") end
  if not fs:GetFont() then fs:SetFont(_G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 11) end
  fs:SetJustifyH(justify or "LEFT")
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  return fs
end
D.FontString = fontString

local function colour(tex, c, a)
  tex:SetColorTexture(c[1], c[2], c[3], a or 1)
end

-- A dark panel with a one-pixel edge (the Meter mod's look), for every run frame.
function D.Panel(f)
  f.back = f:CreateTexture(nil, "BACKGROUND")
  f.back:SetAllPoints()
  colour(f.back, { 0.08, 0.07, 0.1 }, 0.88)
  for _, points in ipairs({ { "TOPLEFT", "TOPRIGHT", "h" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "h" },
    { "TOPLEFT", "BOTTOMLEFT", "v" }, { "TOPRIGHT", "BOTTOMRIGHT", "v" } }) do
    local e = f:CreateTexture(nil, "BORDER")
    e:SetPoint(points[1])
    e:SetPoint(points[2])
    if points[3] == "h" then e:SetHeight(1) else e:SetWidth(1) end
    colour(e, EDGE)
  end
end

-- Holds a frame by its top left corner where it stands (a dragged frame is left on the nearest
-- corner by the client, and one held by a bottom corner grows upwards). Nil when it can't say.
function D.Pin(f)
  local left, top = ns.Try(f.GetLeft, f), ns.Try(f.GetTop, f)
  if type(left) ~= "number" or type(top) ~= "number" or ns.IsSecret(left) or ns.IsSecret(top) then return nil end
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", _G.UIParent, "BOTTOMLEFT", left, top)
  return left, top
end

local function place(f)
  local pos = D.SettingValue("runDisplayPos")
  f:ClearAllPoints()
  if type(pos) == "table" and type(pos.x) == "number" and type(pos.y) == "number" then
    f:SetPoint("TOPLEFT", _G.UIParent, "BOTTOMLEFT", pos.x, pos.y)
  else
    f:SetPoint("TOP", _G.UIParent, "TOP", 0, -60)
    D.Pin(f)
  end
end

local function savePlace(f)
  local left, top = D.Pin(f)
  if not left then return end
  ns.API.Settings.Set("runDisplayPos", { x = math.floor(left + 0.5), y = math.floor(top + 0.5) })
end

local function line(f, i)
  local l = f.lines[i]
  if l then return l end
  l = { left = fontString(f, "GameFontHighlightSmall", "LEFT"),
    right = fontString(f, "GameFontHighlightSmall", "RIGHT") }
  f.lines[i] = l
  return l
end

local function build()
  local f = CreateFrame("Frame", "RynaChronicleRun", _G.UIParent)
  f:SetSize(CARD_W, 20)
  f:SetFrameStrata("MEDIUM")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  D.Panel(f)
  f.title = fontString(f, "GameFontNormalSmall", "LEFT")
  f.title:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
  f.clock = fontString(f, "GameFontHighlightSmall", "RIGHT")
  f.strip = fontString(f, "GameFontHighlightSmall", "LEFT")
  -- The experience bar: the level so far, and in gold the part this run added.
  f.barBack = f:CreateTexture(nil, "ARTWORK")
  colour(f.barBack, { 0.16, 0.15, 0.21 }, 0.9)
  f.barFill = f:CreateTexture(nil, "ARTWORK", nil, 1)
  colour(f.barFill, { 0.42, 0.36, 0.62 })
  f.barGain = f:CreateTexture(nil, "ARTWORK", nil, 2)
  colour(f.barGain, { 0.85, 0.68, 0.2 })
  f.barText = fontString(f, "GameFontHighlightSmall", "CENTER")
  f.rule = f:CreateTexture(nil, "ARTWORK")
  colour(f.rule, EDGE)
  f.rule:SetHeight(1)
  f.note = fontString(f, "GameFontDisableSmall", "LEFT")
  if f.note.SetWordWrap then f.note:SetWordWrap(true) end
  f.lines = {}

  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    ns.Run("run display place", savePlace, self)
  end)
  f:SetScript("OnEnter", function(self)
    self.hovered = true
    ns.Run("run display tooltip", D.ShowTooltip, self)
  end)
  f:SetScript("OnLeave", function(self)
    self.hovered = false
    local tip = _G.GameTooltip
    if tip and tip.Hide then tip:Hide() end
  end)
  local since = 0
  f:SetScript("OnUpdate", function(_, elapsed)
    since = since + (tonumber(elapsed) or 0)
    if since < 1 then return end
    since = 0
    ns.Run("run display tick", D.Tick)
  end)
  f:Hide()
  place(f)
  return f
end

-- The frame, made the first time it is needed; nil (and never tried again) on a client that can't.
function D.Frame()
  if D.frame then return D.frame end
  if D.failed then return nil end
  local ok, f = pcall(build)
  if not ok or not f then
    D.failed = true
    ns.Debug("runs: the live display could not be made: %s", tostring(f))
    return nil
  end
  D.frame = f
  return f
end

local function hideLines(f, from)
  for i = from, #f.lines do
    f.lines[i].left:Hide()
    f.lines[i].right:Hide()
  end
end

local function drawStrip(f, view)
  local capped = false
  if not D.example then capped = D.Capped() end
  local m = V.Strip(view, { capped = capped })
  f.title:Hide()
  f.clock:Hide()
  f.barBack:Hide()
  f.barFill:Hide()
  f.barGain:Hide()
  f.barText:Hide()
  f.rule:Hide()
  f.note:Hide()
  hideLines(f, 1)
  f.strip:Show()
  f.strip:ClearAllPoints()
  f.strip:SetPoint("LEFT", f, "LEFT", PAD + 2, 0)
  local text = V.StripText(m)
  f.strip:SetText(text)
  f:SetAlpha(m.paused and 0.75 or 1)
  local w = ns.Try(f.strip.GetStringWidth, f.strip)
  f:SetSize((type(w) == "number" and w or 300) + 2 * PAD + 6, 20)
  f.model = m
end

local function setLine(f, i, y, left, right, dim)
  local l = line(f, i)
  l.left:ClearAllPoints()
  l.left:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 2 + (dim and 8 or 0), y)
  l.right:ClearAllPoints()
  l.right:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PAD + 2), y)
  l.left:SetText(left or "")
  l.right:SetText(right or "")
  local c = dim and DIM or { 1, 1, 1 }
  l.left:SetTextColor(c[1], c[2], c[3])
  l.right:SetTextColor(c[1], c[2], c[3])
  l.left:Show()
  l.right:Show()
end

local function drawCard(f, view)
  local c = D.CardModel(view)
  f.strip:Hide()
  f:SetAlpha(view.paused and 0.75 or 1)
  local y = -PAD
  f.title:Show()
  f.title:ClearAllPoints()
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 2, y)
  f.title:SetText(c.name)
  f.clock:Show()
  f.clock:ClearAllPoints()
  f.clock:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(PAD + 2), y)
  f.clock:SetText(c.clock)
  y = y - LINE - 2
  local inner = CARD_W - 2 * PAD
  if c.bar then
    f.barBack:ClearAllPoints()
    f.barBack:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    f.barBack:SetSize(inner, BAR_H)
    f.barFill:ClearAllPoints()
    f.barFill:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
    f.barFill:SetSize(math.max(1, inner * c.bar.share), BAR_H)
    f.barGain:ClearAllPoints()
    f.barGain:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + inner * c.bar.from, y)
    f.barGain:SetSize(math.max(1, inner * c.bar.gained), BAR_H)
    f.barText:ClearAllPoints()
    f.barText:SetPoint("TOP", f, "TOP", 0, y - 1)
    f.barText:SetText(c.bar.text)
    for _, r in ipairs({ f.barBack, f.barFill, f.barText }) do r:Show() end
    if c.bar.gained > 0 then f.barGain:Show() else f.barGain:Hide() end
    y = y - BAR_H - 4
  else
    for _, r in ipairs({ f.barBack, f.barFill, f.barGain, f.barText }) do r:Hide() end
  end
  local n = 0
  for _, r in ipairs(c.rows) do
    if n >= MAX_LINES then break end
    n = n + 1
    setLine(f, n, y, r.label, r.value, r.dim)
    y = y - LINE
  end
  if #c.splits > 0 then
    f.rule:ClearAllPoints()
    f.rule:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y - 2)
    f.rule:SetWidth(inner)
    f.rule:Show()
    y = y - 6
  else
    f.rule:Hide()
  end
  for _, s in ipairs(c.splits) do
    if n >= MAX_LINES then break end
    n = n + 1
    local dim = s.state == "next" or s.state == "more" or s.state == "drop"
    local right = s.time
    if s.diffText then right = right .. "  " .. V.Tone(s.diffText, s.tone) end
    setLine(f, n, y, V.SplitLeft(s), right, dim)
    y = y - LINE
  end
  hideLines(f, n + 1)
  if c.note then
    f.note:ClearAllPoints()
    f.note:SetPoint("TOPLEFT", f, "TOPLEFT", PAD + 2, y - 2)
    f.note:SetWidth(inner - 4)
    f.note:SetText(c.note)
    f.note:Show()
    local h = ns.Try(f.note.GetStringHeight, f.note)
    y = y - 4 - (type(h) == "number" and h or LINE)
  else
    f.note:Hide()
  end
  f:SetSize(CARD_W, -y + PAD)
  f.model = c
end

-- Draws the view now in hand (D.view, read at the last refresh), advanced to now.
function D.Draw()
  local f = D.frame
  if not f or not D.view then return end
  local view = D.example and D.view or V.Advance(D.view, ns.Now() - (D.readAt or ns.Now()))
  if D.mode == "card" then drawCard(f, view) else drawStrip(f, view) end
  if f.hovered then D.ShowTooltip(f) end
end

-- Reads the run again and shows, redraws or hides the display.
function D.Refresh()
  local view, mode = source()
  if not view then
    D.view = nil
    if D.frame then D.frame:Hide() end
    return
  end
  local f = D.Frame()
  if not f then return end
  D.view, D.mode, D.readAt = view, mode, ns.Now()
  f:Show()
  D.Draw()
end

-- Once a second while shown: the timer.
function D.Tick()
  if D.frame and D.frame:IsShown() and D.view and not D.example then D.Draw() end
end

-- The strip's hover: the card's detail.
function D.ShowTooltip(f)
  local tip = _G.GameTooltip
  if not tip or D.mode ~= "strip" or not D.view then return end
  local view = D.example and D.view or V.Advance(D.view, ns.Now() - (D.readAt or ns.Now()))
  tip:SetOwner(f, "ANCHOR_BOTTOM")
  tip:ClearLines()
  for _, l in ipairs(V.CardLines(D.CardModel(view))) do
    if l[2] then
      tip:AddDoubleLine(l[1], l[2], 0.8, 0.8, 0.8, 1, 1, 1)
    else
      tip:AddLine(l[1], 0.6, 0.6, 0.6, true)
    end
  end
  tip:Show()
end

-- The setting, and placing it -----------------------------------------------------------------------

local N = ns.N
local LABELS = { strip = N("A thin strip"), card = N("A card"), off = N("Neither") }
function D.Label(mode)
  return L[LABELS[mode] or LABELS.off]
end
D.MODES = { "strip", "card", "off" }

function D.SetDisplay(mode)
  if mode ~= "strip" and mode ~= "card" and mode ~= "off" then return false end
  ns.API.Settings.Set("runDisplay", mode)
  if D.example then D.example.mode = mode end
  if D.example and mode == "off" then D.example = nil end
  D.Refresh()
  ns.API.Panel.RefreshIfShown()
  return true
end

-- A run in The Deadmines on a level 19 character, the mockup's numbers, for placing the display.
function D.ExampleView()
  return {
    id = "example", mapId = 36, instance = L["The Deadmines (an example)"], seconds = 1450, paused = false,
    combatSeconds = 842, inCombat = false, xpPerHour = 21400, xp = { total = 8620 }, kills = { n = 88 },
    loot = { n = 31 }, deaths = 0, worth = { coin = 1800, vendor = 3100, auction = 6300, total = 11200 },
    bosses = { { encounterId = 1, name = "Rhahk'Zor", success = true, split = 340 },
      { encounterId = 2, name = "Sneed", success = true, split = 895 } },
    level = { from = 19, to = 19 }, party = { size = 5 },
  }
end

-- /ryna runs test: the chosen display with example numbers, or gone again. Returns whether it shows:
-- true, false (taken away again), nil (the display is off) or "absent" (this client can't draw it).
function D.Test()
  if D.example then
    D.example = nil
    D.Refresh()
    return false
  end
  local mode = ns.Runs.Display()
  if mode == "off" then return nil end
  local view = D.ExampleView()
  D.example = { mode = mode, view = view, card = V.Card(view, {
    xp = { cur = 5680, max = 8000, level = 19 },
    compare = { runs = 6, fastest = { seconds = 2280, splits = { [1] = 362, [2] = 825 } } },
    fastestRun = { bosses = { { encounterId = 3, name = "Gilnid", success = true, split = 1170 },
      { encounterId = 4, name = "Mr. Smite", success = true, split = 1625 },
      { encounterId = 5, name = "Captain Greenskin", success = true, split = 1900 },
      { encounterId = 6, name = "Edwin VanCleef", success = true, split = 2200 } } },
  }) }
  D.Refresh()
  if not D.frame then
    D.example = nil
    return "absent"
  end
  return D.frame:IsShown()
end

-- After the panel's Defaults: the display follows the settings again.
function D.OnDefaults()
  D.example = nil
  if D.frame then place(D.frame) end
  D.Refresh()
end

ns.Runs.OnChange(function(what)
  if what.open then D.example = nil end
  D.Refresh()
end)
ns.On("PLAYER_ENTERING_WORLD", function() ns.Run("run display", D.Refresh) end)
