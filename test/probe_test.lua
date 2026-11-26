-- /ryna probe (Probe.lua) against a fake client: a reading inside a dungeon, one where the client
-- hides values, the watch (boss events, the coin line, a reset line, the first three fights, an event
-- the client refuses), the kept lines and their cap, and the watch taken up again after a /reload.
-- From the repository root, with Lua 5.1 (what the game runs) or later:
--
--   lua5.1 test/probe_test.lua
--
-- This proves the command; what Forever answers is what the command is for.
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

local errors, chat = {}, {}
local function run(label, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then errors[#errors + 1] = label .. ": " .. tostring(err) end
end

local SECRET = setmetatable({}, { __tostring = function() error("a secret was turned into text") end })

local function passResults(ok, ...)
  if ok then return ... end
  return nil
end

local handlers, commands = {}, {}
local db = { characters = {} }
_G.Ryna = {
  API = 2, VERSION = "test", L = setmetatable({}, { __index = function(_, k) return k end }),
  Try = function(fn, ...)
    if type(fn) ~= "function" then return nil end
    return passResults(pcall(fn, ...))
  end,
  Fn = function(a, b)
    local v = _G[a]
    if b ~= nil then v = type(v) == "table" and v[b] or nil end
    return type(v) == "function" and v or nil
  end,
  IsSecret = function(v) return v == SECRET end,
  Print = function(m) chat[#chat + 1] = m end,
  Run = run,
  After = function(_, label, fn) C_Timer.After(0, function() run(label, fn) end) end,
  On = function(event, f)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], f)
    return true
  end,
  DB = function() return db end,
  RegisterMod = function() return true end,
  Journal = { Add = function() error("the probe wrote to the journal") end },
  Settings = { Get = function() return nil end, Set = function() end, AddDefaults = function() end },
  Slash = { Add = function(spec) commands[spec.word] = spec end },
}

local ns = {}
for _, file in ipairs({ "Mod.lua", "Locales/enUS.lua", "Probe.lua" }) do
  assert(loadfile(ADDON .. file))("Ryna_Chronicle", ns)
end
local P = ns.Probe
check(not ns.off and P and commands.probe and type(commands.probe.run) == "function", "/ryna probe is added")

local function said(text)
  for _, line in ipairs(chat) do
    if line:find(text, 1, true) then return true end
  end
  return false
end
local function kept() return db.chronicle and db.chronicle.probe and db.chronicle.probe.lines or {} end

-- A reading inside The Deadmines, out of combat, with a mob targeted. ----------------------------
local guid = "Creature-0-4170-36-4417-634-00001A2B3C"
local name, xp, money, combat = "Defias Overseer", 1200, 52000, false
_G.InCombatLockdown = function() return combat end
_G.IsInInstance = function() return true, "party" end
_G.GetInstanceInfo = function() return "The Deadmines", "party", 1, "Normal", 5, 0, nil, 36, 5 end
_G.UnitGUID = function(unit) if unit == "target" then return guid end end
_G.UnitName = function() return name end
_G.UnitXP = function() return xp end
_G.UnitXPMax = function() return 21300 end
_G.GetMoney = function() return money end

commands.probe.run("")
check(said("now: in combat false"), "says it is out of combat")
check(said("IsInInstance: true, party"), "IsInInstance, both answers")
check(said("GetInstanceInfo: The Deadmines, party, 1, Normal, 5, 0, nil, 36, 5"),
  "GetInstanceInfo whole, a nil in the middle kept in its place")
check(said("(map 36, copy 4417, npc 634)"), "the GUID's map, instance copy and creature id")
check(said("hidden here: target guid plain, target name plain, xp plain, xp max plain, money plain"),
  "nothing hidden out of combat")
check(#kept() == 5, "the five lines are kept")

-- In combat, with the client hiding the GUID, the name and experience. ----------------------------
chat = {}
combat, guid, name, xp = true, SECRET, SECRET, SECRET
commands.probe.run("now")
check(said("target guid: secret"), "a secret GUID is named, not parsed")
check(said("hidden here: target guid secret, target name secret, xp secret, xp max plain, money plain"),
  "each value says whether it is hidden")

-- Nothing targeted, and a client without a call. ------------------------------------------------
chat = {}
guid, name, xp, combat = nil, nil, 1200, false
_G.GetInstanceInfo = nil
commands.probe.run("")
check(said("target: none"), "no target")
check(said("GetInstanceInfo: missing"), "a call the client lacks is named")

-- A player targeted is not taken apart as a creature.
chat = {}
guid = "Player-91-0A4C7F12"
commands.probe.run("")
check(said("target guid: Player-91-0A4C7F12 (not a creature)"), "a player's GUID is shown whole")

-- The watch. ------------------------------------------------------------------------------------
chat = {}
_G.INSTANCE_RESET_SUCCESS = "%s has been reset."
commands.probe.run("watch")
check(said("watching: ENCOUNTER_START, ENCOUNTER_END, BOSS_KILL, CHAT_MSG_MONEY, CHAT_MSG_SYSTEM, "
  .. "PLAYER_REGEN_DISABLED, LOOT_OPENED, CHAT_MSG_LOOT, START_LOOT_ROLL, LOOT_ROLLS_COMPLETE, LOOT_ITEM_ROLL_WON, "
  .. "LOOT_HISTORY_UPDATE_ENCOUNTER, LOOT_HISTORY_UPDATE_DROP, LOOT_HISTORY_ROLL_COMPLETE, "
  .. "LOOT_HISTORY_ROLL_CHANGED, LOOT_HISTORY_FULL_UPDATE"), "says what it registered")
check(db.chronicle.probe.watch == true, "the watch is remembered")

chat = {}
F.Fire("ENCOUNTER_START", 2741, "Rhahk'Zor", 1, 5)
check(said("ENCOUNTER_START: 2741, Rhahk'Zor, 1, 5"), "a boss pull with its arguments")
F.Fire("ENCOUNTER_END", 2741, "Rhahk'Zor", 1, 5, SECRET)
check(said("ENCOUNTER_END: 2741, Rhahk'Zor, 1, 5, secret"), "a hidden argument is named")
F.Fire("BOSS_KILL")
check(said("BOSS_KILL: no arguments"), "an event with nothing")
F.Fire("CHAT_MSG_MONEY", "You loot 4 Silver, 12 Copper")
check(said("CHAT_MSG_MONEY: You loot 4 Silver, 12 Copper"), "the coin line as received")
F.Fire("CHAT_MSG_MONEY", SECRET)
check(said("CHAT_MSG_MONEY: secret"), "a hidden coin line")
_G.GetLootSourceInfo = function() return "Creature-0-8452-48-8801871-4807-1C5DBBE380", 67 end
F.Fire("LOOT_OPENED")
check(said("loot source guid: Creature-0-8452-48-8801871-4807-1C5DBBE380 (map 48, copy 8801871, npc 4807)"),
  "a looted corpse's GUID, taken apart")
_G.GetLootSourceInfo = function() return SECRET end
F.Fire("LOOT_OPENED")
check(said("loot source guid: secret"), "a hidden loot source is named")

-- Loot and rolls: the line, a roll starting, a roll's system line, the loot history's record of a drop.
local link = "|cff1eff00|Hitem:5196::::::::20:::::|h[Smite's Mighty Hammer]|h|r"
F.Fire("CHAT_MSG_LOOT", "Thorbrand receives loot: " .. link .. ".", "Thorbrand-Forever")
check(said("CHAT_MSG_LOOT: Thorbrand receives loot: ") and said(" | from Thorbrand-Forever"),
  "a loot line and whose it is")
F.Fire("CHAT_MSG_LOOT", SECRET, SECRET)
check(said("CHAT_MSG_LOOT: secret | from secret"), "a hidden loot line")
_G.GetLootRollItemInfo = function() return 132345, "Smite's Mighty Hammer", 1, 3, true, true, true, false end
F.Fire("START_LOOT_ROLL", 7, 60000)
check(said("START_LOOT_ROLL: 7 -> GetLootRollItemInfo: 132345, Smite's Mighty Hammer, 1, 3, true, true, true, false"),
  "a roll starting, with what the client says of it")
chat = {}
F.Fire("CHAT_MSG_SYSTEM", "Thorbrand rolls 87 (Need) for " .. link)
check(said("system line with an item: Thorbrand rolls 87 (Need) for "), "a roll's system line")
_G.C_LootHistory = {
  GetSortedInfoForDrop = function()
    return { itemHyperlink = link, winner = { playerName = SECRET, isSelf = false },
      rollInfos = { { playerName = "Thorbrand", roll = 87, state = 0, isWinner = true } } }
  end,
}
F.Fire("LOOT_HISTORY_UPDATE_DROP", 2916, 3)
check(said("LOOT_HISTORY_UPDATE_DROP: 2916, 3 -> {itemHyperlink=") and said("winner={isSelf=false, playerName=secret}"),
  "the loot history's drop, a hidden name marked")
check(said("rollInfos={1={...}}"), "and no deeper than two levels")

chat = {}
F.Fire("CHAT_MSG_SYSTEM", "Thorbrand has come online.")
check(#chat == 0, "an ordinary system line is ignored")
F.Fire("CHAT_MSG_SYSTEM", "The Deadmines has been reset.")
check(said("reset line: The Deadmines has been reset."), "a reset's system line")
F.Fire("CHAT_MSG_SYSTEM", SECRET)
check(#chat == 1, "a hidden system line is ignored")

chat = {}
for _ = 1, 5 do F.Fire("PLAYER_REGEN_DISABLED") end
check(#chat == 0, "the fight reading waits a moment, since combat's rules aren't in force at the event")
F.RunTimers()
local readings = 0
for _, line in ipairs(chat) do
  if line:find("fight %d of 3") then readings = readings + 1 end
end
check(readings == 3, "a reading at the start of three fights, then no more")

-- Off. --------------------------------------------------------------------------------------------
chat = {}
commands.probe.run("off")
check(said("watching: off") and db.chronicle.probe.watch == nil, "off is said and remembered")
chat = {}
F.Fire("ENCOUNTER_START", 1, "x")
F.Fire("PLAYER_REGEN_DISABLED")
check(#chat == 0, "nothing after off")

-- The kept lines: capped, shown in a box, cleared. -------------------------------------------------
for _ = 1, 60 do commands.probe.run("") end
check(#kept() == 240, "at most 240 lines are kept")
check(kept()[240]:match("^%d%d:%d%d:%d%d hidden here"), "each kept line carries its time")
chat = {}
commands.probe.run("show")
check(#chat == 0, "show opens its box without a chat line")
chat = {}
commands.probe.run("clear")
check(#kept() == 0 and said("cleared"), "clear forgets them")
chat = {}
commands.probe.run("show")
check(said("nothing kept yet"), "show with nothing kept says so")
commands.probe.run("nonsense")
check(said("usage: /ryna probe"), "an unknown word gets the usage line")

-- A watch left on is taken up again at the next login (a /reload). ---------------------------------
commands.probe.run("watch")
chat = {}
for _, f in ipairs(handlers.PLAYER_LOGIN or {}) do run("login", f, "PLAYER_LOGIN") end
check(said("watching again after a reload"), "the watch is taken up again")
chat = {}
F.Fire("BOSS_KILL", 644, "Rhahk'Zor")
check(said("BOSS_KILL: 644, Rhahk'Zor"), "and still hears a boss")
commands.probe.run("off")
chat = {}
for _, f in ipairs(handlers.PLAYER_LOGIN or {}) do run("login", f, "PLAYER_LOGIN") end
check(#chat == 0, "a watch that is off stays off, silently")

-- A client that refuses an event to addons (as it does the combat log's). --------------------------
do
  local create = _G.CreateFrame
  _G.CreateFrame = function(...)
    local f = create(...)
    local register = f.RegisterEvent
    rawset(f, "RegisterEvent", function(self, event)
      if event == "ENCOUNTER_START" then error("blocked") end
      return register(self, event)
    end)
    return f
  end
  local fresh = {}
  for _, file in ipairs({ "Mod.lua", "Locales/enUS.lua", "Probe.lua" }) do
    assert(loadfile(ADDON .. file))("Ryna_Chronicle", fresh)
  end
  chat = {}
  commands.probe.run("watch")
  check(said("watching: ENCOUNTER_END, BOSS_KILL, CHAT_MSG_MONEY, CHAT_MSG_SYSTEM, PLAYER_REGEN_DISABLED, "
    .. "LOOT_OPENED, CHAT_MSG_LOOT") and said("; refused ENCOUNTER_START"),
    "a refused event is named, the rest are still watched")
  commands.probe.run("off")
  _G.CreateFrame = create
end

-- /ryna probe loot: which loot history there is, and what it holds. ---------------------------------------
chat = {}
_G.C_LootHistory = nil
commands.probe.run("loot")
check(said("loot: C_LootHistory missing"), "no loot history at all")
_G.GetLootMethod = function() return "group" end
_G.GetLootThreshold = function() return 2 end
_G.C_LootHistory = {
  GetAllEncounterInfos = function() return { { encounterID = 2916, encounterName = "Ghamoo-ra", startTime = 5 } } end,
  GetSortedDropsForEncounter = function()
    return { { lootListID = 3, itemHyperlink = "[x]", winner = { playerName = "A" } } }
  end,
  GetSortedInfoForDrop = function() return {} end,
}
commands.probe.run("loot")
check(said("loot: C_LootHistory has GetAllEncounterInfos, GetSortedDropsForEncounter, GetSortedInfoForDrop"),
  "the functions the client has, named")
check(said("loot: 1 encounters in the history") and said("encounterName=Ghamoo-ra"), "the encounters it holds")
check(said("loot: drop 1: {itemHyperlink=[x], lootListID=3, winner={playerName=A}}"), "the last encounter's drops")
check(said("loot: method group; threshold 2"), "the loot method and threshold")
_G.C_LootHistory = { GetNumItems = function() return 1 end,
  GetItem = function() return 7, "[x]", 5, false, 2, false end,
  GetPlayerInfo = function() return "Thorbrand", "WARRIOR", 1, 87, true, false end }
chat = {}
commands.probe.run("loot")
check(said("loot: Classic history items: 1") and said("loot: item 1, player 1: Thorbrand, WARRIOR, 1, 87, true, false"),
  "Classic's loot history, where that is the one there is")

-- /ryna probe comms: the prefix, each send, and what arrives. --------------------------------------------
chat = {}
local sent = {}
_G.UnitFullName = function() return "Maddie", "Markham" end
_G.IsInInstance = function() return false, "none" end
_G.IsInGroup = function() return true end
_G.IsInRaid = function() return false end
_G.IsInGuild = function() return true end
_G.C_ChatInfo = {
  InChatMessagingLockdown = function() return false end,
  RegisterAddonMessagePrefix = function() return true end,
  SendAddonMessage = function(prefix, text, channel, target)
    if channel == "GUILD" then error("refused in a test") end
    sent[#sent + 1] = { prefix, text, channel, target }
    return 0
  end,
}
commands.probe.run("comms")
check(said("comms: messaging lockdown false; in combat false; IsInInstance false, none"), "comms says where it is")
check(said("comms: RegisterAddonMessagePrefix: true") and said("comms: UnitFullName: Maddie, Markham"),
  "the prefix's answer and the name as the client gives it")
check(#sent == 3 and sent[1][1] == "RynaProbe" and sent[1][3] == "WHISPER" and sent[1][4] == "Maddie-Markham"
  and sent[2][4] == "Maddie" and sent[3][3] == "PARTY", "a whisper to the whole name, to the short one, and the party")
check(said("comms: sent whisper: 0") and said("comms: sent party: 0"), "each send's answer")
check(said("comms: sent guild: error: ") and said("refused in a test"), "a refused send says why")
check(said("comms: not tried (not in one): raid"), "a channel it isn't in is named")
chat = {}
F.Fire("CHAT_MSG_ADDON", "RynaProbe", "ping whisper", "WHISPER", "Maddie-Markham")
check(said('CHAT_MSG_ADDON: ping whisper | WHISPER | from "Maddie-Markham" (this character)'),
  "a ping that arrives, with its own sender whole")
F.Fire("CHAT_MSG_ADDON", "RynaProbe", "ping guild", "GUILD", "Maddie Markham")
check(said('| GUILD | from "Maddie Markham" (this character)'), "its own name in another form is still its own")
F.Fire("CHAT_MSG_ADDON", "RynaProbe", "ping party", "PARTY", "Thorbrand-Ironfoot")
check(said('CHAT_MSG_ADDON: ping party | PARTY | from "Thorbrand-Ironfoot"') and not said("Ironfoot\" (this"),
  "another prober's ping shows its sender as stamped")
F.Fire("CHAT_MSG_ADDON", "RynaProbe", "ping party", "PARTY", SECRET)
check(said("| PARTY | from secret"), "a hidden sender is named as hidden")
chat = {}
F.Fire("CHAT_MSG_ADDON", "DBM", "x", "PARTY", "Thorbrand-Ironfoot")
check(#chat == 0, "another addon's message is ignored")
for _ = 1, 5 do F.Fire("CHAT_MSG_ADDON", SECRET, SECRET, SECRET, SECRET) end
check(#chat == 3, "a secret prefix is said three times, no more")
chat = {}
_G.C_ChatInfo.SendAddonMessage = nil
commands.probe.run("comms")
check(said("comms: C_ChatInfo.SendAddonMessage missing"), "a client without the call says so")

-- /ryna probe group: the others in the party, never by name. --------------------------------------------
chat = {}
_G.GetNumGroupMembers = function() return 3 end
_G.UnitExists = function(unit) return unit == "party1" or unit == "party2" end
_G.UnitName = function(unit) return unit == "party2" and SECRET or "Thorbrand" end
_G.UnitGUID = function() return "Player-91-0A4C7F12" end
_G.UnitIsAFK = function(unit) return unit == "party1" end
_G.UnitIsConnected = function() return true end
_G.UnitInRange = function() return true, true end
_G.UnitIsDeadOrGhost = function() return false end
_G.UnitGroupRolesAssigned = function() return "TANK" end
_G.UnitLevel = function() return SECRET end
commands.probe.run("group")
check(said("group: in combat false; IsInInstance false, none; members 3"), "group says where it is")
check(said("group: party1: name plain; guid plain; UnitIsAFK true; UnitIsConnected true; UnitInRange true, true; "
  .. "UnitIsVisible missing; UnitIsDeadOrGhost false; UnitGroupRolesAssigned TANK; UnitLevel secret"),
  "a member's answers, a missing call and a hidden one named")
check(said("group: party2: name secret; guid plain; UnitIsAFK false"), "a hidden name is named as hidden")
check(not said("Thorbrand") and not said("Player-91"), "no name and no GUID in a group line")
chat = {}
_G.UnitExists = function() return false end
commands.probe.run("group")
check(said("group: no party members"), "alone, it says so")

-- /ryna probe casts: the next ten by the group. ------------------------------------------------------------
chat = {}
commands.probe.run("casts")
check(said("casts: the next 10 casts by party or raid members"), "casts says what it waits for")
chat = {}
F.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3-1", 585)
check(#chat == 0, "this character's own casts are left out")
F.Fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-3-2", 355)
check(said("cast: party1 spell 355 (cast guid plain)"), "a party member's cast")
F.Fire("UNIT_SPELLCAST_SUCCEEDED", "party2", SECRET, SECRET)
check(said("cast: party2 spell secret (cast guid secret)"), "a hidden spell is named as hidden")
F.Fire("UNIT_SPELLCAST_SUCCEEDED", SECRET, SECRET, SECRET)
check(said("cast: the unit is secret"), "a hidden unit is named as hidden")
for _ = 1, 20 do F.Fire("UNIT_SPELLCAST_SUCCEEDED", "raid7", "Cast-3-3", 1) end
check(said("casts: done"), "it stops by itself")
local castLines = 0
for _, line in ipairs(chat) do
  if line:find("probe: cast: ", 1, true) then castLines = castLines + 1 end
end
check(castLines == 10, "after ten lines")

-- /ryna probe meter: every type, a source as its class and amount. ----------------------------------------
chat = {}
_G.C_DamageMeter = nil
commands.probe.run("meter")
check(said("meter: C_DamageMeter missing"), "no meter at all")
_G.Enum = { DamageMeterType = { DamageDone = 0, HealingDone = 2 } }
_G.C_DamageMeter = {
  IsDamageMeterAvailable = function() return true end,
  GetAvailableCombatSessions = function() return { {}, {} } end,
  GetCombatSessionFromType = function(session, meter)
    if session == 0 then return { durationSeconds = 812, combatSources = { {}, {}, {} } } end
    if meter == 2 then return SECRET end
    return { totalAmount = 900, combatSources = {
      { name = "Maddie", sourceGUID = "Player-1-2", classFilename = "PRIEST", totalAmount = 300, isLocalPlayer = true },
      { name = SECRET, sourceGUID = SECRET, classFilename = "WARRIOR", totalAmount = SECRET, isLocalPlayer = SECRET },
    } }
  end,
}
commands.probe.run("meter")
check(said("meter: available true; in combat false") and said("meter: sessions 2"), "the meter and its sessions")
check(said("meter: overall damage done: 3 sources, 812 seconds"), "how many the overall session holds")
check(said("meter: DamageDone (0): total 900: PRIEST 300 (you), name plain, guid plain; "
  .. "WARRIOR secret, name secret, guid secret"),
  "the last fight's sources: class, amount, and whether the name and GUID are hidden")
check(said("meter: HealingDone (2): secret"), "a hidden session is named as hidden")
check(not said("name Maddie") and not said("Player-1-2"), "no name and no GUID in a meter line")
_G.Enum = nil
chat = {}
commands.probe.run("meter")
check(said("meter: type (0): total 900") and said("meter: type (2): secret") and said("meter: type (10): total 900"),
  "without the client's list, types 0 to 10")

-- /ryna probe guild: what there is to call, and the roster's order. ----------------------------------------
chat = {}
_G.GetNumGuildMembers = function() return 42, 7 end
_G.C_GuildInfo = { GuildRoster = function() end, CanViewOfficerNote = function() return false end, x = 1 }
_G.GetGuildRosterInfo = function()
  return "Keyvah-Proudshield", "Officer", 1, 22, "Paladin", "Ironforge", "", "", true
end
_G.CanEditPublicNote = function() return true end
_G.GuildPromote = function() error("the probe promoted someone") end
_G.GuildRosterSetPublicNote = function() error("the probe wrote a note") end
_G.C_Calendar = { OpenCalendar = function() end, GetNumDayEvents = function() return 0 end, other = function() end }
_G.C_Club = nil
commands.probe.run("guild")
check(said("guild: in a guild true; members 42, 7"), "in a guild, and how many")
check(said("guild: C_GuildInfo has CanViewOfficerNote, GuildRoster"), "the guild calls there are")
check(said("guild: GetGuildRosterInfo(1): Keyvah-Proudshield, Officer, 1, 22, Paladin, Ironforge, , , true"),
  "row 1 in the client's order")
check(said("CanEditPublicNote true") and said("CanGuildPromote missing"), "what this rank may do")
check(said("globals present: GuildRosterSetPublicNote, GuildPromote; missing: GuildRosterSetOfficerNote"),
  "which of the acting calls exist, none of them called")
check(said("guild: C_Calendar has 3 functions; of the ones asked: OpenCalendar, GetNumDayEvents"), "the calendar")
check(said("guild: C_Club missing"), "and communities")

check(#errors == 0, "no handler raised: " .. table.concat(errors, "; "))
print(string.format("probe: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
