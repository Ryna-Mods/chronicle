-- Runs: dungeon and raid runs (ryna_agent docs/ryna-agent-cores-mods.md 7.7; the API's docs/wow.md 20.1).
-- A run is one character inside one copy of one party or raid instance. The data half only: no frames.
--
-- Lifecycle. A run opens on PLAYER_ENTERING_WORLD or ZONE_CHANGED_NEW_AREA inside a party or raid
-- instance when no open run matches. It pauses when the character is outside (time outside is not
-- counted) and resumes on coming back to the same map. It closes when the character enters another
-- instance or another copy (a looted corpse's GUID with this map and another copy), when the game says
-- the instance was reset (INSTANCE_RESET_SUCCESS, while outside), after 30 minutes outside (or at a
-- login after that long), or when a boss this run already killed is pulled again (ENCOUNTER_START with
-- an encounter id the run has a kill for: a new copy). A closed run is never reopened. The copy id is
-- learned only from a looted corpse (GetLootSourceInfo is plain inside; a unit's GUID is secret there).
--
-- Storage: RynaDB.chronicle.runs[guid] = { open = <the open run>, list = { <closed runs, oldest first,
-- the newest 100> }, totals = { [mapId] = { instance, runs, seconds, xp, fastest, fastestId, last } } },
-- outside the character record, as RynaDB.chronicle.session is: the companion app passes a record's
-- unknown keys through to every snapshot, and a hundred runs per character don't belong there. Past
-- 100 closed runs the oldest is folded into its map's totals and dropped. Each close also writes one
-- `run` journal event (docs/wow.md 20.1), which is what reaches ryna.io.
--
-- Recorded only with both the `chronicle` and `runs` settings on (kills and loot come from
-- Chronicle.lua's own counting, which needs `chronicle`); off, nothing changes and stored runs stay.
-- Silent: nothing here prints.
--
-- The API for the in-game views (read only: never change what these return):
--
--   Runs.Current()        the open run as a view, or nil: the stored fields plus live numbers:
--                         seconds (inside so far), paused, outsideFor, inCombat, combatSeconds,
--                         xpPerHour, worth { coin, vendor, auction, total } so far (total: coin plus each
--                         item at the higher of vendor and auction), bosses with `split` (seconds
--                         inside from entering to the boss's end), pulling (a boss fight under way)
--   Runs.List(guid)       closed runs, newest first (guid defaults to the current character)
--   Runs.Totals(guid)     { [mapId] = totals } of the runs folded out of the list
--   Runs.ByInstance(guid) one row per map, newest first: { mapId, instance, runs, fastest, median,
--                         xpPerHour, last } (fastest: seconds of the fastest full clear, or nil)
--   Runs.OnChange(fn)     fn(what) after open, pause, resume, close or a change in the numbers,
--                         coalesced (half a second); `what` is a set: { open = true, change = true, ... }
--   Runs.Compare(run)     a run (closed, or Current()) against the character's runs of its map:
--                         { mapId, runs, full, fastest = { seconds, id, splits } or nil, isFastest,
--                         vsFastest, median = { seconds, xp, kills, worth } or nil, vsMedian }.
--                         A run that didn't kill every boss it started is never a fastest.
--   Runs.Display()        the runDisplay setting: "strip", "card" or "off"
--   Runs.Full(run)        whether a run killed every boss it pulled (and at least one)
--   Runs.CurrentTop()     the open run's most valuable drops so far, priced now (as a closed run's
--                         loot.top), for the summary on leaving
--
-- Settings: runs (on), runSummary (on), runSummaryMeter (on), runDisplay ("off"; the core's
-- AddDefaults takes booleans only, so Runs.Display() reads it with "off" as its default).

local _, ns = ...
if ns.off then return end

local R = {}
ns.Runs = R

local OUTSIDE_LIMIT = 30 * 60
local KEEP = 100
local MAX_CREATURES = 40
local MAX_TOP = 10
local MAX_ITEMS = 300
local MAX_QUESTS = 50
local MAX_BOSSES = 40
local MAX_MEMBERS = 40
local MAX_REP = 40
local MAX_SEEN = 1000
local METER_TRIES = 5
local METER_DELAY = 2
local CHANGE_DELAY = 0.5
local MIN_HOUR_SECONDS = 60 -- rates over less than a minute read as over a minute
local PRICES_VERSION = 1    -- the data layer's auctions table (the Prices mod reads the same)

R.OUTSIDE_LIMIT, R.KEEP = OUTSIDE_LIMIT, KEEP
R.version = 0

ns.API.Settings.AddDefaults({ runs = true, runSummary = true, runSummaryMeter = true })

local DISPLAYS = { strip = true, card = true, off = true }
-- Read from the settings table itself: the core's Settings.Get answers booleans only (anything else
-- reads as its default, which runDisplay has none of).
function R.Display()
  local all = ns.API.Settings.All and ns.API.Settings.All()
  local v = type(all) == "table" and all.runDisplay or nil
  if v == nil then v = ns.Setting("runDisplay") end
  if not ns.IsSecret(v) and type(v) == "string" and DISPLAYS[v] then return v end
  return "off"
end

-- Values ----------------------------------------------------------------------------------------

local function plain(v)
  if v == nil or ns.IsSecret(v) then return nil end
  return v
end

local function num(v)
  v = plain(v)
  if type(v) == "number" then return v end
  return nil
end

local function str(v)
  v = plain(v)
  if type(v) == "string" and v ~= "" then return v end
  return nil
end

local function n0(v)
  if type(v) == "number" then return v end
  return 0
end

local function copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = copy(v) end
  return out
end

-- Adds n to map[key], keeping at most `cap` keys: past it the smallest other key goes.
local function addCapped(map, key, n, cap)
  local isNew = map[key] == nil
  map[key] = n0(map[key]) + n
  if not isNew then return end
  local count, minKey, minN = 0, nil, nil
  for k, v in pairs(map) do
    count = count + 1
    if k ~= key and (minN == nil or n0(v) < minN) then minKey, minN = k, n0(v) end
  end
  if count > cap and minKey ~= nil then map[minKey] = nil end
end

-- Storage ---------------------------------------------------------------------------------------

local function on()
  return ns.rec ~= nil and ns.Setting("chronicle") and ns.Setting("runs") and true or false
end
R.On = on

local function myGuid()
  return ns.rec and ns.rec.guid
end

local function store(guid, make)
  local db = ns.db
  if type(db) ~= "table" or type(guid) ~= "string" then return nil end
  if type(db.chronicle) ~= "table" then
    if not make then return nil end
    db.chronicle = {}
  end
  if type(db.chronicle.runs) ~= "table" then
    if not make then return nil end
    db.chronicle.runs = {}
  end
  local s = db.chronicle.runs[guid]
  if type(s) ~= "table" then
    if not make then return nil end
    s = {}
    db.chronicle.runs[guid] = s
  end
  if type(s.list) ~= "table" then s.list = {} end
  if type(s.totals) ~= "table" then s.totals = {} end
  if s.open ~= nil and type(s.open) ~= "table" then s.open = nil end
  return s
end

local function openRun()
  local s = store(myGuid())
  return s and s.open or nil, s
end

-- Change notices ----------------------------------------------------------------------------------

local listeners, pendingWhat = {}, {}

function R.OnChange(fn)
  if type(fn) == "function" then listeners[#listeners + 1] = fn end
end

local function fire()
  local what = pendingWhat
  pendingWhat = {}
  for i = 1, #listeners do ns.Run("chronicle runs", listeners[i], what) end
end

local function changed(what)
  R.version = R.version + 1
  pendingWhat[what or "change"] = true
  if #listeners > 0 then ns.Debounce("chronicle-runs", CHANGE_DELAY, fire) end
end

-- What the client says --------------------------------------------------------------------------

-- The party or raid instance the character is in: { mapId, kind, name, difficulty }, or nil outside
-- (or when the map id can't be read).
local function where()
  local inside, kind = ns.Try(ns.Fn("IsInInstance"))
  if plain(inside) ~= true then return nil end
  kind = plain(kind)
  if kind ~= "party" and kind ~= "raid" then return nil end
  local name, _, difficulty, _, _, _, _, mapId = ns.Try(ns.Fn("GetInstanceInfo"))
  mapId = num(mapId)
  if not mapId or mapId <= 0 then return nil end
  return { mapId = mapId, kind = kind, name = str(name), difficulty = num(difficulty) }
end
R.Where = where

local function level()
  return num(ns.Try(ns.Fn("UnitLevel"), "player"))
end

-- Reputations as { [factionId] = the absolute standing }.
local function readRep()
  local out = {}
  local count = ns.Fn("C_Reputation", "GetNumFactions")
  local byIndex = ns.Fn("C_Reputation", "GetFactionDataByIndex")
  if count and byIndex then
    for i = 1, num(ns.Try(count)) or 0 do
      local d = ns.Try(byIndex, i)
      if type(d) == "table" and not ns.IsSecret(d) then
        local id, v = num(d.factionID), num(d.currentStanding)
        if id and v then out[tostring(id)] = v end
      end
    end
    if next(out) then return out end
  end
  local info = ns.Fn("GetFactionInfo")
  for i = 1, info and (num(ns.Try(ns.Fn("GetNumFactions"))) or 0) or 0 do
    local _, _, _, _, _, value, _, _, _, _, _, _, _, id = ns.Try(info, i)
    id, value = num(id), num(value)
    if id and value then out[tostring(id)] = value end
  end
  return out
end

-- Worn durability as { [slot] = { cur, max } }.
local function readDur()
  local out = {}
  for slot = 1, 19 do
    local cur, max
    if ns.Sheet and ns.Sheet.Durability then
      cur, max = ns.Sheet.Durability(slot)
    else
      cur, max = ns.Try(ns.Fn("GetInventoryItemDurability"), slot)
      cur, max = num(cur), num(max)
    end
    if cur and max and max > 0 then out[slot] = { cur = cur, max = max } end
  end
  return out
end

local function playerName(unit)
  local name, realm = ns.Try(ns.Fn("UnitName"), unit)
  name, realm = str(name), str(realm)
  if not name then return nil end
  if realm then return name .. "-" .. realm end
  return name
end

-- The group as { size, members }: class, role and level of each other member; GUID and name only
-- with "record group members" on (census and groupMembers, as Sightings.lua records the group) and
-- when the client hands them over plainly.
local function readParty()
  local raid = plain(ns.Try(ns.Fn("IsInRaid"))) == true
  local names = ns.Setting("census") and ns.Setting("groupMembers")
  local members = {}
  local exists, isUnit = ns.Fn("UnitExists"), ns.Fn("UnitIsUnit")
  for i = 1, raid and 40 or 4 do
    local unit = (raid and "raid" or "party") .. i
    if exists and plain(ns.Try(exists, unit)) == true and plain(ns.Try(isUnit, unit, "player")) ~= true
      and #members < MAX_MEMBERS then
      local _, class = ns.Try(ns.Fn("UnitClass"), unit)
      local role = str(ns.Try(ns.Fn("UnitGroupRolesAssigned"), unit))
      if role == "NONE" then role = nil end
      local m = { class = str(class), role = role, level = num(ns.Try(ns.Fn("UnitLevel"), unit)) }
      if names then
        m.guid = str(ns.Try(ns.Fn("UnitGUID"), unit))
        m.name = playerName(unit)
      end
      members[#members + 1] = m
    end
  end
  local size = num(ns.Try(ns.Fn("GetNumGroupMembers"))) or 0
  return { size = math.max(size, #members + 1), members = members }
end

-- The game's damage meter: the fights it holds, as session ids.
local function meterIds()
  local list = ns.Try(ns.Fn("C_DamageMeter", "GetAvailableCombatSessions"))
  local ids = {}
  if type(list) ~= "table" or ns.IsSecret(list) then return ids end
  for _, f in ipairs(list) do
    local id = type(f) == "table" and num(f.sessionID)
    if id then ids[#ids + 1] = id end
  end
  return ids
end

local function idSet(ids)
  local set = {}
  for _, id in ipairs(ids) do set[tostring(id)] = true end
  return set
end

-- Live baselines (in memory: re-read at every open, resume and /reload) --------------------------

local base = { run = nil }
local seen = { n = 0, set = {} } -- creature GUIDs counted on the open run (looted corpses, targets)

local function baseline(run)
  base.run = run
  base.xp = num(ns.Try(ns.Fn("UnitXP"), "player"))
  base.xpMax = num(ns.Try(ns.Fn("UnitXPMax"), "player"))
  base.level = level() or 0
  base.rested = num(ns.Try(ns.Fn("GetXPExhaustion"))) or 0
  base.pendingLevel = nil
  base.rep = readRep()
  base.dur = readDur()
end

local function live(run)
  return run ~= nil and base.run == run and run.insideSince ~= nil
end

-- Experience since the baseline, a level-up included (as Session.lua counts it), and the rested pool
-- spent (GetXPExhaustion going down is rested bonus earned).
local function takeXp(run)
  local xp, xpMax = num(ns.Try(ns.Fn("UnitXP"), "player")), num(ns.Try(ns.Fn("UnitXPMax"), "player"))
  if not xp then return false end
  local lvl = math.max(level() or 0, base.pendingLevel or 0)
  local gained
  if base.xp == nil then
    gained = 0
  elseif lvl > base.level or xp < base.xp then
    gained = math.max(0, n0(base.xpMax) - base.xp) + xp
    base.level = math.max(lvl, base.level + 1)
    base.pendingLevel = nil
  else
    gained = xp - base.xp
  end
  base.xp, base.xpMax = xp, xpMax or base.xpMax
  local rested = num(ns.Try(ns.Fn("GetXPExhaustion"))) or 0
  local spent = math.max(0, base.rested - rested)
  base.rested = rested
  local x = run.xp
  if gained > 0 then x.total = n0(x.total) + gained end
  if spent > 0 then x.rested = n0(x.rested) + spent end
  local now = math.max(level() or 0, base.level or 0)
  if now > 0 then run.level.to = now end
  return gained > 0 or spent > 0
end

local function takeRep(run)
  local now = readRep()
  for id, v in pairs(now) do
    local was = base.rep and base.rep[id]
    if was and v ~= was then addCapped(run.rep, id, v - was, MAX_REP) end
  end
  base.rep = now
end

local function takeDur(run)
  local now = readDur()
  local d = run.durability
  for slot, v in pairs(now) do
    local was = base.dur and base.dur[slot]
    if was and v.max == was.max and v.cur < was.cur then d.lost = n0(d.lost) + (was.cur - v.cur) end
  end
  base.dur = now
end

-- Everything taken from a baseline, up to now (before a pause, a close or a logout).
local function accumulate(run)
  if not live(run) then return end
  takeXp(run)
  takeRep(run)
  takeDur(run)
end

-- Time ------------------------------------------------------------------------------------------

local function insideSeconds(run, now)
  local s = n0(run.seconds)
  if run.insideSince then s = s + math.max(0, (now or ns.Now()) - run.insideSince) end
  return s
end

local function stopCombat(run, at)
  if run.combatSince then
    run.combatSeconds = n0(run.combatSeconds) + math.max(0, at - run.combatSince)
    run.combatSince = nil
  end
end

-- Pricing ---------------------------------------------------------------------------------------

local vendorCache = {}

local function vendorPrice(id)
  local cached = vendorCache[id]
  if cached then return cached end
  local price = num((select(11, ns.Try(ns.Fn("C_Item", "GetItemInfo"), tonumber(id)))))
  if price then vendorCache[id] = price end
  return price or 0
end

-- The auction table from the data layer (the Prices mod's Data/auctions.lua), or nil without it.
local function auctions()
  local D = ns.API.Data
  if type(D) ~= "table" or type(D.Get) ~= "function" then return nil end
  local t = D.Get("auctions", PRICES_VERSION)
  if type(t) ~= "table" or type(t.items) ~= "table" then return nil end
  return t
end

-- An item's auction value: today's median, else the week's, else today's agreed min; nil for none.
local function auctionPrice(t, id)
  local row = t and t.items[tonumber(id)]
  if type(row) ~= "table" then return nil end
  for _, i in ipairs({ 2, 7, 1 }) do
    local v = row[i]
    if type(v) == "number" and v > 0 then return v end
  end
  return nil
end

-- The run's loot priced: vendor total, auction total (nil without the table), the top items, and the
-- best total (each item at the higher of its vendor and auction value: the two totals overlap, so they
-- are never added to each other).
local function priced(run)
  local t = auctions()
  local vendor, auction, best, rows = 0, t and 0 or nil, 0, {}
  for id, e in pairs(run.loot.items or {}) do
    local qty = n0(e.qty)
    local v = vendorPrice(id) * qty
    local a = auctionPrice(t, id)
    a = a and a * qty or nil
    vendor = vendor + v
    if a then auction = auction + a end
    best = best + math.max(v, a or 0)
    rows[#rows + 1] = { id = tonumber(id) or id, qty = qty, vendor = v, auction = a, worth = math.max(v, a or 0) }
  end
  table.sort(rows, function(x, y)
    if x.worth ~= y.worth then return x.worth > y.worth end
    return tostring(x.id) < tostring(y.id)
  end)
  local top = {}
  for i = 1, math.min(MAX_TOP, #rows) do
    local r = rows[i]
    top[i] = { id = r.id, qty = r.qty, vendor = r.vendor, auction = r.auction }
  end
  return vendor, auction, top, best
end

-- Bosses ----------------------------------------------------------------------------------------

local function killed(run, encounterId)
  for _, b in ipairs(run.bosses or {}) do
    if b.encounterId == encounterId and b.success then return true end
  end
  return false
end

-- Whether a run killed every boss it pulled, and at least one: only such a run can be a fastest.
function R.Full(run)
  if type(run) ~= "table" or type(run.bosses) ~= "table" then return false end
  local kills, pulled = 0, {}
  for _, b in ipairs(run.bosses) do
    if type(b) == "table" and b.encounterId then
      pulled[b.encounterId] = pulled[b.encounterId] or false
      if b.success then
        pulled[b.encounterId] = true
        kills = kills + 1
      end
    end
  end
  if type(run.pulling) == "table" and run.pulling.encounterId and not pulled[run.pulling.encounterId] then
    return false
  end
  for _, done in pairs(pulled) do
    if not done then return false end
  end
  return kills > 0
end

-- Opening and closing ---------------------------------------------------------------------------

local function newRun(s, here)
  local now = ns.Now()
  local lvl = level()
  local dur = readDur()
  local of = 0
  for _, v in pairs(dur) do of = of + v.max end
  local run = {
    id = string.format("%d-%d", now, here.mapId), mapId = here.mapId, instance = here.name, kind = here.kind,
    difficulty = here.difficulty, enteredAt = now, seconds = 0, insideSince = now, combatSeconds = 0, entries = 1,
    level = { from = lvl, to = lvl }, xp = { total = 0, kills = 0, quests = 0, rested = 0 },
    kills = { n = 0, creatures = {} }, bosses = {}, loot = { n = 0, qty = 0, byQuality = {}, items = {} },
    coin = 0, durability = { lost = 0, of = of }, deaths = 0, quests = {}, rep = {}, party = readParty(),
    meterSkip = idSet(meterIds()), meterDone = {},
  }
  s.open = run
  seen.n, seen.set = 0, {}
  baseline(run)
  changed("open")
  return run
end

-- The run as the journal's `run` event carries it (docs/wow.md 20.1), priced now.
local function wire(run, leftAt)
  local vendor, auction, top, best = priced(run)
  local bosses = {}
  for i, b in ipairs(run.bosses) do
    bosses[i] = { encounterId = b.encounterId, name = b.name, at = b.at, seconds = b.seconds, success = b.success }
  end
  local byQuality = {}
  for q, n in pairs(run.loot.byQuality) do byQuality[tostring(q)] = n end
  return {
    at = leftAt, id = run.id, mapId = run.mapId, instance = run.instance, kind = run.kind, copy = run.copy,
    difficulty = run.difficulty, enteredAt = run.enteredAt, leftAt = leftAt, seconds = n0(run.seconds),
    combatSeconds = n0(run.combatSeconds), firstPullAt = run.firstPullAt, entries = n0(run.entries),
    level = copy(run.level), xp = copy(run.xp),
    kills = { n = n0(run.kills.n), creatures = copy(run.kills.creatures) },
    bosses = bosses,
    loot = { n = n0(run.loot.n), qty = n0(run.loot.qty), byQuality = byQuality, top = top },
    worth = { coin = n0(run.coin), vendor = vendor, auction = auction, total = n0(run.coin) + best },
    durability = { lost = n0(run.durability.lost), of = n0(run.durability.of) },
    deaths = n0(run.deaths), quests = copy(run.quests), rep = copy(run.rep),
    meter = run.meter and { damage = run.meter.damage, healing = run.meter.healing,
      damageTaken = run.meter.damageTaken } or nil,
    party = copy(run.party),
  }
end
R.Wire = wire

-- A closed run leaves the list: into its map's totals.
local function fold(s, r)
  if type(r) ~= "table" or not r.mapId then return end
  local t = s.totals[r.mapId]
  if type(t) ~= "table" then
    t = { runs = 0, seconds = 0, xp = 0 }
    s.totals[r.mapId] = t
  end
  t.instance = r.instance or t.instance
  t.runs = n0(t.runs) + 1
  t.seconds = n0(t.seconds) + n0(r.seconds)
  t.xp = n0(t.xp) + n0(type(r.xp) == "table" and r.xp.total)
  if R.Full(r) and (t.fastest == nil or n0(r.seconds) < t.fastest) then t.fastest, t.fastestId = n0(r.seconds), r.id end
  if n0(r.leftAt) > n0(t.last) then t.last = r.leftAt end
end

-- Closes the open run: at `at` (when it is inside, now), its event written and the list trimmed.
local function close(s, run, at)
  local now = ns.Now()
  if run.insideSince then
    accumulate(run)
    at = now
    run.seconds = insideSeconds(run, at)
    run.insideSince = nil
    stopCombat(run, at)
  end
  local leftAt = at or run.outsideSince or now
  local event = wire(run, leftAt)
  ns.Journal.Add("run", event)
  local kept = copy(event)
  kept.at = nil
  for i, b in ipairs(run.bosses) do kept.bosses[i].split = b.split end
  s.list[#s.list + 1] = kept
  while #s.list > KEEP do fold(s, table.remove(s.list, 1)) end
  s.open = nil
  if base.run == run then base.run = nil end
  seen.n, seen.set = 0, {}
  changed("close")
  ns.Debug("runs: closed %s, %ds inside", tostring(run.instance or run.mapId), n0(run.seconds))
end

-- The 30 minutes outside: one timer at a time, armed again while the run is paused and not yet due.
local armed = false
local function expire()
  armed = false
  local run = openRun()
  if run and not run.insideSince and run.outsideSince then
    local left = OUTSIDE_LIMIT - (ns.Now() - run.outsideSince)
    if left > 0 then
      armed = true
      ns.After(left + 1, "chronicle runs expire", expire)
      return
    end
  end
  R.Check()
end

local function arm()
  if armed then return end
  armed = true
  ns.After(OUTSIDE_LIMIT + 1, "chronicle runs expire", expire)
end

local function pause(run, at)
  if not run.insideSince then return end
  accumulate(run)
  run.seconds = insideSeconds(run, at)
  run.insideSince = nil
  run.outsideSince = at
  stopCombat(run, at)
  run.pull = nil
  if base.run == run then base.run = nil end
  changed("pause")
  arm()
end

local function resume(run, entry)
  run.insideSince = ns.Now()
  run.outsideSince = nil
  if entry then run.entries = n0(run.entries) + 1 end
  baseline(run)
  changed("resume")
end

-- Where the character is now, against the open run: close what is over, open, pause or resume.
function R.Check()
  local run, s = openRun()
  if not on() then
    -- Off: the clock stops on an open run, and nothing else is touched.
    if run and run.insideSince then pause(run, ns.Now()) end
    return
  end
  s = s or store(myGuid(), true)
  if not s then return end
  local now = ns.Now()
  if run and not run.insideSince and run.outsideSince and now - run.outsideSince >= OUTSIDE_LIMIT then
    close(s, run, run.outsideSince)
    run = nil
  end
  local here = where()
  if not here then
    if run and run.insideSince then
      pause(run, now)
    elseif run then
      arm() -- paused before a /reload or a logout: the 30 minutes still run
    end
    return
  end
  if run and run.mapId ~= here.mapId then
    close(s, run, run.outsideSince)
    run = nil
  end
  if not run then
    newRun(s, here)
    return
  end
  run.difficulty = here.difficulty or run.difficulty
  run.instance = run.instance or here.name
  if not run.insideSince then
    resume(run, true)
  elseif base.run ~= run then
    baseline(run) -- after a /reload inside: the same stretch goes on
  end
end

-- PLAYER_ENTERING_WORLD: after a logout (not a /reload) the time away was outside, so an open run
-- that was inside is paused where the logout left it; then the usual check.
function R.OnEnteringWorld(isInitialLogin, isReloadingUi)
  local run = openRun()
  if run and run.loggedOutAt then
    local reload = isReloadingUi
    if type(reload) ~= "boolean" then
      reload = isInitialLogin ~= true and ns.Now() - n0(run.loggedOutAt) < 60
    end
    if not reload and run.insideSince then
      run.seconds = insideSeconds(run, run.loggedOutAt)
      run.insideSince = nil
      run.outsideSince = run.loggedOutAt
    end
    run.loggedOutAt = nil
    -- The meter's fights from before are either gone or already counted: start from what is there.
    run.meterSkip, run.meterDone = idSet(meterIds()), {}
  end
  R.Check()
end

-- PLAYER_LOGOUT (a /reload too): what the baselines hold goes on the run, which keeps its clock.
function R.OnLogout()
  local run = openRun()
  if not run then return end
  local now = ns.Now()
  accumulate(run)
  stopCombat(run, now)
  run.pull = nil
  run.loggedOutAt = now
end

-- Inside the open run, or nil.
local function inside()
  if not on() then return nil end
  local run = openRun()
  if run and run.insideSince then return run end
  return nil
end

-- What happens inside ------------------------------------------------------------------------------

-- A creature GUID (a looted corpse or a dead target), counted once per run by its creature id.
local function countCreature(run, guid)
  local parts = {}
  for p in guid:gmatch("[^%-]+") do parts[#parts + 1] = p end
  if parts[1] ~= "Creature" and parts[1] ~= "Vehicle" then return parts end
  if seen.set[guid] then return parts end
  if seen.n >= MAX_SEEN then seen.n, seen.set = 0, {} end
  seen.set[guid], seen.n = true, seen.n + 1
  local id = tonumber(parts[6])
  if id then
    addCapped(run.kills.creatures, tostring(id), 1, MAX_CREATURES)
    changed()
  end
  return parts
end

-- A kill from Chronicle.lua: n kills (0 when an experience line adds to a kill already counted) and
-- the experience its line gave; `guid` when the dead unit's GUID was plain (a target outside dungeons).
function R.Kill(n, xp, guid)
  local run = inside()
  if not run then return end
  run.kills.n = n0(run.kills.n) + (num(n) or 0)
  run.xp.kills = n0(run.xp.kills) + (num(xp) or 0)
  if type(guid) == "string" and not ns.IsSecret(guid) then countCreature(run, guid) end
  changed()
end

-- A loot source GUID from Chronicle.lua (GetLootSourceInfo, plain inside a dungeon): the run's copy
-- from the first corpse of its map, a corpse of another copy closing it, and the creature tally.
function R.Source(guid)
  local run, s = openRun()
  if not on() or not run or not run.insideSince then return end
  if type(guid) ~= "string" or ns.IsSecret(guid) or guid == "" then return end
  local kind, map, copyId = guid:match("^(%a+)%-[^%-]*%-[^%-]*%-(%d+)%-(%d+)%-")
  if kind == "Creature" or kind == "Vehicle" then
    map, copyId = tonumber(map), tonumber(copyId)
    if map == run.mapId and copyId then
      if run.copy == nil then
        run.copy = copyId
        changed()
      elseif run.copy ~= copyId then
        close(s, run)
        local here = where()
        if not here then return end
        run = newRun(s, here)
        run.copy = copyId
      end
    end
  end
  countCreature(run, guid)
end

-- An item looted from Chronicle.lua.
function R.Loot(itemId, qty, quality)
  local run = inside()
  if not run then return end
  itemId, qty, quality = tonumber(itemId), num(qty) or 1, num(quality)
  local loot = run.loot
  loot.n = n0(loot.n) + 1
  loot.qty = n0(loot.qty) + qty
  if quality then
    local q = tostring(quality)
    loot.byQuality[q] = n0(loot.byQuality[q]) + 1
  end
  if itemId then
    local key = tostring(itemId)
    local e = loot.items[key]
    if not e then
      local count = 0
      for _ in pairs(loot.items) do count = count + 1 end
      if count < MAX_ITEMS then
        e = { n = 0, qty = 0, quality = quality }
        loot.items[key] = e
      end
    end
    if e then e.n, e.qty = e.n + 1, e.qty + qty end
  end
  changed()
end

-- The coin line (CHAT_MSG_MONEY): the client's own formats, the share line first. Its amount, or nil
-- when the line isn't one or can't be read whole.
local lineFormats, unitFormats

local function patterns()
  if lineFormats then return end
  lineFormats, unitFormats = {}, {}
  local toPattern = ns.Chronicle and ns.Chronicle.FormatToPattern
  if not toPattern then return end
  for _, key in ipairs({ "LOOT_MONEY_SPLIT_GUILD", "YOU_LOOT_MONEY_GUILD", "LOOT_MONEY_SPLIT", "YOU_LOOT_MONEY" }) do
    local p, s = toPattern(_G[key])
    if p and s then lineFormats[#lineFormats + 1] = { pattern = p .. "$", at = s } end
  end
  for _, u in ipairs({ { "GOLD_AMOUNT", 10000 }, { "SILVER_AMOUNT", 100 }, { "COPPER_AMOUNT", 1 } }) do
    local p, _, d = toPattern(_G[u[1]])
    if p and d == 1 then unitFormats[#unitFormats + 1] = { pattern = p:sub(2), times = u[2] } end
  end
end

local function captures(n, ...)
  return (select(n, ...))
end

function R.ParseMoney(text)
  if type(text) ~= "string" or ns.IsSecret(text) then return nil end
  patterns()
  local money
  for _, f in ipairs(lineFormats) do
    if text:match(f.pattern) then
      money = captures(f.at, text:match(f.pattern))
      break
    end
  end
  if type(money) ~= "string" then return nil end
  local total, found = 0, false
  for _, u in ipairs(unitFormats) do
    local a, b, digits = money:find(u.pattern)
    if a and digits then
      total = total + tonumber(digits) * u.times
      money = money:sub(1, a - 1) .. money:sub(b + 1)
      found = true
    end
  end
  if not found or money:gsub("[%s%p]", "") ~= "" then return nil end
  return total
end

function R.OnMoney(text)
  local run = inside()
  if not run then return end
  local amount = R.ParseMoney(text)
  if not amount or amount <= 0 then return end
  run.coin = n0(run.coin) + amount
  changed()
end

-- A reset's system line ("%s has been reset.") names the instance; it closes the open run outside.
local function resetName(msg)
  local format = _G.INSTANCE_RESET_SUCCESS
  if type(format) ~= "string" or type(msg) ~= "string" then return nil end
  local pattern = "^" .. format:gsub("%p", "%%%0"):gsub("%%%%s", "(.+)") .. "$"
  return msg:match(pattern)
end

function R.OnSystem(msg)
  if not on() or ns.IsSecret(msg) then return end
  local name = resetName(msg)
  if not name then return end
  local run, s = openRun()
  if not run or run.insideSince then return end
  if run.instance and name ~= run.instance then return end
  close(s, run, run.outsideSince)
end

function R.OnEncounterStart(encounterId, name)
  local run, s = openRun()
  encounterId = num(encounterId)
  if not on() or not run or not run.insideSince or not encounterId then return end
  if killed(run, encounterId) then
    -- A boss this run already killed: the instance was reset, so this is a new copy.
    close(s, run)
    local here = where()
    if not here then return end
    run = newRun(s, here)
  end
  run.pull = { encounterId = encounterId, name = str(name), at = ns.Now() }
  changed()
end

function R.OnEncounterEnd(encounterId, name, _, _, success)
  local run = inside()
  encounterId = num(encounterId)
  if not run or not encounterId then return end
  local now = ns.Now()
  local pull = run.pull
  if type(pull) ~= "table" or pull.encounterId ~= encounterId then pull = nil end
  success = plain(success)
  local row = {
    encounterId = encounterId, name = str(name) or (pull and pull.name), at = now,
    seconds = pull and math.max(0, now - pull.at) or nil, success = success == 1 or success == true,
    split = insideSeconds(run, now),
  }
  if #run.bosses < MAX_BOSSES then run.bosses[#run.bosses + 1] = row end
  run.pull = nil
  changed()
end

function R.OnCombat(started)
  local run = inside()
  if not run then return end
  local now = ns.Now()
  if started then
    if not run.combatSince then run.combatSince = now end
    if not run.firstPullAt then run.firstPullAt = now end
  else
    stopCombat(run, now)
    ns.After(METER_DELAY, "chronicle runs meter", function() R.HarvestMeter(1) end)
  end
  changed()
end

function R.OnXp()
  local run = inside()
  if not run or base.run ~= run then return end
  if takeXp(run) then changed() end
end

function R.OnLevelUp(newLevel)
  newLevel = num(tonumber(newLevel))
  if newLevel and newLevel > n0(base.level) then base.pendingLevel = newLevel end
end

function R.OnQuest(questId, xp)
  local run = inside()
  if not run then return end
  questId = num(questId)
  if questId and #run.quests < MAX_QUESTS then run.quests[#run.quests + 1] = questId end
  run.xp.quests = n0(run.xp.quests) + (num(xp) or 0)
  changed()
end

function R.OnDeath()
  local run = inside()
  if not run then return end
  run.deaths = n0(run.deaths) + 1
  changed()
end

function R.OnDurability()
  local run = inside()
  if not run or base.run ~= run then return end
  takeDur(run)
  changed()
end

-- The group, the biggest seen inside: a member walking out at the end doesn't shrink it.
function R.OnRoster()
  local run = inside()
  if not run then return end
  local p = readParty()
  if type(run.party) ~= "table" or p.size >= n0(run.party.size) then
    run.party = p
    changed()
  end
end

-- The meter ---------------------------------------------------------------------------------------
--
-- After each fight inside, the game's damage meter (C_DamageMeter) is asked for the fights it holds
-- that this run hasn't counted, and the player's own damage done, healing done and damage taken are
-- added from each, once every value is plain (the session reads are SecretWhenInCombat: the Meter
-- mod's way, polled a few times after combat). A fight that stays hidden is tried again after the
-- next one. Fights the meter held when the run opened (or at a /reload) are never counted.

local function enum(name, fallback)
  local e = _G.Enum
  local g = type(e) == "table" and e.DamageMeterType
  local v = type(g) == "table" and g[name]
  if type(v) == "number" then return v end
  return fallback
end

-- The player's amount in one session and meter type; nil when it can't be read plainly yet.
local function mine(byId, id, kind)
  local session = ns.Try(byId, id, kind)
  if type(session) ~= "table" or ns.IsSecret(session) then return nil end
  local sources = session.combatSources
  if sources == nil then return 0 end
  if type(sources) ~= "table" or ns.IsSecret(sources) then return nil end
  for _, src in ipairs(sources) do
    local me = type(src) == "table" and src.isLocalPlayer
    if me ~= nil and not ns.IsSecret(me) and me == true then
      local amount = src.totalAmount
      if ns.IsSecret(amount) then return nil end
      return type(amount) == "number" and amount or 0
    end
  end
  return 0
end

function R.HarvestMeter(try)
  local run = inside()
  if not run then return end
  local byId = ns.Fn("C_DamageMeter", "GetCombatSessionFromID")
  if not byId then return end
  if plain(ns.Try(ns.Fn("C_DamageMeter", "IsDamageMeterAvailable"))) == false then return end
  local waiting = plain(ns.Try(ns.Fn("InCombatLockdown"))) == true
  if not waiting then
    local ids = meterIds()
    local skip = type(run.meterSkip) == "table" and run.meterSkip or {}
    local done = type(run.meterDone) == "table" and run.meterDone or {}
    local keepSkip, keepDone = {}, {}
    for _, id in ipairs(ids) do
      local key = tostring(id)
      if skip[key] then
        keepSkip[key] = true
      elseif done[key] then
        keepDone[key] = true
      else
        local damage = mine(byId, id, enum("DamageDone", 0))
        local healing = damage and mine(byId, id, enum("HealingDone", 2))
        local taken = healing and mine(byId, id, enum("DamageTaken", 7))
        if damage and healing and taken then
          local m = run.meter or { damage = 0, healing = 0, damageTaken = 0 }
          m.damage, m.healing, m.damageTaken = m.damage + damage, m.healing + healing, m.damageTaken + taken
          run.meter = m
          keepDone[key] = true
          changed()
        else
          waiting = true
        end
      end
    end
    -- Only ids the meter still holds are remembered.
    run.meterSkip, run.meterDone = keepSkip, keepDone
  end
  if waiting and (try or 1) < METER_TRIES then
    ns.After(METER_DELAY, "chronicle runs meter", function() R.HarvestMeter((try or 1) + 1) end)
  end
end

function R.OnMeterReset()
  local run = openRun()
  if run then run.meterSkip, run.meterDone = {}, {} end
end

-- Reading -------------------------------------------------------------------------------------------

local function perHour(amount, seconds)
  return n0(amount) * 3600 / math.max(n0(seconds), MIN_HOUR_SECONDS)
end

function R.Current()
  local run = openRun()
  if not run then return nil end
  local now = ns.Now()
  local view = copy(run)
  view.meterSkip, view.meterDone, view.pull = nil, nil, nil
  view.loot.items = nil
  view.seconds = insideSeconds(run, now)
  view.paused = run.insideSince == nil
  view.outsideFor = run.outsideSince and math.max(0, now - run.outsideSince) or nil
  view.inCombat = run.combatSince ~= nil
  view.combatSeconds = n0(run.combatSeconds) + (run.combatSince and math.max(0, now - run.combatSince) or 0)
  view.xpPerHour = perHour(run.xp.total, view.seconds)
  local vendor, auction, _, best = priced(run)
  view.worth = { coin = n0(run.coin), vendor = vendor, auction = auction, total = n0(run.coin) + best }
  view.pulling = run.pull and copy(run.pull) or nil
  view.full = R.Full(view)
  return view
end

-- The open run's most valuable drops so far, priced now ({ id, qty, vendor, auction }, at most ten,
-- most first), for the summary shown on leaving; {} with no open run. Read only.
function R.CurrentTop()
  local run = openRun()
  if not run then return {} end
  local _, _, top = priced(run)
  return top
end

-- Closed runs, newest first.
function R.List(guid)
  local s = store(guid or myGuid())
  local out = {}
  if not s then return out end
  for i = #s.list, 1, -1 do out[#out + 1] = s.list[i] end
  return out
end

function R.Totals(guid)
  local s = store(guid or myGuid())
  return s and s.totals or {}
end

local function median(list)
  if #list == 0 then return nil end
  table.sort(list)
  local mid = math.floor(#list / 2)
  if #list % 2 == 1 then return list[mid + 1] end
  return (list[mid] + list[mid + 1]) / 2
end

local function worthOf(r)
  local w = type(r.worth) == "table" and r.worth or {}
  if type(w.total) == "number" then return w.total end
  return n0(w.coin) + n0(w.vendor)
end

function R.ByInstance(guid)
  local s = store(guid or myGuid())
  if not s then return {} end
  local rows = {}
  local function row(mapId)
    local r = rows[mapId]
    if not r then
      r = { mapId = mapId, runs = 0, seconds = 0, xp = 0, times = {} }
      rows[mapId] = r
    end
    return r
  end
  for mapId, t in pairs(s.totals) do
    if type(t) == "table" then
      local r = row(mapId)
      r.instance = t.instance
      r.runs, r.seconds, r.xp = r.runs + n0(t.runs), r.seconds + n0(t.seconds), r.xp + n0(t.xp)
      r.fastest, r.last = t.fastest, t.last
    end
  end
  for _, run in ipairs(s.list) do
    if type(run) == "table" and run.mapId then
      local r = row(run.mapId)
      r.instance = run.instance or r.instance
      r.runs, r.seconds = r.runs + 1, r.seconds + n0(run.seconds)
      r.xp = r.xp + n0(type(run.xp) == "table" and run.xp.total)
      r.times[#r.times + 1] = n0(run.seconds)
      if R.Full(run) and (r.fastest == nil or n0(run.seconds) < r.fastest) then r.fastest = n0(run.seconds) end
      if n0(run.leftAt) > n0(r.last) then r.last = run.leftAt end
    end
  end
  local out = {}
  for _, r in pairs(rows) do
    out[#out + 1] = { mapId = r.mapId, instance = r.instance, runs = r.runs, fastest = r.fastest,
      median = median(r.times), xpPerHour = perHour(r.xp, r.seconds), last = r.last }
  end
  table.sort(out, function(a, b)
    if n0(a.last) ~= n0(b.last) then return n0(a.last) > n0(b.last) end
    return a.mapId < b.mapId
  end)
  return out
end

function R.Compare(run, guid)
  if type(run) ~= "table" or not run.mapId then return nil end
  local s = store(guid or myGuid())
  local out = { mapId = run.mapId, runs = 0, full = R.Full(run) }
  if not s then return out end
  local best, bestRun
  local times, xps, kills, worths = {}, {}, {}, {}
  for _, r in ipairs(s.list) do
    if type(r) == "table" and r.mapId == run.mapId and r.id ~= run.id then
      out.runs = out.runs + 1
      times[#times + 1] = n0(r.seconds)
      xps[#xps + 1] = n0(type(r.xp) == "table" and r.xp.total)
      kills[#kills + 1] = n0(type(r.kills) == "table" and r.kills.n)
      worths[#worths + 1] = worthOf(r)
      if R.Full(r) and (best == nil or n0(r.seconds) < best) then best, bestRun = n0(r.seconds), r end
    end
  end
  local t = s.totals[run.mapId]
  if type(t) == "table" then
    out.runs = out.runs + n0(t.runs)
    if t.fastest and (best == nil or t.fastest < best) then best, bestRun = t.fastest, { id = t.fastestId } end
  end
  if best then
    local splits = {}
    for _, b in ipairs(type(bestRun.bosses) == "table" and bestRun.bosses or {}) do
      if b.success and b.split then splits[b.encounterId] = b.split end
    end
    out.fastest = { seconds = best, id = bestRun.id, splits = splits }
  end
  local seconds = n0(run.seconds)
  out.isFastest = out.full and (best == nil or seconds < best) or false
  out.vsFastest = (out.full and best) and (seconds - best) or nil
  if #times > 0 then
    out.median = { seconds = median(times), xp = median(xps), kills = median(kills), worth = median(worths) }
    out.vsMedian = seconds - out.median.seconds
  end
  return out
end

-- Events ------------------------------------------------------------------------------------------

ns.On("PLAYER_ENTERING_WORLD", function(_, isInitialLogin, isReloadingUi)
  if ns.rec then R.OnEnteringWorld(isInitialLogin, isReloadingUi) end
end)
ns.On("ZONE_CHANGED_NEW_AREA", function() if ns.rec then R.Check() end end)
ns.On("PLAYER_LOGOUT", function() if ns.rec then R.OnLogout() end end)
ns.On("PLAYER_REGEN_DISABLED", function() R.OnCombat(true) end)
ns.On("PLAYER_REGEN_ENABLED", function() R.OnCombat(false) end)
ns.On("ENCOUNTER_START", function(_, id, name) R.OnEncounterStart(id, name) end)
ns.On("ENCOUNTER_END", function(_, id, name, difficulty, size, success)
  R.OnEncounterEnd(id, name, difficulty, size, success)
end)
ns.On("CHAT_MSG_MONEY", function(_, text) R.OnMoney(text) end)
ns.On("CHAT_MSG_SYSTEM", function(_, msg) R.OnSystem(msg) end)
ns.On("PLAYER_XP_UPDATE", function() R.OnXp() end)
ns.On("PLAYER_LEVEL_UP", function(_, newLevel) R.OnLevelUp(newLevel) end)
ns.On("QUEST_TURNED_IN", function(_, questId, xp) R.OnQuest(questId, xp) end)
ns.On("PLAYER_DEAD", function() R.OnDeath() end)
ns.On("UPDATE_INVENTORY_DURABILITY", function() R.OnDurability() end)
ns.On("GROUP_ROSTER_UPDATE", function() R.OnRoster() end)
ns.On("DAMAGE_METER_RESET", function() R.OnMeterReset() end)
