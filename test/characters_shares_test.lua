-- Characters, All characters: where the account's gold and time played are (Characters.lua), against
-- the fake client (fake_client.lua): each row's gold and played drawn over a bar of that character's
-- share, the played text carrying the share ("1d 4h · 73%") once more than one character has time,
-- the tiles (Characters and the highest level, Gold and whose when it is all on one, Played and across
-- how many, Last seen), one character on the account, and records with nothing readable (nil, a
-- string, NaN). From the repository root, with Lua 5.1 (what the game runs) or later:
--
--   lua5.1 test/characters_shares_test.lua
--
-- This proves the logic; how the bars look in the default UI and in ElvUI is the game's to show.
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
-- Brennic (you're on it): 39g 87s 86c, 1d 4h played. Alyra: no gold, 10h 22m. Zed: nothing readable.
_G.RynaDB = {
  schema = 1,
  settings = {},
  journal = {},
  characters = {
    [ME] = { guid = ME, fullName = "Brennic-Ashgrove", firstName = "Brennic", lastName = "Ashgrove",
      class = "PALADIN", level = 17, gold = 398786, playedTotal = 100800, playedLevel = 3000, lastSeen = F.now - DAY },
    [ALT] = { guid = ALT, fullName = "Alyra-Dawnmere", firstName = "Alyra", lastName = "Dawnmere", class = "MAGE",
      level = 22, gold = 0, playedTotal = 37320, lastSeen = F.now - 4 * DAY },
    [ALT2] = { guid = ALT2, fullName = "Zed-Stone", firstName = "Zed", lastName = "Stone", class = "WARRIOR",
      level = 1, lastSeen = F.now - 9 * DAY },
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
F.Fire("TIME_PLAYED_MSG", 100800, 3000) -- /played answers for the one you're on (login starts it afresh)

local Wn = core.Window
local Ch = ns.Characters
check(Ch ~= nil and type(Ch.Shares) == "function", "Characters registered, with its shares")

-- The rows, as drawn. --------------------------------------------------------------------------------
SlashCmdList.RYNACHRONICLE("characters")
local f = Wn.frame
eq(Wn.Selected(), "characters", "on Characters")
eq(plain(f.picker:GetText()), "All characters", "All characters")
local function rowFor(name)
  for r = 1, Wn.visible do
    local row = f.rows[r]
    if row:IsShown() and plain(row.cols[1]:GetText()) == name then return row end
  end
end
local me, alyra, zed = rowFor("Brennic-Ashgrove"), rowFor("Alyra-Dawnmere"), rowFor("Zed-Stone")
check(me and alyra and zed, "a row for each of the three characters")
local function barOf(row, c)
  local bar = row.bars[c]
  return bar, select(2, bar:GetMinMaxValues())
end

-- Gold: all of it on Brennic, a full bar; Alyra's 0 and Zed's nothing are empty bars.
local bar, max = barOf(me, 3)
check(bar:IsShown(), "Brennic's gold is over a bar")
eq(bar.text:GetText(), "39g 87s 86c", "Brennic's gold, as today")
eq(bar:GetValue() .. "/" .. max, "398786/398786", "all the account's gold: a full bar")
eq(me.cols[3]:GetText(), "", "the gold's text is on the bar, not under it")
bar, max = barOf(alyra, 3)
check(bar:IsShown(), "Alyra's gold bar is drawn")
eq(bar:GetValue() .. "/" .. max, "0/398786", "no gold: an empty bar")
eq(bar.text:GetText(), "0c", "Alyra's 0 shown as today")
bar = barOf(zed, 3)
check(bar:IsShown(), "Zed's gold bar is drawn though nothing is recorded")
eq(bar:GetValue(), 0, "no gold recorded: an empty bar")
eq(bar.text:GetText(), "", "no gold recorded: its number as today (nothing)")

-- Played: shares of 138,120 s, in the text once more than one character has time.
bar, max = barOf(me, 4)
eq(bar.text:GetText(), "1d 4h · 73%", "Brennic's played with its share")
eq(bar:GetValue() .. "/" .. max, "100800/138120", "its bar is its share")
bar = barOf(alyra, 4)
eq(bar.text:GetText(), "10h 22m · 27%", "Alyra's played with its share")
bar = barOf(zed, 4)
eq(bar.text:GetText(), "pending", "no time played recorded: pending, as today")
eq(bar:GetValue(), 0, "and an empty bar")
check(me.bars[2]:IsShown(), "the level's experience bar is still drawn")

-- The rows still sort by the numbers, not the text over the bars.
Wn.SortBy(3)
eq(plain(f.rows[1].cols[1]:GetText()), "Brennic-Ashgrove", "most gold first")
Wn.SortBy(3)
Wn.SortBy(3)
Wn.SortBy(4)
eq(plain(f.rows[1].cols[1]:GetText()), "Brennic-Ashgrove", "most played first")
eq(plain(f.rows[3].cols[1]:GetText()), "Zed-Stone", "nothing played last")
Wn.SortBy(4)
Wn.SortBy(4)

-- The tiles.
eq(f.tiles[1].label:GetText() .. " " .. f.tiles[1].value:GetText() .. " " .. f.tiles[1].sub:GetText(),
  "Characters 3 highest level 22", "Characters, and the highest level")
eq(f.tiles[2].value:GetText() .. " / " .. f.tiles[2].sub:GetText(), "39g 87s 86c / all on Brennic",
  "Gold: the total, all on one character")
eq(f.tiles[3].value:GetText() .. " / " .. f.tiles[3].sub:GetText(), "1d 14h / across 2 characters",
  "Played: the total, across the two with time")
eq(f.tiles[4].label:GetText() .. " " .. f.tiles[4].value:GetText() .. " / " .. f.tiles[4].sub:GetText(),
  "Last seen 4 days ago / Alyra", "Last seen: the last other character seen")

-- Gold on two characters: no "all on"; the bars are the shares.
local ctx = { character = nil, current = ME, search = "" }
RynaDB.characters[ALT].gold = 398786
local tiles = Ch.AllTiles(ctx)
eq(tiles[2].sub, nil, "gold on two characters: no one named")
local rows = Ch.AllRows(ctx)
eq(rows[1].bars[3].value .. "/" .. rows[1].bars[3].max, "398786/797572", "half the gold: half a bar")

-- Unreadable values: a string, NaN, a negative, a missing record field. ------------------------------
RynaDB.characters[ALT].gold = "lots"
RynaDB.characters[ALT].playedTotal = 0 / 0
RynaDB.characters[ALT2].gold = -5
local s = Ch.Shares()
eq(s.gold[ALT], nil, "gold that isn't a number: unreadable")
eq(s.played[ALT], nil, "NaN played: unreadable")
eq(s.goldTotal, 398786, "a negative gold adds nothing to the total")
eq(s.withTime, 1, "only Brennic has time now")
rows = Ch.AllRows(ctx)
local byName = {}
for _, r in ipairs(rows) do byName[plain(r.cells[1])] = r end
eq(byName["Alyra-Dawnmere"].cells[3], "", "unreadable gold: no number")
eq(byName["Alyra-Dawnmere"].bars[3].value, 0, "unreadable gold: an empty bar")
eq(byName["Alyra-Dawnmere"].cells[4], "pending", "unreadable played: pending")
eq(byName["Brennic-Ashgrove"].cells[4], "1d 4h", "one character with time: no share in its text")
eq(byName["Brennic-Ashgrove"].bars[4].value .. "/" .. byName["Brennic-Ashgrove"].bars[4].max, "100800/100800",
  "and its bar is full")
tiles = Ch.AllTiles(ctx)
eq(tiles[3].sub, nil, "one character with time: no 'across'")
for _, r in ipairs(rows) do
  for c = 3, 4 do
    local b = r.bars[c]
    check(type(b) == "table" and b.max > 0 and b.value >= 0 and b.value <= b.max,
      "every gold and played bar is drawable (" .. plain(r.cells[1]) .. ", column " .. c .. ")")
  end
end

-- One character on the account. ------------------------------------------------------------------------
RynaDB.characters[ALT], RynaDB.characters[ALT2] = nil, nil
rows = Ch.AllRows(ctx)
eq(#rows, 1, "one character, one row")
eq(rows[1].cells[4], "1d 4h", "no share in the played text")
eq(rows[1].bars[3].value .. "/" .. rows[1].bars[3].max, "398786/398786", "its gold bar is full")
tiles = Ch.AllTiles(ctx)
eq(tiles[1].value .. " " .. tiles[1].sub, "1 highest level 17", "Characters: 1, its level")
eq(tiles[2].value, "39g 87s 86c", "Gold: its gold")
eq(tiles[2].sub, nil, "no 'all on' with one character")
eq(tiles[3].value, "1d 4h", "Played: its time")
eq(tiles[3].sub, nil, "no 'across' with one character")
eq(tiles[4].value .. " / " .. tiles[4].sub, "now / Brennic", "Last seen: the one you're on, now")

-- Nothing readable at all: no total, no shares, nothing breaks.
RynaDB.characters[ME].gold, RynaDB.characters[ME].playedTotal, RynaDB.characters[ME].level = nil, nil, nil
ns.Character.playedAt = nil -- as before /played answers
rows = Ch.AllRows(ctx)
eq(rows[1].cells[3] .. "|" .. rows[1].cells[4], "|pending", "no gold, no played")
eq(rows[1].bars[3].value .. "/" .. rows[1].bars[3].max, "0/1", "an empty gold bar")
tiles = Ch.AllTiles(ctx)
eq(tiles[1].sub, nil, "no level recorded: no 'highest level'")
eq(tiles[3].value, "pending", "Played: pending")
Wn.Draw()

check(#F.chat == 0, "nothing in chat: " .. table.concat(F.chat, " / "))
check(core.errors.count == 0, "no errors caught: " .. tostring(core.errors.last))
print(string.format("characters shares: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
