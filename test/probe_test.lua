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
  Fn = function(a)
    local v = _G[a]
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
  .. "PLAYER_REGEN_DISABLED"), "says what it registered")
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
for _ = 1, 30 do commands.probe.run("") end
check(#kept() == 80, "at most 80 lines are kept")
check(kept()[80]:match("^%d%d:%d%d:%d%d hidden here"), "each kept line carries its time")
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
  check(said("watching: ENCOUNTER_END, BOSS_KILL, CHAT_MSG_MONEY, CHAT_MSG_SYSTEM, PLAYER_REGEN_DISABLED; "
    .. "refused ENCOUNTER_START"), "a refused event is named, the rest are still watched")
  commands.probe.run("off")
  _G.CreateFrame = create
end

check(#errors == 0, "no handler raised: " .. table.concat(errors, "; "))
print(string.format("probe: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
