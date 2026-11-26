-- Probe: /ryna probe, the in-game questions dungeon runs wait on (ryna_agent
-- docs/ryna-agent-cores-mods.md 7.7; docs/forever-client-api.md "Still owed", R1 to R5), asked by one
-- command instead of a macro each. It only reads and prints, and only when asked:
--
--   /ryna probe         what the client says right now: in combat or not, IsInInstance,
--                       GetInstanceInfo, the target's GUID (its instance copy and creature id), and
--                       whether the GUID, the name, experience and money are secret here
--   /ryna probe watch   also print a boss's ENCOUNTER_START, ENCOUNTER_END and BOSS_KILL, the coin
--                       line (CHAT_MSG_MONEY), each looted corpse's GUID, an instance reset's
--                       system line, and the same reading
--                       at the start of the next three fights; kept on across a /reload
--                       and, for loot: CHAT_MSG_LOOT, a roll starting (with GetLootRollItemInfo),
--                       a roll's system lines, and the loot history's record of each drop
--   /ryna probe loot    which loot history this client has, and what it holds now (after a boss)
--   /ryna probe comms   addon messages: registers a prefix, sends "ping" to this character by whisper
--                       and to the party, raid and guild it is in, and prints each one that arrives
--                       with its channel and whether the sender's name is plain
--   /ryna probe group   what the client says of party1 to party4: away, connected, in range, dead,
--                       role, level, and whether the name and GUID are hidden (never the name)
--   /ryna probe casts   the next ten casts by party or raid members (UNIT_SPELLCAST_SUCCEEDED)
--   /ryna probe meter   the game's damage meter, every type for the last fight: each source's class
--                       and amount, and whether its name and GUID are hidden (after a fight)
--   /ryna probe guild   the guild calls this client has, row 1 of the roster as the client orders
--                       it, what this rank may do, and whether there is a calendar
--   /ryna probe off     stop watching
--   /ryna probe show    every line so far in a box to copy from (the last 240, kept across a /reload)
--   /ryna probe clear   forget them
--
-- The lines are for a report, so they stay in English whatever the client's language. Nothing here is
-- recorded on a character, sent to the journal or read by the companion app: the lines live in
-- RynaDB.chronicle.probe until cleared. comms is the one probe that sends: the word "ping" under
-- the prefix RynaProbe, only when the command is typed, and shows a ping's sender as the game stamped
-- it, since the form of that name is the question. group, casts and meter need no names: another
-- player shows as a unit, a class and "plain" or "secret".

local _, ns = ...
if ns.off then return end

local P = {}
ns.Probe = P

local MAX_LINES = 240
local FIGHTS = 3
-- The loot events are both generations' (the modern loot history's and Classic's): which of them
-- this client lets an addon register is part of the answer.
local EVENTS = { "ENCOUNTER_START", "ENCOUNTER_END", "BOSS_KILL", "CHAT_MSG_MONEY", "CHAT_MSG_SYSTEM",
  "PLAYER_REGEN_DISABLED", "LOOT_OPENED", "CHAT_MSG_LOOT", "START_LOOT_ROLL", "LOOT_ROLLS_COMPLETE",
  "LOOT_ITEM_ROLL_WON", "LOOT_HISTORY_UPDATE_ENCOUNTER", "LOOT_HISTORY_UPDATE_DROP",
  "LOOT_HISTORY_ROLL_COMPLETE", "LOOT_HISTORY_ROLL_CHANGED", "LOOT_HISTORY_FULL_UPDATE" }
local DESCRIBE_KEYS = 14

local function store()
  local db = ns.db
  if type(db) ~= "table" then return nil end
  if type(db.chronicle) ~= "table" then db.chronicle = {} end
  if type(db.chronicle.probe) ~= "table" then db.chronicle.probe = {} end
  local s = db.chronicle.probe
  if type(s.lines) ~= "table" then s.lines = {} end
  return s
end

local function clock()
  local d = _G.date
  local ok, text = pcall(function() return d("%H:%M:%S") end)
  return ok and type(text) == "string" and text or "?"
end

-- A value as a report can carry it: never compared or formatted when the client hides it.
local function show(v)
  if v == nil then return "nil" end
  if ns.IsSecret(v) then return "secret" end
  return tostring(v)
end

local function hidden(v)
  if v == nil then return "nil" end
  return ns.IsSecret(v) and "secret" or "plain"
end

local function say(text)
  local line = clock() .. " " .. text
  local s = store()
  if s then
    s.lines[#s.lines + 1] = line
    while #s.lines > MAX_LINES do table.remove(s.lines, 1) end
  end
  ns.Print("probe: " .. text)
end

-- A value written out for a report: a table's fields (sorted, at most DESCRIBE_KEYS, two levels deep),
-- each hidden value as "secret", so a paste says both what the client answers and what it hides.
local function describe(v, depth)
  depth = depth or 0
  if v == nil or ns.IsSecret(v) or type(v) ~= "table" then return show(v) end
  if depth >= 2 then return "{...}" end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for i = 1, math.min(#keys, DESCRIBE_KEYS) do
    parts[i] = tostring(keys[i]) .. "=" .. describe(v[keys[i]], depth + 1)
  end
  if #keys > DESCRIBE_KEYS then parts[#parts + 1] = string.format("(+%d more)", #keys - DESCRIBE_KEYS) end
  return "{" .. table.concat(parts, ", ") .. "}"
end

-- A call's results with their count, since a client call may answer nil in the middle (GetInstanceInfo).
local function results(ok, ...)
  return ok, select("#", ...), { ... }
end

-- Every result of a client call as shown text, "missing" when the client has no such call.
local function call(name, ...)
  local f = ns.Fn(name)
  if not f then return "missing" end
  local ok, n, values = results(pcall(f, ...))
  if not ok then return "error" end
  if n < 1 then return "nothing" end
  local parts = {}
  for i = 1, n do parts[i] = show(values[i]) end
  return table.concat(parts, ", ")
end

-- A call in one of the client's tables (C_LootHistory.GetSortedInfoForDrop): its first result, or nil.
local function first2(tableName, name, ...)
  local f = ns.Fn(tableName, name)
  if not f then return nil end
  local ok, v = pcall(f, ...)
  if ok then return v end
  return nil
end

-- Every result of a call in one of the client's tables, as shown text.
local function call2(tableName, name, ...)
  local f = ns.Fn(tableName, name)
  if not f then return "missing" end
  local ok, n, values = results(pcall(f, ...))
  if not ok then return "error" end
  if n < 1 then return "nothing" end
  local parts = {}
  for i = 1, n do parts[i] = describe(values[i]) end
  return table.concat(parts, ", ")
end

local function first(name, ...)
  local f = ns.Fn(name)
  if not f then return nil end
  local ok, v = pcall(f, ...)
  if ok then return v end
  return nil
end

-- The target's GUID taken apart: Creature-0-<server>-<map>-<instance copy>-<npc>-<spawn>.
local function guidText(what, guid)
  if guid == nil then return what .. ": none" end
  if ns.IsSecret(guid) then return what .. " guid: secret" end
  local parts = {}
  for part in tostring(guid):gmatch("[^-]+") do parts[#parts + 1] = part end
  if (parts[1] == "Creature" or parts[1] == "Vehicle") and #parts >= 7 then
    return string.format("%s guid: %s (map %s, copy %s, npc %s)", what, guid, parts[4], parts[5], parts[6])
  end
  return what .. " guid: " .. tostring(guid) .. " (not a creature)"
end

-- The functions in one of the client's tables, sorted.
local function functionNames(t)
  local names = {}
  for k, v in pairs(t) do
    if type(v) == "function" then names[#names + 1] = tostring(k) end
  end
  table.sort(names)
  return names
end

-- A call that failed says why: "refused" and "blocked" are answers.
local function outcome(ok, n, values)
  if not ok then return "error: " .. (ns.IsSecret(values[1]) and "secret" or tostring(values[1])) end
  if n < 1 then return "nothing" end
  local parts = {}
  for i = 1, n do parts[i] = show(values[i]) end
  return table.concat(parts, ", ")
end

local function guidLine()
  return guidText("target", first("UnitGUID", "target"))
end

function P.Now(why)
  say((why or "now") .. ": in combat " .. call("InCombatLockdown"))
  say("IsInInstance: " .. call("IsInInstance"))
  say("GetInstanceInfo: " .. call("GetInstanceInfo"))
  say(guidLine())
  say(string.format("hidden here: target guid %s, target name %s, xp %s, xp max %s, money %s",
    hidden(first("UnitGUID", "target")), hidden(first("UnitName", "target")),
    hidden(first("UnitXP", "player")), hidden(first("UnitXPMax", "player")), hidden(first("GetMoney"))))
end

-- /ryna probe loot: which loot history this client has (the modern one by encounter, Classic's by
-- item, or none), and what it holds right now.
function P.Loot()
  local H = _G.C_LootHistory
  if type(H) ~= "table" then
    say("loot: C_LootHistory " .. (H == nil and "missing" or type(H)))
  else
    local names = functionNames(H)
    say("loot: C_LootHistory has " .. (#names > 0 and table.concat(names, ", ") or "no functions"))
    local encounters = first2("C_LootHistory", "GetAllEncounterInfos")
    if type(encounters) == "table" and not ns.IsSecret(encounters) then
      say(string.format("loot: %d encounters in the history", #encounters))
      local last = encounters[#encounters]
      if type(last) == "table" then
        say("loot: the last encounter: " .. describe(last))
        local drops = first2("C_LootHistory", "GetSortedDropsForEncounter", last.encounterID)
        if type(drops) == "table" and not ns.IsSecret(drops) then
          say(string.format("loot: its drops: %d", #drops))
          for i = 1, math.min(#drops, 3) do say(string.format("loot: drop %d: %s", i, describe(drops[i]))) end
        else
          say("loot: its drops: " .. show(drops))
        end
      end
    else
      say("loot: GetAllEncounterInfos: " .. show(encounters))
    end
    local items = first2("C_LootHistory", "GetNumItems") -- Classic's history, by item
    if items ~= nil then
      say("loot: Classic history items: " .. show(items))
      if type(items) == "number" and not ns.IsSecret(items) and items > 0 then
        say("loot: item 1: " .. call2("C_LootHistory", "GetItem", 1))
        say("loot: item 1, player 1: " .. call2("C_LootHistory", "GetPlayerInfo", 1, 1))
      end
    end
  end
  say("loot: method " .. call("GetLootMethod") .. "; threshold " .. call("GetLootThreshold"))
end

-- /ryna probe comms: does an addon message arrive, on which channels, and is the sender's name plain?
-- The sender is what the game stamps on a message, so it is what an ownership check would stand on.
local PREFIX = "RynaProbe"
local SECRET_PREFIXES = 3
local commsFrame
local secretPrefixes = 0

-- This character's name as the client gives it: whole ("First-Last") and short.
local function ownNames()
  local name, realm
  local f = ns.Fn("UnitFullName")
  if f then
    local ok, a, b = pcall(f, "player")
    if ok then name, realm = a, b end
  end
  if name == nil then name = first("UnitName", "player") end
  if type(name) ~= "string" or ns.IsSecret(name) then return nil end
  if type(realm) == "string" and not ns.IsSecret(realm) and realm ~= "" then
    return name .. "-" .. realm, name
  end
  return name, name
end

-- A sender for a report, as the game stamped it: its form (hyphen, space, with or without the last
-- name) is the answer an ownership check stands on, so it is shown whole. Only someone running this
-- probe sends under its prefix.
local function sender(v)
  if v == nil then return "nil" end
  if ns.IsSecret(v) then return "secret" end
  local full, short = ownNames()
  v = tostring(v)
  local own = full and (v == full or v == short or v:sub(1, #short) == short)
  return "\"" .. v .. "\"" .. (own and " (this character)" or "")
end

local function onComms(_, _, prefix, text, channel, from)
  if ns.IsSecret(prefix) then
    if secretPrefixes < SECRET_PREFIXES then
      secretPrefixes = secretPrefixes + 1
      say("CHAT_MSG_ADDON: a message whose prefix is secret")
    end
    return
  end
  if prefix ~= PREFIX then return end
  say(string.format("CHAT_MSG_ADDON: %s | %s | from %s", show(text), show(channel), sender(from)))
end

function P.Comms()
  say("comms: messaging lockdown " .. call2("C_ChatInfo", "InChatMessagingLockdown")
    .. "; in combat " .. call("InCombatLockdown") .. "; IsInInstance " .. call("IsInInstance"))
  say("comms: RegisterAddonMessagePrefix: " .. call2("C_ChatInfo", "RegisterAddonMessagePrefix", PREFIX))
  say("comms: UnitFullName: " .. call("UnitFullName", "player"))
  if not commsFrame then
    commsFrame = ns.Try(_G.CreateFrame, "Frame")
    if commsFrame then
      commsFrame:SetScript("OnEvent", function(...) ns.Run("probe", onComms, ...) end)
    end
  end
  if not commsFrame then
    say("comms: this client gave no frame")
  elseif not pcall(commsFrame.RegisterEvent, commsFrame, "CHAT_MSG_ADDON") then
    say("comms: refused CHAT_MSG_ADDON")
  end
  secretPrefixes = 0
  local send = ns.Fn("C_ChatInfo", "SendAddonMessage")
  if not send then
    say("comms: C_ChatInfo.SendAddonMessage missing")
    return
  end
  local function try(label, channel, target)
    local sent = outcome(results(pcall(send, PREFIX, "ping " .. label, channel, target)))
    say(string.format("comms: sent %s: %s", label, sent))
  end
  local full, short = ownNames()
  if full then
    try("whisper", "WHISPER", full)
    if short ~= full then try("whisper-short", "WHISPER", short) end
  else
    say("comms: this character's name is hidden here, no whisper tried")
  end
  local skipped = {}
  local channels = { { "party", "PARTY", "IsInGroup" }, { "raid", "RAID", "IsInRaid" },
    { "guild", "GUILD", "IsInGuild" } }
  for _, c in ipairs(channels) do
    local inIt = first(c[3])
    if inIt and not ns.IsSecret(inIt) then try(c[1], c[2]) else skipped[#skipped + 1] = c[1] end
  end
  if #skipped > 0 then say("comms: not tried (not in one): " .. table.concat(skipped, ", ")) end
  say("comms: each ping that arrives prints a CHAT_MSG_ADDON line; none within a few seconds means none arrived")
end

-- /ryna probe group: what the client lets an addon know of the others in the party, in or out of a
-- fight. A member's name and GUID are reported only as plain or secret.
local GROUP_CALLS = { "UnitIsAFK", "UnitIsConnected", "UnitInRange", "UnitIsVisible", "UnitIsDeadOrGhost",
  "UnitGroupRolesAssigned", "UnitLevel" }

function P.Group()
  say("group: in combat " .. call("InCombatLockdown") .. "; IsInInstance " .. call("IsInInstance")
    .. "; members " .. call("GetNumGroupMembers"))
  local seen = 0
  for i = 1, 4 do
    local unit = "party" .. i
    local exists = first("UnitExists", unit)
    if exists and not ns.IsSecret(exists) then
      seen = seen + 1
      local parts = { "name " .. hidden(first("UnitName", unit)), "guid " .. hidden(first("UnitGUID", unit)) }
      for _, name in ipairs(GROUP_CALLS) do parts[#parts + 1] = name .. " " .. call(name, unit) end
      say("group: " .. unit .. ": " .. table.concat(parts, "; "))
    end
  end
  if seen == 0 then say("group: no party members (party1 to party4)") end
end

-- /ryna probe casts: does the client tell an addon what the others cast? The next few, then it stops.
local CASTS = 10
local castFrame
local casts = 0

local function stopCasts()
  if castFrame then pcall(castFrame.UnregisterEvent, castFrame, "UNIT_SPELLCAST_SUCCEEDED") end
end

local function onCast(_, _, unit, castGuid, spellId)
  if ns.IsSecret(unit) then
    say("cast: the unit is secret")
  elseif type(unit) == "string" and (unit:find("^party%d") or unit:find("^raid%d")) then
    say(string.format("cast: %s spell %s (cast guid %s)", unit, show(spellId), hidden(castGuid)))
  else
    return
  end
  casts = casts + 1
  if casts >= CASTS then
    stopCasts()
    say("casts: done")
  end
end

function P.Casts()
  if not castFrame then
    castFrame = ns.Try(_G.CreateFrame, "Frame")
    if castFrame then castFrame:SetScript("OnEvent", function(...) ns.Run("probe", onCast, ...) end) end
  end
  if not castFrame then
    say("casts: this client gave no frame")
    return
  end
  casts = 0
  if pcall(castFrame.RegisterEvent, castFrame, "UNIT_SPELLCAST_SUCCEEDED") then
    say(string.format("casts: the next %d casts by party or raid members", CASTS))
  else
    say("casts: refused UNIT_SPELLCAST_SUCCEEDED")
  end
end

-- /ryna probe meter: the game's own damage meter, one line a meter type, by the client's own list of
-- types where it has one: the current session (type 1, the last fight), which is what a run adds up,
-- and for damage done the overall one (type 0), which on Forever held 66 sources for a party of five
-- (2026-11-26). A source is its class and amount, and whether its name and GUID are hidden: the GUID
-- is what would tie a source to a party member.
local METER_SOURCES = 6

function P.Meter()
  if type(_G.C_DamageMeter) ~= "table" then
    say("meter: C_DamageMeter missing")
    return
  end
  say("meter: available " .. call2("C_DamageMeter", "IsDamageMeterAvailable")
    .. "; in combat " .. call("InCombatLockdown"))
  local sessions = first2("C_DamageMeter", "GetAvailableCombatSessions")
  local counted = type(sessions) == "table" and not ns.IsSecret(sessions)
  say("meter: sessions " .. (counted and tostring(#sessions) or show(sessions)))
  local types = {}
  local E = type(_G.Enum) == "table" and _G.Enum.DamageMeterType
  if type(E) == "table" then
    for k, v in pairs(E) do
      if type(v) == "number" then types[#types + 1] = { name = tostring(k), id = v } end
    end
  else
    for id = 0, 10 do types[#types + 1] = { name = "type", id = id } end
  end
  table.sort(types, function(a, b) return a.id < b.id end)
  local overall = first2("C_DamageMeter", "GetCombatSessionFromType", 0, 0)
  if type(overall) == "table" and not ns.IsSecret(overall) and type(overall.combatSources) == "table"
    and not ns.IsSecret(overall.combatSources) then
    say(string.format("meter: overall damage done: %d sources, %s seconds", #overall.combatSources,
      show(overall.durationSeconds)))
  else
    say("meter: overall damage done: " .. show(overall))
  end
  for _, t in ipairs(types) do
    local s = first2("C_DamageMeter", "GetCombatSessionFromType", 1, t.id)
    if type(s) ~= "table" or ns.IsSecret(s) then
      say(string.format("meter: %s (%d): %s", t.name, t.id, show(s)))
    else
      local parts = {}
      local sources = s.combatSources
      if type(sources) == "table" and not ns.IsSecret(sources) then
        for i = 1, math.min(#sources, METER_SOURCES) do
          local c = sources[i]
          if type(c) == "table" and not ns.IsSecret(c) then
            local you = not ns.IsSecret(c.isLocalPlayer) and c.isLocalPlayer == true
            parts[#parts + 1] = show(c.classFilename) .. " " .. show(c.totalAmount)
              .. (you and " (you)" or "") .. ", name " .. hidden(c.name) .. ", guid " .. hidden(c.sourceGUID)
          end
        end
        if #sources > METER_SOURCES then
          parts[#parts + 1] = string.format("(+%d more)", #sources - METER_SOURCES)
        end
      end
      say(string.format("meter: %s (%d): total %s: %s", t.name, t.id, show(s.totalAmount),
        #parts > 0 and table.concat(parts, "; ") or "no sources"))
    end
  end
end

-- /ryna probe guild: which guild calls this client has, the order GetGuildRosterInfo answers in (row 1,
-- which Chronicle's roster already keeps), what this rank may do, and whether there is a calendar.
-- It only asks: nothing here writes a note, changes a rank or invites.
local GUILD_MAY = { "CanViewOfficerNote", "CanEditOfficerNote", "CanEditPublicNote", "CanGuildPromote",
  "CanGuildDemote", "CanGuildRemove", "CanGuildInvite" }
local GUILD_GLOBALS = { "GuildRosterSetPublicNote", "GuildRosterSetOfficerNote", "GuildPromote", "GuildDemote",
  "GuildUninvite", "GuildInvite", "SetGuildMemberRank", "QueryGuildEventLog", "GetNumGuildEvents",
  "GetGuildEventInfo", "GetGuildRosterLastOnline" }
local CALENDAR_CALLS = { "OpenCalendar", "GetNumDayEvents", "GetNumGuildEvents", "GetGuildEventInfo",
  "CreateGuildSignUpEvent", "EventGetInvite" }

function P.Guild()
  say("guild: in a guild " .. call("IsInGuild") .. "; members " .. call("GetNumGuildMembers"))
  local G = _G.C_GuildInfo
  if type(G) ~= "table" then
    say("guild: C_GuildInfo " .. (G == nil and "missing" or type(G)))
  else
    local names = functionNames(G)
    say("guild: C_GuildInfo has " .. (#names > 0 and table.concat(names, ", ") or "no functions"))
  end
  say("guild: GetGuildRosterInfo(1): " .. call("GetGuildRosterInfo", 1))
  local may = {}
  for i, name in ipairs(GUILD_MAY) do may[i] = name .. " " .. call(name) end
  say("guild: " .. table.concat(may, "; "))
  local present, missing = {}, {}
  for _, name in ipairs(GUILD_GLOBALS) do
    local list = ns.Fn(name) and present or missing
    list[#list + 1] = name
  end
  say("guild: globals present: " .. (#present > 0 and table.concat(present, ", ") or "none")
    .. "; missing: " .. (#missing > 0 and table.concat(missing, ", ") or "none"))
  local C = _G.C_Calendar
  if type(C) ~= "table" then
    say("guild: C_Calendar " .. (C == nil and "missing" or type(C)))
  else
    local has = {}
    for _, name in ipairs(CALENDAR_CALLS) do
      if ns.Fn("C_Calendar", name) then has[#has + 1] = name end
    end
    say(string.format("guild: C_Calendar has %d functions; of the ones asked: %s", #functionNames(C),
      #has > 0 and table.concat(has, ", ") or "none"))
  end
  say("guild: C_Club " .. (type(_G.C_Club) == "table" and "present" or "missing"))
end

-- An instance reset's system line, by the client's own text ("%s has been reset."), whatever the language.
local function isReset(msg)
  local format = _G.INSTANCE_RESET_SUCCESS
  if type(format) ~= "string" or type(msg) ~= "string" then return false end
  local pattern = "^" .. format:gsub("%p", "%%%0"):gsub("%%%%s", ".+") .. "$"
  return msg:match(pattern) ~= nil
end

local frame
local fights = 0

local function onEvent(_, event, ...)
  if event == "PLAYER_REGEN_DISABLED" then
    if fights >= FIGHTS then return end
    fights = fights + 1
    -- A moment in, not at the event: InCombatLockdown is still false inside this handler, and what
    -- combat hides may not be hidden yet (seen 2026-11-20).
    local label = string.format("fight %d of %d", fights, FIGHTS)
    ns.After(2, "probe", function() P.Now(label) end)
  elseif event == "CHAT_MSG_SYSTEM" then
    local msg = ...
      if ns.IsSecret(msg) or type(msg) ~= "string" then return end
    if isReset(msg) then
      say("reset line: " .. msg)
    elseif msg:find("|Hitem:", 1, true) then
      say("system line with an item: " .. msg) -- a roll's lines ("X rolls 87 (Need) for [item]", "X won")
    end
  elseif event == "LOOT_OPENED" then
    -- Each corpse's GUID as the loot window names it: is the copy field the same for every creature?
    say(guidText("loot source", first("GetLootSourceInfo", 1)))
  elseif event == "CHAT_MSG_MONEY" then
    say("CHAT_MSG_MONEY: " .. show((...)))
  elseif event == "CHAT_MSG_LOOT" then
    -- "X receives loot: [item]": the line, and the name the client sends beside it.
    local text, player = ...
    say("CHAT_MSG_LOOT: " .. show(text) .. " | from " .. show(player))
  elseif event == "START_LOOT_ROLL" then
    local rollId = ...
    say("START_LOOT_ROLL: " .. show(rollId) .. " -> GetLootRollItemInfo: " .. call("GetLootRollItemInfo", rollId))
  elseif event == "LOOT_HISTORY_UPDATE_DROP" then
    -- The modern loot history's own record of one drop: the winner and every roll, if it says.
    local encounterId, dropId = ...
    local info = first2("C_LootHistory", "GetSortedInfoForDrop", encounterId, dropId)
    say(string.format("LOOT_HISTORY_UPDATE_DROP: %s, %s -> %s", show(encounterId), show(dropId), describe(info)))
  else
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = show((select(i, ...))) end
    say(event .. ": " .. (#parts > 0 and table.concat(parts, ", ") or "no arguments"))
  end
end

-- Starts or stops the listeners. Registering is the probe too: an event the client refuses an addon
-- is named, so "refused ENCOUNTER_START" is an answer.
function P.Watch(on, quiet)
  local s = store()
  if s then s.watch = on and true or nil end
  if not on then
    stopCasts()
    if frame then
      for _, event in ipairs(EVENTS) do pcall(frame.UnregisterEvent, frame, event) end
    end
    if not quiet then say("watching: off") end
    return
  end
  fights = 0
  if not frame then
    frame = ns.Try(_G.CreateFrame, "Frame")
    if not frame then
      say("watching: this client gave no frame")
      return
    end
    frame:SetScript("OnEvent", function(...) ns.Run("probe", onEvent, ...) end)
  end
  local taken, refused = {}, {}
  for _, event in ipairs(EVENTS) do
    local ok = pcall(frame.RegisterEvent, frame, event)
    local list = ok and taken or refused
    list[#list + 1] = event
  end
  if quiet then return end
  say("watching: " .. (#taken > 0 and table.concat(taken, ", ") or "nothing")
    .. (#refused > 0 and ("; refused " .. table.concat(refused, ", ")) or ""))
end

-- Every kept line in one box, selected, to copy with Ctrl+C (chat lines can't be copied).
local box
function P.Show()
  local s = store()
  local text = s and table.concat(s.lines, "\n") or ""
  if text == "" then
    ns.Print("probe: nothing kept yet; /ryna probe takes a reading")
    return
  end
  if not box then
    local f = ns.Try(_G.CreateFrame, "Frame", "RynaChronicleProbe", _G.UIParent)
    local edit = f and ns.Try(_G.CreateFrame, "EditBox", nil, f)
    if not f or not edit then
      ns.Print("probe: this client gave no box; the lines are above in chat")
      return
    end
    f:SetSize(620, 320)
    f:SetPoint("CENTER")
    pcall(f.SetFrameStrata, f, "DIALOG")
    local bg = f:CreateTexture()
    pcall(bg.SetAllPoints, bg, f)
    pcall(bg.SetColorTexture, bg, 0.04, 0.04, 0.05, 0.95)
    pcall(edit.SetMultiLine, edit, true)
    pcall(edit.SetAutoFocus, edit, false)
    pcall(edit.SetFontObject, edit, _G.ChatFontNormal)
    edit:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
    edit:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    edit:SetWidth(600)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    local special = _G.UISpecialFrames
    if type(special) == "table" then table.insert(special, "RynaChronicleProbe") end
    box = { frame = f, edit = edit }
  end
  box.edit:SetText(text)
  box.frame:Show()
  pcall(box.edit.SetFocus, box.edit)
  pcall(box.edit.HighlightText, box.edit)
end

function P.Clear()
  local s = store()
  if s then s.lines = {} end
  ns.Print("probe: cleared")
end

local function command(arg)
  if arg == "" or arg == "now" then
    P.Now()
  elseif arg == "watch" or arg == "on" then
    P.Watch(true)
  elseif arg == "off" then
    P.Watch(false)
  elseif arg == "loot" then
    P.Loot()
  elseif arg == "comms" then
    P.Comms()
  elseif arg == "group" then
    P.Group()
  elseif arg == "casts" then
    P.Casts()
  elseif arg == "meter" then
    P.Meter()
  elseif arg == "guild" then
    P.Guild()
  elseif arg == "show" then
    P.Show()
  elseif arg == "clear" then
    P.Clear()
  else
    ns.Print("usage: /ryna probe (a reading now), /ryna probe "
      .. "watch||off||loot||comms||group||casts||meter||guild||show||clear")
  end
end
P.Command = command

-- A watch left on is taken up again after a /reload or a login, without a line of its own.
ns.On("PLAYER_LOGIN", function()
  local s = store()
  if s and s.watch then
    P.Watch(true, true)
    say("watching again after a reload")
  end
end)

ns.API.Slash.Add({ word = "probe", order = 90, run = command,
  help = "/ryna probe: what the client answers here (for a report); /ryna probe "
    .. "watch||off||loot||comms||group||casts||meter||guild||show||clear" })
