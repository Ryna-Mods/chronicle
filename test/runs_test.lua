-- Dungeon runs (Runs.lua) against a fake client: open, pause, resume and every way a run closes;
-- time inside against time outside; a /reload and a login mid-run; the instance copy learned from a
-- looted corpse, another copy id and a boss pulled again never ending a run; a wipe then a kill; experience
-- across a level-up; the coin line in both formats and one that can't be read; secrets skipped; the
-- meter; the journal event's shape; the 100-run cap folding into totals; Compare never taking a partial
-- run as the fastest; and `runs` off. From the repository root, with Lua 5.1 (what the game runs) or later:
--
--   lua5.1 test/runs_test.lua
--
-- This proves the logic; what Forever sends inside a dungeon is in docs/forever-client-api.md.
-- luacheck: ignore 1

local ADDON = "Ryna_Chronicle/"
local F = dofile("test/fake_client.lua")
F.Install()

local failures, checks = 0, 0
local function check(cond, what)
  checks = checks + 1
  if not cond then
    failures = failures + 1
    print("FAIL: " .. what)
  end
end

local errors, chat, journal = {}, {}, {}
local function run(label, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then errors[#errors + 1] = label .. ": " .. tostring(err) end
end

-- A secret: any comparison, arithmetic or formatting of it raises, as the client's do.
local SECRET = setmetatable({}, {
  __tostring = function() error("a secret was turned into text") end,
  __eq = function() error("a secret was compared") end,
  __lt = function() error("a secret was compared") end,
  __le = function() error("a secret was compared") end,
  __add = function() error("arithmetic on a secret") end,
  __sub = function() error("arithmetic on a secret") end,
  __concat = function() error("a secret was concatenated") end,
})
local function isSecret(v) return rawequal(v, SECRET) end

local function passResults(ok, ...)
  if ok then return ... end
  return nil
end

local now = 1800000000
local settings = { chronicle = true, runs = true, census = true, groupMembers = true }
local handlers = {}
local db = { characters = {} }
local pendingDebounce = {}
local auctionsTable = nil

local function after(_, label, fn) C_Timer.After(0, function() run(label, fn) end) end
_G.Ryna = {
  API = 2, VERSION = "test", L = setmetatable({}, { __index = function(_, k) return k end }),
  Try = function(fn, ...)
    if type(fn) ~= "function" then return nil end
    return passResults(pcall(fn, ...))
  end,
  Fn = function(a, b)
    local v = _G[a]
    if b ~= nil then
      if type(v) ~= "table" then return nil end
      v = v[b]
    end
    return type(v) == "function" and v or nil
  end,
  IsSecret = isSecret,
  NonEmpty = function(s) if type(s) == "string" and s ~= "" then return s end end,
  Now = function() return now end,
  Print = function(m) chat[#chat + 1] = m end,
  PrintRaw = function(m) chat[#chat + 1] = m end,
  Debug = function() end,
  Run = run,
  After = after,
  Debounce = function(key, _, fn)
    if pendingDebounce[key] then return end
    pendingDebounce[key] = true
    after(0, key, function()
      pendingDebounce[key] = nil
      fn()
    end)
  end,
  ReportError = function(label, err) errors[#errors + 1] = label .. ": " .. tostring(err) end,
  MoneyText = function(c) return tostring(c) end,
  On = function(event, f)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], f)
    return true
  end,
  DB = function() return db end,
  RegisterMod = function() return true end,
  Journal = { Add = function(t, fields)
    local e = { type = t }
    for k, v in pairs(fields or {}) do e[k] = v end
    journal[#journal + 1] = e
    return e
  end },
  Settings = {
    Get = function(k) return settings[k] end,
    Set = function(k, v) settings[k] = v end,
    AddDefaults = function(d)
      for k, v in pairs(d) do if settings[k] == nil then settings[k] = v end end
    end,
  },
  Data = { Get = function(name, version)
    if name == "auctions" and version == 1 and auctionsTable then return auctionsTable end
    return nil, "absent"
  end },
}

-- The client --------------------------------------------------------------------------------------

_G.COMBATLOG_XPGAIN_FIRSTPERSON = "%s dies, you gain %d experience."
_G.LOOT_MONEY_SPLIT = "Your share of the loot is %s."
_G.YOU_LOOT_MONEY = "You loot %s"
_G.GOLD_AMOUNT, _G.SILVER_AMOUNT, _G.COPPER_AMOUNT = "%d Gold", "%d Silver", "%d Copper"
_G.INSTANCE_RESET_SUCCESS = "%s has been reset."

local BFD = { mapId = 48, name = "Blackfathom Deeps", kind = "party" }
local DM = { mapId = 36, name = "The Deadmines", kind = "party" }
local SFK = { mapId = 33, name = "Shadowfang Keep", kind = "party" }
local inst = nil
_G.IsInInstance = function()
  if inst then return true, inst.kind end
  return false, "none"
end
_G.GetInstanceInfo = function()
  if inst then return inst.name, inst.kind, 1, "Normal", 5, 0, false, inst.mapId, 5, nil, false end
  return "Eastern Kingdoms", "none", 0, "", 0, 0, false, 0, 0, nil, false
end

local player = { xp = 500, xpMax = 1000, level = 20, rested = 300 }
_G.UnitXP = function() return player.xp end
_G.UnitXPMax = function() return player.xpMax end
_G.GetXPExhaustion = function() return player.rested end
_G.UnitLevel = function(unit)
  if unit == "player" then return player.level end
  return 21
end
-- Inside a dungeon a unit's GUID and name are secret (2026-11-20).
_G.UnitGUID = function(unit)
  if unit == "player" then return "Player-91-0A4C7F12" end
  if unit == "target" then return inst and SECRET or nil end
  if unit == "party1" then return "Player-91-00B3E9D1" end
  return nil
end
_G.UnitName = function(unit)
  if unit == "party1" then return "Thorbrand", "Ironhew" end
  return SECRET
end
_G.UnitIsDead = function() return false end

local dur = { [1] = { 80, 100 }, [5] = { 120, 120 } }
_G.GetInventoryItemDurability = function(slot)
  local d = dur[slot]
  if d then return d[1], d[2] end
end

local rep = { [72] = 3000 }
_G.C_Reputation = {
  GetNumFactions = function() return 1 end,
  GetFactionDataByIndex = function() return { factionID = 72, currentStanding = rep[72], name = "Stormwind" } end,
}

local group = 1
_G.GetNumGroupMembers = function() return group end
_G.IsInRaid = function() return false end
_G.UnitExists = function(unit) return group > 1 and unit == "party1" end
_G.UnitIsUnit = function(a, b) return a == b end
_G.UnitClass = function(unit) if unit == "party1" then return "Warrior", "WARRIOR" end end
_G.UnitGroupRolesAssigned = function(unit) if unit == "party1" then return "TANK" end return "NONE" end

local sell = { [5196] = 3470, [2589] = 13 }
_G.C_Item.GetItemInfo = function(id)
  local price = sell[id]
  if not price then return nil end
  return "Item " .. id, "link", 2, 20, 1, "Armor", "Mail", 1, "", 0, price
end

-- The loot window: its slots' { itemId, qty, quality } and sources.
local window = { slots = {}, source = nil }
_G.GetNumLootItems = function() return #window.slots end
_G.GetLootSlotType = function(i)
  local s = window.slots[i]
  return s and s.money and 2 or 1
end
_G.GetLootSlotLink = function(i)
  local s = window.slots[i]
  return s and not s.money and ("|cff1eff00|Hitem:" .. s[1] .. "::::|h[x]|h|r") or nil
end
_G.GetLootSlotInfo = function(i)
  local s = window.slots[i]
  if s then return 0, "Item " .. s[1], s[2], nil, s[3] end
end
_G.GetLootSourceInfo = function() return window.source, 1 end

-- The game's damage meter: the fights it holds, with the player's amounts or a secret.
local meter = { sessions = {} }
_G.Enum.DamageMeterType = { DamageDone = 0, HealingDone = 2, DamageTaken = 7 }
_G.C_DamageMeter = {
  IsDamageMeterAvailable = function() return true end,
  GetAvailableCombatSessions = function()
    local list = {}
    for _, s in ipairs(meter.sessions) do list[#list + 1] = { sessionID = s.id, name = "fight" } end
    return list
  end,
  GetCombatSessionFromID = function(id, kind)
    for _, s in ipairs(meter.sessions) do
      if s.id == id then
        local amount = s[kind]
        return { combatSources = {
          { isLocalPlayer = false, totalAmount = 999999 },
          { isLocalPlayer = true, totalAmount = amount },
        } }
      end
    end
  end,
}
_G.InCombatLockdown = function() return false end

local function fire(event, ...)
  for _, f in ipairs(handlers[event] or {}) do run(event, f, event, ...) end
end

local rec = { guid = "Player-91-0A4C7F12", zone = "Ashenvale", kills = {}, loot = {}, objects = {} }
local ns
local function load()
  for k in pairs(handlers) do handlers[k] = nil end
  ns = {}
  for _, file in ipairs({ "Mod.lua", "Locales/enUS.lua", "Chronicle.lua", "Runs.lua" }) do
    assert(loadfile(ADDON .. file))("Ryna_Chronicle", ns)
  end
  rawset(ns, "rec", rec)
end
load()
local R = ns.Runs
check(not ns.off and R and type(R.Current) == "function", "Runs.lua loads")
check(settings.runSummary == true and settings.runSummaryMeter == true, "its boolean settings get defaults")
check(R.Display() == "off", "runDisplay reads off until chosen")
settings.runDisplay = "card"
check(R.Display() == "card", "runDisplay reads the choice")
settings.runDisplay = "bogus"
check(R.Display() == "off", "runDisplay reads off for anything else")

local function enter(where)
  inst = where
  fire("ZONE_CHANGED_NEW_AREA")
end
local function leave()
  inst = nil
  fire("ZONE_CHANGED_NEW_AREA")
end
local function runs() return db.chronicle.runs[rec.guid] end
local function events()
  local out = {}
  for _, e in ipairs(journal) do if e.type == "run" then out[#out + 1] = e end end
  return out
end
local function lastEvent() local e = events(); return e[#e] end

-- A corpse looted: its item slots, or a coin slot alone when there are none (every slot has a source).
local function loot(source, slots)
  if #slots == 0 then slots = { { money = true } } end
  window.source, window.slots = source, slots
  fire("LOOT_OPENED")
  for i = 1, #slots do fire("LOOT_SLOT_CLEARED", i) end
  fire("LOOT_CLOSED")
end

-- What OnChange heard; a /reload loads the files again, so the view listens again (listen()).
local changes = {}
local function listen()
  ns.Runs.OnChange(function(what)
    for k in pairs(what) do changes[k] = (changes[k] or 0) + 1 end
  end)
end
listen()

-- Opening, time inside, pausing outside, resuming. ------------------------------------------------
group = 2
meter.sessions = { { id = 1, [0] = 5000, [2] = 0, [7] = 100 } } -- a fight from before the run
inst = BFD
fire("PLAYER_ENTERING_WORLD", true, false)
local cur = R.Current()
check(cur and cur.mapId == 48 and cur.instance == "Blackfathom Deeps" and cur.kind == "party", "a run opens inside")
check(cur.entries == 1 and cur.paused == false and cur.seconds == 0, "entered once, not paused")
check(cur.id == now .. "-48" and cur.enteredAt == now, "its id is <enteredAt>-<mapId>")
check(cur.copy == nil, "no copy known before a corpse is looted")
F.RunTimers()
check(changes.open == 1, "OnChange hears the open")

now = now + 600
check(R.Current().seconds == 600, "ten minutes inside")
leave()
check(R.Current().paused == true and R.Current().seconds == 600, "walking out pauses it")
now = now + 300
check(R.Current().seconds == 600 and R.Current().outsideFor == 300, "time outside isn't counted")
F.RunTimers()
check(changes.pause == 1, "OnChange hears the pause")
check(#events() == 0 and runs().open ~= nil, "a pause under 30 minutes keeps the run open (the expiry timer ran early)")
enter(BFD)
check(R.Current().entries == 2 and not R.Current().paused, "coming back resumes it")
now = now + 100
check(R.Current().seconds == 700, "and the clock goes on")

-- Experience across a level-up, a kill from the experience line, rested. -------------------------
player.xp, player.rested = 900, 100
fire("PLAYER_XP_UPDATE")
check(R.Current().xp.total == 400 and R.Current().xp.rested == 200, "experience and rested spent")
fire("CHAT_MSG_COMBAT_XP_GAIN", "Blackfathom Myrmidon dies, you gain 120 experience.")
check(R.Current().kills.n == 1 and R.Current().xp.kills == 120,
  "a kill from the experience line, its name's GUID secret")
fire("PLAYER_LEVEL_UP", 21)
player.xp, player.xpMax, player.level = 150, 1200, 21
fire("PLAYER_XP_UPDATE")
check(R.Current().xp.total == 650, "the rest of the old bar plus the new: 400 + 100 + 150")
check(R.Current().level.from == 20 and R.Current().level.to == 21, "level from and to")
fire("QUEST_TURNED_IN", 2040, 300, 0)
check(R.Current().xp.quests == 300 and R.Current().quests[1] == 2040, "a quest turned in")

-- Loot: the copy from the first corpse, the creature tally, the same corpse again. ------------------
local corpse = "Creature-0-8452-48-8801871-4807-1C5DBBE380"
loot(corpse, { { 5196, 1, 3 }, { 2589, 4, 1 } })
cur = R.Current()
check(cur.copy == 8801871, "the copy from a looted corpse")
check(cur.kills.creatures["4807"] == 1, "the corpse counts its creature")
check(cur.loot.n == 2 and cur.loot.qty == 5 and cur.loot.byQuality["3"] == 1 and cur.loot.byQuality["1"] == 1,
  "drops, pieces and qualities")
check(cur.worth.vendor == 3470 + 4 * 13 and cur.worth.auction == nil, "vendor worth so far, no auction without Prices")
check(cur.worth.total == cur.worth.coin + 3470 + 4 * 13, "the total: coin plus the loot, no auction to weigh")
-- With the auction table: an item worth more at auction counts there, one worth more at a vendor
-- counts there, and the two totals are never added to each other.
auctionsTable = { version = 1, items = { [5196] = { 39000, 41000, 3, 2, 2, 1800000000, 40000, 5, 9 },
  [2589] = { 5, 0, 1, 1, 1, 1800000000, 0, 0, 0 } } }
cur = R.Current()
check(cur.worth.auction == 41000 + 4 * 5, "auction worth: today's median, else the agreed min")
check(cur.worth.total == cur.worth.coin + 41000 + 4 * 13, "the total takes each item's better value")
auctionsTable = nil
loot(corpse, {})
check(R.Current().kills.creatures["4807"] == 1, "the same corpse opened again isn't counted twice")
loot(SECRET, { { 2589, 1, 1 } })
check(R.Current().loot.n == 3 and R.Current().copy == 8801871, "a secret source is skipped, its item still counted")
loot("Creature-0-8452-36-777-634-0000000001", {})
check(R.Current().copy == 8801871 and #events() == 0, "a corpse of another map doesn't touch the copy")

-- Coin. ---------------------------------------------------------------------------------------------
fire("CHAT_MSG_MONEY", "Your share of the loot is 42 Copper.")
check(R.Current().coin == 42, "the share line")
fire("CHAT_MSG_MONEY", "You loot 1 Gold, 4 Silver, 12 Copper")
check(R.Current().coin == 42 + 10412, "the solo line")
fire("CHAT_MSG_MONEY", "You loot a shiny pebble")
fire("CHAT_MSG_MONEY", "Your share of the loot is 3 Silver and a button.")
fire("CHAT_MSG_MONEY", SECRET)
check(R.Current().coin == 10454, "a line that can't be read whole, or a secret, adds nothing")
check(R.ParseMoney("You loot 7 Silver") == 700, "silver alone")

-- Combat, a wipe then a kill, the meter. ----------------------------------------------------------
local firstPull = now
fire("PLAYER_REGEN_DISABLED")
fire("ENCOUNTER_START", 2916, "Ghamoo-ra", 1, 5)
now = now + 40
fire("ENCOUNTER_END", 2916, "Ghamoo-ra", 1, 5, 0, {})
meter.sessions[2] = { id = 2, [0] = SECRET, [2] = SECRET, [7] = SECRET }
fire("PLAYER_REGEN_ENABLED")
cur = R.Current()
check(cur.combatSeconds == 40 and cur.firstPullAt == firstPull, "combat time and the first pull")
check(#cur.bosses == 1 and cur.bosses[1].success == false and cur.bosses[1].seconds == 40, "the wipe is kept")
F.RunTimers(1)
check(R.Current().meter == nil, "a fight still hidden isn't read")
meter.sessions[2] = { id = 2, [0] = 41000, [2] = 900, [7] = 8800 }
F.RunTimers()
cur = R.Current()
check(cur.meter and cur.meter.damage == 41000 and cur.meter.healing == 900 and cur.meter.damageTaken == 8800,
  "the fight read once plain, and the one from before the run left out")
now = now + 60
fire("PLAYER_REGEN_DISABLED")
fire("ENCOUNTER_START", 2916, "Ghamoo-ra", 1, 5)
now = now + 50
fire("ENCOUNTER_END", 2916, "Ghamoo-ra", 1, 5, 1, {})
fire("PLAYER_REGEN_ENABLED")
F.RunTimers()
cur = R.Current()
check(#cur.bosses == 2 and cur.bosses[2].success == true and cur.bosses[2].seconds == 50, "then the kill")
check(cur.bosses[2].split == cur.seconds, "its split is the time inside so far")
check(cur.meter.damage == 41000, "a fight counted once")
check(R.Full(cur), "every boss pulled was killed")

-- Durability, a death, reputation, the group. -----------------------------------------------------
dur[1] = { 70, 100 }
fire("UPDATE_INVENTORY_DURABILITY")
fire("PLAYER_DEAD")
rep[72] = 3250
cur = R.Current()
check(cur.durability.lost == 10 and cur.durability.of == 220 and cur.deaths == 1, "durability lost and a death")
check(cur.party.size == 2 and cur.party.members[1].class == "WARRIOR" and cur.party.members[1].role == "TANK"
  and cur.party.members[1].name == "Thorbrand-Ironhew", "the group, names with group members on")

-- A /reload mid-run: everything kept, nothing counted twice. ---------------------------------------
fire("PLAYER_LOGOUT")
local before = R.Current()
load()
R = ns.Runs
listen()
now = now + 5
fire("PLAYER_ENTERING_WORLD", false, true)
cur = R.Current()
check(cur and cur.id == before.id and cur.entries == before.entries, "a /reload keeps the run, not a new entry")
check(cur.seconds == before.seconds + 5 and cur.coin == 10454 and #cur.bosses == 2, "its numbers kept")
check(cur.rep["72"] == 250, "reputation gained, taken at the logout")
meter.sessions[3] = { id = 3, [0] = 100, [2] = 0, [7] = 0 }
fire("PLAYER_REGEN_DISABLED")
fire("PLAYER_REGEN_ENABLED")
F.RunTimers()
check(R.Current().meter.damage == 41100, "a fight after the reload is counted, the ones before aren't again")

-- A corpse with another copy id: counted, and the run goes on (seen in game 2026-11-21: the id isn't
-- the same for every creature of one copy, and a run must never start over at a loot window). -------
local firstId = cur.id
loot("Creature-0-8452-48-9900000-4811-1C5DBBE381", {})
loot("Creature-0-8452-48-9900000-4812-1C5DBBE382", {})
check(#events() == 0 and R.Current().id == firstId, "a corpse of another copy id doesn't end the run")
check(R.Current().copy == 8801871 and R.Current().otherCopies["9900000"] == 2,
  "the first id stays, the other is counted")

-- The reset line while outside closes it, at the moment the character walked out. -------------------
now = now + 10
leave()
fire("CHAT_MSG_SYSTEM", "Blackfathom Deeps has been reset.")
check(#events() == 1, "the run closes")
local e = lastEvent()
check(e.id == firstId and e.mapId == 48 and e.instance == "Blackfathom Deeps" and e.kind == "party",
  "the event names the run")
check(e.copy == 8801871 and e.difficulty == 1 and e.at == e.leftAt and e.leftAt == now, "copy, difficulty and leftAt")
check(e.seconds == cur.seconds + 10 and e.entries == 2 and e.combatSeconds == 90 and e.firstPullAt == firstPull,
  "time inside, combat and entries")
check(e.level.from == 20 and e.level.to == 21, "levels")
check(e.xp.total == 650 and e.xp.kills == 120 and e.xp.quests == 300 and e.xp.rested == 200, "experience")
check(e.kills.n == 1 and e.kills.creatures["4807"] == 1, "kills")
check(#e.bosses == 2 and e.bosses[1].encounterId == 2916 and e.bosses[1].name == "Ghamoo-ra"
  and e.bosses[2].success == true and e.bosses[1].split == nil, "bosses, without the in-game split")
check(e.loot.n == 3 and e.loot.qty == 6 and e.loot.byQuality["1"] == 2, "loot")
check(#e.loot.top == 2 and e.loot.top[1].id == 5196 and e.loot.top[1].vendor == 3470 and e.loot.top[2].qty == 5,
  "the most valuable first")
check(e.worth.coin == 10454 and e.worth.vendor == 3470 + 65 and e.worth.auction == nil, "worth")
check(e.worth.total == 10454 + 3470 + 65, "the event's total: coin plus each item at its better value")
check(e.durability.lost == 10 and e.durability.of == 220 and e.deaths == 1 and e.quests[1] == 2040, "the rest")
check(e.rep["72"] == 250 and e.meter.damage == 41100 and e.party.members[1].guid == "Player-91-00B3E9D1",
  "rep, meter, party")
check(runs().list[1].bosses[2].split ~= nil and runs().list[1].at == nil, "the kept copy has the splits")
check(lastEvent().otherCopies["9900000"] == 2, "the event carries the other ids it saw")
check(R.Current() == nil, "and no run is open outside")

-- A boss pulled again after its kill: listed again, the run goes on. ----------------------------------
enter(BFD)
cur = R.Current()
check(cur and cur.id ~= firstId and cur.copy == nil, "a new run on going back in after the reset")
local secondId = cur.id
fire("ENCOUNTER_START", 2916, "Ghamoo-ra", 1, 5)
now = now + 20
fire("ENCOUNTER_END", 2916, "Ghamoo-ra", 1, 5, 1)
fire("ENCOUNTER_START", 2916, "Ghamoo-ra", 1, 5)
check(#events() == 1 and R.Current().id == secondId and R.Current().pulling.encounterId == 2916,
  "a killed boss pulled again doesn't end the run")
now = now + 20
fire("ENCOUNTER_END", 2916, "Ghamoo-ra", 1, 5, 1)
check(#R.Current().bosses == 2 and R.Full(R.Current()), "it is listed twice, and the run is still a full one")
now = now + 30
leave()
fire("CHAT_MSG_SYSTEM", "Blackfathom Deeps has been reset.")
check(#events() == 2, "closed by its own reset")
enter(BFD)

-- Another instance. -----------------------------------------------------------------------------------
leave()
now = now + 60
enter(DM)
check(#events() == 3 and lastEvent().mapId == 48 and lastEvent().leftAt == now - 60,
  "another instance closes it, left when walked out")
check(R.Current().mapId == 36, "and opens one there")

-- The reset line. -------------------------------------------------------------------------------------
leave()
fire("CHAT_MSG_SYSTEM", "Blackfathom Deeps has been reset.")
check(#events() == 3, "another instance's reset leaves it")
fire("CHAT_MSG_SYSTEM", SECRET)
fire("CHAT_MSG_SYSTEM", "Thorbrand has come online.")
check(#events() == 3, "other lines and secrets leave it")
fire("CHAT_MSG_SYSTEM", "The Deadmines has been reset.")
check(#events() == 4 and lastEvent().mapId == 36 and R.Current() == nil, "its reset closes it")

-- Thirty minutes outside. -----------------------------------------------------------------------------
enter(DM)
now = now + 100
leave()
local out = now
now = now + 1799
F.RunTimers()
check(#events() == 4, "not yet at 29:59")
now = now + 2
F.RunTimers()
check(#events() == 5 and lastEvent().leftAt == out and lastEvent().seconds == 100, "closed after 30 minutes outside")

-- Logging out inside and in again: soon resumes, much later closes. ---------------------------------
enter(BFD)
now = now + 200
fire("PLAYER_LOGOUT")
load()
R = ns.Runs
listen()
now = now + 600
fire("PLAYER_ENTERING_WORLD", true, false)
cur = R.Current()
check(cur and cur.seconds == 200 and cur.entries == 2 and #events() == 5,
  "a login ten minutes later resumes, the time away outside")
now = now + 50
fire("PLAYER_LOGOUT")
local loggedOut = now
load()
R = ns.Runs
listen()
now = now + 3 * 3600
fire("PLAYER_ENTERING_WORLD", true, false)
check(#events() == 6 and lastEvent().leftAt == loggedOut and lastEvent().seconds == 250,
  "a login hours later closes it at the logout")
check(R.Current() and R.Current().seconds == 0 and R.Current().entries == 1, "and opens a new one")

-- Another group: back in the same dungeon with nobody from the run in the group is another copy
-- (The Stockade, 2026-11-23: nobody reset anything, and the old run's clock went on). ----------------
local guidOf, nameOf = _G.UnitGUID, _G.UnitName
local mate = "Player-91-00B3E9D1"
_G.UnitGUID = function(unit)
  if unit == "party1" then return mate end
  return guidOf(unit)
end
local groupBase = #events()
local runA = R.Current().id
now = now + 100
leave()
now = now + 50
enter(BFD)
check(#events() == groupBase and R.Current().id == runA and R.Current().entries == 2,
  "out and back in with the same group resumes")
now = now + 10
leave()
group = 1
fire("GROUP_ROSTER_UPDATE")
now = now + 20
enter(BFD)
check(#events() == groupBase and R.Current().id == runA and R.Current().entries == 3, "back in alone resumes")
now = now + 10
leave()
local leftA = now
group, mate = 2, "Player-91-0FFFFFFF"
fire("GROUP_ROSTER_UPDATE")
now = now + 60
enter(BFD)
check(#events() == groupBase + 1 and lastEvent().id == runA and lastEvent().leftAt == leftA
  and lastEvent().seconds == 120, "another group closes it, left when walked out")
cur = R.Current()
check(cur and cur.id ~= runA and cur.entries == 1 and cur.seconds == 0, "and a new run opens for the new group")
check(lastEvent().mates == nil and lastEvent().matesOut == nil and runs().list[#runs().list].mates == nil,
  "who the run was with never leaves the open run")
for k in pairs(runs().open.mates) do
  check(type(k) == "number", "the open run keeps a hash, never a GUID or a name")
end
local runB = cur.id
now = now + 30
leave()
mate = SECRET
_G.UnitName = function() return SECRET end
fire("GROUP_ROSTER_UPDATE")
now = now + 30
enter(BFD)
check(#events() == groupBase + 1 and R.Current().id == runB, "a member who can't be read changes nothing")
_G.UnitGUID, _G.UnitName, mate = guidOf, nameOf, nil

-- Secrets in the instance's answer: no run is guessed. -----------------------------------------------
leave()
fire("CHAT_MSG_SYSTEM", "Blackfathom Deeps has been reset.")
check(R.Current() == nil, "reset")
local mapOf = _G.GetInstanceInfo
_G.GetInstanceInfo = function() return SECRET, "party", 1, "Normal", 5, 0, false, SECRET end
inst = BFD
fire("ZONE_CHANGED_NEW_AREA")
check(R.Current() == nil, "a secret map id opens nothing")
_G.GetInstanceInfo = mapOf
inst = nil

-- Names only with group members on. ---------------------------------------------------------------
settings.groupMembers = false
enter(BFD)
cur = R.Current()
check(cur.party.members[1].class == "WARRIOR" and cur.party.members[1].name == nil and cur.party.members[1].guid == nil,
  "group members off: class, role and level only")
settings.groupMembers = true

-- Compare: a partial run is never the fastest. ------------------------------------------------------
-- A full clear in 900 s, then a faster run that wiped on a boss it never killed.
leave()
fire("CHAT_MSG_SYSTEM", "Blackfathom Deeps has been reset.")
local function quickRun(seconds, bosses)
  enter(SFK)
  for _, b in ipairs(bosses) do
    fire("ENCOUNTER_START", b[1], "Boss " .. b[1], 1, 5)
    now = now + 10
    fire("ENCOUNTER_END", b[1], "Boss " .. b[1], 1, 5, b[2] and 1 or 0)
  end
  now = now + seconds - 10 * #bosses
  leave()
  fire("CHAT_MSG_SYSTEM", "Shadowfang Keep has been reset.")
  return lastEvent()
end
local full = quickRun(900, { { 1, true }, { 2, true } })
local partial = quickRun(500, { { 1, true }, { 2, false } })
check(R.Full(full) and not R.Full(partial), "full and partial told apart")
local cmp = R.Compare(partial)
check(cmp.fastest and cmp.fastest.seconds == 900 and cmp.isFastest == false and cmp.vsFastest == nil,
  "a partial run is never the fastest")
cmp = R.Compare(full)
check(cmp.fastest == nil and cmp.isFastest == true and cmp.median.seconds ~= nil, "the full clear is, against the rest")
local third = quickRun(800, { { 1, true }, { 2, true } })
cmp = R.Compare(third)
check(cmp.isFastest and cmp.fastest.seconds == 900 and cmp.vsFastest == -100 and cmp.fastest.splits[1] ~= nil,
  "a faster full clear, with the fastest's splits")
local rows = R.ByInstance()
local bfd
for _, r in ipairs(rows) do if r.mapId == 33 then bfd = r end end
check(bfd and bfd.fastest == 800 and bfd.runs == 3 and bfd.median == 800 and bfd.instance == "Shadowfang Keep",
  "ByInstance: runs, the fastest full clear and the median")
check(rows[1].mapId == 33, "ByInstance: the latest first")
check(#R.List() == #events() and R.List()[1].id == third.id, "List, newest first")

-- The 100-run cap folds the oldest into totals. -------------------------------------------------------
local closedBefore = #events()
for i = 1, 110 do
  enter(i % 2 == 0 and BFD or DM)
  now = now + 60
end
leave()
now = now + 1801
F.RunTimers()
local closed = #events()
check(closed == closedBefore + 110, "every run closed")
check(#runs().list == 100, "the list keeps 100")
local folded = 0
for _, t in pairs(runs().totals) do folded = folded + t.runs end
check(folded == closed - 100, "the rest are in the totals")
check(runs().totals[33] and runs().totals[33].fastest == 800, "the totals keep a fastest full clear")
check(R.Totals()[48] == runs().totals[48], "Totals reads them")

-- `runs` off: nothing recorded, stored runs kept. -------------------------------------------------------
settings.runs = false
local kept = #runs().list
enter(BFD)
fire("CHAT_MSG_MONEY", "You loot 5 Copper")
check(R.Current() == nil and #runs().list == kept and #events() == closed, "runs off: nothing opens, nothing goes")
leave()
settings.runs = true

changes = {}
enter(BFD)
now = now + 10
leave()
enter(BFD)
fire("PLAYER_DEAD")
leave()
fire("CHAT_MSG_SYSTEM", "Blackfathom Deeps has been reset.")
F.RunTimers()
check(changes.open == 1 and changes.pause == 1 and changes.close == 1 and changes.resume == 1 and changes.change == 1,
  "OnChange hears open, pause, resume, change and close, coalesced")
check(changes.close and changes.resume and changes.change, "OnChange hears close, resume and changes")

-- Forgetting: the runs one visit was cut into, then everything. --------------------------------------
do
  local s = runs()
  local open = s.open
  s.list = {
    { id = "a", mapId = 48, enteredAt = 1000, leftAt = 1200 },   -- three in a row, each starting as the
    { id = "b", mapId = 48, enteredAt = 1200, leftAt = 1260 },   -- last one ended: one visit, cut up;
    { id = "c", mapId = 48, enteredAt = 1261, leftAt = 1500 },   -- the third is the rest of it, and stays
    { id = "d", mapId = 48, enteredAt = 9000, leftAt = 9900 },   -- a run of its own, later
    { id = "e", mapId = 36, enteredAt = 9900, leftAt = 9990 },   -- another dungeon straight after: not a cut
    { id = "f", mapId = 36, enteredAt = 20000, leftAt = 20500 },
    { id = "g", mapId = 36, enteredAt = 20498, leftAt = 21000 }, -- overlapping, not a cut
  }
  s.totals = { [48] = { runs = 3, seconds = 900, xp = 10 } }
  check(R.ForgetCount("split") == 2 and R.ForgetCount("all") == 7 and R.ForgetCount("nonsense") == 0,
    "counting what would go changes nothing")
  check(#s.list == 7, "nothing forgotten by counting")
  check(R.Forget("nonsense") == 0 and #runs().list == 7, "an unknown kind forgets nothing")
  check(R.Forget("split") == 2, "the two pieces that were cut off go")
  local left = {}
  for _, r in ipairs(runs().list) do left[#left + 1] = r.id end
  check(table.concat(left) == "cdefg", "the rest of that visit and the others stay, in their order")
  check(runs().totals[48].runs == 3, "the totals of older runs are left alone")
  check(R.Forget("split") == 0, "nothing left to cut")
  check(R.Forget("all") == 5 and #runs().list == 0 and next(runs().totals) == nil,
    "all: every closed run and the totals")
  check(runs().open == open, "the open run is never forgotten")
end
check(#chat == 0, "silent: nothing in chat")
check(#errors == 0, "no handler raised: " .. table.concat(errors, "; "))
print(string.format("runs: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
