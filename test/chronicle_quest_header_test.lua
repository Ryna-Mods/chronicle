-- Chronicle's quest log (Quests.lua, Q.ScanLog) against a fake client: each active quest records the
-- header row it sits under (`header`, docs/wow.md section 14), on a modern client (C_QuestLog.GetInfo,
-- as Forever's own quest log reads it) and on a classic one (GetQuestLogTitle). From the repository
-- root, with Lua 5.1 (what the game runs) or later:
--
--   lua5.1 test/chronicle_quest_header_test.lua
--
-- This proves the logic; the row shapes are from Blizzard's Forever UI source and API docs
-- (docs/forever-client-api.md "Quests and gossip"), and the game has the final say.
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

local errors, chat = {}, {}
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
_G.GetLocale = function() return "enUS" end
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
  DebugChanged = function() end,
  Run = run,
  Debounce = function() end,
  ReportError = function(label, err) errors[#errors + 1] = label .. ": " .. tostring(err) end,
  On = function(event, f)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], f)
    return true
  end,
  DB = function() return {} end,
  RegisterMod = function() return true end,
  Journal = { Add = function() end },
  Settings = { Get = function() return nil end, Set = function() end, AddDefaults = function() end },
}

local ns = {}
for _, file in ipairs({ "Mod.lua", "Locales/enUS.lua", "Quests.lua" }) do
  local chunk = assert(loadfile(ADDON .. file))
  chunk("Ryna_Chronicle", ns)
end
check(not ns.off and ns.Quests and type(ns.Quests.ScanLog) == "function", "Quests.lua loads")

-- The log as rows: { header = "Title" } or { id, title }. A header with title SECRET or "" stands
-- for one whose title can't be read.
local LOG = {
  { id = 90, title = "Before any header" },
  { header = "Elwynn Forest" },
  { id = 11, title = "A Threat Within" },
  { id = 12, title = "Wolves Across the Border" },
  { header = "Shaman" },
  { id = 13, title = "Call of Earth" },
  { header = SECRET },
  { id = 14, title = "Hidden header" },
  { header = "" },
  { id = 15, title = "Empty header" },
  { header = "Westfall" },
  { id = 16, title = "The Defias Brotherhood" },
}

local function modern(rows)
  _G.GetNumQuestLogEntries, _G.GetQuestLogTitle = nil, nil
  _G.C_QuestLog = {
    GetNumQuestLogEntries = function() return #rows, 6 end,
    GetInfo = function(i)
      local r = rows[i]
      if not r then return nil end
      if r.header then
        return { title = r.header, questLogIndex = i, questID = 0, level = 0, isHeader = true, isCollapsed = false }
      end
      return { title = r.title, questLogIndex = i, questID = r.id, level = 10, isHeader = false }
    end,
    GetQuestObjectives = function() return {} end,
  }
end

local function classic(rows)
  _G.C_QuestLog = nil
  _G.GetNumQuestLogEntries = function() return #rows, 6 end
  -- title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID
  _G.GetQuestLogTitle = function(i)
    local r = rows[i]
    if not r then return nil end
    if r.header then return r.header, 0, 0, true, false, nil, nil, 0 end
    return r.title, 10, 0, false, false, nil, nil, r.id
  end
  _G.GetNumQuestLeaderBoards = function() return 0 end
end

local function scan()
  ns.rec = { quests = { active = {}, completed = {} } }
  ns.Quests.acceptedAt = nil
  run("scan", ns.Quests.ScanLog)
  local by = {}
  for _, q in ipairs(ns.rec.quests.active) do by[q.id] = q end
  return ns.rec.quests.active, by
end

for _, shape in ipairs({ { "modern", modern }, { "classic", classic } }) do
  local name, setup = shape[1], shape[2]
  setup(LOG)
  local active, by = scan()
  check(#active == 7, name .. ": every quest row is a quest, no header row is")
  check(by[90] and by[90].header == nil, name .. ": a quest before any header row has none")
  check(by[11] and by[11].header == "Elwynn Forest", name .. ": the header row above the quest")
  check(by[12] and by[12].header == "Elwynn Forest", name .. ": every quest under it, not just the first")
  check(by[13] and by[13].header == "Shaman", name .. ": a category header (a class's quests)")
  check(by[14] and by[14].header == nil, name .. ": a secret header title is never kept")
  check(by[15] and by[15].header == nil, name .. ": an empty header title is none, not the previous one")
  check(by[16] and by[16].header == "Westfall", name .. ": the next header takes over")
  check(by[11] and by[11].title == "A Threat Within" and by[11].level == 10,
    name .. ": the rest of the entry as before")
end

check(#chat == 0, "nothing in chat")
check(#errors == 0, "no handler raised: " .. table.concat(errors, "; "))
print(string.format("chronicle quest headers: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
