-- RunSummary: the two small frames dungeon runs show unasked (ryna_agent docs/ryna-agent-cores-mods.md
-- 7.7 "In game"), never a chat line.
--
-- The summary (runSummary, on): each time the character walks out of the instance (the run pauses), the
-- run so far against this character's earlier runs of the dungeon: time (best, or the difference from
-- the fastest), experience, worth, kills and bosses, deaths, the run's own damage and healing
-- (runSummaryMeter, when the game's meter gave them), the two most valuable drops and a last line of the
-- rest. It says "so far" until the run closes; a run that closes while it is up is shown closed. It
-- goes when the character goes back in, and on Close or Escape. "Open in Ryna" opens Dungeons › Runs.
-- A run row there opens the same frame on that run.
--
-- The first-time choice: the first time on the account that a character enters a dungeon or raid while
-- runDisplay was never set, one notice offers a thin strip, a card or neither, and says where to change
-- it. Shown once whatever is chosen (RynaDB.chronicle.runsNoticeSeen), never in combat (it waits for the
-- fight to end).
--
-- Both are plain frames in the Meter mod's dark style (RunDisplay.lua's panel), made under pcall: a
-- client missing a template or method leaves them absent, never an error.

local _, ns = ...
if ns.off then return end
local L = ns.L

local S = {}
ns.RunSummary = S
local Nt = {}
ns.RunNotice = Nt

local V = ns.RunView
local D = ns.RunDisplay
local WIDTH = 380
local PAD = 10
local TILE_H = 44

-- CreateFrame with the first template this client has (none, last).
local function create(kind, name, parent, templates)
  for _, template in ipairs(templates or {}) do
    local ok, f = pcall(CreateFrame, kind, name, parent, template)
    if ok and f then return f end
  end
  local ok, f = pcall(CreateFrame, kind, name, parent)
  if ok then return f end
  return nil
end

local function button(parent, label, w)
  local b = create("Button", nil, parent, { "UIPanelButtonTemplate" })
  if not b then return nil end
  b:SetSize(w, 22)
  if not b:GetFontString() then
    local fs = D.FontString(b, "GameFontNormal", "CENTER")
    fs:SetAllPoints()
    b:SetFontString(fs)
  end
  b:SetText(label)
  return b
end

local function wrapped(parent, font, width)
  local fs = D.FontString(parent, font, "LEFT")
  if fs.SetWordWrap then fs:SetWordWrap(true) end
  if fs.SetJustifyV then fs:SetJustifyV("TOP") end
  fs:SetWidth(width)
  return fs
end

local function height(fs, fallback)
  local h = ns.Try(fs.GetStringHeight, fs)
  if type(h) == "number" and h > 0 then return h end
  return fallback or 12
end

-- A small movable frame on the panel, closed by Escape.
local function frame(name, width)
  local f = create("Frame", name, _G.UIParent)
  f:SetWidth(width)
  f:SetFrameStrata("DIALOG")
  if f.SetToplevel then f:SetToplevel(true) end
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    D.Pin(self)
  end)
  D.Panel(f)
  if type(_G.UISpecialFrames) == "table" then table.insert(_G.UISpecialFrames, name) end
  f:SetPoint("TOP", _G.UIParent, "TOP", 0, -140)
  f:Hide()
  return f
end

-- The summary ---------------------------------------------------------------------------------------

-- An item's name and quality from the client, or nil (asked to load, for next time).
function S.ItemInfo(id)
  id = tonumber(id)
  if not id then return nil end
  local name, _, quality = ns.Try(ns.Fn("C_Item", "GetItemInfo"), id)
  if name == nil or ns.IsSecret(name) or type(name) ~= "string" or name == "" then
    ns.Try(ns.Fn("C_Item", "RequestLoadItemDataByID"), id)
    return nil
  end
  if ns.IsSecret(quality) or type(quality) ~= "number" then quality = nil end
  return name, quality
end

-- The summary's model for a run: the open one (Runs.Current()) so far, or a closed one.
function S.Model(run, closed)
  local list = ns.Runs.List()
  local top
  if closed then
    top = type(run.loot) == "table" and run.loot.top or {}
  else
    top = ns.Runs.CurrentTop()
  end
  return V.Summary(run, {
    closed = closed, compare = ns.Runs.Compare(run), capped = D.Capped() and true or false,
    meter = ns.Setting("runSummaryMeter") and true or false,
    index = V.RunIndex(run, list, ns.Runs.Totals()), top = top, itemInfo = S.ItemInfo,
  })
end

local function buildSummary()
  local f = frame("RynaChronicleRunSummary", WIDTH)
  local inner = WIDTH - 2 * PAD
  f.name = D.FontString(f, "GameFontNormal", "LEFT")
  f.name:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
  f.head = D.FontString(f, "GameFontDisableSmall", "RIGHT")
  f.head:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -PAD - 1)
  f.tiles = {}
  local tileW = math.floor(inner / 3)
  for i = 1, 6 do
    local t = {}
    local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
    local x, y = PAD + col * tileW, -(PAD + 22 + row * TILE_H)
    t.label = D.FontString(f, "GameFontDisableSmall", "LEFT")
    t.label:SetPoint("TOPLEFT", f, "TOPLEFT", x, y)
    t.value = D.FontString(f, "GameFontHighlightLarge", "LEFT")
    t.value:SetPoint("TOPLEFT", f, "TOPLEFT", x, y - 12)
    t.sub = D.FontString(f, "GameFontDisableSmall", "LEFT")
    t.sub:SetPoint("TOPLEFT", f, "TOPLEFT", x, y - 30)
    t.sub:SetWidth(tileW - 4)
    f.tiles[i] = t
  end
  f.drops = {}
  for i = 1, 2 do
    f.drops[i] = { name = D.FontString(f, "GameFontHighlightSmall", "LEFT"),
      value = D.FontString(f, "GameFontHighlightSmall", "RIGHT") }
  end
  f.rest = wrapped(f, "GameFontDisableSmall", inner)
  f.note = wrapped(f, "GameFontHighlightSmall", inner)
  f.close = button(f, L["Close"], 80)
  f.open = button(f, L["Open in Ryna"], 120)
  if f.close then
    f.close:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
    f.close:SetScript("OnClick", function() f:Hide() end)
  end
  if f.open then
    if f.close then
      f.open:SetPoint("RIGHT", f.close, "LEFT", -6, 0)
    else
      f.open:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
    end
    f.open:SetScript("OnClick", function()
      f:Hide()
      ns.Run("ryna window", ns.Window.Open, "dungeons")
    end)
  end
  f:SetScript("OnHide", function() S.run = nil end)
  return f
end

function S.Frame()
  if S.frame then return S.frame end
  if S.failed then return nil end
  local ok, f = pcall(buildSummary)
  if not ok or not f then
    S.failed = true
    ns.Debug("runs: the summary could not be made: %s", tostring(f))
    return nil
  end
  S.frame = f
  return f
end

local function qualityColour(q)
  local RW = ns.API.Window
  if q ~= nil and type(RW) == "table" and type(RW.QualityColor) == "function" then
    local c = ns.Try(RW.QualityColor, q)
    if type(c) == "string" then return c end
  end
  return "|cffffffff"
end

function S.Draw(m)
  local f = S.frame
  if not f then return end
  f.model = m
  f.name:SetText(m.name)
  f.head:SetText(m.head)
  for i, t in ipairs(f.tiles) do
    local tile = m.tiles[i]
    if tile then
      t.label:SetText(tile.label)
      t.value:SetText(tile.value)
      t.sub:SetText(V.Tone(tile.sub, tile.tone or "dim"))
      t.label:Show()
      t.value:Show()
      t.sub:Show()
    else
      t.label:Hide()
      t.value:Hide()
      t.sub:Hide()
    end
  end
  local rows = math.floor((#m.tiles + 2) / 3)
  local y = -(PAD + 22 + rows * TILE_H + 4)
  for i, d in ipairs(f.drops) do
    local drop = m.drops[i]
    if drop then
      d.name:ClearAllPoints()
      d.name:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y)
      d.value:ClearAllPoints()
      d.value:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, y)
      d.name:SetText(qualityColour(drop.quality) .. drop.name .. "|r")
      d.value:SetText(drop.value)
      d.name:Show()
      d.value:Show()
      y = y - 15
    else
      d.name:Hide()
      d.value:Hide()
    end
  end
  for _, part in ipairs({ { f.rest, m.rest }, { f.note, m.note } }) do
    local fs, text = part[1], part[2]
    if text and text ~= "" then
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, y - 2)
      fs:SetText(text)
      fs:Show()
      y = y - 6 - height(fs)
    else
      fs:Hide()
    end
  end
  if f.open then
    if ns.Window and ns.Window.available then f.open:Show() else f.open:Hide() end
  end
  f:SetHeight(-y + 22 + 2 * PAD)
end

-- Shows the summary of a run: the open one so far (closed false) or a closed one.
function S.Show(run, closed)
  if type(run) ~= "table" then return end
  local f = S.Frame()
  if not f then return end
  S.run, S.closed = run, closed and true or false
  S.Draw(S.Model(run, closed))
  f:Show()
end

function S.Hide()
  if S.frame then S.frame:Hide() end
end

function S.Shown()
  return S.frame ~= nil and S.frame:IsShown() and true or false
end

-- What Runs.lua says: on walking out, the run so far; back in, gone; closed while up, shown closed.
function S.OnChange(what)
  if what.open or what.resume then
    if S.Shown() and not S.closed then S.Hide() end
    return
  end
  if what.close and S.Shown() and not S.closed then
    local last = ns.Runs.List()[1]
    if last then S.Show(last, true) else S.Hide() end
    return
  end
  if what.pause then
    if not ns.Setting("runSummary") then return end
    -- Not for a death: a ghost outside is on the way back in, and a wipe is no time for a summary.
    local dead = ns.Try(ns.Fn("UnitIsDeadOrGhost"), "player")
    if dead ~= nil and not ns.IsSecret(dead) and dead == true then return end
    local run = ns.Runs.Current()
    if run and run.paused then S.Show(run, false) end
    return
  end
  if S.Shown() and not S.closed then
    local run = ns.Runs.Current()
    if run then S.Show(run, false) end
  end
end

-- The first-time choice ------------------------------------------------------------------------------

local function store()
  local db = ns.db
  if type(db) ~= "table" then return nil end
  if type(db.chronicle) ~= "table" then db.chronicle = {} end
  return db.chronicle
end

function Nt.Seen()
  local s = store()
  return s ~= nil and s.runsNoticeSeen == true
end

-- Whether the display was ever chosen (the setting holds a choice, "off" included).
function Nt.Chosen()
  local v = D.SettingValue("runDisplay")
  return not ns.IsSecret(v) and type(v) == "string"
end

local function buildNotice()
  local w = 400
  local f = frame("RynaChronicleRunsNotice", w)
  local inner = w - 2 * PAD
  f.title = D.FontString(f, "GameFontNormal", "LEFT")
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -PAD)
  f.title:SetText(L["Ryna can track this run"])
  f.body = wrapped(f, "GameFontHighlightSmall", inner)
  f.body:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
  f.body:SetText(L["Time, experience, kills, bosses and what the loot is worth. Show it while you play?"])
  f.buttons = {}
  local prev
  for i, mode in ipairs(D.MODES) do
    local b = button(f, D.Label(mode), 118)
    if b then
      if prev then
        b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
      else
        b:SetPoint("TOPLEFT", f.body, "BOTTOMLEFT", 0, -10)
      end
      b:SetScript("OnClick", function()
        f:Hide()
        ns.Run("run display", D.SetDisplay, mode)
      end)
      f.buttons[i] = b
      prev = b
    end
  end
  f.hint = wrapped(f, "GameFontDisableSmall", inner)
  f.hint:SetText(L["Change it any time in /ryna, on the Recording tab, or with /ryna runs strip, card or off."])
  if prev then
    f.hint:SetPoint("TOPLEFT", f.buttons[1], "BOTTOMLEFT", 0, -8)
  else
    f.hint:SetPoint("TOPLEFT", f.body, "BOTTOMLEFT", 0, -8)
  end
  f:SetHeight(PAD + 16 + 6 + height(f.body, 24) + 10 + 22 + 8 + height(f.hint, 12) + PAD)
  return f
end

function Nt.Frame()
  if Nt.frame then return Nt.frame end
  if Nt.failed then return nil end
  local ok, f = pcall(buildNotice)
  if not ok or not f then
    Nt.failed = true
    ns.Debug("runs: the notice could not be made: %s", tostring(f))
    return nil
  end
  Nt.frame = f
  return f
end

local function inCombat()
  local v = ns.Try(ns.Fn("InCombatLockdown"))
  return v ~= nil and not ns.IsSecret(v) and v == true
end

-- On a run's opening: the notice, once per account, while the display was never chosen.
function Nt.Maybe()
  if Nt.Seen() or Nt.Chosen() or not ns.Runs.Current() then return end
  if inCombat() then
    Nt.waiting = true
    return
  end
  Nt.waiting = false
  local f = Nt.Frame()
  if not f then return end
  local s = store()
  if s then s.runsNoticeSeen = true end
  f:Show()
end

ns.Runs.OnChange(function(what)
  S.OnChange(what)
  if what.open then Nt.Maybe() end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
  if Nt.waiting then ns.Run("runs notice", Nt.Maybe) end
end)
