-- Window: Chronicle's sections of Ryna's window (the core's Ryna.Window, Window.lua there), under
-- Me. /chronicle, /ryna chronicle, a click on the session strip (Strip.lua) and the button on the
-- Recording tab open the window on Session.
--
--   Session     this session's numbers (Session.lua) as tiles and rows, then its kills by creature
--   Characters  Characters.lua
--   Items       Items.lua
--   Kills       a character's lifetime `kills`, most first; a row's tooltip lists that creature's
--               zones and drops (from loot[*].from["c:<id>"] over kills[id].looted)
--   Loot        a character's lifetime `loot`, newest first, in the item's quality colour, with
--               where it came from
--   Zones       one row per zone the character has been in: kills, creatures, drops, pieces (the
--               tallies' `zones` and `logZones`), quests done, deaths and time spent (`places`,
--               Places.lua), then "Earlier travels"; a row opens Kills on that zone
--
-- Kills and Loot have a zone picker (the core's section filter, 7.6): All zones, This zone, each
-- zone the character has counts in, then Earlier travels (what was counted before Ryna kept zones).
-- With a zone picked the numbers and the tiles are that zone's.
--   History     two views, by the section's picker. Levels: the journal's `level` events for a
--               character, oldest first, with the time played at each level. Play: when the
--               character played, from the journal's sessions (Play.lua): tiles (this week, the last 30
--               days, the busiest weekday and hour, the longest sitting), a row per day, newest first,
--               with a bar of the time played and the sessions that day, then "When you play, by hour":
--               a row per weekday, Monday first, of 24 blocks whose brightness is that hour's share of
--               the busiest weekday-hour (the window's strip), and a row labelling the hours under them
--
-- Kills, Loot and History are one character's: the one the picker names, the one you're on when it
-- says All characters. Session is the one you're on. Rows are built light (ids and sort keys) and
-- their text is filled only for the rows on screen, so 2,000 creatures cost what 20 do. The window
-- redraws when Session.lua says something changed (at most every half second) and only while it is
-- shown; a section's rows are rebuilt only when its data's version changed.
--
-- With a core older than the window (0.3.9 and before have no Ryna.Window), none of this registers:
-- /chronicle says the core is too old, the strip's click does nothing, and the Recording tab's
-- button isn't there. Everything else in Chronicle works as before.

local _, ns = ...
if ns.off then return end
local L = ns.L
local N = ns.N

local Wn = {}
ns.Window = Wn

local RW = ns.API.Window
Wn.available = type(RW) == "table" and type(RW.AddSection) == "function"
Wn.keys = {} -- the sections Chronicle registered, by key

local MAX_DROPS = 12
local Ch = ns.Chronicle

-- The zone picker's own values (zone names are the rest; none starts with "@").
local HERE, EARLIER = "@here", "@earlier"
Wn.HERE, Wn.EARLIER = HERE, EARLIER

local function num(v)
  if type(v) == "number" then return v end
  return tonumber(v) or 0
end

local function plain(s)
  return ns.Status.Plain(s) or s
end

local function when(t)
  if type(t) ~= "number" then return "" end
  return date("%Y-%m-%d %H:%M", t)
end

-- A character's record from the saved file (the one you're on is ns.rec, the same table).
function Wn.Record(guid)
  local db = ns.db
  local chars = db and db.characters
  local rec = type(chars) == "table" and guid ~= nil and chars[guid] or nil
  if type(rec) == "table" then return rec end
  return nil
end

local function recMap(rec, name)
  local m = type(rec) == "table" and rec[name]
  if type(m) == "table" then return m end
  return nil
end

-- A character's name as the window shows it.
function Wn.Name(rec)
  return plain(type(rec) == "table" and ns.NonEmpty(rec.fullName) or nil) or L["Unknown character"]
end

-- Where a character's own numbers come from, for a footer: live for the one you're on, else the
-- saved file as of its last logout.
function Wn.RecordFooter(ctx)
  local rec = Wn.Record(ctx.character)
  if not rec then return "" end
  if ctx.character == ctx.current then
    return string.format(L["Counted in game for %s, the character you're on."], Wn.Name(rec))
  end
  return string.format(L["From your saved file: %s as of %s, its last logout."], Wn.Name(rec),
    ns.Status.Ago(rec.lastSeen) or L["an unknown time"])
end

-- A loot source key as the Loot section names it: the creature's name, "object", "container", "fishing".
function Wn.SourceName(key, rec)
  if key == "f" then return L["fishing"] end
  local kind, id = tostring(key):match("^(%a):?(%d*)$")
  if kind == "c" then
    local kills = recMap(rec, "kills")
    local e = kills and kills[id]
    return (type(e) == "table" and ns.NonEmpty(e.name)) or string.format(L["creature %s"], id)
  elseif kind == "o" then
    return L["object"]
  elseif kind == "i" then
    return L["container"]
  end
  return tostring(key)
end

-- An entry's sources, most first: "Kobold Vermin, object".
local function sourcesText(from, max, rec)
  if type(from) ~= "table" then return "" end
  local best = {}
  for k, v in pairs(from) do
    local n = num(v)
    local pos = #best + 1
    while pos > 1 and num(from[best[pos - 1]]) < n do pos = pos - 1 end
    if pos <= max then
      table.insert(best, pos, k)
      best[max + 1] = nil
    end
  end
  for i, k in ipairs(best) do best[i] = plain(Wn.SourceName(k, rec)) end
  return table.concat(best, ", ")
end

-- Creature `id`'s drops from a record: { name, quality, n } most first, at most MAX_DROPS.
function Wn.Drops(id, rec)
  local list = {}
  local loot = recMap(rec, "loot")
  if not loot then return list end
  local key = "c:" .. tostring(id)
  for _, e in pairs(loot) do
    local n = type(e) == "table" and type(e.from) == "table" and num(e.from[key]) or 0
    if n > 0 then
      local pos = #list + 1
      while pos > 1 and list[pos - 1].n < n do pos = pos - 1 end
      if pos <= MAX_DROPS then
        table.insert(list, pos, { name = ns.NonEmpty(e.name) or "?", quality = e.quality, n = n })
        list[MAX_DROPS + 1] = nil
      end
    end
  end
  return list
end

-- An entry's zones, most first: { { zone, n, qty, fromLogs } }.
local function zonesOf(e)
  local list = {}
  for zone, n in pairs(Ch.Zones(e)) do
    local _, qty, fromLogs = Ch.InZone(e, zone)
    local pos = #list + 1
    while pos > 1 and list[pos - 1].n < n do pos = pos - 1 end
    table.insert(list, pos, { zone = zone, n = n, qty = qty, fromLogs = fromLogs })
  end
  return list
end
Wn.ZonesOf = zonesOf

-- "Earlier travels" explained: before Ryna kept zones, and once the entry hit the cap, in other zones.
function Wn.EarlierNote(capped)
  if capped then return L["counted before Ryna kept zones, or in other zones"] end
  return L["counted before Ryna kept zones"]
end

-- An entry's "By zone" lines under its tooltip; `pieces` for loot (drops and pieces per zone).
local function zoneLines(tip, e, pieces)
  local list = zonesOf(e)
  if #list == 0 then return end
  local S = ns.Session
  tip:AddLine(" ")
  tip:AddLine(L["By zone"])
  for _, z in ipairs(list) do
    local value = S.Number(z.n)
    if pieces then
      value = string.format(L["%s (%s pieces)"], value, S.Number(z.qty or 0))
    elseif z.fromLogs > 0 then
      value = string.format(L["%s (%s placed from your combat logs)"], value, S.Number(z.fromLogs))
    end
    tip:AddDoubleLine(plain(z.zone), value, 0.8, 0.8, 0.8, 1, 1, 1)
  end
  local n, qty = Ch.Earlier(e)
  if n > 0 then
    tip:AddDoubleLine(L["Earlier travels"], pieces and string.format(L["%s (%s pieces)"], S.Number(n),
      S.Number(qty)) or S.Number(n), 0.8, 0.8, 0.8, 1, 1, 1)
    tip:AddLine(Wn.EarlierNote(Ch.Capped(e)), 0.6, 0.6, 0.6, true)
  end
end

-- What a creature's tooltip says: its numbers, its zones, then its drops with how often.
function Wn.CreatureTooltip(tip, id, rec)
  local kills = recMap(rec, "kills")
  local e = kills and kills[id]
  if type(e) ~= "table" then return end
  local S = ns.Session
  tip:AddLine(plain(ns.NonEmpty(e.name) or string.format(L["creature %s"], id)))
  tip:AddDoubleLine(L["Killed"], string.format(L["%s (%s yours)"], S.Number(e.n), S.Number(e.own)),
    0.8, 0.8, 0.8, 1, 1, 1)
  tip:AddDoubleLine(L["Experience"], S.Number(e.xp), 0.8, 0.8, 0.8, 1, 1, 1)
  if ns.NonEmpty(e.zone) then
    tip:AddDoubleLine(L["Last"], string.format(L["%s, %s"], plain(e.zone), ns.Status.Ago(e.last) or "?"),
      0.8, 0.8, 0.8, 1, 1, 1)
  end
  local looted = num(e.looted)
  tip:AddDoubleLine(L["Corpses looted"], S.Number(looted), 0.8, 0.8, 0.8, 1, 1, 1)
  zoneLines(tip, e, false)
  if looted <= 0 then return end
  local drops = Wn.Drops(id, rec)
  if #drops == 0 then return end
  tip:AddLine(" ")
  tip:AddLine(L["Drops"])
  for _, d in ipairs(drops) do
    tip:AddDoubleLine(RW.QualityColor(d.quality) .. plain(d.name) .. "|r",
      string.format(L["%d of %d (%d%%)"], d.n, looted, math.floor(d.n * 100 / looted + 0.5)),
      1, 1, 1, 1, 1, 1)
  end
end

-- An item's sources under its own tooltip (the core drew the game's tooltip from the link).
function Wn.ItemTooltip(tip, id, rec, hadLink)
  local loot = recMap(rec, "loot")
  local e = loot and loot[id]
  if type(e) ~= "table" then return end
  if not hadLink then
    tip:AddLine(RW.QualityColor(e.quality) .. plain(ns.NonEmpty(e.name) or string.format(L["item %s"], id)) .. "|r")
  end
  tip:AddLine(" ")
  tip:AddLine(string.format(L["From: %s"], sourcesText(e.from, 8, rec)), 0.8, 0.8, 0.8, true)
  zoneLines(tip, e, true)
end

-- The sections ------------------------------------------------------------------------------------

local function add(spec)
  if RW.AddSection(spec) then Wn.keys[spec.key] = true end
end

-- Session ------------------------------------------------------------------------------------------

local function sessionTiles()
  local s = ns.Session.Get()
  if not s then return nil end
  local S = ns.Session
  return {
    { label = L["Kills"], value = S.Number(s.kills), sub = string.format(L["%s/h"], S.Number(s.killsPerHour)) },
    { label = L["Experience"], value = S.Number(s.xp), sub = string.format(L["%s/h"], S.Number(s.xpPerHour)) },
    { label = L["Money"], value = S.Money(s.gold), sub = string.format(L["%s/h"], S.Money(s.goldPerHour)) },
    { label = L["Since"], value = date("%H:%M", s.startAt), sub = S.Duration(s.elapsed) },
  }
end

local function sessionRows()
  local rows = {}
  local s = ns.Session.Get()
  if not s then return rows end
  local S = ns.Session
  local function stat(label, value) rows[#rows + 1] = { cells = { label, value, "" } } end
  stat(L["Levels gained"], S.Number(s.levels))
  stat(L["Gained / spent"], string.format(L["%s / %s"], S.Money(s.goldGained), S.Money(s.goldSpent)))
  stat(L["Quests turned in"], S.Number(s.quests))
  stat(L["Items looted"], S.Number(s.items))
  stat(L["Deaths"], S.Number(s.deaths))
  rows[#rows + 1] = { header = true, cells = { L["Kills this session"], L["Kills"], L["Experience"] } }
  for _, k in ipairs(s.creatures) do
    rows[#rows + 1] = { ref = k.id or false, cells = { plain(k.name) or "?", S.Number(k.n), S.Number(k.xp) } }
  end
  return rows
end

-- The zone picker ------------------------------------------------------------------------------------

-- The zone the player is in now ("This zone"), from the record of the character you're on.
local function hereZone()
  local zone = ns.rec and ns.NonEmpty(ns.rec.zone)
  if zone and not ns.IsSecret(zone) then return zone end
  return nil
end

-- The zone a picker value means: a zone name, EARLIER, or nil for all zones.
local function pickedZone(value)
  if value == HERE then return hereZone() or false end
  return value
end
Wn.PickedZone = pickedZone

-- Entry `e`'s numbers for a picker value: n, loot's qty, and the part of n placed from logs.
local function inPick(e, value)
  local zone = pickedZone(value)
  if zone == nil then return num(e.n), num(e.qty), 0 end
  if zone == false then return 0, 0, 0 end
  if zone == EARLIER then
    local n, qty = Ch.Earlier(e)
    return n, qty, 0
  end
  local n, qty, fromLogs = Ch.InZone(e, zone)
  return n, qty or 0, fromLogs
end
Wn.InPick = inPick

-- The picker's choices for a map ("kills" or "loot") of the character in ctx: All zones, This zone,
-- the zones with counts (most first), and Earlier travels when anything is left from before.
local function zoneChoices(ctx, name)
  local here = hereZone()
  local out = {
    { value = nil, label = L["All zones"] },
    { value = HERE, label = here and string.format(L["This zone (%s)"], plain(here)) or L["This zone"] },
  }
  local m = recMap(Wn.Record(ctx.character), name)
  if not m then return out end
  local totals, earlier = {}, 0
  for _, e in pairs(m) do
    if type(e) == "table" then
      for zone, n in pairs(Ch.Zones(e)) do totals[zone] = (totals[zone] or 0) + n end
      earlier = earlier + (Ch.Earlier(e))
    end
  end
  local zones = {}
  for zone in pairs(totals) do zones[#zones + 1] = zone end
  table.sort(zones, function(a, b)
    if totals[a] ~= totals[b] then return totals[a] > totals[b] end
    return a < b
  end)
  for _, zone in ipairs(zones) do out[#out + 1] = { value = zone, label = plain(zone) } end
  if earlier > 0 then out[#out + 1] = { value = EARLIER, label = L["Earlier travels"] } end
  return out
end

-- The footer with a zone picked: since when zones are counted.
local function zoneFooter(ctx)
  local base = Wn.RecordFooter(ctx)
  if ctx.filter == nil then return base end
  if ctx.filter == EARLIER then
    return L["Earlier travels: counted before Ryna kept zones, or in zones past the eight it keeps."]
  end
  local rec = Wn.Record(ctx.character)
  local since = rec and type(rec.zonesSince) == "number" and when(rec.zonesSince) or L["not yet"]
  return string.format(L["Counted by zone since %s."], since) .. " " .. base
end

-- Kills ----------------------------------------------------------------------------------------------

local killsTotals = {}

local function killsRows(ctx)
  local rows = {}
  local rec = Wn.Record(ctx.character)
  local kills = recMap(rec, "kills")
  killsTotals.rec, killsTotals.filter = rec, ctx.filter
  killsTotals.creatures, killsTotals.n, killsTotals.xp, killsTotals.fromLogs = 0, 0, 0, 0
  if not kills then return rows end
  local all = ctx.filter == nil
  for id, e in pairs(kills) do
    local n, _, fromLogs = 0, nil, 0
    if type(e) == "table" then n, _, fromLogs = inPick(e, ctx.filter) end
    if n > 0 then
      killsTotals.creatures = killsTotals.creatures + 1
      killsTotals.n = killsTotals.n + n
      killsTotals.xp = killsTotals.xp + num(e.xp)
      killsTotals.fromLogs = killsTotals.fromLogs + fromLogs
      local name = ns.NonEmpty(e.name) or string.format(L["creature %s"], id)
      if RW.Match(name, ctx.search) then
        rows[#rows + 1] = { ref = id, rec = rec, e = e, n = n, all = all,
          sort = { name:lower(), n, all and num(e.xp) or num(e.n), (ns.NonEmpty(e.zone) or ""):lower(),
            num(e.last) } }
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.sort[2] ~= b.sort[2] then return a.sort[2] > b.sort[2] end
    return a.ref < b.ref
  end)
  return rows
end

local function killsFill(row)
  local e = row.e
  row.cells = {
    plain(ns.NonEmpty(e.name) or string.format(L["creature %s"], row.ref)), ns.Session.Number(row.n),
    ns.Session.Number(row.all and e.xp or e.n), plain(ns.NonEmpty(e.zone) or ""), ns.Status.Ago(e.last) or "",
  }
end

-- The columns: with a zone picked, Experience (not kept per zone) gives way to the kills in all zones.
-- (Two tables made once, so the window lays its columns out again only when the kind changes.)
local function killsColumnsFor(third)
  return { { title = L["Creature"], width = 210 }, { title = L["Kills"], width = 60, justify = "RIGHT" },
    { title = third, width = 80, justify = "RIGHT" },
    { title = L["Last zone"], width = 150 }, { title = L["Last"], width = 110, justify = "RIGHT" } }
end
local killsColumnsAll, killsColumnsZone = killsColumnsFor(L["Experience"]), killsColumnsFor(L["In all"])
local function killsColumns(ctx)
  if ctx.filter == nil then return killsColumnsAll end
  return killsColumnsZone
end

local function killsTiles(ctx)
  if killsTotals.rec ~= Wn.Record(ctx.character) or killsTotals.filter ~= ctx.filter then return nil end
  local S = ns.Session
  local tiles = {
    { label = L["Creatures"], value = S.Number(killsTotals.creatures) },
    { label = L["Kills"], value = S.Number(killsTotals.n) },
  }
  if ctx.filter == nil then
    tiles[3] = { label = L["Experience"], value = S.Number(killsTotals.xp) }
  elseif killsTotals.fromLogs > 0 then
    tiles[3] = { label = L["From your combat logs"], value = S.Number(killsTotals.fromLogs) }
  end
  return tiles
end

-- Loot ------------------------------------------------------------------------------------------------

local lootTotals = {}

local function lootRows(ctx)
  local rows = {}
  local rec = Wn.Record(ctx.character)
  local loot = recMap(rec, "loot")
  lootTotals.rec, lootTotals.filter, lootTotals.items, lootTotals.n, lootTotals.qty = rec, ctx.filter, 0, 0, 0
  if not loot then return rows end
  for id, e in pairs(loot) do
    local n, qty = 0, 0
    if type(e) == "table" then n, qty = inPick(e, ctx.filter) end
    if n > 0 then
      lootTotals.items = lootTotals.items + 1
      lootTotals.n = lootTotals.n + n
      lootTotals.qty = lootTotals.qty + qty
      local name = ns.NonEmpty(e.name) or string.format(L["item %s"], id)
      if RW.Match(name, ctx.search) then
        rows[#rows + 1] = { ref = id, rec = rec, e = e, n = n, qty = qty, quality = e.quality,
          link = ns.NonEmpty(e.link), sort = { name:lower(), n, qty, nil, num(e.last) } }
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.sort[5] ~= b.sort[5] then return a.sort[5] > b.sort[5] end
    return a.ref < b.ref
  end)
  return rows
end

local function lootFill(row)
  local e = row.e
  row.icon = RW.ItemIcon(row.ref)
  row.cells = {
    plain(ns.NonEmpty(e.name) or string.format(L["item %s"], row.ref)), ns.Session.Number(row.n),
    ns.Session.Number(row.qty), sourcesText(e.from, 2, row.rec), ns.Status.Ago(e.last) or "",
  }
end

local function lootTiles(ctx)
  if lootTotals.rec ~= Wn.Record(ctx.character) or lootTotals.filter ~= ctx.filter then return nil end
  local S = ns.Session
  return {
    { label = L["Items"], value = S.Number(lootTotals.items) },
    { label = L["Looted"], value = S.Number(lootTotals.n) },
    { label = L["Count"], value = S.Number(lootTotals.qty) },
  }
end

-- Zones ------------------------------------------------------------------------------------------------

local zonesTotals = {}

local function zoneRow(byZone, zone)
  local z = byZone[zone]
  if not z then
    z = { zone = zone, kills = 0, creatures = 0, drops = 0, pieces = 0, quests = 0, deaths = 0, seconds = 0 }
    byZone[zone] = z
  end
  return z
end

-- One row per zone: the tallies' zones summed, and `places` (the stay under way added for the
-- character you're on). "Earlier travels" last, for what no zone holds.
local function zonesRows(ctx)
  local rows = {}
  local rec = Wn.Record(ctx.character)
  zonesTotals.rec, zonesTotals.zones, zonesTotals.seconds, zonesTotals.quests, zonesTotals.deaths =
    rec, 0, 0, 0, 0
  if not rec then return rows end
  local byZone = {}
  local earlier = { kills = 0, creatures = 0, drops = 0, pieces = 0, capped = false }
  for _, e in pairs(recMap(rec, "kills") or {}) do
    if type(e) == "table" then
      for zone, n in pairs(Ch.Zones(e)) do
        local z = zoneRow(byZone, zone)
        z.kills, z.creatures = z.kills + n, z.creatures + 1
      end
      local n = Ch.Earlier(e)
      if n > 0 then
        earlier.kills, earlier.creatures = earlier.kills + n, earlier.creatures + 1
        earlier.capped = earlier.capped or Ch.Capped(e)
      end
    end
  end
  for _, e in pairs(recMap(rec, "loot") or {}) do
    if type(e) == "table" then
      for zone in pairs(Ch.Zones(e)) do
        local n, qty = Ch.InZone(e, zone)
        local z = zoneRow(byZone, zone)
        z.drops, z.pieces = z.drops + n, z.pieces + (qty or 0)
      end
      local n, qty = Ch.Earlier(e)
      if n > 0 then
        earlier.drops, earlier.pieces = earlier.drops + n, earlier.pieces + qty
        earlier.capped = earlier.capped or Ch.Capped(e)
      end
    end
  end
  for zone, p in pairs(recMap(rec, "places") or {}) do
    if type(p) == "table" then
      local z = zoneRow(byZone, zone)
      z.quests, z.deaths, z.seconds = num(p.quests), num(p.deaths), num(p.seconds)
      z.first, z.last = p.first, p.last
    end
  end
  if rec == ns.rec and ns.Places then
    local zone, extra = ns.Places.Current()
    if zone and extra > 0 then
      local z = zoneRow(byZone, zone)
      z.seconds = z.seconds + extra
    end
  end
  for zone, z in pairs(byZone) do
    zonesTotals.zones = zonesTotals.zones + 1
    zonesTotals.seconds = zonesTotals.seconds + z.seconds
    zonesTotals.quests = zonesTotals.quests + z.quests
    zonesTotals.deaths = zonesTotals.deaths + z.deaths
    if RW.Match(zone, ctx.search) then
      rows[#rows + 1] = { ref = zone, z = z,
        cells = { plain(zone), ns.Session.Number(z.kills), ns.Session.Number(z.creatures),
          ns.Session.Number(z.drops), ns.Session.Number(z.pieces), ns.Session.Number(z.quests),
          ns.Session.Number(z.deaths), z.seconds > 0 and ns.Session.Duration(z.seconds) or "" },
        sort = { zone:lower(), z.kills, z.creatures, z.drops, z.pieces, z.quests, z.deaths, z.seconds } }
    end
  end
  table.sort(rows, function(a, b)
    if a.z.seconds ~= b.z.seconds then return a.z.seconds > b.z.seconds end
    if a.z.kills ~= b.z.kills then return a.z.kills > b.z.kills end
    return a.ref < b.ref
  end)
  if (earlier.kills > 0 or earlier.drops > 0) and RW.Match(L["Earlier travels"], ctx.search) then
    rows[#rows + 1] = { ref = EARLIER, earlier = earlier,
      cells = { L["Earlier travels"], ns.Session.Number(earlier.kills), ns.Session.Number(earlier.creatures),
        ns.Session.Number(earlier.drops), ns.Session.Number(earlier.pieces), "", "", "" },
      sort = { nil, earlier.kills, earlier.creatures, earlier.drops, earlier.pieces } }
  end
  return rows
end

local function zonesTiles(ctx)
  if zonesTotals.rec ~= Wn.Record(ctx.character) then return nil end
  local S = ns.Session
  return {
    { label = L["Zones"], value = S.Number(zonesTotals.zones) },
    { label = L["Time spent"], value = S.Duration(zonesTotals.seconds) },
    { label = L["Quests done"], value = S.Number(zonesTotals.quests) },
    { label = L["Deaths"], value = S.Number(zonesTotals.deaths) },
  }
end

local function zonesTooltip(row, tip)
  if row.earlier then
    tip:AddLine(L["Earlier travels"])
    tip:AddLine(Wn.EarlierNote(row.earlier.capped), 0.8, 0.8, 0.8, true)
  else
    tip:AddLine(plain(row.ref))
    local z = row.z
    if type(z.first) == "number" then
      tip:AddDoubleLine(L["First here"], when(z.first), 0.8, 0.8, 0.8, 1, 1, 1)
    end
    if type(z.last) == "number" then
      tip:AddDoubleLine(L["Last here"], ns.Status.Ago(z.last) or "?", 0.8, 0.8, 0.8, 1, 1, 1)
    end
  end
  tip:AddLine(L["Click to see its kills."], 0.6, 0.6, 0.6)
end

-- A row opens Kills on its zone (Earlier travels on Earlier travels).
local function zonesClick(row)
  if not row.ref or not RW.SetFilter then return end
  RW.SetFilter("kills", row.ref)
  RW.Open("kills")
end

local function zonesFooter(ctx)
  local rec = Wn.Record(ctx.character)
  if not rec then return "" end
  local places = type(rec.placesSince) == "number" and when(rec.placesSince) or L["not yet"]
  local zones = type(rec.zonesSince) == "number" and when(rec.zonesSince) or L["not yet"]
  return string.format(L["Time, quests and deaths since %s; kills and loot by zone since %s."], places, zones)
end

-- History (levels) ------------------------------------------------------------------------------------

local function historyRows(ctx)
  local rows = {}
  local db, rec = ns.db, Wn.Record(ctx.character)
  if not db or not rec then return rows end
  local journal = type(db.journal) == "table" and db.journal or {}
  for i = 1, #journal do
    local e = journal[i]
    if type(e) == "table" and e.type == "level" and e.char == rec.guid and type(e.level) == "number" then
      rows[#rows + 1] = { level = e.level, at = e.at, playedTotal = num(e.playedTotal) }
    end
  end
  -- The time at each level: until the next level's played total; the current one from /played.
  for i = 1, #rows - 1 do
    local a, b = rows[i], rows[i + 1]
    if a.playedTotal > 0 and b.playedTotal > 0 then a.atLevel = b.playedTotal - a.playedTotal end
  end
  local atLevel = rec.playedLevel
  if rec == ns.rec then
    local _, now = ns.Character.PlayedNow()
    atLevel = now or atLevel
  end
  local n = #rows
  if n > 0 and rows[n].level == rec.level then
    rows[n].atLevel = atLevel
  elseif type(rec.level) == "number" then
    -- Reached before the journal's 30 days: the current level, with no date.
    rows[n + 1] = { level = rec.level, playedTotal = 0, atLevel = atLevel }
  end
  for _, r in ipairs(rows) do
    r.cells = {
      tostring(r.level), r.at and when(r.at) or L["before the journal"],
      r.atLevel and ns.Session.Duration(r.atLevel) or "",
      r.playedTotal > 0 and ns.Session.Duration(r.playedTotal) or "",
    }
    r.sort = { r.level, r.at or 0, r.atLevel or 0, r.playedTotal }
  end
  return rows
end

local function historyTiles(ctx)
  local rec = Wn.Record(ctx.character)
  if not rec then return nil end
  local total, atLevel = rec.playedTotal, rec.playedLevel
  if rec == ns.rec then
    local t, a = ns.Character.PlayedNow()
    total, atLevel = t or total, a or atLevel
  end
  return {
    { label = L["Level"], value = tostring(rec.level or "?") },
    { label = L["Played"], value = type(total) == "number" and ns.Session.Duration(total) or L["pending"] },
    { label = L["Time at the level"],
      value = type(atLevel) == "number" and ns.Session.Duration(atLevel) or L["pending"] },
  }
end

-- History › Play ----------------------------------------------------------------------------------------

local PLAY = "play"
Wn.PLAY = PLAY

local DAY_NAMES = {
  { "WEEKDAY_MONDAY", N("Monday") }, { "WEEKDAY_TUESDAY", N("Tuesday") },
  { "WEEKDAY_WEDNESDAY", N("Wednesday") }, { "WEEKDAY_THURSDAY", N("Thursday") },
  { "WEEKDAY_FRIDAY", N("Friday") }, { "WEEKDAY_SATURDAY", N("Saturday") }, { "WEEKDAY_SUNDAY", N("Sunday") },
}

-- A weekday's name (Monday 1 .. Sunday 7): the client's own, else ours.
function Wn.WeekdayName(wd)
  local e = DAY_NAMES[wd]
  if not e then return "" end
  local name = ns.NonEmpty(_G[e[1]])
  if name and not ns.IsSecret(name) then return name end
  return L[e[2]]
end

-- An hour of the day (0..23) as "12 AM", "6 AM", "12 PM", "6 PM".
function Wn.HourName(h)
  h = tonumber(h) or 0
  if h == 0 then return L["12 AM"] end
  if h == 12 then return L["12 PM"] end
  if h < 12 then return string.format(L["%d AM"], h) end
  return string.format(L["%d PM"], h - 12)
end

-- A time played as History › Play writes it: "3h 05m", "42m", "under a minute".
function Wn.PlayedText(seconds)
  local m = math.floor((tonumber(seconds) or 0) / 60)
  if m < 1 then return L["under a minute"] end
  if m < 60 then return string.format(L["%dm"], m) end
  return string.format(L["%dh %02dm"], math.floor(m / 60), m % 60)
end

-- A day's name: "Today", "Yesterday", else "Thursday, 2026-11-13" (the computer's calendar).
function Wn.DayName(day, index)
  if index == 1 then return L["Today"] end
  if index == 2 then return L["Yesterday"] end
  local p = day.parts
  if type(p) ~= "table" then return "" end
  return string.format(L["%s, %s"], Wn.WeekdayName(ns.Play.Weekday(p)),
    string.format("%04d-%02d-%02d", p.year or 0, p.month or 0, p.day or 0))
end

-- The tally for a character (the rows and the tiles share it): rebuilt with the rows.
local playTally = {}

local function playTallyFor(rec)
  local db = ns.db
  local journal = db and type(db.journal) == "table" and db.journal or {}
  local now = ns.Now()
  local current = ns.API.Journal and ns.API.Journal.Session and ns.API.Journal.Session() or nil
  local sittings = ns.Play.Sittings(journal, rec.guid, current, now)
  return ns.Play.Tally(sittings, { now = now, oldest = ns.Play.Oldest(journal) })
end

local PLAY_COLOR = { r = 0.42, g = 0.36, b = 0.62 }
local STRIP_COLOR = { 0.71, 0.58, 0.9 }

local function playRows(ctx)
  local rows = {}
  local rec = Wn.Record(ctx.character)
  playTally.rec, playTally.t = rec, nil
  if not rec then return rows end
  local t = playTallyFor(rec)
  playTally.t = t
  for i, day in ipairs(t.days) do
    local played = day.seconds > 0
    rows[#rows + 1] = {
      day = day,
      cells = { Wn.DayName(day, i), played and Wn.PlayedText(day.seconds) or L["not played"],
        day.sessions > 0 and tostring(day.sessions) or "" },
      bars = { [2] = { value = day.seconds, max = t.maxDay > 0 and t.maxDay or 1,
        r = PLAY_COLOR.r, g = PLAY_COLOR.g, b = PLAY_COLOR.b } },
      sort = { day.start, day.seconds, day.sessions },
    }
  end
  rows[#rows + 1] = { header = true, cells = { L["When you play, by hour"] } }
  for wd = 1, 7 do
    rows[#rows + 1] = { weekday = wd, cells = { Wn.WeekdayName(wd), "", "" },
      strips = { [2] = { values = ns.Play.Shares(t, wd), color = STRIP_COLOR } } }
  end
  rows[#rows + 1] = { axis = true, cells = { "", "", "" },
    strips = { [2] = { count = 24, labels = { [1] = Wn.HourName(0), [7] = Wn.HourName(6),
      [13] = Wn.HourName(12), [19] = Wn.HourName(18) } } } }
  return rows
end

local function playTiles(ctx)
  local rec = Wn.Record(ctx.character)
  local t = playTally.t
  if not rec or playTally.rec ~= rec or not t then return nil end
  local function sessions(n) return ns.Plural(n, L["%d session"], L["%d sessions"]) end
  local tiles = {
    { label = L["This week"], value = t.week.seconds > 0 and Wn.PlayedText(t.week.seconds) or L["not played"],
      sub = sessions(t.week.sessions) },
    { label = L["Last 30 days"], value = t.month.seconds > 0 and Wn.PlayedText(t.month.seconds) or L["not played"],
      sub = ns.Plural(t.month.days, L["on %d day"], L["on %d days"]) },
  }
  if t.busiestDay then
    tiles[3] = { label = L["Busiest"], value = Wn.WeekdayName(t.busiestDay),
      sub = string.format(L["around %s"], Wn.HourName(t.busiestHour)) }
  else
    tiles[3] = { label = L["Busiest"], value = L["not yet"] }
  end
  if t.longest and t.longest.seconds > 0 then
    local p = ns.Play.LocalParts(t.longest.start)
    local day = p and string.format("%04d-%02d-%02d", p.year or 0, p.month or 0, p.day or 0) or ""
    tiles[4] = { label = L["Longest sitting"], value = Wn.PlayedText(t.longest.seconds),
      sub = p and string.format(L["%s, %s"], Wn.WeekdayName(ns.Play.Weekday(p)), day) or nil }
  else
    tiles[4] = { label = L["Longest sitting"], value = L["not yet"] }
  end
  return tiles
end

local function playTooltip(row, tip)
  if row.day then
    tip:AddLine(row.cells[1])
    tip:AddDoubleLine(L["Played"], row.day.seconds > 0 and Wn.PlayedText(row.day.seconds) or L["not played"],
      0.8, 0.8, 0.8, 1, 1, 1)
    tip:AddDoubleLine(L["Sessions"], tostring(row.day.sessions), 0.8, 0.8, 0.8, 1, 1, 1)
  elseif row.weekday and playTally.t then
    local hours = playTally.t.hours[row.weekday]
    tip:AddLine(Wn.WeekdayName(row.weekday))
    local any = false
    for h = 1, 24 do
      if hours[h] >= 60 then
        any = true
        tip:AddDoubleLine(Wn.HourName(h - 1), Wn.PlayedText(hours[h]), 0.8, 0.8, 0.8, 1, 1, 1)
      end
    end
    if not any then tip:AddLine(L["not played"], 0.6, 0.6, 0.6) end
  end
end

local LEVEL_COLUMNS = { { title = L["Level"], width = 70 }, { title = L["Reached"], width = 160 },
  { title = L["Time at the level"], width = 150, justify = "RIGHT" },
  { title = L["Played when reached"], width = 160, justify = "RIGHT" } }
local PLAY_COLUMNS = { { title = L["Day"], width = 170 },
  { title = L["Played"], width = 330, kind = "strip" },
  { title = L["Sessions"], width = 80, justify = "RIGHT" } }

if Wn.available then
  add({
    key = "session", group = "me", order = 10, label = L["Session"], characters = "current",
    search = false, sortable = false,
    columns = { { title = L["This session"], width = 250 }, { title = "", width = 150, justify = "RIGHT" },
      { title = "", width = 120, justify = "RIGHT" } },
    version = function() return ns.Session.version end,
    tiles = sessionTiles,
    rows = sessionRows,
    tooltip = function(row, tip) if row.ref then Wn.CreatureTooltip(tip, row.ref, ns.rec) end end,
    footer = function() return L["Counted in game since you logged in; a /reload keeps it."] end,
  })
  add({
    key = "kills", group = "me", order = 40, label = L["Kills"], characters = "one",
    columns = killsColumns,
    -- and the zone you're in, which "This zone" follows.
    version = function() return (ns.Chronicle.killsVersion or 0) .. ":" .. tostring(hereZone()) end,
    rows = killsRows, fill = killsFill, tiles = killsTiles,
    filter = function(ctx) return zoneChoices(ctx, "kills") end,
    tooltip = function(row, tip) Wn.CreatureTooltip(tip, row.ref, row.rec) end,
    footer = zoneFooter,
  })
  add({
    key = "loot", group = "me", order = 50, label = L["Loot"], characters = "one", icons = true,
    columns = { { title = L["Item"], width = 190 }, { title = L["Looted"], width = 60, justify = "RIGHT" },
      { title = L["Count"], width = 60, justify = "RIGHT" }, { title = L["From"], width = 160, sort = false },
      { title = L["Last"], width = 110, justify = "RIGHT" } },
    version = function() return (ns.Chronicle.lootVersion or 0) .. ":" .. tostring(hereZone()) end,
    rows = lootRows, fill = lootFill, tiles = lootTiles,
    filter = function(ctx) return zoneChoices(ctx, "loot") end,
    tooltip = function(row, tip, _, hadLink) Wn.ItemTooltip(tip, row.ref, row.rec, hadLink) end,
    footer = zoneFooter,
  })
  add({
    key = "zones", group = "me", order = 55, label = L["Zones"], characters = "one",
    columns = { { title = L["Zone"], width = 140 }, { title = L["Kills"], width = 55, justify = "RIGHT" },
      { title = L["Creatures"], width = 65, justify = "RIGHT" }, { title = L["Drops"], width = 55, justify = "RIGHT" },
      { title = L["Pieces"], width = 55, justify = "RIGHT" }, { title = L["Quests"], width = 55, justify = "RIGHT" },
      { title = L["Deaths"], width = 55, justify = "RIGHT" }, { title = L["Time"], width = 75, justify = "RIGHT" } },
    version = function()
      -- and the minute: the stay under way counts on.
      return (ns.Chronicle.killsVersion or 0) .. ":" .. (ns.Chronicle.lootVersion or 0) .. ":"
        .. (ns.Places and ns.Places.version or 0) .. ":" .. math.floor(GetTime() / 60)
    end,
    rows = zonesRows, tiles = zonesTiles, tooltip = zonesTooltip, click = zonesClick, footer = zonesFooter,
  })
  -- History's views (its picker): Levels, and Play when the core can draw the strip.
  local playView = RW.STRIP_MAX ~= nil
  add({
    key = "history", group = "me", order = 60, label = L["History"], characters = "one", search = false,
    -- (a core before the strip would print a function as the title, so only with Play)
    title = playView and function(ctx)
      if ctx.filter == PLAY then return string.format(L["%s › %s"], L["History"], L["Play"]) end
      return L["History"]
    end or nil,
    filter = playView and function()
      return { { value = nil, label = L["Levels"] }, { value = PLAY, label = L["Play"] } }
    end or nil,
    columns = function(ctx) return ctx.filter == PLAY and PLAY_COLUMNS or LEVEL_COLUMNS end,
    version = function()
      local db = ns.db
      -- and the minute: the current level's time played counts on.
      return tostring(db and type(db.journal) == "table" and #db.journal or 0) .. ":" .. ns.Session.levelVersion
        .. ":" .. math.floor(GetTime() / 60)
    end,
    rows = function(ctx)
      if ctx.filter == PLAY then return playRows(ctx) end
      return historyRows(ctx)
    end,
    tiles = function(ctx)
      if ctx.filter == PLAY then return playTiles(ctx) end
      return historyTiles(ctx)
    end,
    tooltip = function(row, tip, ctx) if ctx.filter == PLAY then playTooltip(row, tip) end end,
    footer = function(ctx)
      if ctx.filter == PLAY then
        return L["From the journal in your saved file, which keeps 30 days; times are on this computer's clock."]
      end
      return L["From the journal's level-ups (it keeps 30 days) and /played."]
    end,
  })
  -- Redrawn when Session.lua says something changed, only while the window is open.
  ns.Session.Watch(function() return RW.IsShown() end, function() RW.Refresh() end)
end

-- The window's sections whose data changed outside the session (a bag scan, a gear or reputation
-- scan): a redraw at most every half second, only while the window is open. Rows rebuild only if
-- the section's version moved.
function Wn.Changed()
  if not Wn.available or not RW.IsShown() then return end
  ns.Debounce("chronicle-window", 0.5, function() RW.Refresh() end)
end

-- Opening it -------------------------------------------------------------------------------------------

local function tooOld()
  ns.Print(L["the Ryna addon here is too old for its window. Update it from the Ryna companion app."])
end

-- Opens the window on section `key`; with none, on the section it was last on (the core remembers it
-- across sessions; Session the first time, the rail's first).
function Wn.Open(key)
  if not Wn.available then return tooOld() end
  RW.Open(key and Wn.keys[key] and key or nil)
end

-- The strip's click: opens the window where it was last, or closes it.
function Wn.Toggle()
  if not Wn.available then return tooOld() end
  if RW.IsShown() then RW.Hide() else RW.Open() end
end

-- /chronicle, and /ryna chronicle: opens the window where it was last, or closes it ("/chronicle
-- kills" opens a section; "levels" and "play" open History on that view).
local ALIASES = { levels = "history", play = "history" }
local function command(arg)
  arg = tostring(arg or ""):lower():match("^%s*(%S*)")
  local key = ALIASES[arg] or arg
  if key ~= "" and Wn.keys[key] then
    -- "levels" and "play" are History's two views.
    if Wn.available and RW.STRIP_MAX ~= nil and (arg == "levels" or arg == "play") then
      RW.SetFilter("history", arg == "play" and PLAY or nil)
    end
    Wn.Open(key)
  else
    Wn.Toggle()
  end
end
Wn.Command = command

SLASH_RYNACHRONICLE1 = "/chronicle"
if type(SlashCmdList) == "table" then
  SlashCmdList.RYNACHRONICLE = function(msg) ns.Run("/chronicle", command, msg) end
end
ns.API.Slash.Add({ word = "chronicle", order = 30, run = command,
  help = L["/ryna chronicle (or /chronicle): Ryna's window; /chronicle session, characters, items, "
    .. "kills, loot, zones or history opens that section, and levels or play History's view"] })
