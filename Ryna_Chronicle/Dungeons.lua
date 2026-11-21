-- Dungeons: Dungeons › Runs in Ryna's window (World group), and /ryna runs (ryna_agent
-- docs/ryna-agent-cores-mods.md 7.7 "In game"). From the saved file alone, for any character of the
-- account (the window's picker):
--
--   tiles   runs, time inside, experience, worth
--   rows    one per dungeon (Runs.ByInstance): runs, fastest, median, a bar of the fastest against the
--           median, experience an hour, last run. A click opens it in place to its runs, newest first
--           (date, bosses killed of pulled, time, "best" or "left early", experience, worth); a run's
--           click opens its summary (RunSummary.lua).
--
--   /ryna runs                 opens Dungeons
--   /ryna runs strip|card|off  the live display (RunDisplay.lua)
--   /ryna runs test            the chosen display with example numbers, to place it; again to hide it
--
-- With a core older than the window none of the section registers, and /ryna runs says so when typed.

local _, ns = ...
if ns.off then return end
local L = ns.L

local Dn = {}
ns.Dungeons = Dn

local V = ns.RunView
local RW = ns.API.Window
local KEY = "dungeons"
Dn.KEY = KEY
Dn.open = {}       -- dungeons opened to their runs, by map id
Dn.openVersion = 0

local PLUS = "|TInterface\\Buttons\\UI-PlusButton-Up:12|t "
local MINUS = "|TInterface\\Buttons\\UI-MinusButton-Up:12|t "

local function ago(t)
  return ns.Status.Ago(t) or ""
end

-- The section's rows for a character (ctx.character), with the dungeons in Dn.open opened.
function Dn.Rows(ctx)
  local guid = ctx.character
  local rows = V.DungeonRows(ns.Runs.ByInstance(guid), ns.Runs.List(guid), ns.Runs.Totals(guid), Dn.open, ago)
  for _, r in ipairs(rows) do
    if r.kind == "dungeon" then
      r.cells[1] = (r.open and MINUS or PLUS) .. r.cells[1]
      r.color = "|cffffd100"
    else
      r.cells[1] = "    " .. r.cells[1]
      if r.best then
        r.cells[4] = V.Tone(r.cells[4], "good")
      elseif r.partial then
        r.cells[4] = V.Tone(r.cells[4], "dim")
      end
    end
  end
  return rows
end

function Dn.Tiles(ctx)
  local guid = ctx.character
  local t = V.Tiles(ns.Runs.List(guid), ns.Runs.Totals(guid))
  return {
    { label = L["Runs"], value = ns.Session.Number(t.runs) },
    { label = L["Time inside"], value = ns.Session.Duration(t.seconds) },
    { label = L["Experience"], value = V.Short(t.xp) },
    { label = L["Worth"], value = ns.Session.Money(t.worth) },
  }
end

function Dn.Click(row)
  if row.kind == "dungeon" then
    Dn.open[row.mapId] = not Dn.open[row.mapId] or nil
    Dn.openVersion = Dn.openVersion + 1
    if RW.Refresh then RW.Refresh(KEY) end
  elseif row.kind == "run" and ns.RunSummary then
    ns.RunSummary.Show(row.run, true)
  end
end

function Dn.Tooltip(row, tip)
  if row.kind == "dungeon" then
    tip:AddLine(row.name)
    tip:AddLine(row.open and L["Click to close its runs."] or L["Click to see its runs."], 0.6, 0.6, 0.6)
  else
    tip:AddLine(row.cells[1]:gsub("^%s+", ""), 1, 1, 1)
    tip:AddLine(L["Click for its summary."], 0.6, 0.6, 0.6)
  end
end

local COLUMNS = {
  { title = L["Dungeon"], width = 168 }, { title = L["Runs"], width = 44, justify = "RIGHT" },
  { title = L["Fastest"], width = 64, justify = "RIGHT" }, { title = L["Median"], width = 64, justify = "RIGHT" },
  { title = L["Fastest against median"], width = 110, kind = "bar" },
  { title = L["XP an hour"], width = 72, justify = "RIGHT" }, { title = L["Last run"], width = 90, justify = "RIGHT" },
}

if ns.Window and ns.Window.available then
  if RW.AddSection({
    key = KEY, group = "world", order = 20, label = L["Dungeons"], characters = "one", search = false,
    sortable = false,
    -- (a core before function titles would print the function, so only on one that has them)
    title = RW.STRIP_MAX ~= nil and function() return string.format(L["%s › %s"], L["Dungeons"], L["Runs"]) end
      or nil,
    columns = COLUMNS,
    version = function() return tostring(ns.Runs.version) .. ":" .. Dn.openVersion end,
    rows = Dn.Rows, tiles = Dn.Tiles, click = Dn.Click, tooltip = Dn.Tooltip,
    empty = L["No dungeon runs recorded yet. A run is recorded each time this character enters a dungeon or raid."],
    footer = function()
      return L["From your saved file. Runs are kept from the Chronicle release that adds them; the newest 100 "
        .. "per character, older ones as totals."]
    end,
  }) then
    ns.Window.keys[KEY] = true
  end
  -- Redrawn when a run changes, only while the window is open (and rebuilt only on Runs.version).
  ns.Runs.OnChange(function() ns.Window.Changed() end)
end

-- /ryna runs ------------------------------------------------------------------------------------------

local HELP = L["/ryna runs: your dungeon runs; /ryna runs strip, card or off: the live display; "
  .. "/ryna runs test: place it"]

function Dn.Command(arg)
  arg = tostring(arg or ""):lower():match("^%s*(%S*)")
  local D = ns.RunDisplay
  if arg == "" then
    return ns.Window.Open(KEY)
  end
  if arg == "strip" or arg == "card" or arg == "off" then
    D.SetDisplay(arg)
    ns.Print(string.format(L["The live run display is now: %s."], D.Label(arg)))
    return
  end
  if arg == "test" then
    local shown = D.Test()
    if shown == "absent" then
      ns.Print(L["The run display can't be drawn on this client."])
    elseif shown == nil then
      ns.Print(L["The live run display is off: choose /ryna runs strip or /ryna runs card first."])
    elseif shown then
      ns.Print(L["The run display is showing an example: drag it where you want it, then type /ryna runs test again."])
    else
      ns.Print(L["The example run is gone."])
    end
    return
  end
  ns.Print(HELP)
end

ns.API.Slash.Add({ word = "runs", order = 32, run = function(arg) Dn.Command(arg) end,
  help = HELP })
