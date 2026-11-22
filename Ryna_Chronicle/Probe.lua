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
--   /ryna probe off     stop watching
--   /ryna probe show    every line so far in a box to copy from (the last 240, kept across a /reload)
--   /ryna probe clear   forget them
--
-- The lines are for a report, so they stay in English whatever the client's language. Nothing here is
-- recorded on a character, sent to the journal or read by the companion app: the lines live in
-- RynaDB.chronicle.probe until cleared.

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
    local names = {}
    for k, v in pairs(H) do
      if type(v) == "function" then names[#names + 1] = tostring(k) end
    end
    table.sort(names)
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
  elseif arg == "show" then
    P.Show()
  elseif arg == "clear" then
    P.Clear()
  else
    ns.Print("usage: /ryna probe (a reading now), /ryna probe watch||off||loot||show||clear")
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
  help = "/ryna probe: what the client answers here (for a report); /ryna probe watch||off||loot||show||clear" })
