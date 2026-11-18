-- Chronicle's gold on the character record (Character.lua: C.Login, PLAYER_MONEY, C.Logout) against a
-- fake client: login, a money change, then logout with GetMoney answering 0, nothing or a secret
-- there, as it did for every character on 2026-11-12 (the record saved 0 while the journal had their
-- gold). From the repository root, with Lua 5.1 (what the game runs) or later:
--
--   lua5.1 test/chronicle_gold_test.lua
--
-- This proves the logic; what GetMoney returns during PLAYER_LOGOUT on Forever is for the game to say.
-- luacheck: ignore 1

local ADDON = "Ryna_Chronicle/"

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

local SECRET = setmetatable({}, { __tostring = function() return "secret" end })

local function passResults(ok, ...)
  if ok then return ... end
  return nil
end
local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  return passResults(pcall(fn, ...))
end
local function fn(a, b)
  local v = _G[a]
  if b ~= nil then
    if type(v) ~= "table" then return nil end
    v = v[b]
  end
  return type(v) == "function" and v or nil
end

local handlers = {}
local db = { characters = {} }
_G.GetLocale = function() return "enUS" end
_G.time = os.time
_G.GetTime = function() return 1000 end
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) chat[#chat + 1] = msg end }
_G.Ryna = {
  API = 1, VERSION = "test", L = setmetatable({}, { __index = function(_, k) return k end }),
  Try = try, Fn = fn,
  IsSecret = function(v) return v == SECRET end,
  NonEmpty = function(s) if type(s) == "string" and s ~= "" and s ~= SECRET then return s end end,
  Locale = function() return "enUS" end,
  Now = function() return 1800000000 end,
  Print = function(m) chat[#chat + 1] = "Ryna: " .. m end,
  Debug = function() end,
  Run = run,
  Debounce = function() end,
  ReportError = function(label, err) errors[#errors + 1] = label .. ": " .. tostring(err) end,
  MoneyText = function(c) return tostring(c) end,
  DurationText = function(s) return tostring(s) end,
  On = function(event, f)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], f)
    return true
  end,
  DB = function() return db end,
  RegisterMod = function() return true end,
  Journal = { Add = function(t, e) journal[#journal + 1] = { type = t, data = e } end },
  Settings = { Get = function() return nil end, Set = function() end, AddDefaults = function() end },
}

local ns = {}
for _, file in ipairs({ "Mod.lua", "Locales/enUS.lua", "Character.lua" }) do
  local chunk = assert(loadfile(ADDON .. file))
  chunk("Ryna_Chronicle", ns)
end
local C = ns.Character
check(not ns.off and C and type(C.Login) == "function", "Character.lua loads")

local GUID = "Player-1-0F00A001"
_G.UnitGUID = function() return GUID end
_G.UnitName = function() return "Aerin" end

-- `money` is what GetMoney answers now: a number, nil (nothing), SECRET, or "error" (it throws).
local money
_G.GetMoney = function()
  if money == "error" then error("GetMoney failed") end
  return money
end

local function fire(event, ...)
  for _, f in ipairs(handlers[event] or {}) do run(event, f, event, ...) end
end

-- One session: login with `atLogin`, then each of `changes` as a PLAYER_MONEY, then logout with
-- `atLogout`. `before` is the record saved by the last session (nil for none). Returns the saved
-- gold and the gold journal events.
local function session(before, atLogin, changes, atLogout)
  db.characters = {}
  if before ~= nil then db.characters[GUID] = { guid = GUID, gold = before } end
  journal = {}
  C.lastMoney, C.goldAnchor = nil, nil
  money = atLogin
  run("login", C.Login)
  for _, amount in ipairs(changes) do
    money = amount
    fire("PLAYER_MONEY")
  end
  money = atLogout
  run("logout", C.Logout)
  local golds = {}
  for _, e in ipairs(journal) do
    if e.type == "gold" then golds[#golds + 1] = e.data end
  end
  return db.characters[GUID].gold, golds
end

-- The bug: login, a money change, logout reading 0. ---------------------------------------------
check(session(nil, 52000, { 61000 }, 0) == 61000, "logout reading 0 keeps the last PLAYER_MONEY amount")
check(session(nil, 52000, { 61000 }, nil) == 61000, "logout reading nothing keeps the last PLAYER_MONEY amount")
check(session(nil, 52000, { 61000 }, SECRET) == 61000, "a secret at logout is never saved or compared")
check(session(nil, 52000, { 61000 }, "error") == 61000, "GetMoney throwing at logout keeps the amount")
check(session(nil, 52000, {}, 0) == 52000, "no money change: logout reading 0 keeps the login amount")
check(session(nil, 52000, { 61000 }, 70000) == 70000, "a positive logout read is the latest: taken")

-- A real 0 stays 0. ------------------------------------------------------------------------------
check(session(nil, 52000, { 0 }, 0) == 0, "spent down to 0 (PLAYER_MONEY said 0): 0 is saved")
check(session(nil, 0, {}, 0) == 0, "a new character with no money: 0")
check(session(nil, 0, { 300 }, 0) == 300, "a first copper, then logout reading 0: 300")

-- Login reads that can't be trusted. -------------------------------------------------------------
check(session(61000, 0, {}, 0) == 61000,
  "login and logout both reading 0 for a character saved with gold: the saved amount stays")
check(session(61000, nil, {}, nil) == 61000, "login and logout both unreadable: the saved amount stays")
check(session(61000, SECRET, {}, 0) == 61000, "a secret at login: the saved amount stays")
local gold, events = session(61000, 0, { 65000 }, 0)
check(gold == 65000, "login reading 0, then PLAYER_MONEY: that amount")
check(#events == 0, "and no gold event for the jump from a 0 that was never real")
gold, events = session(61000, 61000, { 75000 }, 0)
check(gold == 75000 and #events == 1 and events[1].delta == 14000 and events[1].total == 75000,
  "a real change of a gold or more is still a gold event")

check(#chat == 0, "nothing in chat")
check(#errors == 0, "no handler raised: " .. table.concat(errors, "; "))
print(string.format("chronicle gold: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
