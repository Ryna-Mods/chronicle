-- RunView: what the dungeon run views say (ryna_agent docs/ryna-agent-cores-mods.md 7.7, "In game"),
-- as plain tables of words and numbers. Nothing here calls the client or makes a frame: the strip and
-- the card (RunDisplay.lua), the summary on leaving (RunSummary.lua) and Dungeons › Runs (Dungeons.lua)
-- draw what these return. Every input is a run as Runs.lua hands it over (Runs.Current() for the open
-- one, an entry of Runs.List() for a closed one) and, where a view compares, Runs.Compare()'s answer.
--
--   V.Clock(s)             "24:10", "1:04:10"
--   V.Diff(s)              "+1:10", "-0:22", "0:00"
--   V.Short(n)             "8.6k", "21.4k", "412k", "1.2m"; under a thousand as it is
--   V.Bosses(run)          killed, pulled (distinct encounters), wipes
--   V.BossText(k, total)   "2 bosses", or "2 of 6 bosses" when a boss count is known (none is yet)
--   V.Advance(view, dt)    the open run's view dt seconds later (the timer between refreshes)
--   V.Strip(run, opts)     the strip's segments
--   V.Card(run, opts)      the card's bar, rows and splits (and V.CardLines for the strip's tooltip)
--   V.Summary(run, opts)   the summary's head, tiles, drops and last line
--   V.Tiles(list, totals), V.DungeonRows(instances, list, totals, open)   Dungeons › Runs
--
-- opts.capped is "no experience possible here" (the level cap): experience and kills leave, drops take
-- their place (the game gives no kill count without experience).

local _, ns = ...
if ns.off then return end
local L = ns.L

local V = {}
ns.RunView = V

V.SEP = "  ·  "
local OUTSIDE_LIMIT = 30 * 60
local UPCOMING = 2 -- the fastest run's bosses still to come, by name, on the card

local function n0(v)
  if type(v) == "number" and v == v then return v end
  return 0
end

local function tab(v)
  if type(v) == "table" then return v end
  return {}
end

local function number(n) return ns.Session.Number(n) end
local function money(c) return ns.Session.Money(c) end

function V.Clock(seconds)
  local s = math.floor(math.max(0, n0(seconds)))
  local h, m, sec = math.floor(s / 3600), math.floor(s / 60) % 60, s % 60
  if h > 0 then return string.format("%d:%02d:%02d", h, m, sec) end
  return string.format("%d:%02d", m, sec)
end

function V.Diff(seconds)
  local d = math.floor(n0(seconds) + 0.5)
  if d > 0 then return "+" .. V.Clock(d) end
  if d < 0 then return "-" .. V.Clock(-d) end
  return V.Clock(0)
end

function V.Short(n)
  n = n0(n)
  local a = math.abs(n)
  local sign = n < 0 and "-" or ""
  if a < 1000 then return sign .. tostring(math.floor(a + 0.5)) end
  local unit, v = L["%sk"], a / 1000
  if a >= 1000000 then unit, v = L["%sm"], a / 1000000 end
  local text
  if v >= 100 then
    text = tostring(math.floor(v + 0.5))
  else
    local tenths = math.floor(v * 10 + 0.5)
    if tenths % 10 == 0 then
      text = tostring(math.floor(tenths / 10))
    else
      text = string.format("%d.%d", math.floor(tenths / 10), tenths % 10)
    end
  end
  return sign .. string.format(unit, text)
end

-- Experience an hour from a total and a time (under a minute counts as a minute, as Runs.lua does).
function V.PerHour(amount, seconds)
  return n0(amount) * 3600 / math.max(n0(seconds), 60)
end

function V.Bosses(run)
  local killed, pulled, wipes = {}, {}, 0
  for _, b in ipairs(tab(type(run) == "table" and run.bosses)) do
    if type(b) == "table" and b.encounterId ~= nil then
      pulled[b.encounterId] = true
      if b.success then killed[b.encounterId] = true else wipes = wipes + 1 end
    end
  end
  local k, p = 0, 0
  for _ in pairs(killed) do k = k + 1 end
  for _ in pairs(pulled) do p = p + 1 end
  return k, p, wipes
end

function V.BossText(killed, total)
  if type(total) == "number" and total > 0 then return string.format(L["%d of %d bosses"], killed, total) end
  return ns.Plural(killed, L["%d boss"], L["%d bosses"])
end

function V.Name(run)
  if type(run.instance) == "string" and run.instance ~= "" then return run.instance end
  return string.format(L["instance %s"], tostring(run.mapId or "?"))
end

-- The time left to come back in before a paused run closes.
function V.TimeLeft(run)
  return math.max(0, OUTSIDE_LIMIT - n0(run.outsideFor))
end

function V.Capped(level, maxLevel, xpMax)
  if type(xpMax) == "number" and xpMax <= 0 then return true end
  return type(level) == "number" and type(maxLevel) == "number" and maxLevel > 0 and level >= maxLevel
end

-- The open run's view dt seconds after it was read: the clocks that run, and the rate that follows.
function V.Advance(view, dt)
  dt = math.max(0, n0(dt))
  if type(view) ~= "table" or dt == 0 then return view end
  local out = {}
  for k, v in pairs(view) do out[k] = v end
  if view.paused then
    out.outsideFor = n0(view.outsideFor) + dt
  else
    out.seconds = n0(view.seconds) + dt
    if view.inCombat then out.combatSeconds = n0(view.combatSeconds) + dt end
    out.xpPerHour = V.PerHour(tab(view.xp).total, out.seconds)
  end
  return out
end

local function clockText(run)
  local clock = V.Clock(run.seconds)
  if run.paused then return string.format(L["%s paused"], clock) end
  return clock
end

local function worthTotal(run)
  local w = tab(run.worth)
  if type(w.total) == "number" then return w.total end
  return n0(w.coin) + n0(w.vendor)
end

-- The strip -----------------------------------------------------------------------------------------

-- { name, clock, paused, parts = { "21.4k xp/hr", "88 kills", "2 bosses", "1g 12s" }, note }
-- opts = { capped, totalBosses }
function V.Strip(run, opts)
  opts = opts or {}
  local m = { name = V.Name(run), clock = clockText(run), paused = run.paused and true or false, parts = {} }
  if m.paused then
    m.note = string.format(L["Back inside within %s to carry on"], V.Clock(V.TimeLeft(run)))
    return m
  end
  local killed = V.Bosses(run)
  local p = m.parts
  if opts.capped then
    p[#p + 1] = V.BossText(killed, opts.totalBosses)
    p[#p + 1] = ns.Plural(n0(tab(run.loot).n), L["%d drop"], L["%d drops"])
  else
    p[#p + 1] = string.format(L["%s xp/hr"], V.Short(run.xpPerHour))
    p[#p + 1] = ns.Plural(n0(tab(run.kills).n), L["%d kill"], L["%d kills"])
    p[#p + 1] = V.BossText(killed, opts.totalBosses)
  end
  p[#p + 1] = money(worthTotal(run))
  return m
end

-- The strip as one line, the dungeon's name in the game's gold.
function V.StripText(m)
  local out = { "|cffffd100" .. m.name .. "|r", m.clock }
  for _, p in ipairs(m.parts) do out[#out + 1] = p end
  if m.note then out[#out + 1] = "|cff9d9d9d" .. m.note .. "|r" end
  return table.concat(out, V.SEP)
end

-- The card ------------------------------------------------------------------------------------------

-- opts = { capped, xp = { cur, max, level } (the client's now), compare (Runs.Compare(run)),
-- fastestRun (that fastest run, for the names of the bosses still to come), totalBosses }
-- -> { name, clock, note, bar = { share, from, gained, text } or nil, rows = { { label, value, dim } },
--      splits = { { state = "kill"|"wipe"|"pull"|"next"|"more", name, time, diff, diffText, tone } } }
function V.Card(run, opts)
  opts = opts or {}
  local c = { name = V.Name(run), clock = clockText(run), rows = {}, splits = {} }
  local xp, kills, loot = tab(run.xp), tab(run.kills), tab(run.loot)
  local x = opts.xp
  if not opts.capped and type(x) == "table" and n0(x.max) > 0 then
    local share = math.min(1, n0(x.cur) / x.max)
    local gained = math.min(share, n0(xp.total) / x.max)
    c.bar = { share = share, from = share - gained, gained = gained,
      text = string.format(L["Level %d · %d%% · +%d%% this run"], n0(x.level),
        math.floor(math.min(n0(x.cur), x.max) * 100 / x.max),
        math.floor(n0(xp.total) * 100 / x.max + 0.5)) }
  end
  local function row(label, value, dim) c.rows[#c.rows + 1] = { label = label, value = value, dim = dim } end
  if opts.capped then
    row(L["Experience"], L["none at the level cap"])
    row(L["Kills"], L["not counted at the level cap"])
    row(L["Drops"], number(loot.n))
  else
    row(L["Experience"], string.format(L["%s · %s/hr"], number(xp.total), V.Short(run.xpPerHour)))
    row(L["Kills"], number(kills.n))
  end
  row(L["In combat"], string.format(L["%s of %s"], V.Clock(run.combatSeconds), V.Clock(run.seconds)))
  local w = tab(run.worth)
  row(L["Worth"], money(worthTotal(run)))
  if w.auction ~= nil then
    row(L["coin · vendor · auction"], money(w.coin) .. " · " .. money(w.vendor) .. " · " .. money(w.auction), true)
  end
  row(L["Deaths"], number(run.deaths))

  local cmp = type(opts.compare) == "table" and opts.compare or {}
  local fastest = type(cmp.fastest) == "table" and cmp.fastest or nil
  local splits = fastest and tab(fastest.splits) or {}
  local killedHere = {}
  for _, b in ipairs(tab(run.bosses)) do
    if type(b) == "table" then
      local name = b.name or string.format(L["boss %s"], tostring(b.encounterId))
      if b.success then
        killedHere[b.encounterId] = true
        local s = { state = "kill", name = name, time = V.Clock(b.split) }
        local best = splits[b.encounterId]
        if type(best) == "number" and type(b.split) == "number" then
          s.diff = b.split - best
          s.diffText = V.Diff(s.diff)
          s.tone = s.diff < 0 and "good" or (s.diff > 0 and "bad" or nil)
        end
        c.splits[#c.splits + 1] = s
      else
        c.splits[#c.splits + 1] = { state = "wipe", name = name, time = L["wipe"], tone = "bad" }
      end
    end
  end
  if type(run.pulling) == "table" then
    c.splits[#c.splits + 1] = { state = "pull", name = run.pulling.name
      or string.format(L["boss %s"], tostring(run.pulling.encounterId)), time = L["fighting"] }
  end
  -- The fastest run's bosses this one hasn't killed yet, in that run's order.
  local upcoming = {}
  if type(opts.fastestRun) == "table" then
    for _, b in ipairs(tab(opts.fastestRun.bosses)) do
      if type(b) == "table" and b.success and not killedHere[b.encounterId] and type(b.split) == "number" then
        upcoming[#upcoming + 1] = b
      end
    end
  end
  for i, b in ipairs(upcoming) do
    if i > UPCOMING then
      c.splits[#c.splits + 1] = { state = "more", name = string.format(L["%d more"], #upcoming - UPCOMING), time = "" }
      break
    end
    c.splits[#c.splits + 1] = { state = "next", name = b.name or string.format(L["boss %s"], tostring(b.encounterId)),
      time = string.format(L["best %s"], V.Clock(b.split)) }
  end
  if n0(cmp.runs) == 0 then
    c.note = L["Your first run here. Bosses are listed as you meet them."]
  elseif not fastest then
    c.note = L["No full clear here yet to compare with."]
  end
  if run.paused then
    c.note = string.format(L["Back inside within %s to carry on"], V.Clock(V.TimeLeft(run)))
  end
  return c
end

-- The card as tooltip lines ({ left, right } pairs, a lone left for a line of its own): the strip's hover.
function V.CardLines(c)
  local out = { { c.name, c.clock } }
  if c.bar then out[#out + 1] = { c.bar.text } end
  for _, r in ipairs(c.rows) do out[#out + 1] = { r.label, r.value } end
  if #c.splits > 0 then out[#out + 1] = { " " } end
  for _, s in ipairs(c.splits) do
    local right = s.time
    if s.diffText then right = right .. "  " .. V.Tone(s.diffText, s.tone) end
    out[#out + 1] = { V.Mark(s.state) .. s.name, right }
  end
  if c.note then out[#out + 1] = { c.note } end
  return out
end

local MARKS = {
  kill = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t ",
  wipe = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12|t ",
  pull = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:12|t ",
}

-- A split's mark: the game's own ready-check ticks (a kill, a wipe, a fight under way); none otherwise.
function V.Mark(state)
  return MARKS[state] or ""
end

local TONES = { good = "|cff40ff40", bad = "|cffff6060", dim = "|cff9d9d9d" }

function V.Tone(text, tone)
  local c = TONES[tone]
  if not c or text == nil or text == "" then return text or "" end
  return c .. text .. "|r"
end

-- The summary ---------------------------------------------------------------------------------------

-- Which run of its dungeon this is, oldest first: the ones folded into totals, then the list's.
function V.RunIndex(run, list, totals)
  local n = n0(type(totals) == "table" and type(totals[run.mapId]) == "table" and totals[run.mapId].runs)
  for _, r in ipairs(tab(list)) do
    if type(r) == "table" and r.mapId == run.mapId and r.id ~= run.id and n0(r.enteredAt) <= n0(run.enteredAt) then
      n = n + 1
    end
  end
  return n + 1
end

local function players(run)
  local size = n0(tab(run.party).size)
  if size <= 1 then return L["solo"] end
  return ns.Plural(size, L["%d player"], L["%d players"])
end

-- opts = { closed, compare, capped, meter (the setting, and run.meter there), index, top (the run's
-- most valuable drops: { id, qty, vendor, auction }), itemInfo = function(id) -> name, quality }
-- -> { name, head, closed, tiles = { { label, value, sub, tone } }, drops = { { name, quality, value } },
--      rest, note }
function V.Summary(run, opts)
  opts = opts or {}
  local cmp = type(opts.compare) == "table" and opts.compare or {}
  local closed = opts.closed and true or false
  local s = { name = V.Name(run), closed = closed, tiles = {}, drops = {} }
  if closed then
    s.head = string.format(L["run %d · %s"], n0(opts.index) > 0 and opts.index or 1, players(run))
  else
    s.head = string.format(L["so far · %s"], players(run))
  end
  local killed, _, wipes = V.Bosses(run)
  local xp, loot = tab(run.xp), tab(run.loot)
  local function tile(label, value, sub, tone)
    s.tiles[#s.tiles + 1] = { label = label, value = value, sub = sub or "", tone = tone }
  end

  -- Time: best only for a closed run that killed every boss it pulled (Compare's isFastest).
  local timeSub, timeTone = V.BossText(killed), nil
  if closed and cmp.isFastest then
    timeTone = "good"
    if type(cmp.fastest) == "table" then
      timeSub = string.format(L["best · was %s"], V.Clock(cmp.fastest.seconds))
    else
      timeSub = L["best"]
    end
  elseif closed and type(cmp.vsFastest) == "number" then
    timeSub = string.format(L["%s on your best"], V.Diff(cmp.vsFastest))
    timeTone = cmp.vsFastest > 0 and "bad" or "good"
  elseif closed and not ns.Runs.Full(run) then
    timeSub = timeSub .. " · " .. L["left early"]
  end
  tile(L["Time"], V.Clock(run.seconds), timeSub, timeTone)

  local median = type(cmp.median) == "table" and cmp.median or nil
  if opts.capped then
    tile(L["Drops"], number(loot.n), L["no experience at the level cap"])
  else
    local sub = { string.format(L["%s/hr"], V.Short(V.PerHour(xp.total, run.seconds))) }
    if median and type(median.xp) == "number" then sub[2] = string.format(L["median %s"], V.Short(median.xp)) end
    tile(L["Experience"], number(xp.total), table.concat(sub, " · "))
  end

  local worthSub = {}
  if median and type(median.worth) == "number" then worthSub[1] = string.format(L["median %s"], money(median.worth)) end
  if tab(run.worth).auction == nil then worthSub[#worthSub + 1] = L["no auction prices"] end
  tile(L["Worth"], money(worthTotal(run)), table.concat(worthSub, " · "))

  local kills = n0(tab(run.kills).n)
  if opts.capped and kills == 0 then
    tile(L["Kills"], L["not counted"], V.BossText(killed))
  else
    tile(L["Kills"], number(kills), V.BossText(killed))
  end
  tile(L["Deaths"], number(run.deaths), wipes == 0 and L["no wipes"] or ns.Plural(wipes, L["%d wipe"], L["%d wipes"]))

  local m = run.meter
  if opts.meter and type(m) == "table" then
    local dmg, heal = n0(m.damage), n0(m.healing)
    if heal > dmg then
      tile(L["You did"], V.Short(heal),
        dmg > 0 and string.format(L["healing · %s damage"], V.Short(dmg)) or L["healing"])
    else
      tile(L["You did"], V.Short(dmg),
        heal > 0 and string.format(L["damage · %s healing"], V.Short(heal)) or L["damage"])
    end
  end

  -- The two most valuable drops.
  for _, d in ipairs(tab(opts.top)) do
    if #s.drops >= 2 then break end
    d = tab(d)
    local vendor, auction = n0(d.vendor), d.auction
    local worth = math.max(vendor, n0(auction))
    if d.id ~= nil and worth > 0 then
      local name, quality
      if type(opts.itemInfo) == "function" then name, quality = opts.itemInfo(d.id) end
      name = name or string.format(L["item %s"], tostring(d.id))
      if n0(d.qty) > 1 then name = string.format(L["%s x%d"], name, d.qty) end
      local value
      if type(auction) == "number" and auction >= vendor then
        value = string.format(L["%s auction"], money(auction))
      else
        value = string.format(L["%s vendor"], money(vendor))
      end
      s.drops[#s.drops + 1] = { name = name, quality = quality, value = value }
    end
  end

  local rest = {}
  local more = n0(loot.n) - #s.drops
  if more > 0 then
    if #s.drops > 0 then
      rest[1] = ns.Plural(more, L["%d more drop"], L["%d more drops"])
    else
      rest[1] = ns.Plural(more, L["%d drop"], L["%d drops"])
    end
  end
  local lv = tab(run.level)
  if type(lv.from) == "number" and type(lv.to) == "number" and lv.to > lv.from then
    rest[#rest + 1] = string.format(L["level %d to %d"], lv.from, lv.to)
  end
  local quests = #tab(run.quests)
  if quests > 0 then rest[#rest + 1] = ns.Plural(quests, L["%d quest turned in"], L["%d quests turned in"]) end
  local dur = tab(run.durability)
  if n0(dur.lost) > 0 and n0(dur.of) > 0 then
    rest[#rest + 1] = string.format(L["wear %d%%"], math.floor(n0(dur.lost) * 100 / dur.of + 0.5))
  end
  s.rest = table.concat(rest, " · ")

  if not closed and run.paused then
    s.note = string.format(L["Go back in within %s and this run carries on."], V.Clock(V.TimeLeft(run)))
  end
  return s
end

-- Dungeons › Runs -------------------------------------------------------------------------------------

-- The tiles' numbers over a character's runs: the list's and the totals folded out of it (worth is
-- the list's alone: totals don't keep it).
function V.Tiles(list, totals)
  local t = { runs = 0, seconds = 0, xp = 0, worth = 0 }
  for _, r in ipairs(tab(list)) do
    if type(r) == "table" then
      t.runs, t.seconds = t.runs + 1, t.seconds + n0(r.seconds)
      t.xp = t.xp + n0(tab(r.xp).total)
      t.worth = t.worth + worthTotal(r)
    end
  end
  for _, f in pairs(tab(totals)) do
    if type(f) == "table" then
      t.runs, t.seconds, t.xp = t.runs + n0(f.runs), t.seconds + n0(f.seconds), t.xp + n0(f.xp)
    end
  end
  return t
end

local function when(t)
  if type(t) ~= "number" then return "" end
  local ok, text = pcall(date, "%a %d %b, %H:%M", t)
  return ok and type(text) == "string" and text or ""
end

-- A dungeon's best run in the list: the fastest that killed every boss it pulled, unless the totals
-- (runs folded out of the list) hold a faster one.
local function bestId(runs, folded)
  local best, id
  for _, r in ipairs(runs) do
    if ns.Runs.Full(r) and (best == nil or n0(r.seconds) < best) then best, id = n0(r.seconds), r.id end
  end
  if type(folded) == "table" and type(folded.fastest) == "number" and best and folded.fastest < best then
    return nil
  end
  return id
end

-- One row per dungeon (Runs.ByInstance), newest first; under each dungeon in `open` its runs, newest
-- first. A dungeon row: { kind = "dungeon", mapId, open, name, cells, bars }; a run row: { kind = "run",
-- run, best, partial, cells, bars }. Cells by column: dungeon or date, runs or bosses, fastest or the
-- run's time, median or its mark, the bar, experience an hour or the run's experience, last run or worth.
function V.DungeonRows(instances, list, totals, open, ago)
  local rows = {}
  open = open or {}
  for _, d in ipairs(tab(instances)) do
    local isOpen = open[d.mapId] and true or false
    local bars
    if type(d.fastest) == "number" and type(d.median) == "number" and d.median > 0 then
      bars = { [5] = { value = d.fastest, max = d.median, r = 0.85, g = 0.68, b = 0.2 } }
    end
    rows[#rows + 1] = { kind = "dungeon", mapId = d.mapId, open = isOpen, name = d.instance
        or string.format(L["instance %s"], tostring(d.mapId)),
      cells = { "", number(d.runs), d.fastest and V.Clock(d.fastest) or "", d.median and V.Clock(d.median) or "", "",
        V.Short(d.xpPerHour), (ago and ago(d.last)) or "" },
      bars = bars }
    rows[#rows].cells[1] = rows[#rows].name
    if isOpen then
      local runs, slowest = {}, 0
      for _, r in ipairs(tab(list)) do
        if type(r) == "table" and r.mapId == d.mapId then
          runs[#runs + 1] = r
          slowest = math.max(slowest, n0(r.seconds))
        end
      end
      local best = bestId(runs, type(totals) == "table" and totals[d.mapId] or nil)
      for _, r in ipairs(runs) do
        local k, p = V.Bosses(r)
        local partial = not ns.Runs.Full(r)
        local mark = ""
        if r.id == best then mark = L["best"] elseif partial then mark = L["left early"] end
        rows[#rows + 1] = { kind = "run", run = r, mapId = d.mapId, best = r.id == best, partial = partial,
          cells = { when(r.leftAt or r.enteredAt), string.format("%d/%d", k, p), V.Clock(r.seconds), mark, "",
            number(tab(r.xp).total), money(worthTotal(r)) },
          bars = slowest > 0 and { [5] = { value = n0(r.seconds), max = slowest, r = 0.42, g = 0.36, b = 0.62 } }
            or nil }
      end
    end
  end
  return rows
end
