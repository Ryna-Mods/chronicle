-- What the dungeon run views say (RunView.lua), from runs built by hand, with the real core and
-- Chronicle loaded over the fake client: the clock and number formats; the strip mid-run, paused and
-- at the level cap; the card with and without an earlier run, with a wipe, splits faster and slower,
-- the fastest run's bosses still to come; the summary so far and closed, best and not, a partial run
-- never best (through the real Runs.Compare), the damage and healing tile on and off, the drops and
-- the last line; Dungeons › Runs' tiles, rows and an opened dungeon. From the repository root:
--
--   lua5.1 test/run_views_test.lua
-- luacheck: ignore 1

local H = dofile("test/run_harness.lua")
local check, eq = H.check, H.eq
local ns = H.Load()
local V = ns.RunView
local F = H.F
check(V ~= nil, "RunView loads")

-- Formats. -------------------------------------------------------------------------------------------
eq(V.Clock(1450), "24:10", "a clock under an hour")
eq(V.Clock(3850), "1:04:10", "a clock past an hour")
eq(V.Clock(59.9), "0:59", "seconds are floored")
eq(V.Diff(-22), "-0:22", "faster")
eq(V.Diff(70), "+1:10", "slower")
eq(V.Diff(0), "0:00", "the same")
eq(V.Short(999), "999", "under a thousand")
eq(V.Short(8620), "8.6k", "thousands with a tenth")
eq(V.Short(21400), "21.4k", "21.4k")
eq(V.Short(9000), "9k", "no .0")
eq(V.Short(412000), "412k", "past a hundred thousand, whole")
eq(V.Short(1234567), "1.2m", "millions")
eq(V.BossText(2), "2 bosses", "bosses without a count")
eq(V.BossText(1), "1 boss", "one boss")
eq(V.BossText(2, 6), "2 of 6 bosses", "with a count, once one is known")
check(V.Capped(60, 60, 0) and V.Capped(20, 60, 0) and not V.Capped(20, 60, 5000) and V.Capped(60, 60, 5000),
  "the level cap: at the top level, or no experience to the next")

local adv = V.Advance({ seconds = 100, paused = false, inCombat = true, combatSeconds = 10, xp = { total = 3600 } }, 20)
eq(adv.seconds, 120, "Advance: the timer runs")
eq(adv.combatSeconds, 30, "Advance: in combat, so does the combat time")
eq(math.floor(adv.xpPerHour + 0.5), 108000, "Advance: the rate follows")
local still = V.Advance({ seconds = 100, paused = true, outsideFor = 60 }, 20)
eq(still.seconds, 100, "Advance paused: the timer stops")
eq(still.outsideFor, 80, "Advance paused: the time outside runs")

-- The strip. ------------------------------------------------------------------------------------------
local function midRun()
  return {
    id = "r1", mapId = 36, instance = "The Deadmines", seconds = 1450, paused = false, xpPerHour = 21400,
    kills = { n = 88 }, loot = { n = 31 }, xp = { total = 2640 }, combatSeconds = 842, deaths = 0,
    worth = { coin = 1800, vendor = 3100, auction = 6300, total = 11200 },
    bosses = { { encounterId = 1, name = "Rhahk'Zor", success = true, split = 340 },
      { encounterId = 2, name = "Sneed", success = true, split = 895 } },
    party = { size = 5 }, level = { from = 19, to = 19 },
  }
end
local s = V.Strip(midRun())
eq(s.name, "The Deadmines", "strip: the dungeon")
eq(s.clock, "24:10", "strip: the timer")
eq(table.concat(s.parts, "|"), "21.4k xp/hr|88 kills|2 bosses|1g 12s", "strip: xp/hr, kills, bosses, worth")
check(not s.paused and s.note == nil, "strip: not paused, no note")
local line = F.Plain(V.StripText(s))
eq(line, "The Deadmines  ·  24:10  ·  21.4k xp/hr  ·  88 kills  ·  2 bosses  ·  1g 12s", "strip: one line")

local paused = midRun()
paused.paused, paused.outsideFor = true, 300
s = V.Strip(paused)
eq(s.clock, "24:10 paused", "paused: the timer stops and says so")
eq(#s.parts, 0, "paused: the numbers leave")
eq(s.note, "Back inside within 25:00 to carry on", "paused: the time left of the 30 minutes")

s = V.Strip(midRun(), { capped = true })
eq(table.concat(s.parts, "|"), "2 bosses|31 drops|1g 12s", "at the cap: xp/hr and kills give way to drops")

-- The card. --------------------------------------------------------------------------------------------
local fastestRun = { bosses = {
  { encounterId = 1, name = "Rhahk'Zor", success = true, split = 362 },
  { encounterId = 2, name = "Sneed", success = true, split = 825 },
  { encounterId = 3, name = "Gilnid", success = true, split = 1170 },
  { encounterId = 4, name = "Mr. Smite", success = true, split = 1625 },
  { encounterId = 5, name = "Captain Greenskin", success = true, split = 1900 },
  { encounterId = 6, name = "Edwin VanCleef", success = true, split = 2200 } } }
local cmp = { runs = 6, fastest = { seconds = 2280, id = "fast", splits = { [1] = 362, [2] = 825, [3] = 1170 } } }
local run = midRun()
run.bosses[3] = { encounterId = 3, name = "Gilnid", success = false, split = 1300 }
local c = V.Card(run, { xp = { cur = 5680, max = 8000, level = 19 }, compare = cmp, fastestRun = fastestRun })
eq(c.name .. " " .. c.clock, "The Deadmines 24:10", "card: name and timer")
eq(c.bar.text, "Level 19 · 71% · +33% this run", "card: the experience bar's words")
check(math.abs(c.bar.share - 0.71) < 1e-9 and math.abs(c.bar.gained - 0.33) < 1e-9
  and math.abs(c.bar.from - 0.38) < 1e-9, "card: the bar's level and this run's part of it")
local rows = {}
for _, r in ipairs(c.rows) do rows[#rows + 1] = r.label .. "=" .. r.value end
eq(table.concat(rows, "|"), "Experience=2,640 · 21.4k/hr|Kills=88|In combat=14:02 of 24:10|Worth=1g 12s|"
  .. "coin · vendor · auction=18s · 31s · 63s|Deaths=0", "card: its rows")
check(c.rows[5].dim, "card: the worth's parts are the dim line")
eq(c.splits[1].state .. " " .. c.splits[1].name .. " " .. c.splits[1].time, "kill Rhahk'Zor 5:40", "split 1")
eq(c.splits[1].diffText, "-0:22", "split 1: 22 seconds faster than the fastest run")
eq(c.splits[1].tone, "good", "faster is good")
eq(c.splits[2].diffText .. " " .. c.splits[2].tone, "+1:10 bad", "split 2: slower")
eq(c.splits[3].state .. " " .. c.splits[3].time, "wipe wipe", "a wipe is shown as a wipe")
check(c.splits[3].diffText == nil, "a wipe compares nothing")
eq(c.splits[4].state .. " " .. c.splits[4].name .. " " .. c.splits[4].time, "next Gilnid best 19:30",
  "the fastest run's next boss, with its split")
eq(c.splits[5].name, "Mr. Smite", "and the one after")
eq(c.splits[6].state .. " " .. c.splits[6].name, "more 2 more", "the rest as a count")
check(c.note == nil, "an earlier run to compare: no note")
local tipText = {}
for _, l in ipairs(V.CardLines(c)) do
  tipText[#tipText + 1] = F.Plain(l[1]) .. (l[2] and ("=" .. F.Plain(l[2])) or "")
end
check(table.concat(tipText, "|"):find("Sneed=14:55  +1:10", 1, true) ~= nil, "the card as tooltip lines")

c = V.Card(midRun(), { compare = { runs = 0 } })
eq(c.note, "Your first run here. Bosses are listed as you meet them.", "first run here: says so")
check(c.splits[1].diffText == nil and #c.splits == 2, "first run: bosses as they die, nothing compared")
check(c.bar == nil, "no experience reading: no bar")
c = V.Card(midRun(), { compare = { runs = 2 } })
eq(c.note, "No full clear here yet to compare with.", "earlier runs but no full clear")
c = V.Card(midRun(), { capped = true, compare = { runs = 0 } })
eq(c.rows[1].value .. "|" .. c.rows[2].value .. "|" .. c.rows[3].label, "none at the level cap|not counted at the "
  .. "level cap|Drops", "card at the cap: says so, and counts drops")
local pulling = midRun()
pulling.pulling = { encounterId = 3, name = "Gilnid" }
c = V.Card(pulling, { compare = { runs = 0 } })
eq(c.splits[3].state .. " " .. c.splits[3].time, "pull fighting", "a boss fight under way")

-- The summary. ------------------------------------------------------------------------------------------
local function closedRun()
  return {
    id = "c7", mapId = 36, instance = "The Deadmines", enteredAt = 1000, seconds = 2280, combatSeconds = 1500,
    xp = { total = 14200 }, kills = { n = 142 }, deaths = 1, party = { size = 5 },
    bosses = { { encounterId = 1, success = true, split = 340 }, { encounterId = 2, success = true, split = 900 },
      { encounterId = 3, success = true, split = 1200 }, { encounterId = 4, success = true, split = 1600 },
      { encounterId = 5, success = true, split = 1900 }, { encounterId = 6, success = true, split = 2250 } },
    worth = { coin = 2000, vendor = 9000, auction = 50000, total = 16600 },
    loot = { n = 61, top = { { id = 5191, qty = 1, vendor = 2000, auction = 41000 },
      { id = 5196, qty = 1, vendor = 3400 }, { id = 2589, qty = 4, vendor = 52 } } },
    level = { from = 19, to = 20 }, quests = { 101, 102 }, durability = { lost = 7, of = 100 },
    meter = { damage = 9000, healing = 412000, damageTaken = 3000 },
  }
end
local info = function(id) return ns.RunSummary.ItemInfo(id) end
local best = { runs = 6, full = true, isFastest = true, vsFastest = -192,
  fastest = { seconds = 2472, id = "c6", splits = {} },
  median = { seconds = 2550, xp = 13650, kills = 130, worth = 12000 } }
local m = V.Summary(closedRun(), { closed = true, compare = best, meter = true, index = 7, top = closedRun().loot.top,
  itemInfo = info })
eq(m.name .. " / " .. m.head, "The Deadmines / run 7 · 5 players", "summary: the head")
local tiles = {}
for _, t in ipairs(m.tiles) do tiles[#tiles + 1] = t.label .. "=" .. t.value .. " (" .. t.sub .. ")" end
eq(table.concat(tiles, "|"), "Time=38:00 (best · was 41:12)|Experience=14,200 (22.4k/hr · median 13.7k)|"
  .. "Worth=1g 66s (median 1g 20s)|Kills=142 (6 bosses)|Deaths=1 (no wipes)|You did=412k (healing · 9k damage)",
  "summary closed, a best: its tiles")
eq(m.tiles[1].tone, "good", "best is good")
eq(#m.drops, 2, "the two most valuable drops")
eq(m.drops[1].name .. " " .. m.drops[1].value .. " q" .. tostring(m.drops[1].quality),
  "Cookie's Stirring Rod 4g 10s auction q3", "drop 1: by its auction value")
eq(m.drops[2].name .. " " .. m.drops[2].value, "Smite's Mighty Hammer 34s vendor", "drop 2: by its vendor value")
eq(m.rest, "59 more drops · level 19 to 20 · 2 quests turned in · wear 7%", "the last line")
check(m.note == nil, "a closed run has no 'go back in'")

m = V.Summary(closedRun(), { closed = true, compare = best, meter = false, index = 7, top = {}, itemInfo = info })
eq(#m.tiles, 5, "the damage and healing tile off: five tiles")
eq(m.rest:sub(1, 8), "61 drops", "no drop priced: all of them in the last line")
local nometer = closedRun()
nometer.meter = nil
eq(#V.Summary(nometer, { closed = true, compare = best, meter = true }).tiles, 5, "no meter numbers: no tile")
local dps = closedRun()
dps.meter = { damage = 250000, healing = 0 }
m = V.Summary(dps, { closed = true, compare = best, meter = true })
eq(m.tiles[6].value .. " " .. m.tiles[6].sub, "250k damage", "a damage dealer's tile")
local unknown = V.Summary(closedRun(), { closed = true, compare = best, top = { { id = 777, qty = 2, vendor = 500 } },
  itemInfo = function() return nil end })
eq(unknown.drops[1].name, "item 777 x2", "an item the client hasn't loaded: by its id")

local slower = { runs = 6, full = true, isFastest = false, vsFastest = 192, fastest = { seconds = 2088 } }
m = V.Summary(closedRun(), { closed = true, compare = slower, index = 8 })
eq(m.tiles[1].sub .. " " .. m.tiles[1].tone, "+3:12 on your best bad", "not the best: the difference")
local noAuction = closedRun()
noAuction.worth = { coin = 2000, vendor = 9000, total = 11000 }
m = V.Summary(noAuction, { closed = true, compare = { runs = 0, full = true, isFastest = true } })
eq(m.tiles[1].sub, "best", "the first full clear is the best, with nothing to be 'was'")
eq(m.tiles[3].sub, "no auction prices", "no Prices table: says so")

local sofar = midRun()
sofar.paused, sofar.outsideFor, sofar.party = true, 600, { size = 3 }
m = V.Summary(sofar, { closed = false, compare = { runs = 6, full = true, isFastest = true, vsFastest = -900,
  fastest = { seconds = 2280 } } })
eq(m.head, "so far · 3 players", "so far: until the run closes")
eq(m.tiles[1].sub, "2 bosses", "so far is never best, nor a difference from a full clear")
eq(m.note, "Go back in within 20:00 and this run carries on.", "so far: the time left to go back in")
sofar.party = { size = 1 }
eq(V.Summary(sofar, {}).head, "so far · solo", "alone: solo")
m = V.Summary(closedRun(), { closed = true, capped = true, compare = best })
eq(m.tiles[2].label .. " " .. m.tiles[2].value, "Drops 61", "summary at the cap: drops in experience's place")

-- A partial run is never the best, through the real Runs.Compare: a full clear and a quick partial one.
local list = {
  { id = "full", mapId = 36, instance = "The Deadmines", enteredAt = 100, leftAt = 2600, seconds = 2472,
    bosses = { { encounterId = 1, success = true, split = 400 }, { encounterId = 2, success = true, split = 2400 } },
    xp = { total = 13000 }, kills = { n = 120 }, worth = { total = 12000 }, loot = { n = 50 } },
  { id = "partial", mapId = 36, instance = "The Deadmines", enteredAt = 5000, leftAt = 6000, seconds = 980,
    bosses = { { encounterId = 1, success = true, split = 380 }, { encounterId = 2, success = false, split = 900 } },
    xp = { total = 5900 }, kills = { n = 40 }, worth = { total = 4800 }, loot = { n = 12 } },
}
RynaDB.chronicle = RynaDB.chronicle or {}
RynaDB.chronicle.runs = { [H.ME] = { list = list, totals = {} } }
local pc = ns.Runs.Compare(list[2])
check(pc.isFastest == false, "Compare: the partial run isn't the fastest")
m = V.Summary(list[2], { closed = true, compare = pc, index = 2 })
check(not m.tiles[1].sub:find("best", 1, true), "a partial run never says best: " .. m.tiles[1].sub)
eq(m.tiles[1].sub, "1 boss · left early", "it says how far it got")
eq(V.RunIndex(list[2], ns.Runs.List(), { [36] = { runs = 4 } }), 6, "run index: four folded, one before it")

-- Dungeons › Runs. ----------------------------------------------------------------------------------------
local t = V.Tiles(ns.Runs.List(), { [36] = { runs = 3, seconds = 7000, xp = 30000 } })
eq(t.runs .. " " .. t.seconds .. " " .. t.xp .. " " .. t.worth, "5 10452 48900 16800",
  "tiles: the list and the totals (worth from the list)")
local instances = ns.Runs.ByInstance()
eq(#instances, 1, "one dungeon")
local agoSeen
rows = V.DungeonRows(instances, ns.Runs.List(), ns.Runs.Totals(), {}, function(at)
  agoSeen = at
  return "a while ago"
end)
eq(#rows, 1, "closed: one row per dungeon")
eq(table.concat(rows[1].cells, "|"),
  "The Deadmines|2|41:12|28:46||" .. V.Short(instances[1].xpPerHour) .. "|a while ago",
  "the dungeon's row: runs, fastest, median, bar, xp an hour, last run")
eq(agoSeen, 6000, "last run is the newest's leaving")
check(rows[1].bars[5].value == 2472 and rows[1].bars[5].max == 1726, "the bar: fastest against median")
rows = V.DungeonRows(instances, ns.Runs.List(), ns.Runs.Totals(), { [36] = true })
eq(#rows, 3, "opened: its two runs under it")
check(rows[1].open and rows[2].kind == "run" and rows[2].run.id == "partial", "newest run first")
eq(rows[2].cells[2] .. " " .. rows[2].cells[3] .. " " .. rows[2].cells[4], "1/2 16:20 left early", "the partial run")
eq(rows[3].cells[2] .. " " .. rows[3].cells[3] .. " " .. rows[3].cells[4], "2/2 41:12 best", "the full clear: best")
eq(rows[3].cells[6] .. " " .. rows[3].cells[7], "13,000 1g 20s", "a run's experience and worth")
check(rows[2].cells[1] ~= "", "a run's date")
rows = V.DungeonRows(instances, ns.Runs.List(), { [36] = { fastest = 2000 } }, { [36] = true })
eq(rows[3].cells[4], "", "a faster run folded into the totals: no run in the list is marked best")

H.check(H.core.errors.count == 0, "no errors caught: " .. tostring(H.core.errors.last))
H.done("run views")
