-- Characters: the Characters section of Ryna's window (under Me), every character on the account
-- from the saved file (RynaDB.characters, what Character.lua records; nothing new is recorded here).
--
-- All characters: one row each, the one you're on first: the name in its class colour, the level
-- (with the experience bar), gold and time played (each over a bar of that character's share of the
-- account's, and the played bar's text with the share, "1d 4h · 73%", once more than one character
-- has time), professions with their ranks, and when it was last seen; tiles for how many characters
-- (and the highest level), their gold (and whose it is, when it is all on one), their time played,
-- and the last time another character was seen (docs/ryna-agent-cores-mods.md 7.5, "Owed after the
-- portal's 12 to 15 November features"). A click on a row picks that
-- character. One character: its detail, as headed groups of rows: the character (class, guild, zone,
-- talents), its gear by slot (the game's own item tooltip on hover), its professions and its
-- reputations, each with a bar.
--
-- One character's Quests (the detail's picker: Character, Quests; 7.5, "The quest log by zone or
-- heading"): its saved quest log, for any character on the account, so an alt's log reads without
-- logging over. The column heading's line counts it ("14 active · 4 ready to turn in"); the quests sit
-- under heading rows with a count ("Zephras Isle (6)"), by the heading the game's log filed each
-- under (Quests.lua's `header`), the groups with the most quests first, then by name, and the quests
-- in the log's own order within one. A quest's row: its title, its level and a bar of its objectives
-- done ("1 / 3"; "ready" on a full bar when every one is done; no bar when none was saved). Quests
-- saved before headings were recorded sit last, under "Picked up before this was recorded"; a
-- heading is never guessed. What the record keeps per objective is its text and whether it is done,
-- so the bar counts objectives, and the tooltip lists each one's text (the game's own "6/10").
--
-- The character you're on is live (its record is the one Chronicle keeps up to date); the others are
-- as of their last logout, and the footer says so.

local _, ns = ...
if ns.off then return end
local L = ns.L
local N = ns.N

local Wn = ns.Window
if not (Wn and Wn.available) then return end
local RW = ns.API.Window

local Ch = {}
ns.Characters = Ch

local function num(v)
  if type(v) == "number" then return v end
  return tonumber(v)
end

local function plain(s)
  return ns.Status.Plain(s) or s
end

-- Equipment slots 0 to 19: the client's own name for each (its GlobalStrings), else English.
local SLOTS = {
  [0] = { "AMMOSLOT", N("Ammo") }, { "HEADSLOT", N("Head") }, { "NECKSLOT", N("Neck") },
  { "SHOULDERSLOT", N("Shoulder") }, { "SHIRTSLOT", N("Shirt") }, { "CHESTSLOT", N("Chest") },
  { "WAISTSLOT", N("Waist") }, { "LEGSSLOT", N("Legs") }, { "FEETSLOT", N("Feet") },
  { "WRISTSLOT", N("Wrist") }, { "HANDSSLOT", N("Hands") }, { "FINGER0SLOT", N("Finger") },
  { "FINGER1SLOT", N("Finger") }, { "TRINKET0SLOT", N("Trinket") }, { "TRINKET1SLOT", N("Trinket") },
  { "BACKSLOT", N("Back") }, { "MAINHANDSLOT", N("Main Hand") }, { "SECONDARYHANDSLOT", N("Off Hand") },
  { "RANGEDSLOT", N("Ranged") }, { "TABARDSLOT", N("Tabard") },
}

function Ch.SlotName(slot)
  local e = SLOTS[tonumber(slot)]
  if not e then return tostring(slot) end
  return ns.NonEmpty(_G[e[1]]) or L[e[2]]
end

-- A reputation standing's name in the client's language ("Friendly"), from its GlobalStrings.
function Ch.StandingName(standing)
  standing = tonumber(standing)
  if not standing then return "" end
  return ns.NonEmpty(_G["FACTION_STANDING_LABEL" .. standing]) or tostring(standing)
end

local function standingColor(standing)
  local colors = _G.FACTION_BAR_COLORS
  local c = type(colors) == "table" and colors[tonumber(standing)]
  if type(c) == "table" and type(c.r) == "number" then return c.r, c.g, c.b end
  return nil
end

-- An item link's name ("Linen Boots"), from its [brackets].
function Ch.LinkName(link)
  if type(link) ~= "string" or ns.IsSecret(link) then return nil end
  return link:match("|h%[(.-)%]|h")
end

-- "Mining 75, Tailoring 120".
function Ch.ProfessionsText(rec)
  local parts = {}
  for _, p in ipairs(type(rec.professions) == "table" and rec.professions or {}) do
    if type(p) == "table" and ns.NonEmpty(p.name) then
      parts[#parts + 1] = string.format(L["%s %s"], plain(p.name), tostring(num(p.rank) or "?"))
    end
  end
  return table.concat(parts, ", ")
end

-- Played totals: the one you're on counted on from its last /played.
local function played(rec)
  if rec == ns.rec then
    local total, atLevel = ns.Character.PlayedNow()
    if total then return total, atLevel end
  end
  return num(rec.playedTotal), num(rec.playedLevel)
end

local function lastSeen(rec, ctx)
  if rec.guid ~= nil and rec.guid == ctx.current then return L["now"] end
  return ns.Status.Ago(num(rec.lastSeen)) or L["never"]
end

-- All characters --------------------------------------------------------------------------------------

local ALL_COLUMNS = {
  { title = L["Character"], width = 140 }, { title = L["Level"], width = 50, justify = "RIGHT", kind = "bar" },
  { title = L["Gold"], width = 115, justify = "RIGHT", kind = "bar" },
  { title = L["Played"], width = 105, justify = "RIGHT", kind = "bar" },
  { title = L["Professions"], width = 110 }, { title = L["Last seen"], width = 70, justify = "RIGHT" },
}

-- The share bars' colours: the game's gold text colour and a muted violet, both dimmed so the
-- white text over them reads.
local GOLD_BAR = { 0.55, 0.45, 0.05 }
local PLAYED_BAR = { 0.33, 0.31, 0.45 }

-- Each character's short name: its first name, or its full name when another character on the
-- account shares the first name (or it has none).
local function shortNames(list)
  local count, out = {}, {}
  for _, c in ipairs(list) do
    local first = ns.NonEmpty(c.rec.firstName)
    if first then count[first] = (count[first] or 0) + 1 end
  end
  for _, c in ipairs(list) do
    local first = ns.NonEmpty(c.rec.firstName)
    out[c.guid] = (first and count[first] == 1 and plain(first)) or c.name
  end
  return out
end

-- The account's gold and time played, and each character's part of them (nothing is recorded for
-- this: it is the saved file's gold and played, summed). A value the record doesn't have (nil, or
-- not a number) counts as nothing and is drawn as an empty bar.
-- -> { list (RW.Characters()), names, gold = { [guid] = copper or nil }, played = { [guid] = s or nil },
--      goldTotal, playedTotal, withGold, withTime, maxLevel, richest (a guid) }
function Ch.Shares()
  local list = RW.Characters()
  local s = { list = list, names = shortNames(list), gold = {}, played = {}, goldTotal = 0, playedTotal = 0,
    withGold = 0, withTime = 0 }
  for _, c in ipairs(list) do
    local gold, total, level = num(c.rec.gold), played(c.rec), num(c.rec.level)
    -- Unreadable: a secret value (never in a saved file, but never compared either) or NaN.
    if gold and (ns.IsSecret(gold) or gold ~= gold) then gold = nil end
    if total and (ns.IsSecret(total) or total ~= total) then total = nil end
    if level and (ns.IsSecret(level) or level ~= level) then level = nil end
    s.gold[c.guid], s.played[c.guid] = gold, total
    if gold and gold > 0 then
      s.goldTotal = s.goldTotal + gold
      s.withGold = s.withGold + 1
      s.richest = c.guid
    end
    if total and total > 0 then
      s.playedTotal = s.playedTotal + total
      s.withTime = s.withTime + 1
    end
    if level and (s.maxLevel == nil or level > s.maxLevel) then s.maxLevel = level end
  end
  if s.withGold ~= 1 then s.richest = nil end
  return s
end

-- A share of a total as a whole percent (0 when there is no total).
function Ch.Percent(part, total)
  if not part or not total or total <= 0 or part <= 0 then return 0 end
  return math.floor(part * 100 / total + 0.5)
end

-- The played cell's text: "1d 4h · 73%" when more than one character has time and the share rounds
-- to at least 1%; "1d 4h" otherwise; "pending" (/played hasn't answered) when there is none.
function Ch.PlayedText(total, s)
  if not total then return L["pending"] end
  local text = ns.Session.Duration(total)
  local pct = Ch.Percent(total, s.playedTotal)
  if s.withTime > 1 and pct >= 1 then return string.format(L["%s · %d%%"], text, pct) end
  return text
end

-- A bar of `part` of `total`; an empty one (max 1) when either is missing.
local function shareBar(part, total, color)
  local max = total and total > 0 and total or 1
  local value = part and part > 0 and part or 0
  return { value = math.min(value, max), max = max, r = color[1], g = color[2], b = color[3] }
end

local DETAIL_COLUMNS = {
  { title = "", width = 220 }, { title = "", width = 140 }, { title = "", width = 170, kind = "bar" },
  { title = "", width = 50, justify = "RIGHT" },
}

function Ch.AllRows(ctx)
  local rows = {}
  local s = Ch.Shares()
  for _, c in ipairs(s.list) do
    local rec = c.rec
    if RW.Match(c.name, ctx.search) then
      local gold, total = s.gold[c.guid], s.played[c.guid]
      local xp, xpMax = num(rec.xp), num(rec.xpMax)
      rows[#rows + 1] = {
        ref = c.guid, rec = rec, color = RW.ClassColor(rec.class),
        cells = { c.name, tostring(num(rec.level) or "?"), RW.Money(gold), Ch.PlayedText(total, s),
          Ch.ProfessionsText(rec), lastSeen(rec, ctx) },
        bars = { [2] = xp and xpMax and xpMax > 0 and { value = xp, max = xpMax } or nil,
          [3] = shareBar(gold, s.goldTotal, GOLD_BAR), [4] = shareBar(total, s.playedTotal, PLAYED_BAR) },
        sort = { c.name:lower(), num(rec.level) or 0, gold or 0, total or 0, nil,
          c.current and math.huge or (num(rec.lastSeen) or 0) },
      }
    end
  end
  return rows
end

-- The tiles over every character: Characters (and the highest level), Gold (and whose, when it is all
-- on one of several), Played (and across how many), and Last seen: the last time another character
-- was seen (the one you're on is "now"; with no other character, that is the tile).
function Ch.AllTiles(ctx)
  local s = Ch.Shares()
  local n = #s.list
  local gold = { label = L["Gold"], value = RW.Money(s.goldTotal) }
  if n > 1 and s.richest then gold.sub = string.format(L["all on %s"], s.names[s.richest]) end
  local playedTile = { label = L["Played"],
    value = s.withTime > 0 and ns.Session.Duration(s.playedTotal) or L["pending"] }
  if n > 1 and s.withTime > 1 then playedTile.sub = string.format(L["across %d characters"], s.withTime) end
  local last, lastAt
  for _, c in ipairs(s.list) do
    local at = num(c.rec.lastSeen)
    if c.guid ~= ctx.current and at and (lastAt == nil or at > lastAt) then last, lastAt = c, at end
  end
  local seen
  if last then
    seen = { label = L["Last seen"], value = ns.Status.Ago(lastAt) or L["never"], sub = s.names[last.guid] }
  else
    for _, c in ipairs(s.list) do
      if c.guid == ctx.current then seen = { label = L["Last seen"], value = L["now"], sub = s.names[c.guid] } end
    end
    seen = seen or { label = L["Last seen"], value = L["never"] }
  end
  return {
    { label = L["Characters"], value = tostring(n),
      sub = s.maxLevel and string.format(L["highest level %d"], s.maxLevel) or nil },
    gold, playedTile, seen,
  }
end

-- One character -----------------------------------------------------------------------------------------

function Ch.DetailRows(ctx)
  local rec = Wn.Record(ctx.character)
  local rows = {}
  if not rec then return rows end
  local groups = {}
  local function group(title)
    local g = { title = title, rows = {} }
    groups[#groups + 1] = g
    return g
  end
  local function line(g, row) g.rows[#g.rows + 1] = row end

  local about = group(L["Character"])
  line(about, { cells = { L["Class"], plain(RW.ClassName(rec.class) or "?") } })
  if type(rec.guild) == "table" and ns.NonEmpty(rec.guild.name) then
    line(about, { cells = { L["Guild"], plain(rec.guild.name) } })
  end
  if ns.NonEmpty(rec.zone) then
    local where = ns.NonEmpty(rec.subzone) and string.format(L["%s, %s"], plain(rec.zone), plain(rec.subzone))
      or plain(rec.zone)
    line(about, { cells = { L["Zone"], where } })
  end
  if ns.NonEmpty(rec.talents) then line(about, { cells = { L["Talents"], plain(rec.talents) } }) end

  local gear = group(L["Gear"])
  local items = {}
  for _, g in ipairs(type(rec.gear) == "table" and rec.gear or {}) do
    if type(g) == "table" then items[#items + 1] = g end
  end
  table.sort(items, function(a, b) return (num(a.slot) or 99) < (num(b.slot) or 99) end)
  for _, g in ipairs(items) do
    local link = ns.NonEmpty(g.link)
    line(gear, {
      icon = RW.ItemIcon(g.itemId), link = link, quality = g.quality,
      cells = { plain(Ch.LinkName(link) or string.format(L["item %s"], tostring(g.itemId))), Ch.SlotName(g.slot) },
    })
  end

  local profs = group(L["Professions"])
  for _, p in ipairs(type(rec.professions) == "table" and rec.professions or {}) do
    if type(p) == "table" and ns.NonEmpty(p.name) then
      local rank, max = num(p.rank) or 0, num(p.max) or 0
      line(profs, { cells = { plain(p.name), "", string.format(L["%s / %s"], rank, max) },
        bars = { [3] = { value = rank, max = max, r = 0.25, g = 0.5, b = 0.9 } } })
    end
  end

  local reps = group(L["Reputations"])
  for _, r in ipairs(type(rec.reputations) == "table" and rec.reputations or {}) do
    if type(r) == "table" and ns.NonEmpty(r.name) then
      local value, max = num(r.value), num(r.max)
      local red, green, blue = standingColor(r.standing)
      line(reps, { cells = { plain(r.name), Ch.StandingName(r.standing),
          value and max and string.format(L["%s / %s"], value, max) or "" },
        bars = { [3] = value and max and { value = value, max = max, r = red, g = green, b = blue } or nil } })
    end
  end

  for _, g in ipairs(groups) do
    local matched = {}
    for _, row in ipairs(g.rows) do
      if RW.Match(row.cells[1], ctx.search) or RW.Match(row.cells[2], ctx.search) then
        matched[#matched + 1] = row
      end
    end
    if #matched > 0 or ctx.search == "" then
      rows[#rows + 1] = { header = true, cells = { g.title } }
      if #matched == 0 then rows[#rows + 1] = { cells = { "|cff999999" .. L["None recorded yet."] .. "|r" } } end
      for _, row in ipairs(matched) do rows[#rows + 1] = row end
    end
  end
  return rows
end

-- One character's quests ----------------------------------------------------------------------------------

local QUESTS = "quests"
Ch.QUESTS = QUESTS

-- The progress bars' colours, as the mockup's: a muted violet, and a muted green for ready.
local QUEST_BAR = { 0.31, 0.29, 0.4 }
local READY_BAR = { 0.24, 0.42, 0.24 }

-- A number from the saved file, or nil when it isn't one (a string, NaN, a secret value).
local function readable(v)
  v = num(v)
  if v == nil or ns.IsSecret(v) or v ~= v then return nil end
  return v
end

-- A saved quest's objectives: how many are done and how many there are, or nil when none was saved
-- (a quest with nothing to count: talk to someone, or an entry with no objectives list).
function Ch.QuestProgress(q)
  local list = type(q) == "table" and type(q.objectives) == "table" and q.objectives or {}
  local done, total = 0, 0
  for _, o in ipairs(list) do
    if type(o) == "table" then
      total = total + 1
      if o.done == true then done = done + 1 end
    end
  end
  if total == 0 then return nil end
  return done, total
end

-- A quest row's progress: its text and its bar. "ready" on a full bar when every objective is done,
-- "1 / 3" over a third of one, and nothing (no bar) when it has no objectives to count.
function Ch.QuestBar(q)
  local done, total = Ch.QuestProgress(q)
  if not done then return "", nil, false end
  if done == total then
    return L["ready"], { value = total, max = total, r = READY_BAR[1], g = READY_BAR[2], b = READY_BAR[3] }, true
  end
  return string.format(L["%s / %s"], done, total),
    { value = done, max = total, r = QUEST_BAR[1], g = QUEST_BAR[2], b = QUEST_BAR[3] }, false
end

local function questTitle(q)
  local title = ns.NonEmpty(q.title)
  if title then return plain(title) end
  local id = readable(q.id)
  if id then return string.format(L["quest %s"], tostring(id)) end
  return L["Unknown quest"]
end

-- A character's saved quest log, grouped: { active, ready, groups = { { title, quests }, ... },
-- unrecorded = { quests } }, each quest { q, title, level, header, text, bar, ready }. Groups with the
-- most quests first, then by name; quests in the log's own order.
function Ch.QuestLog(rec)
  local log = { active = 0, ready = 0, groups = {}, unrecorded = {} }
  local quests = type(rec) == "table" and type(rec.quests) == "table" and rec.quests.active
  local byTitle = {}
  for _, q in ipairs(type(quests) == "table" and quests or {}) do
    if type(q) == "table" then
      local text, bar, ready = Ch.QuestBar(q)
      local level = readable(q.level)
      local header = ns.NonEmpty(q.header)
      local e = { q = q, title = questTitle(q), level = level and level > 0 and level or nil,
        header = header and plain(header) or nil, text = text, bar = bar, ready = ready }
      log.active = log.active + 1
      if ready then log.ready = log.ready + 1 end
      if e.header then
        local g = byTitle[e.header]
        if not g then
          g = { title = e.header, quests = {} }
          byTitle[e.header] = g
          log.groups[#log.groups + 1] = g
        end
        g.quests[#g.quests + 1] = e
      else
        log.unrecorded[#log.unrecorded + 1] = e
      end
    end
  end
  table.sort(log.groups, function(a, b)
    if #a.quests ~= #b.quests then return #a.quests > #b.quests end
    local x, y = a.title:lower(), b.title:lower()
    if x ~= y then return x < y end
    return a.title < b.title
  end)
  return log
end

-- The column heading's line: "14 active · 4 ready to turn in".
function Ch.QuestCounts(log)
  return string.format(L["%d active · %d ready to turn in"], log.active, log.ready)
end

function Ch.QuestColumns(ctx)
  local log = Ch.QuestLog(Wn.Record(ctx.character))
  return {
    { title = Ch.QuestCounts(log), width = 340, sort = false },
    { title = L["Level"], width = 50, justify = "RIGHT", sort = false },
    { title = L["Progress"], width = 170, kind = "bar", sort = false },
  }
end

function Ch.QuestRows(ctx)
  local rows = {}
  local rec = Wn.Record(ctx.character)
  if not rec then return rows end
  local log = Ch.QuestLog(rec)
  if log.active == 0 then
    rows[1] = { cells = { "|cff999999" .. L["No quests in this character's log."] .. "|r" } }
    return rows
  end
  local function add(title, list)
    local matched = {}
    for _, e in ipairs(list) do
      if RW.Match(e.title, ctx.search) or RW.Match(title, ctx.search) then matched[#matched + 1] = e end
    end
    if #matched == 0 then return end
    rows[#rows + 1] = { header = true, cells = { string.format(L["%s (%d)"], title, #matched) } }
    for _, e in ipairs(matched) do
      rows[#rows + 1] = { quest = e, cells = { e.title, e.level and tostring(e.level) or "", e.text },
        bars = { [3] = e.bar } }
    end
  end
  for _, g in ipairs(log.groups) do add(g.title, g.quests) end
  add(L["Picked up before this was recorded"], log.unrecorded)
  return rows
end

-- A quest row's tooltip: its title, level and heading, and each objective as saved, done ones dimmed.
function Ch.QuestTooltip(row, tip)
  local e = row.quest
  tip:AddLine(e.title, 1, 0.82, 0)
  if e.level then tip:AddLine(string.format(L["Level %s"], tostring(e.level)), 1, 1, 1) end
  if e.header then tip:AddLine(e.header, 0.8, 0.8, 0.8) end
  local any = false
  for i, o in ipairs(type(e.q.objectives) == "table" and e.q.objectives or {}) do
    if type(o) == "table" then
      if not any then tip:AddLine(" ") end
      any = true
      local text = ns.NonEmpty(o.text) and plain(o.text) or string.format(L["Objective %d"], i)
      if o.done == true then
        tip:AddLine(string.format(L["%s (done)"], text), 0.5, 0.75, 0.5, true)
      else
        tip:AddLine(text, 1, 1, 1, true)
      end
    end
  end
  if e.ready then
    tip:AddLine(" ")
    tip:AddLine(L["Every objective is done: ready to turn in."], 0.6, 0.6, 0.6, true)
  elseif not any then
    tip:AddLine(" ")
    tip:AddLine(L["No objectives to count were saved for this quest."], 0.6, 0.6, 0.6, true)
  end
end

-- The quests' footer: where the log came from and how old it is.
function Ch.QuestFooter(ctx)
  local rec = Wn.Record(ctx.character)
  if not rec then return "" end
  if ctx.character == ctx.current then
    return string.format(L["Counted in game for %s, the character you're on."], Wn.Name(rec))
  end
  return string.format(L["From your saved file, as %s last logged out, %s."], Wn.Name(rec),
    ns.Status.Ago(num(rec.lastSeen)) or L["an unknown time ago"])
end

-- Whether the context is one character's Quests.
local function onQuests(ctx)
  return ctx.character ~= nil and ctx.filter == QUESTS
end
Ch.OnQuests = onQuests

function Ch.DetailTiles(ctx)
  local rec = Wn.Record(ctx.character)
  if not rec then return nil end
  local total, atLevel = played(rec)
  return {
    { label = L["Level"], value = tostring(num(rec.level) or "?"), sub = RW.ClassName(rec.class) },
    { label = L["Gold"], value = RW.Money(rec.gold) },
    { label = L["Played"], value = total and ns.Session.Duration(total) or L["pending"],
      sub = atLevel and string.format(L["%s at this level"], ns.Session.Duration(atLevel)) or nil },
    { label = L["Last seen"], value = lastSeen(rec, ctx) },
  }
end

-- A character row's tooltip: what the row says, in full.
function Ch.Tooltip(row, tip, ctx)
  local rec = row.rec
  if not rec or row.cells == nil or row.link then return end
  tip:AddLine(row.color .. Wn.Name(rec) .. "|r")
  tip:AddLine(string.format(L["Level %s %s"], tostring(num(rec.level) or "?"), plain(RW.ClassName(rec.class) or "")),
    1, 1, 1)
  if type(rec.guild) == "table" and ns.NonEmpty(rec.guild.name) then
    tip:AddDoubleLine(L["Guild"], plain(rec.guild.name), 0.8, 0.8, 0.8, 1, 1, 1)
  end
  if ns.NonEmpty(rec.zone) then tip:AddDoubleLine(L["Zone"], plain(rec.zone), 0.8, 0.8, 0.8, 1, 1, 1) end
  tip:AddDoubleLine(L["Gold"], RW.Money(rec.gold), 0.8, 0.8, 0.8, 1, 1, 1)
  local total = played(rec)
  tip:AddDoubleLine(L["Played"], total and ns.Session.Duration(total) or L["pending"], 0.8, 0.8, 0.8, 1, 1, 1)
  for _, p in ipairs(type(rec.professions) == "table" and rec.professions or {}) do
    if type(p) == "table" and ns.NonEmpty(p.name) then
      tip:AddDoubleLine(plain(p.name), string.format(L["%s / %s"], tostring(num(p.rank) or "?"),
        tostring(num(p.max) or "?")), 0.8, 0.8, 0.8, 1, 1, 1)
    end
  end
  tip:AddDoubleLine(L["Last seen"], lastSeen(rec, ctx), 0.8, 0.8, 0.8, 1, 1, 1)
  tip:AddLine(" ")
  tip:AddLine(L["Click for this character's gear, professions and reputations."], 0.6, 0.6, 0.6, true)
end

function Ch.Footer(ctx)
  if ctx.character == nil then
    return L["From your saved file: each character as of its last logout; the one you're on is live."]
  end
  return Wn.RecordFooter(ctx)
end

-- The section's version: the session's (gold, experience, levels), the record's scans, and the
-- minute (time played and "last seen" move on).
function Ch.Version()
  return tostring(ns.Session.version) .. ":" .. tostring(ns.Character.version or 0) .. ":"
    .. tostring(ns.Quests and ns.Quests.version or 0) .. ":" .. math.floor(GetTime() / 60)
end

-- One character's views (the section's picker, shown only with one character picked): Character
-- (class, gear, professions, reputations) and Quests. A core before titles could follow the context
-- would print a function as the title, so the picker comes with the strip's core, as History's does.
local views = RW.STRIP_MAX ~= nil

if RW.AddSection({
  key = "characters", group = "me", order = 20, label = L["Characters"], icons = true,
  title = views and function(ctx)
    if onQuests(ctx) then
      return string.format(L["%s › %s"], Wn.Name(Wn.Record(ctx.character)), L["Quests"])
    end
    return L["Characters"]
  end or nil,
  filter = views and function(ctx)
    if ctx.character == nil then return {} end
    return { { value = nil, label = L["Character"] }, { value = QUESTS, label = L["Quests"] } }
  end or nil,
  columns = function(ctx)
    if ctx.character == nil then return ALL_COLUMNS end
    if onQuests(ctx) then return Ch.QuestColumns(ctx) end
    return DETAIL_COLUMNS
  end,
  sortable = true,
  rows = function(ctx)
    if ctx.character == nil then return Ch.AllRows(ctx) end
    if onQuests(ctx) then return Ch.QuestRows(ctx) end
    return Ch.DetailRows(ctx)
  end,
  tiles = function(ctx)
    if ctx.character == nil then return Ch.AllTiles(ctx) end
    if onQuests(ctx) then return nil end
    return Ch.DetailTiles(ctx)
  end,
  tooltip = function(row, tip, ctx)
    if row.quest then return Ch.QuestTooltip(row, tip) end
    return Ch.Tooltip(row, tip, ctx)
  end,
  click = function(row) if row.ref and row.rec then RW.Choose(row.ref) end end,
  footer = function(ctx)
    if onQuests(ctx) then return Ch.QuestFooter(ctx) end
    return Ch.Footer(ctx)
  end,
  version = Ch.Version,
}) then
  Wn.keys.characters = true
end
