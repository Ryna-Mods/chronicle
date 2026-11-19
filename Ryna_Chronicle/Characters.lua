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
-- One character's Talents, Spells and Stats (the detail's picker: Character, Talents, Spells, Stats,
-- Quests): the character sheet Sheet.lua records (docs/wow.md 19.1), each its own view of headed groups,
-- below at "One character's sheet".
--
-- One character's Quests (the detail's picker; 7.5, "The quest log by zone or
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

-- Headed groups of rows ({ { title, rows, empty }, ... }) as the section's rows: each group's heading,
-- then its rows that match the search (cells 1 and 2). A group with no rows shows its `empty` line
-- ("None recorded yet." by default) when nothing is searched for, and is left out when something is.
function Ch.GroupedRows(groups, ctx)
  local rows = {}
  for _, g in ipairs(groups) do
    local matched = {}
    for _, row in ipairs(g.rows) do
      if RW.Match(row.cells[1], ctx.search) or RW.Match(row.cells[2], ctx.search) then
        matched[#matched + 1] = row
      end
    end
    if #matched > 0 or ctx.search == "" then
      rows[#rows + 1] = { header = true, cells = { g.title } }
      if #matched == 0 then
        rows[#rows + 1] = { cells = { "|cff999999" .. (g.empty or L["None recorded yet."]) .. "|r" } }
      end
      for _, row in ipairs(matched) do rows[#rows + 1] = row end
    end
  end
  return rows
end

-- A list of groups and its two helpers: group(title) adds one, line(g, row) adds a row to it.
local function grouper()
  local groups = {}
  local function group(title)
    local g = { title = title, rows = {} }
    groups[#groups + 1] = g
    return g
  end
  local function line(g, row) g.rows[#g.rows + 1] = row end
  return groups, group, line
end

function Ch.DetailRows(ctx)
  local rec = Wn.Record(ctx.character)
  if not rec then return {} end
  local groups, group, line = grouper()

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

  return Ch.GroupedRows(groups, ctx)
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

-- One character's sheet: Talents, Spells and Stats ---------------------------------------------------------
--
-- Three more of the detail's views (the picker: Character, Talents, Spells, Stats, Quests), from the
-- character sheet on the record (Sheet.lua; docs/wow.md 19.1), for any character on the account. Each is
-- headed groups of rows like Character's, so a long list (a spellbook of 200 spells) is its own view and
-- never makes the Character page long.
--
-- Talents: each spec (the active one first; the other too once dual spec is bought and readable), each
-- tree headed by its points ("Discipline · 14 points"), then its taken talents by row and column with
-- their ranks over a bar ("Meditation", "2 / 3"). Before the sheet was recorded, the record's talent text.
-- Spells: the spellbook by tab, each spell's rank (its subtext, "Rank 2") and the level it was learned at;
-- then what the class trainer offered on the last visit that isn't learned yet, lowest level first, green
-- when it can be learned now and red when not, with its cost. Stats: health, power, the five attributes,
-- armour, resistances, attack and spell power, crit, avoidance and mana regen (read out of combat), then
-- skills with their ranks over a bar, currencies, and rested experience, the hearthstone, honourable kills
-- and the gear's durability.

local TALENTS, SPELLS, STATS = "talents", "spells", "stats"
Ch.TALENTS, Ch.SPELLS, Ch.STATS = TALENTS, SPELLS, STATS

local VIEW_LABELS = { [TALENTS] = L["Talents"], [SPELLS] = L["Spells"], [STATS] = L["Stats"], [QUESTS] = L["Quests"] }
Ch.VIEW_LABELS = VIEW_LABELS

local TALENT_BAR = { 0.55, 0.42, 0.15 }
local SKILL_BAR = { 0.25, 0.5, 0.9 }
local AVAILABLE, UNAVAILABLE = "|cff40c040", "|cffd05050"

local function list(v)
  return type(v) == "table" and v or {}
end

-- A number as text: whole numbers bare ("1,240" is left to the game: "1240"), others to two places with
-- trailing zeros dropped ("3.1"); "" for anything unreadable.
function Ch.NumText(v)
  v = readable(v)
  if not v then return "" end
  if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return string.format("%d", v) end
  local s = string.format("%.2f", v):gsub("(%.%d-)0+$", "%1"):gsub("%.$", "")
  return s
end
local numText = Ch.NumText

local function pct(v)
  local s = numText(v)
  if s == "" then return "" end
  return string.format(L["%s%%"], s)
end

local function bar(value, max, color)
  value, max = readable(value), readable(max)
  if not value or not max or max <= 0 then return nil end
  return { value = math.min(math.max(value, 0), max), max = max, r = color[1], g = color[2], b = color[3] }
end

-- Talents ------------------------------------------------------------------------------------------------

function Ch.TalentRows(ctx)
  local rec = Wn.Record(ctx.character)
  if not rec then return {} end
  local groups, group, line = grouper()
  local specs = type(rec.specs) == "table" and rec.specs or {}
  local specList = {}
  for _, spec in ipairs(list(specs.list)) do
    if type(spec) == "table" then specList[#specList + 1] = spec end
  end
  local active = readable(specs.active)
  for i, spec in ipairs(specList) do
    local g = readable(spec.group)
    local specTitle
    if #specList > 1 or (readable(specs.count) or 1) > 1 then
      if (active and g == active) or (not active and i == 1) then
        specTitle = string.format(L["Spec %s (active)"], numText(g or i))
      else
        specTitle = string.format(L["Spec %s"], numText(g or i))
      end
    end
    for _, tree in ipairs(list(spec.trees)) do
      if type(tree) == "table" and ns.NonEmpty(tree.name) then
        local title = string.format(L["%s · %s points"], plain(tree.name), numText(tree.points) ~= "" and
          numText(tree.points) or "0")
        if specTitle then title = string.format(L["%s · %s"], specTitle, title) end
        local tg = group(title)
        tg.empty = L["No talents taken."]
        for _, t in ipairs(list(tree.talents)) do
          local rank, max = type(t) == "table" and readable(t.rank), type(t) == "table" and readable(t.max)
          if rank and rank > 0 then
            local n = ns.NonEmpty(t.name) and plain(t.name)
              or string.format(L["spell %s"], numText(t.spellId) ~= "" and numText(t.spellId) or "?")
            line(tg, { talent = t, cells = { n, string.format(L["%s / %s"], numText(rank), numText(max or rank)) },
              bars = { [2] = bar(rank, max or rank, TALENT_BAR) } })
          end
        end
      end
    end
  end
  if #groups == 0 then
    local g = group(L["Talents"])
    if ns.NonEmpty(rec.talents) then
      line(g, { cells = { plain(rec.talents), "" } })
      local note = L["Each talent shows once this character logs in with this version of Chronicle."]
      line(g, { cells = { "|cff999999" .. note .. "|r", "" } })
    else
      g.empty = L["Not recorded yet: log in on this character to read its sheet."]
    end
  end
  return Ch.GroupedRows(groups, ctx)
end

local TALENT_COLUMNS = {
  { title = L["Talent"], width = 340, sort = false },
  { title = L["Rank"], width = 170, kind = "bar", sort = false },
}

-- Spells -----------------------------------------------------------------------------------------------

-- What the trainer offered that isn't learned yet: { service, ... }, lowest level first, then by name.
function Ch.TrainerNext(rec)
  local out = {}
  local trainer = type(rec) == "table" and type(rec.trainer) == "table" and rec.trainer or {}
  for _, sv in ipairs(list(trainer.services)) do
    if type(sv) == "table" and ns.NonEmpty(sv.name) and (sv.state == "available" or sv.state == "unavailable") then
      out[#out + 1] = sv
    end
  end
  table.sort(out, function(a, b)
    local la, lb = readable(a.level) or 0, readable(b.level) or 0
    if la ~= lb then return la < lb end
    return a.name < b.name
  end)
  return out
end

function Ch.SpellRows(ctx)
  local rec = Wn.Record(ctx.character)
  if not rec then return {} end
  local groups, group, line = grouper()
  local byTab = {}
  local spells = type(rec.spells) == "table" and rec.spells or {}
  for _, sp in ipairs(list(spells.list)) do
    if type(sp) == "table" and ns.NonEmpty(sp.name) then
      local tab = ns.NonEmpty(sp.tab) and plain(sp.tab) or L["Spells"]
      local g = byTab[tab]
      if not g then
        g = group(tab)
        byTab[tab] = g
      end
      local rankText = ns.NonEmpty(sp.sub) and plain(sp.sub) or (sp.passive == true and L["Passive"]) or ""
      local level = readable(sp.level)
      line(g, { spell = sp, cells = { plain(sp.name), rankText, level and numText(level) or "", "" } })
    end
  end
  for _, g in ipairs(groups) do g.title = string.format(L["%s (%d)"], g.title, #g.rows) end
  if #groups == 0 then
    group(L["Spells"]).empty = L["Not recorded yet: log in on this character to read its sheet."]
  end

  local trainer = type(rec.trainer) == "table" and rec.trainer or nil
  local nextUp = Ch.TrainerNext(rec)
  local title = L["At the trainer"]
  if trainer then
    local who = ns.NonEmpty(trainer.name) and plain(trainer.name) or L["the class trainer"]
    title = string.format(L["At the trainer: %s, %s"], who, ns.Status.Ago(num(trainer.at)) or L["an unknown time ago"])
  end
  local tg = group(title)
  tg.empty = trainer and L["Nothing left to learn there on that visit."]
    or L["Visit your class trainer to see what you can learn next."]
  for _, sv in ipairs(nextUp) do
    local level = readable(sv.level)
    line(tg, { service = sv, color = sv.state == "available" and AVAILABLE or UNAVAILABLE,
      cells = { plain(sv.name), ns.NonEmpty(sv.sub) and plain(sv.sub) or "", level and numText(level) or "",
        readable(sv.cost) and RW.Money(sv.cost) or "" } })
  end
  return Ch.GroupedRows(groups, ctx)
end

local SPELL_COLUMNS = {
  { title = L["Spell"], width = 250, sort = false },
  { title = L["Rank"], width = 120, sort = false },
  { title = L["Level"], width = 50, justify = "RIGHT", sort = false },
  { title = L["Cost"], width = 120, justify = "RIGHT", sort = false },
}

-- Stats ---------------------------------------------------------------------------------------------------

local ATTRIBUTES = {
  { "strength", N("Strength") }, { "agility", N("Agility") }, { "stamina", N("Stamina") },
  { "intellect", N("Intellect") }, { "spirit", N("Spirit") },
}
local SCHOOLS = {
  { "holy", N("Holy") }, { "fire", N("Fire") }, { "nature", N("Nature") }, { "frost", N("Frost") },
  { "shadow", N("Shadow") }, { "arcane", N("Arcane") },
}

-- The power's name in the client's language ("Mana", from its GlobalStrings), else "Power".
local function powerName(token)
  token = ns.NonEmpty(token)
  return token and ns.NonEmpty(_G[token]) or L["Power"]
end

-- Durability over every equipped item that has it: current, max, and the item with the least share.
function Ch.Durability(rec)
  local cur, max, worst, worstShare = 0, 0, nil, nil
  for _, g in ipairs(list(type(rec) == "table" and rec.gear)) do
    local d, m = type(g) == "table" and readable(g.dur), type(g) == "table" and readable(g.durMax)
    if d and m and m > 0 then
      cur, max = cur + d, max + m
      local share = d / m
      if worstShare == nil or share < worstShare then worst, worstShare = g, share end
    end
  end
  if max == 0 then return nil end
  return cur, max, worst
end

function Ch.StatRows(ctx)
  local rec = Wn.Record(ctx.character)
  if not rec then return {} end
  local groups, group, line = grouper()
  local function stat(g, label, value, extra)
    if value == nil or value == "" then return end
    line(g, { cells = { label, value, extra or "" } })
  end

  local st = type(rec.stats) == "table" and rec.stats or {}
  local sg = group(L["Stats"])
  sg.empty = L["Not recorded yet: stats are read out of combat, on this character."]
  stat(sg, L["Health"], numText(st.health))
  stat(sg, powerName(st.powerType), numText(st.power))
  local attrs = type(st.attributes) == "table" and st.attributes or {}
  for _, a in ipairs(ATTRIBUTES) do stat(sg, L[a[2]], numText(attrs[a[1]])) end
  stat(sg, L["Armor"], numText(st.armor))
  local res = type(st.resistances) == "table" and st.resistances or {}
  for _, school in ipairs(SCHOOLS) do
    stat(sg, string.format(L["%s resistance"], L[school[2]]), numText(res[school[1]]))
  end
  stat(sg, L["Attack power"], numText(st.attackPower))
  stat(sg, L["Ranged attack power"], numText(st.rangedAttackPower))
  local sp = type(st.spellPower) == "table" and st.spellPower or {}
  for _, school in ipairs(SCHOOLS) do
    stat(sg, string.format(L["%s spell damage"], L[school[2]]), numText(sp[school[1]]))
  end
  stat(sg, L["Healing"], numText(st.healing))
  local crit = type(st.crit) == "table" and st.crit or {}
  stat(sg, L["Melee crit"], pct(crit.melee))
  stat(sg, L["Ranged crit"], pct(crit.ranged))
  stat(sg, L["Spell crit"], pct(crit.spell))
  stat(sg, L["Dodge"], pct(st.dodge))
  stat(sg, L["Parry"], pct(st.parry))
  stat(sg, L["Block"], pct(st.block))
  local regen = type(st.manaRegen) == "table" and st.manaRegen or {}
  local function perFive(v)
    local text = numText(v)
    return text ~= "" and string.format(L["%s per 5 s"], text) or ""
  end
  stat(sg, L["Mana regen (casting)"], perFive(regen.casting))
  stat(sg, L["Mana regen (not casting)"], perFive(regen.idle))

  local kg = group(L["Skills"])
  for _, sk in ipairs(list(rec.skills)) do
    if type(sk) == "table" and ns.NonEmpty(sk.name) then
      local rank, max = readable(sk.rank), readable(sk.max)
      line(kg, { cells = { plain(sk.name), ns.NonEmpty(sk.group) and plain(sk.group) or "",
          rank and string.format(L["%s / %s"], numText(rank), max and numText(max) or "?") or "" },
        bars = { [3] = bar(rank, max, SKILL_BAR) } })
    end
  end

  local cg = group(L["Currencies"])
  for _, c in ipairs(list(rec.currencies)) do
    if type(c) == "table" and ns.NonEmpty(c.name) then
      local q, max = readable(c.quantity), readable(c.max)
      local text = ""
      if q and max and max > 0 then
        text = string.format(L["%s / %s"], numText(q), numText(max))
      elseif q then
        text = numText(q)
      end
      line(cg, { cells = { plain(c.name), ns.NonEmpty(c.group) and plain(c.group) or "", text },
        bars = { [3] = (max and max > 0) and bar(q, max, SKILL_BAR) or nil } })
    end
  end

  local og = group(L["Other"])
  local rested = readable(rec.restedXp)
  if rested then stat(og, L["Rested experience"], rested > 0 and numText(rested) or L["none"]) end
  if ns.NonEmpty(rec.hearth) then stat(og, L["Hearthstone"], plain(rec.hearth)) end
  local hk = type(rec.pvp) == "table" and readable(rec.pvp.honorableKills)
  if hk then stat(og, L["Honorable kills"], numText(hk)) end
  local cur, max, worst = Ch.Durability(rec)
  if cur then
    local worstText = worst and (Ch.LinkName(ns.NonEmpty(worst.link)) or Ch.SlotName(worst.slot)) or ""
    line(og, { cells = { L["Durability"], worstText ~= "" and string.format(L["lowest: %s"], plain(worstText)) or "",
        pct(math.floor(cur * 100 / max + 0.5)) }, bars = { [3] = bar(cur, max, SKILL_BAR) } })
  end
  return Ch.GroupedRows(groups, ctx)
end

local STAT_COLUMNS = {
  { title = "", width = 220, sort = false }, { title = "", width = 160, sort = false },
  { title = "", width = 170, kind = "bar", sort = false },
}

-- The view the context is on: QUESTS, TALENTS, SPELLS, STATS, or nil (Character, or All characters).
local function view(ctx)
  if ctx.character == nil then return nil end
  if VIEW_LABELS[ctx.filter] then return ctx.filter end
  return nil
end
Ch.View = view

local SHEET_VIEWS = {
  [TALENTS] = { rows = Ch.TalentRows, columns = TALENT_COLUMNS },
  [SPELLS] = { rows = Ch.SpellRows, columns = SPELL_COLUMNS },
  [STATS] = { rows = Ch.StatRows, columns = STAT_COLUMNS },
}
Ch.SHEET_VIEWS = SHEET_VIEWS

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
-- (class, gear, professions, reputations), Talents, Spells, Stats and Quests. A core before titles could
-- follow the context would print a function as the title, so the picker comes with the strip's core, as
-- History's does.
local views = RW.STRIP_MAX ~= nil

if RW.AddSection({
  key = "characters", group = "me", order = 20, label = L["Characters"], icons = true,
  title = views and function(ctx)
    local v = view(ctx)
    if v then
      return string.format(L["%s › %s"], Wn.Name(Wn.Record(ctx.character)), VIEW_LABELS[v])
    end
    return L["Characters"]
  end or nil,
  filter = views and function(ctx)
    if ctx.character == nil then return {} end
    return { { value = nil, label = L["Character"] }, { value = TALENTS, label = L["Talents"] },
      { value = SPELLS, label = L["Spells"] }, { value = STATS, label = L["Stats"] },
      { value = QUESTS, label = L["Quests"] } }
  end or nil,
  columns = function(ctx)
    if ctx.character == nil then return ALL_COLUMNS end
    local v = view(ctx)
    if v == QUESTS then return Ch.QuestColumns(ctx) end
    if SHEET_VIEWS[v] then return SHEET_VIEWS[v].columns end
    return DETAIL_COLUMNS
  end,
  sortable = true,
  rows = function(ctx)
    if ctx.character == nil then return Ch.AllRows(ctx) end
    local v = view(ctx)
    if v == QUESTS then return Ch.QuestRows(ctx) end
    if SHEET_VIEWS[v] then return SHEET_VIEWS[v].rows(ctx) end
    return Ch.DetailRows(ctx)
  end,
  tiles = function(ctx)
    if ctx.character == nil then return Ch.AllTiles(ctx) end
    if view(ctx) then return nil end
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
