-- Characters, one character's Talents, Spells and Stats (Characters.lua) against the fake client
-- (fake_client.lua) and the real core: the detail's picker offers them, each view's title, columns and
-- grouped rows from the character sheet on the record (Sheet.lua; docs/wow.md 19.1): talents per spec
-- and tree with their points, taken talents with "2 / 3" over a bar; spells by tab with rank and level,
-- then what the trainer offered that isn't learned yet; stats, skills, currencies and the odds and ends.
-- A character saved before the sheet (no new fields), and one whose fields are the wrong shape, draw
-- without an error. From the repository root, with Lua 5.1 (what the game runs) or later:
--
--   lua5.1 test/characters_sheet_test.lua
--
-- This proves the logic; how it looks in the default UI and in ElvUI is the game's to show.
-- luacheck: ignore 1

local CORE = (os.getenv("RYNA_CORE") or ".core/Ryna_Core") .. "/"
local CHRON = "Ryna_Chronicle/"
local F = dofile("test/fake_client.lua")
local plain = F.Plain

local failures, checks = 0, 0
local function check(cond, what)
  checks = checks + 1
  if not cond then
    failures = failures + 1
    print("FAIL: " .. what)
  end
end
local function eq(got, want, what)
  check(got == want, what .. ": got " .. tostring(got) .. ", want " .. tostring(want))
end

F.Install()

local ME = "Player-91-0000000A"
local ALT = "Player-91-0000000B"
local OLD = "Player-91-0000000C"
local JUNK = "Player-91-0000000D"
_G.UnitGUID = function(unit) if unit == "player" then return ME end end
_G.UnitName = function(unit) if unit == "player" then return "Brennic" end end
_G.UnitFullName = function(unit) if unit == "player" then return "Brennic", "Ashgrove" end end
_G.GetNormalizedRealmName = function() return "91" end
_G.UnitClass = function() return "Paladin", "PALADIN" end
_G.UnitLevel = function() return 17 end
_G.UnitXP = function() return 1200 end
_G.UnitXPMax = function() return 4800 end
_G.GetMoney = function() return 398786 end
_G.GetRealZoneText = function() return "Westfall" end
_G.GetInventoryItemLink = function() return nil end
_G.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() return nil end }
_G.C_AddOns = { GetAddOnMetadata = function() return "0.0.0" end }
_G.MANA = "Mana"

local DAY = 86400
local function talent(node, name, rank, max, row, col)
  return { node = node, spellId = node + 14000, name = name, rank = rank, max = max, row = row, col = col }
end

local sheet = {
  specs = { active = 1, count = 2, list = {
    { group = 1, trees = {
      { id = 31, name = "Discipline", points = 14, talents = {
        talent(501, "Meditation", 2, 3, 1, 2), talent(502, "Inner Focus", 0, 1, 2, 1),
        talent(503, nil, 5, 5, 1, 3) } },
      { id = 32, name = "Holy", points = 1, talents = { talent(504, "Holy Specialization", 1, 5, 1, 2) } },
      { id = 33, name = "Shadow", points = 0, talents = { talent(505, "Spirit Tap", 0, 5, 1, 1) } },
    } },
    { group = 2, trees = {
      { id = 32, name = "Holy", points = 7, talents = { talent(504, "Holy Specialization", 5, 5, 1, 2) } },
    } },
  } },
  spells = { at = F.now - DAY, list = {
    { id = 6603, name = "Auto Attack", tab = "General", passive = false },
    { id = 81, name = "Dodge", tab = "General", passive = true, sub = "Passive" },
    { id = 2054, name = "Heal", rank = 2, sub = "Rank 2", tab = "Holy", passive = false, level = 22 },
    { id = 2061, name = "Flash Heal", tab = "Holy", passive = false, level = 20 },
  } },
  trainer = { at = F.now - 2 * DAY, name = "Brother Joshua", services = {
    { name = "Smite", sub = "Rank 4", rank = 4, level = 14, cost = 800, state = "unavailable" },
    { name = "Lesser Heal", sub = "Rank 2", rank = 2, level = 4, cost = 100, state = "used" },
    { name = "Renew", sub = "Rank 1", rank = 1, level = 8, cost = 100, state = "available" },
  } },
  stats = { at = F.now - DAY, health = 1240, power = 1830, powerType = "MANA",
    attributes = { strength = 28, agility = 31, stamina = 62, intellect = 88, spirit = 95 }, armor = 240,
    resistances = { holy = 0, fire = 5 }, attackPower = 60, spellPower = { holy = 44 }, healing = 61,
    crit = { melee = 3.1, ranged = 0, spell = 6.4 }, dodge = 3.2, manaRegen = { idle = 21.4, casting = 6.1 } },
  skills = { { group = "Weapon Skills", name = "Staves", rank = 105, max = 115 },
    { group = "Languages", name = "Common", rank = 300, max = 300 } },
  currencies = { { id = 1901, name = "Honor Points", quantity = 75, max = 0, group = "Player vs. Player" },
    { id = 42, name = "Badge", quantity = 3, max = 50, group = "Dungeon and Raid" } },
  restedXp = 12000, hearth = "Stormwind City", pvp = { honorableKills = 12 },
}

local altRec = { guid = ALT, fullName = "Alyra-Dawnmere", firstName = "Alyra", class = "MAGE", level = 22,
  lastSeen = F.now - 4 * DAY, talents = "Discipline 14 / Holy 1 / Shadow 0",
  gear = { { slot = 1, itemId = 100, link = "|cff|Hitem:100::|h[Cap]|h|r", dur = 30, durMax = 40 },
    { slot = 7, itemId = 200, link = "|cff|Hitem:200::|h[Linen Pants]|h|r", dur = 5, durMax = 40 },
    { slot = 2, itemId = 300, link = "|cff|Hitem:300::|h[Amulet]|h|r" } } }
for k, v in pairs(sheet) do altRec[k] = v end

_G.RynaDB = {
  schema = 1, settings = {}, journal = {},
  characters = {
    [ME] = { guid = ME, fullName = "Brennic-Ashgrove", firstName = "Brennic", class = "PALADIN", level = 17,
      lastSeen = F.now - DAY },
    [ALT] = altRec,
    [OLD] = { guid = OLD, fullName = "Zed-Stone", firstName = "Zed", class = "WARRIOR", level = 12,
      lastSeen = F.now - 2 * 3600, talents = "Arms 3 / Fury 0 / Protection 0" },
    [JUNK] = { guid = JUNK, fullName = "Nim-Stone", firstName = "Nim", class = "ROGUE", level = 1,
      specs = { list = { "x", { trees = "no" },
        { trees = { { name = "Combat", points = "a", talents = { 1, {} } } } } } },
      spells = { list = { 1, { name = 5 }, { name = "Sinister Strike", level = 0 / 0, sub = 3 } } },
      trainer = "nope", stats = { health = "x", attributes = "no", crit = { melee = 0 / 0 } },
      skills = { "x", { name = "Daggers", rank = "a" } }, currencies = "no", restedXp = "x",
      pvp = { honorableKills = "z" },
      gear = { { slot = 1, dur = 5, durMax = 0 }, "x" } },
  },
}

local core = {}
F.LoadAddon(CORE, "Ryna_Core", core)
F.Fire("ADDON_LOADED", "Ryna_Core")
local ns = {}
F.LoadAddon(CHRON, "Ryna_Chronicle", ns)
F.Fire("ADDON_LOADED", "Ryna_Chronicle")
F.Fire("PLAYER_LOGIN")
F.Fire("PLAYER_ENTERING_WORLD", true, false)
F.DropTimers()

local Wn = core.Window
local Ch = ns.Characters
local SetFilter = _G.Ryna.Window.SetFilter
check(type(Ch.TalentRows) == "function" and type(Ch.SpellRows) == "function" and type(Ch.StatRows) == "function",
  "Characters has the sheet's views")

local function texts(rows)
  local out = {}
  for _, r in ipairs(rows) do out[#out + 1] = (r.header and "# " or "") .. plain(r.cells[1]) end
  return table.concat(out, " / ")
end
local function rowNamed(rows, name)
  for _, r in ipairs(rows) do if not r.header and plain(r.cells[1]) == name then return r end end
end

-- The picker. ----------------------------------------------------------------------------------------------
SlashCmdList.RYNACHRONICLE("characters")
local f = Wn.frame
Wn.Choose(ALT)
check(f.filter:IsShown(), "one character: the view picker")
eq(plain(f.rows[1].cols[1]:GetText()), "Character", "the Character view as before")

-- Talents. -------------------------------------------------------------------------------------------------
SetFilter("characters", Ch.TALENTS)
eq(Wn.ctx.filter, "talents", "on Talents")
eq(f.filter:GetText(), "Talents", "the picker says Talents")
eq(f.title:GetText(), "Alyra-Dawnmere › Talents", "the title names the character")
eq(f.headCells[1]:GetText() .. "|" .. f.headCells[2]:GetText(), "Talent|Rank", "Talent and Rank columns")
local rows = Wn.views.characters.rows
eq(texts(rows), table.concat({
  "# Spec 1 (active) · Discipline · 14 points", "Meditation", "spell 14503",
  "# Spec 1 (active) · Holy · 1 points", "Holy Specialization",
  "# Spec 1 (active) · Shadow · 0 points", "No talents taken.",
  "# Spec 2 · Holy · 7 points", "Holy Specialization",
}, " / "), "each spec's trees with their points, then the taken talents")
local r = rowNamed(rows, "Meditation")
eq(r.cells[2], "2 / 3", "a talent's rank of its max")
eq(r.bars[2].value .. "/" .. r.bars[2].max, "2/3", "over a bar")
check(rowNamed(rows, "Inner Focus") == nil, "an untaken talent isn't listed")
eq(f.tiles[1]:IsShown(), false, "no tiles over the sheet")
local found = Ch.TalentRows({ character = ALT, current = ME, search = "medit", filter = Ch.TALENTS })
eq(texts(found), "# Spec 1 (active) · Discipline · 14 points / Meditation", "search: the talent under its tree")

-- Before the sheet: the talents text and a line saying the rest comes at the next login.
Wn.Choose(OLD)
rows = Wn.views.characters.rows
eq(texts(rows), "# Talents / Arms 3 / Fury 0 / Protection 0 / Each talent shows once this character logs in"
  .. " with this version of Chronicle.", "an old record: its talents text")

-- Spells. --------------------------------------------------------------------------------------------------
Wn.Choose(ALT)
SetFilter("characters", Ch.SPELLS)
eq(f.title:GetText(), "Alyra-Dawnmere › Spells", "the Spells title")
eq(f.headCells[1]:GetText() .. "|" .. f.headCells[2]:GetText() .. "|" .. f.headCells[3]:GetText() .. "|"
  .. f.headCells[4]:GetText(), "Spell|Rank|Level|Cost", "the Spells columns")
rows = Wn.views.characters.rows
eq(texts(rows), table.concat({
  "# General (2)", "Auto Attack", "Dodge", "# Holy (2)", "Heal", "Flash Heal",
  "# At the trainer: Brother Joshua, 2 days ago", "Renew", "Smite",
}, " / "), "spells by tab, then what the trainer offered that isn't learned, lowest level first")
r = rowNamed(rows, "Heal")
eq(r.cells[2] .. "|" .. r.cells[3], "Rank 2|22", "a spell's rank and level")
eq(rowNamed(rows, "Dodge").cells[2], "Passive", "a passive spell")
r = rowNamed(rows, "Renew")
eq(r.cells[2] .. "|" .. r.cells[3], "Rank 1|8", "a service's rank and level")
check(r.cells[4] ~= "", "and its cost")
eq(r.color, "|cff40c040", "learnable now: green")
eq(rowNamed(rows, "Smite").color, "|cffd05050", "not yet: red")
check(rowNamed(rows, "Lesser Heal") == nil, "a used service isn't listed")
Wn.Choose(OLD)
rows = Wn.views.characters.rows
eq(texts(rows), "# Spells / Not recorded yet: log in on this character to read its sheet. / # At the trainer / "
  .. "Visit your class trainer to see what you can learn next.", "an old record: both said")

-- Stats. ---------------------------------------------------------------------------------------------------
Wn.Choose(ALT)
SetFilter("characters", Ch.STATS)
eq(f.title:GetText(), "Alyra-Dawnmere › Stats", "the Stats title")
rows = Wn.views.characters.rows
local function value(name) local x = rowNamed(rows, name) return x and plain(x.cells[2]) end
eq(value("Health") .. "|" .. value("Mana") .. "|" .. value("Spirit") .. "|" .. value("Armor"), "1240|1830|95|240",
  "health, power by its name, attributes, armor")
eq(value("Fire resistance") .. "|" .. value("Holy spell damage") .. "|" .. value("Healing"), "5|44|61",
  "resistances, spell damage, healing")
eq(value("Melee crit") .. "|" .. value("Spell crit") .. "|" .. value("Dodge"), "3.1%|6.4%|3.2%", "percentages")
eq(value("Mana regen (casting)"), "6.1 per 5 s", "mana regen")
check(rowNamed(rows, "Parry") == nil, "a stat not recorded isn't listed")
r = rowNamed(rows, "Staves")
eq(plain(r.cells[2]) .. "|" .. r.cells[3] .. "|" .. r.bars[3].value .. "/" .. r.bars[3].max,
  "Weapon Skills|105 / 115|105/115", "a skill: its group, rank of max over a bar")
eq(rowNamed(rows, "Honor Points").cells[3], "75", "a currency with no max: its quantity")
eq(rowNamed(rows, "Badge").cells[3], "3 / 50", "with a max: of its max")
eq(value("Rested experience") .. "|" .. value("Hearthstone") .. "|" .. value("Honorable kills"),
  "12000|Stormwind City|12", "rested experience, hearthstone, honourable kills")
r = rowNamed(rows, "Durability")
eq(r.cells[2] .. "|" .. r.cells[3], "lowest: Linen Pants|44%", "durability: the lowest item, the total share")
Wn.Choose(OLD)
rows = Wn.views.characters.rows
eq(texts(rows), "# Stats / Not recorded yet: stats are read out of combat, on this character. / # Skills / "
  .. "None recorded yet. / # Currencies / None recorded yet. / # Other / None recorded yet.", "an old record: stats")

-- Wrong shapes everywhere: every view draws, with nothing it can't read.
Wn.Choose(JUNK)
for _, v in ipairs({ Ch.TALENTS, Ch.SPELLS, Ch.STATS }) do
  SetFilter("characters", v)
  check(#Wn.views.characters.rows > 0, v .. ": drawn for a record of the wrong shape")
end
SetFilter("characters", Ch.TALENTS)
check(rowNamed(Wn.views.characters.rows, "Combat") == nil, "junk talents: nothing made up")
SetFilter("characters", Ch.SPELLS)
eq(rowNamed(Wn.views.characters.rows, "Sinister Strike").cells[3], "", "a NaN level: nothing shown")
eq(Ch.NumText(0 / 0) .. Ch.NumText("x") .. Ch.NumText(nil), "", "NumText: nothing for what isn't a number")
eq(Ch.NumText(3) .. "|" .. Ch.NumText(3.10) .. "|" .. Ch.NumText(21.456), "3|3.1|21.46", "NumText: whole and decimal")

-- The character you're on, with nothing read yet; back to Character and to All characters.
Wn.Choose(ME)
for _, v in ipairs({ Ch.TALENTS, Ch.SPELLS, Ch.STATS }) do
  SetFilter("characters", v)
  check(#Wn.views.characters.rows > 0, v .. ": the character you're on, nothing read yet")
end
eq(f.footer:GetText(), "Counted in game for Brennic-Ashgrove, the character you're on.", "its footer: live")
SetFilter("characters", nil)
eq(plain(f.rows[1].cols[1]:GetText()), "Character", "Character again: the detail as before")
Wn.Choose(nil)
check(not f.filter:IsShown(), "All characters: no picker")
eq(f.headCells[1]:GetText(), "Character", "the all-characters columns")

check(#F.chat == 0, "nothing in chat: " .. table.concat(F.chat, " / "))
check(core.errors.count == 0, "no errors caught: " .. tostring(core.errors.last))
print(string.format("characters sheet: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
