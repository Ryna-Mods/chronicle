-- Loot rolls on a dungeon run (Runs.lua's drops, RunView.lua's words, the card and the summary), with
-- the real core and Chronicle over the fake client and its loot history (C_LootHistory as Forever has
-- it, /ryna probe 2026-11-23): a drop recorded, then updated in place (never twice); the winner and the
-- rolls read; roll states through the client's enum and through the numbers seen in game; secret,
-- absent and malformed fields skipped; a drop read again when the run pauses and closes; the 60-drop
-- cap; `drops` absent on the event with none; names kept with "record group members" off and no GUID
-- anywhere; a key from a closed run never taken again; a client without C_LootHistory; and the view's
-- lines for a decided drop, an undecided one and one everyone passed on. From the repository root:
--
--   lua5.1 test/run_drops_test.lua
-- luacheck: ignore 1

local H = dofile("test/run_harness.lua")
local check, eq = H.check, H.eq
local F = H.F

-- A secret: reading into it, comparing or printing it raises, as the client's do.
local SECRET = setmetatable({}, {
  __index = function() error("a secret was indexed") end,
  __tostring = function() error("a secret was turned into text") end,
  __eq = function() error("a secret was compared") end,
  __lt = function() error("a secret was compared") end,
  __le = function() error("a secret was compared") end,
  __concat = function() error("a secret was concatenated") end,
})
_G.issecretvalue = function(v) return rawequal(v, SECRET) end

-- "Record group members" off: the party keeps no names, the rolls still do (her call, 2026-11-23).
local ns, core = H.Load({ db = { schema = 1, settings = { census = true, groupMembers = false }, journal = {},
  characters = {} } })
local R, V, S = ns.Runs, ns.RunView, ns.RunSummary
F.LootHistory()

local BOSS = 3480
local LINK = "|cff1eff00|Hitem:132539::::::::23:::::|h[Glinteye Slippers]|h|r"
local function runEvents()
  local out = {}
  for _, e in ipairs(RynaDB.journal) do if e.type == "run" then out[#out + 1] = e end end
  return out
end
local function lastRun() local e = runEvents(); return e[#e] end

-- Whether any key or string in t (deeply) looks like a GUID.
local function hasGuid(t)
  if type(t) == "string" then return t:find("Player%-") ~= nil end
  if type(t) ~= "table" then return false end
  for k, v in pairs(t) do
    if type(k) == "string" and k:lower():find("guid") then return true end
    if hasGuid(v) then return true end
  end
  return false
end

H.Enter(H.DM)
F.Fire("ENCOUNTER_START", BOSS, "Mr. Smite", 1, 5)
H.Later(40)
F.Fire("ENCOUNTER_END", BOSS, "Mr. Smite", 1, 5, 1)

-- A drop while people choose: no winner yet. -------------------------------------------------------
F.Drop(BOSS, { lootListKey = 9193473, itemHyperlink = LINK, allPassed = false, duration = 180000, isTied = false,
  playerRollState = 4, startTime = 902567149,
  rollInfos = {
    { playerName = "Brennic", playerClass = "PALADIN", playerGUID = "Player-91-0000000A", state = 4, isSelf = true },
    { playerName = "Sam Hammiche", playerClass = "WARLOCK", playerGUID = "Player-6921-007EA58B", state = 0 },
  } })
local firstSeen = F.now
F.Fire("LOOT_HISTORY_UPDATE_DROP", BOSS, 9193473)
local d = R.Current().drops
eq(#d, 1, "the drop is recorded")
eq(d[1].key .. " " .. d[1].encounterId .. " " .. d[1].itemId, "9193473 3480 132539", "its key, boss and item id")
eq(d[1].name, "Glinteye Slippers", "the item's name from the link")
eq(d[1].at, firstSeen, "when it was first seen")
check(d[1].winner == nil and d[1].allPassed == nil, "undecided: no winner, allPassed absent")
eq(#d[1].rolls, 2, "both rolls read")
eq(d[1].rolls[1].type .. " " .. tostring(d[1].rolls[1].self) .. " " .. tostring(d[1].rolls[1].roll), "none true nil",
  "the player's own roll before choosing: none, self, no number")
eq(d[1].rolls[2].name .. " " .. d[1].rolls[2].class .. " " .. d[1].rolls[2].type, "Sam Hammiche WARLOCK need",
  "another player's: the name with its space, the class, need")
check(d[1].rolls[2].self == nil and d[1].rolls[2].won == nil, "self and won absent unless true")

-- The same drop decided: replaced, not added. -------------------------------------------------------
H.Later(30)
F.Drop(BOSS, { lootListKey = 9193473, itemHyperlink = LINK, allPassed = false, playerRollState = 3,
  winner = { isSelf = false, isWinner = true, playerClass = "WARLOCK", playerGUID = "Player-6921-007EA58B",
    playerName = "Sam Hammiche", roll = 23, state = 0 },
  rollInfos = {
    { playerName = "Brennic", playerClass = "PALADIN", playerGUID = "Player-91-0000000A", state = 3, roll = 61,
      isSelf = true, isWinner = false },
    { playerName = "Sam Hammiche", playerClass = "WARLOCK", playerGUID = "Player-6921-007EA58B", state = 0, roll = 23,
      isWinner = true },
    "not a roll", {}, { playerName = SECRET, playerClass = "PRIEST", state = 5, isSelf = SECRET, roll = SECRET },
    { state = 9 },
  } })
F.Fire("LOOT_HISTORY_UPDATE_DROP", BOSS, 9193473)
F.Fire("LOOT_ROLLS_COMPLETE", 9193473)
d = R.Current().drops
eq(#d, 1, "an update replaces the drop, never a second copy")
eq(d[1].at, firstSeen, "and keeps when it was first seen")
local w = d[1].winner
eq(w.name .. " " .. w.class .. " " .. w.type .. " " .. w.roll, "Sam Hammiche WARLOCK need 23", "the winner")
check(w.self == nil and w.won == nil, "the winner carries no self (not the player) and no won")
eq(#d[1].rolls, 3, "a roll that isn't a table, an empty one and one with nothing known are left out")
eq(d[1].rolls[1].type .. " " .. d[1].rolls[1].roll, "greed 61", "the player's own greed")
check(d[1].rolls[2].won == true and d[1].rolls[1].won == nil, "the winner's roll is marked won")
local sec = d[1].rolls[3]
check(sec.name == nil and sec.roll == nil and sec.self == nil and sec.class == "PRIEST" and sec.type == "pass",
  "secret fields skipped, the plain ones kept")
check(not hasGuid(d), "no GUID anywhere in a drop")

-- Roll states: the client's enum by name, else the numbers seen in game. ---------------------------
eq(R.RollType(0) .. " " .. R.RollType(1) .. " " .. R.RollType(2) .. " " .. R.RollType(3) .. " " .. R.RollType(4)
  .. " " .. R.RollType(5), "need offspec transmog greed none pass", "the enum's six states")
check(R.RollType(9) == nil and R.RollType(SECRET) == nil and R.RollType(nil) == nil, "an unknown state is left out")
Enum.EncounterLootDropRollState = { NeedMainSpec = 10, NeedOffSpec = 11, Transmog = 12, Greed = 13, NoDecision = 14,
  Pass = 15 }
eq(R.RollType(13), "greed", "read through the enum by name")
check(R.RollType(3) == nil, "a number the enum doesn't name isn't guessed")
Enum.EncounterLootDropRollState = { Greed = 3, Pass = 5 }
eq(R.RollType(0) .. " " .. R.RollType(3) .. " " .. R.RollType(4), "need greed none",
  "names the enum lacks fall back to the numbers")
Enum.EncounterLootDropRollState = nil
eq(R.RollType(0) .. " " .. R.RollType(5), "need pass", "no enum: the numbers seen in game")
Enum.EncounterLootDropRollState = { NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoDecision = 4,
  Pass = 5 }

-- What isn't a drop. ----------------------------------------------------------------------------------
F.Drop(BOSS, { lootListKey = 1, itemHyperlink = SECRET })
F.Drop(BOSS, { lootListKey = 2, itemHyperlink = "[No id]" })
F.Drop(BOSS, { lootListKey = SECRET, itemHyperlink = LINK })
F.Drop(BOSS, { lootListKey = 4, itemHyperlink = "|cffffffff|Hitem:2589::::|h[Linen Cloth]|h|r", rollInfos = SECRET,
  winner = SECRET })
F.Fire("LOOT_HISTORY_UPDATE_DROP", BOSS, 1)
F.Fire("LOOT_HISTORY_UPDATE_DROP", BOSS, 2)
F.Fire("LOOT_HISTORY_UPDATE_DROP", BOSS, SECRET)
F.Fire("LOOT_HISTORY_UPDATE_DROP", SECRET, 4)
eq(#R.Current().drops, 1, "a secret link, a link with no item id, a secret key or encounter: nothing recorded")
F.Fire("LOOT_HISTORY_UPDATE_ENCOUNTER", BOSS)
d = R.Current().drops
eq(#d, 2, "the encounter read again: the readable one added")
check(d[2].itemId == 2589 and d[2].rolls == nil and d[2].winner == nil, "secret rolls and winner: absent")

-- Everyone passed, and a roll that times out without another event. --------------------------------
F.Drop(BOSS, { lootListKey = 4, itemHyperlink = "|cffffffff|Hitem:2589::::|h[Linen Cloth]|h|r", allPassed = true,
  rollInfos = { { playerName = "Brennic", playerClass = "PALADIN", state = 5, isSelf = true } } })
F.Fire("LOOT_HISTORY_UPDATE_DROP", BOSS, 4)
eq(R.Current().drops[2].allPassed, true, "everyone passed")
F.Drop(BOSS + 1, { lootListKey = 77, itemHyperlink = "|cff0070dd|Hitem:5191::::|h[Cookie's Stirring Rod]|h|r",
  rollInfos = { { playerName = "Brennic", playerClass = "PALADIN", state = 4, isSelf = true } } })
F.Fire("LOOT_HISTORY_UPDATE_DROP", BOSS + 1, 77)
eq(#R.Current().drops, 3, "a drop of a boss the run has no end for")

-- The views: a decided drop, an all-passed one, an undecided one. ------------------------------------
local cur = R.Current()
eq(F.Plain(V.WinnerText(cur.drops[1])), "Sam Hammiche · Need 23", "decided: the winner and their roll")
eq(V.WinnerText(cur.drops[2]), "Everyone passed", "everyone passed")
eq(V.WinnerText(cur.drops[3]), "Rolling", "undecided on the open run: rolling")
eq(V.WinnerText(cur.drops[3], { closed = true }), "No winner recorded", "undecided on a closed run")
local lines = {}
for _, l in ipairs(V.RollLines(cur.drops[1])) do lines[#lines + 1] = F.Plain(l[1]) .. " = " .. l[2] end
eq(table.concat(lines, " | "), "Brennic (you) = Greed 61 | |TInterface\\RaidFrame\\ReadyCheck-Ready:12|t Sam "
  .. "Hammiche = Need 23 | Someone = Pass", "every roll: the player's own marked, the winner ticked")
local colored = V.RollLines(cur.drops[1], { colour = true })
check(colored[1][1]:find("|cfff58cba", 1, true) == 1, "with colour: the name in its class colour")
local groups = V.BossDrops(cur, { itemInfo = S.ItemInfo })
eq(#groups, 2, "drops by boss: Mr. Smite's, then the boss with no end heard")
eq(groups[1].name .. ": " .. groups[1].drops[1].name .. ", " .. groups[1].drops[2].name,
  "Mr. Smite: Glinteye Slippers, Linen Cloth", "the boss's drops in order, named from the link")
eq(groups[2].name .. ": " .. groups[2].drops[1].name .. " q" .. tostring(groups[2].drops[1].quality),
  "boss 3481: Cookie's Stirring Rod q3", "an unknown boss by its id; the client's name and quality when it has them")

-- The card: each drop under its boss's kill.
local card = V.Card(cur, { compare = { runs = 0 }, itemInfo = S.ItemInfo })
local splits = {}
for _, s in ipairs(card.splits) do splits[#splits + 1] = s.state .. ":" .. F.Plain(s.name) .. "=" .. F.Plain(s.time) end
eq(table.concat(splits, " | "), "kill:Mr. Smite=0:40 | drop:Glinteye Slippers=Sam Hammiche · Need 23 | "
  .. "drop:Linen Cloth=Everyone passed | boss:boss 3481= | drop:Cookie's Stirring Rod=Rolling",
  "the card's splits: drops under the kill, a boss without one after")
local tip = {}
for _, l in ipairs(V.CardLines(card)) do tip[#tip + 1] = F.Plain(l[1]) end
check(table.concat(tip, "|"):find("   Glinteye Slippers", 1, true) ~= nil, "the strip's tooltip shows them too")

-- Paused: nothing new is taken, and the drops are read again (a roll that timed out). ---------------
F.Drop(BOSS + 1, { lootListKey = 77, itemHyperlink = "|cff0070dd|Hitem:5191::::|h[Cookie's Stirring Rod]|h|r",
  winner = { playerName = "Brennic", playerClass = "PALADIN", state = 3, roll = 88, isSelf = true, isWinner = true },
  rollInfos = { { playerName = "Brennic", playerClass = "PALADIN", state = 3, roll = 88, isSelf = true,
    isWinner = true } } })
H.Leave()
cur = R.Current()
check(cur.paused and cur.drops[3].winner and cur.drops[3].winner.roll == 88 and cur.drops[3].winner.self == true,
  "walking out reads the drops again: the timed-out roll is final")
eq(F.Plain(V.WinnerText(cur.drops[3])), "Brennic (you) · Greed 88", "the player's own win")
F.Drop(BOSS, { lootListKey = 5, itemHyperlink = LINK })
F.Fire("LOOT_HISTORY_UPDATE_DROP", BOSS, 5)
eq(#R.Current().drops, 3, "outside: no new reading")

-- The summary frame: bosses, drops, and every roll on hover.
S.Show(R.Current(), false)
local f = S.frame
check(f and f:IsShown(), "the summary shows")
local shown = {}
for _, l in ipairs(f.lootLines) do
  if l:IsShown() then shown[#shown + 1] = F.Plain(l.left:GetText()) .. "=" .. F.Plain(l.right:GetText() or "") end
end
eq(table.concat(shown, " | "), "Mr. Smite= |    Glinteye Slippers=Sam Hammiche · Need 23 |    Linen Cloth=Everyone "
  .. "passed | boss 3481= |    Cookie's Stirring Rod=Brennic (you) · Greed 88", "the summary's loot lines")
f.lootLines[2]._scripts.OnEnter(f.lootLines[2])
local texts = {}
for _, l in ipairs(GameTooltip.lines) do texts[#texts + 1] = F.Plain(l.left) .. (l.right and ("=" .. l.right) or "") end
local joined = table.concat(texts, " | ")
check(joined:find("link item:132539", 1, true) == 1, "the hover: the item's own tooltip first: " .. joined)
check(joined:find("Sam Hammiche · Need 23 | Brennic (you)=Greed 61", 1, true) ~= nil, "then the winner and the rolls")
f.lootLines[2]._scripts.OnLeave(f.lootLines[2])
S.Hide()

-- Closed: the event's drops, as the contract has them. ----------------------------------------------
H.Later(31 * 60)
F.RunTimers()
local e = lastRun()
check(e and type(e.drops) == "table" and #e.drops == 3, "the run's event carries its three drops")
local w1 = e.drops[1]
eq(w1.key .. " " .. w1.encounterId .. " " .. w1.itemId .. " " .. w1.name .. " " .. w1.at,
  "9193473 3480 132539 Glinteye Slippers " .. firstSeen, "a drop on the wire")
check(w1.allPassed == nil and e.drops[2].allPassed == true, "allPassed only when true")
eq(w1.winner.name .. " " .. w1.winner.type .. " " .. w1.winner.roll, "Sam Hammiche need 23", "its winner")
check(w1.winner.self == nil and w1.winner.won == nil, "no self or won on another player's win")
check(#w1.rolls == 3 and w1.rolls[1].self == true and w1.rolls[2].won == true and w1.rolls[1].won == nil,
  "its rolls, self and won only when true")
check(not hasGuid(e.drops), "no GUID anywhere on the wire")
check(e.party.members == nil or #e.party.members == 0 or e.party.members[1].name == nil,
  "the party's names stay off with group members off")
local kept = R.List()[1]
check(kept.drops and #kept.drops == 3 and kept.drops[3].winner.roll == 88, "the closed run keeps them")

-- A new run: a key from the closed run is never taken again; none means no `drops`. ----------------
H.Enter(H.DM)
F.Fire("LOOT_HISTORY_UPDATE_ENCOUNTER", BOSS)
F.Fire("LOOT_HISTORY_UPDATE_DROP", BOSS, 9193473)
eq(#R.Current().drops, 1, "an earlier run's drops aren't taken again")
eq(R.Current().drops[1].key, 5, "only the drop the closed run never had")
H.Leave()
H.Later(31 * 60)
F.RunTimers()
H.Enter(H.SFK)
H.Leave()
H.Later(31 * 60)
F.RunTimers()
check(lastRun().drops == nil, "a run with no drops: `drops` absent on the wire, not an empty table")

-- The cap: 60 drops, oldest first; an update of one still lands. ----------------------------------
H.Enter(H.SFK)
F.loot.encounters = {}
for i = 1, 70 do
  F.Drop(900, { lootListKey = 100000 + i, itemHyperlink = "|Hitem:" .. (1000 + i) .. "::|h[Thing " .. i .. "]|h" })
end
F.Fire("LOOT_HISTORY_UPDATE_ENCOUNTER", 900)
d = R.Current().drops
eq(#d, 60, "at most 60 drops")
eq(d[1].key .. " " .. d[60].key, "100001 100060", "the oldest first, the rest left out")
F.Drop(900, { lootListKey = 100001, itemHyperlink = "|Hitem:1001::|h[Thing 1]|h", allPassed = true })
F.Fire("LOOT_HISTORY_UPDATE_DROP", 900, 100001)
check(#R.Current().drops == 60 and R.Current().drops[1].allPassed == true, "an update at the cap still lands")
local many = {}
for i = 1, 50 do many[i] = { playerName = "P" .. i, state = 3, roll = i } end
F.Drop(900, { lootListKey = 100002, itemHyperlink = "|Hitem:1002::|h[Thing 2]|h", rollInfos = many })
F.Fire("LOOT_HISTORY_UPDATE_DROP", 900, 100002)
eq(#R.Current().drops[2].rolls, 40, "at most 40 rolls, in the game's order")
eq(R.Current().drops[2].rolls[40].name, "P40", "the first forty")

-- The summary at the cap of its lines: the rest counted.
S.Show(R.Current(), false)
local last
for _, l in ipairs(S.frame.lootLines) do if l:IsShown() then last = F.Plain(l.left:GetText()) end end
eq(last, "38 more items rolled for", "past 24 lines, one line counts the rest")
S.Hide()

-- A client without the loot history: nothing breaks, nothing is recorded. --------------------------
_G.C_LootHistory = nil
H.Leave()
H.Later(31 * 60)
F.RunTimers()
check(lastRun().drops and #lastRun().drops == 60, "the run closed with what it had")
H.Enter(H.DM)
F.Fire("LOOT_HISTORY_UPDATE_DROP", BOSS, 9193473)
F.Fire("LOOT_HISTORY_UPDATE_ENCOUNTER", BOSS)
F.Fire("LOOT_ROLLS_COMPLETE", 9193473)
check(R.Current().drops == nil, "no C_LootHistory: no drops")
H.Leave()
H.Later(31 * 60)
F.RunTimers()
check(lastRun().drops == nil, "and the run closes without them")

check(#F.chat == 0, "silent: nothing in chat")
check(core.errors.count == 0, "no errors caught: " .. tostring(core.errors.last))
H.done("run drops")
