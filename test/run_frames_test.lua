-- Dungeon runs in game against the fake client, with the real core and Chronicle: the first-time
-- choice (shown once per account, never in combat), the live display (strip and card, only while a run
-- is open, paused outside, the timer ticking, the strip's hover), the summary on walking out (so far,
-- gone on going back in, shown closed when the run closes while it is up, Close), Dungeons › Runs in
-- Ryna's window (its rows, a dungeon opened, a run's summary), the Recording tab's run settings, and
-- /ryna runs (open, strip, card, off, test). Nothing in chat but the answers to what was typed.
-- From the repository root:
--
--   lua5.1 test/run_frames_test.lua
-- luacheck: ignore 1

local H = dofile("test/run_harness.lua")
local check, eq = H.check, H.eq
local F = H.F

-- The Recording tab, captured as it is added (the panel itself is the core's to test).
local recording
local ns, core = H.Load({ beforeChronicle = function()
  local add = Ryna.Panel.AddTab
  Ryna.Panel.AddTab = function(spec)
    if spec.key == "recording" then recording = spec end
    return add(spec)
  end
end })
local R, D, S, Nt = ns.Runs, ns.RunDisplay, ns.RunSummary, ns.RunNotice
local settings = RynaDB.settings
local plain = F.Plain
check(R and D and S and Nt and ns.Dungeons, "the run views load")
check(settings.runs == true and settings.runSummary == true and settings.runSummaryMeter == true,
  "runs, runSummary and runSummaryMeter default on")
check(settings.runDisplay == nil and R.Display() == "off", "the display is unset, which reads off")
local chatAtStart = #F.chat

-- The first dungeon: the choice, once. ---------------------------------------------------------------
H.inCombat = true
H.Enter(H.DM)
check(R.Current() ~= nil, "a run opens on entering")
check(Nt.frame == nil or not Nt.frame:IsShown(), "in combat: the notice waits")
check(D.frame == nil or not D.frame:IsShown(), "no display chosen: nothing on screen")
H.inCombat = false
F.Fire("PLAYER_REGEN_ENABLED")
check(Nt.frame and Nt.frame:IsShown(), "out of combat: the notice")
eq(Nt.frame.title:GetText(), "Ryna can track this run", "its title")
eq(#Nt.frame.buttons, 3, "three choices")
eq(Nt.frame.buttons[1]:GetText() .. "|" .. Nt.frame.buttons[2]:GetText() .. "|" .. Nt.frame.buttons[3]:GetText(),
  "A thin strip|A card|Neither", "a thin strip, a card, neither")
check(Nt.frame.hint:GetText():find("/ryna", 1, true) ~= nil, "it says where to change it")
check(RynaDB.chronicle.runsNoticeSeen == true, "shown: remembered for the account")
F.Click(Nt.frame.buttons[1])
check(not Nt.frame:IsShown(), "a choice closes it")
eq(settings.runDisplay, "strip", "the strip chosen")

-- The strip. -------------------------------------------------------------------------------------------
local f = D.frame
check(f and f:IsShown(), "the strip shows inside")
eq(D.mode, "strip", "as a strip")
local text = plain(f.strip:GetText())
check(text:find("The Deadmines  ·  0:00  ·  0 xp/hr  ·  0 kills  ·  0 bosses  ·  0c", 1, true) == 1,
  "the strip's line: " .. text)
H.Later(65)
f._scripts.OnUpdate(f, 1)
check(plain(f.strip:GetText()):find("1:05", 1, true) ~= nil,
  "the timer ticks once a second: " .. plain(f.strip:GetText()))
F.Fire("ENCOUNTER_START", 1, "Rhahk'Zor")
H.Later(30)
F.Fire("ENCOUNTER_END", 1, "Rhahk'Zor", 1, 5, 1)
F.RunTimers()
check(plain(f.strip:GetText()):find("1 boss", 1, true) ~= nil, "a boss killed: the strip says so")
f._scripts.OnEnter(f)
local tips = {}
for _, l in ipairs(GameTooltip.lines) do tips[#tips + 1] = plain(l.left) .. "=" .. plain(l.right or "") end
local tip = table.concat(tips, "|")
check(tip:find("Rhahk'Zor=1:35", 1, true) ~= nil, "the hover shows the card's detail, with the split: " .. tip)
check(tip:find("Your first run here", 1, true) ~= nil, "and that this is the first run here")
f._scripts.OnLeave(f)

-- Dragging keeps its place, by the top left corner.
f._scripts.OnDragStart(f)
f.GetLeft, f.GetTop = function() return 300 end, function() return 700 end
f._scripts.OnDragStop(f)
check(type(settings.runDisplayPos) == "table" and settings.runDisplayPos.x == 300 and settings.runDisplayPos.y == 700,
  "a drag keeps its place")
eq(f:GetPoint(1), "TOPLEFT", "held by its top left corner, so it grows downwards")

-- The card, by the slash word. ---------------------------------------------------------------------------
local before = #F.chat
SlashCmdList.RYNA("runs card")
eq(settings.runDisplay, "card", "/ryna runs card")
check(H.Said(before, "The live run display is now: A card."), "the answer to what was typed")
eq(D.mode, "card", "now a card")
eq(f.title:GetText() .. " " .. f.clock:GetText(), "The Deadmines 1:35", "the card's head")
check(f.barText:IsShown() and f.barText:GetText():find("^Level 17 · 25%%") ~= nil, "the experience bar: " ..
  tostring(f.barText:GetText()))
local lines = {}
for _, l in ipairs(f.lines) do
  if l.left:IsShown() then lines[#lines + 1] = plain(l.left:GetText()) .. "=" .. plain(l.right:GetText()) end
end
local card = table.concat(lines, "|")
check(card:find("Kills=0", 1, true) and card:find("In combat=0:00 of 1:35", 1, true) and card:find("Deaths=0", 1, true),
  "the card's rows: " .. card)
check(card:find("Rhahk'Zor=1:35", 1, true) ~= nil, "the boss's split")
check(f.note:IsShown() and f.note:GetText():find("first run", 1, true) ~= nil, "nothing to compare: says so")

-- Walking out: paused, and the summary. --------------------------------------------------------------------
H.Later(60)
H.Leave()
check(R.Current().paused, "outside: the run pauses")
check(f:IsShown(), "a paused run still shows")
eq(f.clock:GetText(), "2:35 paused", "its timer stopped")
check(S.frame and S.frame:IsShown(), "the summary on walking out")
eq(S.frame.name:GetText() .. " / " .. S.frame.head:GetText(), "The Deadmines / so far · solo", "it says so far")
eq(S.frame.tiles[1].value:GetText(), "2:35", "the time inside")
check(S.frame.note:GetText():find("Go back in within 30:00", 1, true) ~= nil, "and how long the run waits")
check(S.frame.open:IsShown(), "Open in Ryna, with the window there")
H.Later(120)
f._scripts.OnUpdate(f, 1)
eq(f.clock:GetText(), "2:35 paused", "outside, the timer stays stopped")
H.Enter(H.DM)
check(not R.Current().paused, "back in: the run goes on")
check(not S.frame:IsShown(), "back in: the summary goes")
eq(R.Current().entries, 2, "the same run, entered twice")

-- A death puts the character outside as a ghost: the run pauses, with no summary on the way back in.
_G.UnitIsDeadOrGhost = function() return true end
H.Leave()
check(R.Current().paused and not S.frame:IsShown(), "a death outside pauses the run without a summary")
_G.UnitIsDeadOrGhost = function() return false end
H.Enter(H.DM)

-- Out again, then the 30 minutes pass while the summary is up: it is shown closed.
H.Leave()
check(S.frame:IsShown(), "out again: the summary again")
H.Later(31 * 60)
F.Fire("ZONE_CHANGED_NEW_AREA")
F.RunTimers()
check(R.Current() == nil and #R.List() == 1, "past 30 minutes the run closes")
check(S.frame:IsShown(), "the summary stays up")
eq(S.frame.head:GetText(), "run 1 · solo", "and now the run is closed")
check(not S.frame.note:IsShown(), "no 'go back in' for a closed run")
check(not f:IsShown(), "no open run: the display goes")
F.Click(S.frame.close)
check(not S.frame:IsShown(), "Close")

-- Another dungeon: no notice the second time; the summary off; the display off. -------------------------
settings.runSummary = false
H.Enter(H.SFK)
check(not Nt.frame:IsShown(), "the notice is shown once per account")
check(f:IsShown() and f.title:GetText() == "Shadowfang Keep", "the card for the new run")
H.Leave()
check(not S.frame:IsShown(), "runSummary off: no summary on leaving")
settings.runSummary = true
H.Enter(H.SFK)
before = #F.chat
SlashCmdList.RYNA("runs off")
check(not f:IsShown(), "/ryna runs off: the display goes, even inside")
check(H.Said(before, "The live run display is now: Neither."), "and says so")
SlashCmdList.RYNA("runs strip")
check(f:IsShown() and D.mode == "strip", "/ryna runs strip: back, as a strip")
settings.runs = false
D.Refresh()
check(not f:IsShown(), "runs off: no display")
settings.runs = true
D.Refresh()

-- /ryna runs test: the example, placed outside a run. ----------------------------------------------------
H.Leave()
H.Later(31 * 60)
F.Fire("ZONE_CHANGED_NEW_AREA")
F.RunTimers()
S.Hide()
check(R.Current() == nil and not f:IsShown(), "no open run: nothing")
before = #F.chat
SlashCmdList.RYNA("runs test")
check(f:IsShown() and plain(f.strip:GetText()):find("The Deadmines (an example)", 1, true) == 1,
  "/ryna runs test: the strip with example numbers")
check(H.Said(before, "drag it where you want it"), "it says what to do")
SlashCmdList.RYNA("runs card")
check(f:IsShown() and D.mode == "card" and f.lines[1].right:GetText() ~= "",
  "switching while placing: the card example")
check(f.lines[7].left:GetText():find("Rhahk'Zor", 1, true) ~= nil
  and plain(f.lines[7].right:GetText()) == "5:40  -0:22",
  "the example's splits: " .. tostring(f.lines[7].left:GetText()))
SlashCmdList.RYNA("runs test")
check(not f:IsShown(), "again: gone")
check(H.Said(before, "The example run is gone."), "and says so")
SlashCmdList.RYNA("runs off")
before = #F.chat
SlashCmdList.RYNA("runs test")
check(H.Said(before, "The live run display is off"), "test with the display off: says to choose one")
check(not f:IsShown(), "and shows nothing")
SlashCmdList.RYNA("runs card")

-- Dungeons › Runs. -------------------------------------------------------------------------------------------
local Wn = core.Window
SlashCmdList.RYNA("runs")
eq(Wn.Selected(), "dungeons", "/ryna runs opens Dungeons")
local w = Wn.frame
eq(w.title:GetText(), "Dungeons › Runs", "its title")
check(w.groupHeads.world:IsShown(), "in the World group")
eq(w.tiles[1].label:GetText() .. "=" .. w.tiles[1].value:GetText(), "Runs=2", "tile: runs")
eq(w.tiles[2].label:GetText(), "Time inside", "tile: time inside")
eq(w.tiles[4].label:GetText(), "Worth", "tile: worth")
check(plain(w.rows[1].cols[1]:GetText()):find("Shadowfang Keep", 1, true) ~= nil, "newest dungeon first")
check(plain(w.rows[2].cols[1]:GetText()):find("The Deadmines", 1, true) ~= nil, "then the older")
check(not w.rows[3]:IsShown(), "two dungeons, closed")
F.Click(w.rows[2])
check(w.rows[3]:IsShown() and w.rows[3].cols[3]:GetText() == "2:35", "a dungeon opens to its runs")
eq(w.rows[3].cols[2]:GetText(), "1/1", "bosses killed of pulled")
check(plain(w.rows[3].cols[4]:GetText()) == "best", "a full clear, the only one: best")
F.Click(w.rows[3])
check(S.frame:IsShown() and S.frame.head:GetText() == "run 1 · solo", "a run opens its summary")
F.Click(S.frame.open)
check(not S.frame:IsShown() and Wn.Selected() == "dungeons", "Open in Ryna: the summary goes, Dungeons shows")
F.Click(w.rows[2])
check(not w.rows[3]:IsShown(), "a second click closes the dungeon")
check(plain(w.footer:GetText()):find("the newest 100 per character, older ones as totals", 1, true) ~= nil,
  "the footer says where the runs come from")
core.Window.Choose(H.ALT)
check(not w.rows[1]:IsShown(), "another character with no runs: an empty list")
check(w.empty:GetText():find("No dungeon runs recorded yet", 1, true) == 1, "and its empty text")
core.Window.Choose(nil)

-- The Recording tab's run settings. --------------------------------------------------------------------------
check(recording ~= nil, "the Recording tab")
local tabFrame = F.new("Frame", nil, UIParent)
local ok, err = pcall(recording.build, tabFrame)
check(ok, "the Recording tab builds: " .. tostring(err))
local stack = { y = 0 }
function stack.add(_, h) stack.y = stack.y - (h or 0) end
function stack.text() end
ok, err = pcall(recording.layout, stack, settings)
check(ok, "and lays out: " .. tostring(err))
local labels = {}
for _, fr in ipairs(F.frames) do
  if fr._kind == "FontString" and type(fr._text) == "string" then labels[fr._text] = fr end
end
check(labels["Record dungeon runs"] and labels["Show a summary when I leave"]
  and labels["My damage and healing on the summary"] and labels["Dungeon runs"], "its switches and heading")
local control
for _, fr in ipairs(F.frames) do
  if fr._kind == "Button" and type(fr._text) == "string" and fr._text:find("(click to change)", 1, true) then
    control = fr
  end
end
check(control and control._text == "A card (click to change)", "the three-way choice, a button on this client")
F.Click(control)
eq(settings.runDisplay, "off", "a click steps it on: card, then neither")
F.Click(control)
eq(settings.runDisplay, "strip", "then a thin strip")

check(#F.chat - chatAtStart == 9, "nothing in chat but the answers to /ryna runs (" .. (#F.chat - chatAtStart) .. ")")
check(core.errors.count == 0, "no errors caught: " .. tostring(core.errors.last))
H.done("run frames")
