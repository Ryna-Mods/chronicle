-- Characters, one character's Quests (Characters.lua), against the fake client (fake_client.lua): the
-- detail's picker (Character, Quests; hidden with All characters), the column heading's counts ("5 active
-- · 1 ready to turn in"), the quests grouped under heading rows with a count, the most quests first and
-- then by name, each quest's level and progress ("1 / 3" over a third of a bar, "ready" on a full one, no
-- bar with nothing to count), the last group of quests saved before headings were recorded (present and
-- absent), an empty log, unreadable fields (nil, a string, NaN, entries that aren't tables), search, the
-- tooltip and the footer. Nothing is recorded for it. From the repository root, with Lua 5.1 (what the
-- game runs) or later:
--
--   lua5.1 test/characters_quests_test.lua
--
-- This proves the logic; how it looks in the default UI and in ElvUI is the game's to show.
-- luacheck: ignore 1

local CORE = (os.getenv("RYNA_CORE") or ".core/Ryna_Core") .. "/"
local CHRON = "Ryna_Chronicle/"
local F = dofile("test/fake_client.lua")
local plain = F.Plain

local failures, checks = 0, 0
local function check(cond, what)
  checks = checks + 1
  if not cond then
    failures = failures + 1
    print("FAIL: " .. what)
  end
end
local function eq(got, want, what)
  check(got == want, what .. ": got " .. tostring(got) .. ", want " .. tostring(want))
end

F.Install()

local ME = "Player-91-0000000A"
local ALT = "Player-91-0000000B"
local ALT2 = "Player-91-0000000C"
local EMPTY = "Player-91-0000000D"
_G.UnitGUID = function(unit) if unit == "player" then return ME end end
_G.UnitName = function(unit) if unit == "player" then return "Brennic" end end
_G.UnitFullName = function(unit) if unit == "player" then return "Brennic", "Ashgrove" end end
_G.GetNormalizedRealmName = function() return "91" end
_G.UnitClass = function() return "Paladin", "PALADIN" end
_G.UnitRace = function() return "Human", "Human" end
_G.UnitFactionGroup = function() return "Alliance" end
_G.UnitSex = function() return 3 end
_G.UnitLevel = function() return 17 end
_G.UnitXP = function() return 1200 end
_G.UnitXPMax = function() return 4800 end
_G.GetMoney = function() return 398786 end
_G.GetRealZoneText = function() return "Westfall" end
_G.GetSubZoneText = function() return "Sentinel Hill" end
_G.GetInventoryItemLink = function() return nil end
_G.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() return nil end }
_G.C_AddOns = { GetAddOnMetadata = function() return "0.0.0" end }

local DAY = 86400
local function obj(text, done) return { text = text, done = done } end

-- Alyra's log, in the game's order: Zephras Isle (3: ready, half done, nothing to count), Shaman (1),
-- Elwynn Forest (1), and two saved before headings were recorded; plus entries that aren't quests.
local alyraLog = {
  { id = 86001, title = "Gustberry Harvest", level = 9, header = "Zephras Isle",
    objectives = { obj("Gustberry: 8/8", true) } },
  { id = 86002, title = "The Lowland Raiders", level = 10, header = "Zephras Isle",
    objectives = { obj("Lowland Raider slain: 6/10", false), obj("Raider Chief slain: 1/1", true) } },
  { id = 333, title = "Call of Fire", level = 10, header = "Shaman",
    objectives = { obj("Fire Totem", true), obj(nil, false), obj("Fire Sapta", false) } },
  "junk",
  { id = 86003, title = "Speak with Elder", level = 8, header = "Zephras Isle", objectives = {} },
  { id = 54, title = "Report to Goldshire", level = 5, header = "Elwynn Forest" },
  { id = 86012, level = "x", objectives = "nope" }, -- no title, an unreadable level, no list: before headings
  { title = "Old Errand", level = 0 / 0, header = "", objectives = { "junk", obj("Done thing", true) } },
}

_G.RynaDB = {
  schema = 1,
  settings = {},
  journal = {},
  characters = {
    [ME] = { guid = ME, fullName = "Brennic-Ashgrove", firstName = "Brennic", class = "PALADIN", level = 17,
      lastSeen = F.now - DAY, quests = { active = {}, completed = {} } },
    [ALT] = { guid = ALT, fullName = "Alyra-Dawnmere", firstName = "Alyra", class = "MAGE", level = 22,
      lastSeen = F.now - 4 * DAY, quests = { active = alyraLog, completed = { 1, 2 } } },
    [ALT2] = { guid = ALT2, fullName = "Zed-Stone", firstName = "Zed", class = "WARRIOR", level = 12,
      lastSeen = F.now - 2 * 3600, quests = { active = {
        { id = 7, title = "Kobold Camp Cleanup", level = 3, header = "Northshire",
          objectives = { obj("Kobold Vermin slain: 10/10", true) } },
      }, completed = {} } },
    [EMPTY] = { guid = EMPTY, fullName = "Nim-Stone", firstName = "Nim", class = "ROGUE", level = 1 },
  },
}

local core = {}
F.LoadAddon(CORE, "Ryna_Core", core)
F.Fire("ADDON_LOADED", "Ryna_Core")
local ns = {}
F.LoadAddon(CHRON, "Ryna_Chronicle", ns)
F.Fire("ADDON_LOADED", "Ryna_Chronicle")
F.Fire("PLAYER_LOGIN")
F.Fire("PLAYER_ENTERING_WORLD", true, false)
F.DropTimers()

local Wn = core.Window
local Ch = ns.Characters
check(type(Ch.QuestLog) == "function", "Characters has the quest log")

-- The picker: hidden with All characters, Character and Quests with one picked. ------------------------
SlashCmdList.RYNACHRONICLE("characters")
local f = Wn.frame
eq(Wn.Selected(), "characters", "on Characters")
check(not f.filter:IsShown(), "All characters: no view picker")
eq(f.title:GetText(), "Characters", "its title as before")
Wn.Choose(ALT)
check(f.filter:IsShown(), "one character: the view picker")
eq(f.filter:GetText(), "Character", "Character first")
eq(f.title:GetText(), "Characters", "the detail's title as before")
eq(plain(f.rows[1].cols[1]:GetText()), "Character", "the detail as before: the Character group first")

_G.Ryna.Window.SetFilter("characters", Ch.QUESTS)
eq(Wn.ctx.filter, "quests", "on Quests")
eq(f.filter:GetText(), "Quests", "the picker says Quests")
eq(f.title:GetText(), "Alyra-Dawnmere › Quests", "the title names the character")

-- The counts and the columns. -------------------------------------------------------------------------
eq(f.headCells[1]:GetText(), "7 active · 2 ready to turn in", "the counts line: seven quests, two ready")
eq(f.headCells[2]:GetText() .. "|" .. f.headCells[3]:GetText(), "Level|Progress", "Level and Progress")
for c = 1, 3 do check(not f.headButtons[c]:IsShown(), "column " .. c .. " doesn't sort (the groups stay)") end
eq(f.tiles[1]:IsShown(), false, "no tiles over the quests")

-- The groups: Zephras Isle (3) first, then the ones with one, by name, then before headings. -----------
local rows = Wn.views.characters.rows
local seen = {}
for _, r in ipairs(rows) do seen[#seen + 1] = (r.header and "# " or "") .. plain(r.cells[1]) end
eq(table.concat(seen, " / "), table.concat({
  "# Zephras Isle (3)", "Gustberry Harvest", "The Lowland Raiders", "Speak with Elder",
  "# Elwynn Forest (1)", "Report to Goldshire",
  "# Shaman (1)", "Call of Fire",
  "# Picked up before this was recorded (2)", "quest 86012", "Old Errand",
}, " / "), "groups by size then name, quests in the log's order, the unrecorded last")

local function rowNamed(name)
  for _, r in ipairs(rows) do if not r.header and plain(r.cells[1]) == name then return r end end
end
-- Ready: "ready" on a full bar.
local r = rowNamed("Gustberry Harvest")
eq(r.cells[2] .. "|" .. r.cells[3], "9|ready", "a ready quest: its level and ready")
eq(r.bars[3].value .. "/" .. r.bars[3].max, "1/1", "on a full bar")
-- Partly done: objectives done of objectives.
r = rowNamed("The Lowland Raiders")
eq(r.cells[3], "1 / 2", "half its objectives done")
eq(r.bars[3].value .. "/" .. r.bars[3].max, "1/2", "half a bar")
r = rowNamed("Call of Fire")
eq(r.cells[2] .. "|" .. r.cells[3], "10|1 / 3", "a third done, an objective with no text counted")
-- Nothing to count: no bar.
r = rowNamed("Speak with Elder")
eq(r.cells[3], "", "no objectives: no text")
eq(r.bars[3], nil, "and no bar")
eq(rowNamed("Report to Goldshire").bars[3], nil, "no objectives list: no bar")
-- Unreadable fields.
r = rowNamed("quest 86012")
eq(r.cells[2] .. "|" .. r.cells[3], "|", "an unreadable level and objectives: nothing shown")
eq(r.bars[3], nil, "and no bar")
r = rowNamed("Old Errand")
eq(r.cells[2], "", "a NaN level: nothing shown")
eq(r.cells[3], "ready", "an objective that isn't a table isn't counted")

-- Drawn: the bars in the Progress column.
local function drawn(name)
  for i = 1, Wn.visible do
    local row = f.rows[i]
    if row:IsShown() and plain(row.cols[1]:GetText()) == name then return row end
  end
end
local d = drawn("The Lowland Raiders")
check(d and d.bars[3]:IsShown(), "the progress bar is drawn")
eq(d and d.bars[3].text:GetText(), "1 / 2", "with its text on it")
d = drawn("Speak with Elder")
check(d and not d.bars[3]:IsShown(), "no bar drawn for a quest with nothing to count")

-- The footer.
eq(f.footer:GetText(), "From your saved file, as Alyra-Dawnmere last logged out, 4 days ago.",
  "the footer: the saved file, its last logout, how long ago")

-- The tooltip: the objectives as saved.
local tip = _G.GameTooltip
tip.lines = {}
Ch.QuestTooltip(rowNamed("The Lowland Raiders"), tip)
local lines = {}
for _, l in ipairs(tip.lines) do lines[#lines + 1] = l.left end
eq(table.concat(lines, " / "), "The Lowland Raiders / Level 10 / Zephras Isle /   / Lowland Raider slain: 6/10"
  .. " / Raider Chief slain: 1/1 (done)", "the tooltip lists each objective's own text")
tip.lines = {}
Ch.QuestTooltip(rowNamed("Speak with Elder"), tip)
eq(tip.lines[#tip.lines].left, "No objectives to count were saved for this quest.", "nothing to count, said")

-- Search: a title, or a heading (all its quests).
local ctx = { character = ALT, current = ME, search = "raiders", filter = Ch.QUESTS }
local found = Ch.QuestRows(ctx)
eq(#found, 2, "a title search: its heading and the quest")
eq(found[1].cells[1], "Zephras Isle (1)", "the heading counts what is shown")
ctx.search = "shaman"
found = Ch.QuestRows(ctx)
eq(#found == 2 and found[2].cells[1], "Call of Fire", "a heading search: its quests")

-- The no-header group absent: every quest has its heading. ---------------------------------------------
Wn.Choose(ALT2)
rows = Wn.views.characters.rows
eq(#rows, 2, "one heading, one quest")
eq(rows[1].cells[1], "Northshire (1)", "its heading")
for _, x in ipairs(rows) do
  check(not (x.header and x.cells[1]:find("Picked up", 1, true)), "no 'Picked up before' group when there are none")
end
eq(f.headCells[1]:GetText(), "1 active · 1 ready to turn in", "its counts")
eq(f.footer:GetText(), "From your saved file, as Zed-Stone last logged out, 2 hours ago.", "its footer")

-- An empty log (no quests table at all). --------------------------------------------------------------
Wn.Choose(EMPTY)
rows = Wn.views.characters.rows
eq(#rows, 1, "an empty log: one line")
eq(plain(rows[1].cells[1]), "No quests in this character's log.", "saying so")
eq(f.headCells[1]:GetText(), "0 active · 0 ready to turn in", "and zero counts")
local log = Ch.QuestLog(nil)
eq(log.active .. "/" .. log.ready .. "/" .. #log.groups .. "/" .. #log.unrecorded, "0/0/0/0", "no record: nothing")
log = Ch.QuestLog({ quests = { active = "nope" } })
eq(log.active, 0, "a log that isn't a list: nothing")

-- The character you're on: live, and the footer says so. ----------------------------------------------
Wn.Choose(ME)
eq(f.title:GetText(), "Brennic-Ashgrove › Quests", "the one you're on")
eq(f.footer:GetText(), "Counted in game for Brennic-Ashgrove, the character you're on.", "its footer: live")

-- Back to All characters: the picker hides, the list is as before; Character again for the detail.
Wn.Choose(nil)
check(not f.filter:IsShown(), "All characters: the picker hides again")
eq(f.headCells[1]:GetText(), "Character", "the all-characters columns")
_G.Ryna.Window.SetFilter("characters", nil)
Wn.Choose(ALT)
eq(plain(f.rows[1].cols[1]:GetText()), "Character", "Character: the detail as before")

check(#F.chat == 0, "nothing in chat: " .. table.concat(F.chat, " / "))
check(core.errors.count == 0, "no errors caught: " .. tostring(core.errors.last))
print(string.format("characters quests: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
