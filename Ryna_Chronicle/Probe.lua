-- Probe: /ryna probe, the in-game questions dungeon runs wait on (ryna_agent
-- docs/ryna-agent-cores-mods.md 7.7; docs/forever-client-api.md "Still owed", R1 to R5), asked by one
-- command instead of a macro each. It only reads and prints, and only when asked:
--
--   /ryna probe         what the client says right now: in combat or not, IsInInstance,
--                       GetInstanceInfo, the target's GUID (its instance copy and creature id), and
--                       whether the GUID, the name, experience and money are secret here
--   /ryna probe watch   also print a boss's ENCOUNTER_START, ENCOUNTER_END and BOSS_KILL, the coin
--                       line (CHAT_MSG_MONEY), an instance reset's system line, and the same reading
--                       at the start of the next three fights; kept on across a /reload
--   /ryna probe off     stop watching
--   /ryna probe show    every line so far in a box to copy from (the last 80, kept across a /reload)
--   /ryna probe clear   forget them
--
-- The lines are for a report, so they stay in English whatever the client's language. Nothing here is
-- recorded on a character, sent to the journal or read by the companion app: the lines live in
-- RynaDB.chronicle.probe until cleared.

local _, ns = ...
if ns.off then return end

local P = {}
ns.Probe = P

local MAX_LINES = 80
local FIGHTS = 3
local EVENTS = { "ENCOUNTER_START", "ENCOUNTER_END", "BOSS_KILL", "CHAT_MSG_MONEY", "CHAT_MSG_SYSTEM",
  "PLAYER_REGEN_DISABLED" }

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

local function first(name, ...)
  local f = ns.Fn(name)
  if not f then return nil end
  local ok, v = pcall(f, ...)
  if ok then return v end
  return nil
end

-- The target's GUID taken apart: Creature-0-<server>-<map>-<instance copy>-<npc>-<spawn>.
local function guidLine()
  local guid = first("UnitGUID", "target")
  if guid == nil then return "target: none" end
  if ns.IsSecret(guid) then return "target guid: secret" end
  local parts = {}
  for part in tostring(guid):gmatch("[^-]+") do parts[#parts + 1] = part end
  if (parts[1] == "Creature" or parts[1] == "Vehicle") and #parts >= 7 then
    return string.format("target guid: %s (map %s, copy %s, npc %s)", guid, parts[4], parts[5], parts[6])
  end
  return "target guid: " .. tostring(guid) .. " (not a creature)"
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
    P.Now(string.format("fight %d of %d", fights, FIGHTS))
  elseif event == "CHAT_MSG_SYSTEM" then
    local msg = ...
    if not ns.IsSecret(msg) and isReset(msg) then say("reset line: " .. msg) end
  elseif event == "CHAT_MSG_MONEY" then
    say("CHAT_MSG_MONEY: " .. show((...)))
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
  elseif arg == "show" then
    P.Show()
  elseif arg == "clear" then
    P.Clear()
  else
    ns.Print("usage: /ryna probe (a reading now), /ryna probe watch||off||show||clear")
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
  help = "/ryna probe: what the client answers here (for a report); /ryna probe watch||off||show||clear" })
