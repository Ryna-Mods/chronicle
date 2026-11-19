-- The character sheet's scanners (Sheet.lua; docs/wow.md 19.1) against a fake client (no game needed):
-- loads Chronicle's namespace (Mod.lua), its strings, Character.lua and Sheet.lua with a stand-in for
-- the core's mod API, then reads each part on a Forever-shaped client and checks its shape against the
-- contract: talents per spec and tree (row and column from the node positions, the name from the
-- definition's override or the spell), the spellbook (rank from the subtext, "Rank 3" is 3), the class
-- trainer (its list late at TRAINER_SHOW, a profession trainer skipped), stats (out of combat only),
-- skills, currencies, rested experience, the hearthstone, honourable kills and gear durability. A missing
-- API, a secret value and combat each leave the part out (the record keeps what it had), and the record
-- carries every part forward at the next login. From the repository root, with Lua 5.1 (what the game
-- runs) or later:
--
--   lua5.1 test/sheet_test.lua
--
-- This proves the logic; that Forever answers these calls with these shapes is from Blizzard's Forever
-- UI source, and the game has the final say.
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
local function eq(got, want, what)
  check(got == want, what .. ": got " .. tostring(got) .. ", want " .. tostring(want))
end

local errors, chat = {}, {}
local function run(label, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then errors[#errors + 1] = label .. ": " .. tostring(err) end
end

-- A secret: any comparison, arithmetic or indexing of it throws, as the 12.x engine does.
local SECRET = setmetatable({}, {
  __tostring = function() return "secret" end,
  __lt = function() error("compared a secret") end,
  __le = function() error("compared a secret") end,
  __add = function() error("arithmetic on a secret") end,
  __sub = function() error("arithmetic on a secret") end,
  __mul = function() error("arithmetic on a secret") end,
  __div = function() error("arithmetic on a secret") end,
  __index = function() error("indexed a secret") end,
  __len = function() error("length of a secret") end,
})

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

local handlers, debounced, timers = {}, {}, {}
local DB = { characters = {} }
_G.GetLocale = function() return "enUS" end
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) chat[#chat + 1] = msg end }
_G.Ryna = {
  API = 2, VERSION = "test", L = setmetatable({}, { __index = function(_, k) return k end }),
  Try = try, Fn = fn,
  IsSecret = function(v) return rawequal(v, SECRET) end,
  NonEmpty = function(s) if type(s) == "string" and s ~= "" then return s end end,
  Locale = function() return "enUS" end,
  Now = function() return 1800000000 end,
  Print = function(m) chat[#chat + 1] = "Ryna: " .. m end,
  Debug = function() end,
  DebugChanged = function() end,
  Debugging = function() return false end,
  Run = run,
  After = function(_, _, f) timers[#timers + 1] = f end,
  Debounce = function(key, _, f) debounced[key] = f end,
  ReportError = function(label, err) errors[#errors + 1] = label .. ": " .. tostring(err) end,
  On = function(event, f)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], f)
    return true
  end,
  DB = function() return DB end,
  RegisterMod = function() return true end,
  Journal = { Add = function() end },
  Settings = { Get = function() return nil end, Set = function() end, AddDefaults = function() end },
}

local ns = {}
for _, file in ipairs({ "Mod.lua", "Locales/enUS.lua", "Character.lua", "Sheet.lua" }) do
  local chunk = assert(loadfile(ADDON .. file))
  chunk("Ryna_Chronicle", ns)
end
local S = ns.Sheet
check(not ns.off and S and type(S.ScanAll) == "function", "Sheet.lua loads")

local function fire(event, ...)
  for _, f in ipairs(handlers[event] or {}) do run(event, f, event, ...) end
end
local function runTimers()
  for _ = 1, 10 do
    if #timers == 0 then return end
    local batch = timers
    timers = {}
    for _, t in ipairs(batch) do run("timer", t) end
  end
end

-- Nothing of the client: every scan leaves the record as it was, and nothing errors. -----------------
local function clearClient()
  for _, k in ipairs({ "C_ClassTalents", "C_Traits", "C_SpecializationInfo", "GetNumSpecGroups", "C_Spell",
    "C_SpellBook", "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceCost", "C_Trainer",
    "IsTradeskillTrainer", "UnitName", "InCombatLockdown", "UnitAffectingCombat", "UnitHealthMax", "UnitPowerMax",
    "UnitPowerType", "UnitStat", "UnitArmor", "UnitResistance", "UnitAttackPower", "UnitRangedAttackPower",
    "GetSpellBonusDamage", "GetSpellBonusHealing", "GetCritChance", "GetRangedCritChance", "GetSpellCritChance",
    "GetDodgeChance", "GetParryChance", "GetBlockChance", "GetManaRegen", "C_SkillInfo", "GetNumSkillLines",
    "GetSkillLineInfo", "C_CurrencyInfo", "GetXPExhaustion", "GetBindLocation", "GetPVPLifetimeStats",
    "GetInventoryItemDurability", "Enum" }) do
    _G[k] = nil
  end
end
clearClient()

local kept = { specs = { active = 1, count = 1, list = {} }, spells = { at = 1, list = {} }, stats = { at = 1 },
  skills = { { name = "Staves" } }, currencies = { { name = "Honor Points" } }, hearth = "Goldshire" }
ns.rec = {}
for k, v in pairs(kept) do ns.rec[k] = v end
run("scan all", S.ScanAll)
check(#errors == 0, "a client with none of it: nothing errors (" .. table.concat(errors, "; ") .. ")")
for k, v in pairs(kept) do check(ns.rec[k] == v, "a client with none of it keeps " .. k) end
eq(ns.rec.restedXp, nil, "no GetXPExhaustion: no rested experience")
eq(ns.rec.pvp, nil, "no GetPVPLifetimeStats: no pvp")
fire("TRAINER_SHOW")
runTimers()
eq(ns.rec.trainer, nil, "no trainer API: no trainer")

ns.rec = nil
run("no record", S.ScanAll)
check(#errors == 0, "no character record yet: nothing happens")

-- Talents ----------------------------------------------------------------------------------------------
-- A class tree (777) with three trait groups; configs 4954925 (spec 1) and 4954926 (spec 2). Nodes:
-- { id, group, posX, posY, rank, max, entry }. Entry -> definition -> spell / override name.
local SPELLS = { [14521] = "Meditation", [14522] = "Inner Focus", [14523] = "Holy Specialization",
  [14524] = "Spirit Tap" }
local function talentClient(opts)
  opts = opts or {}
  local nodes = opts.nodes or {
    -- Discipline (31): rows at posY 100, 200; columns at posX 1000, 1600, 2200 (shared with the others).
    { 501, 31, 1600, 100, 2, 3, 901 },
    { 502, 31, 1000, 200, 0, 1, 902 },
    { 503, 31, 2200, 100, 5, 5, 903 },
    -- Holy (32).
    { 504, 32, 1600, 200, 1, 2, 904 },
    -- Shadow (33): none taken.
    { 505, 33, 1000, 100, 0, 5, 905 },
  }
  _G.C_ClassTalents = { GetActiveConfigID = function() return opts.activeConfig or 4954925 end }
  _G.C_SpecializationInfo = {
    GetActiveSpecGroup = function() return opts.active or 1 end,
    GetCombatConfigIDForSpecGroup = function(g)
      if opts.otherConfig == false and g ~= (opts.active or 1) then return nil end
      return 4954924 + g
    end,
  }
  _G.GetNumSpecGroups = function() return opts.count or 1 end
  _G.C_Spell = { GetSpellName = function(id) return SPELLS[id] end }
  _G.C_Traits = {
    GetConfigInfo = function(configId)
      if configId == 4954925 or configId == 4954926 then return { ID = configId, treeIDs = { 777 } } end
    end,
    GetGroupDisplayInfoByTreeID = function(treeId)
      if treeId ~= 777 then return {} end
      return { { groupID = 31, displayName = "Discipline" }, { groupID = 32, displayName = "Holy" },
        { groupID = 33, displayName = opts.secretName and SECRET or "Shadow" } }
    end,
    GetGroupCurrencyInfo = function(configId, ids)
      local spent = configId == 4954926 and { [31] = 0, [32] = 7, [33] = 0 } or { [31] = 14, [32] = 1, [33] = 0 }
      local out = {}
      for _, id in ipairs(ids) do
        out[#out + 1] = { traitNodeGroupID = id, currencyInfos = { { spent = spent[id] } } }
      end
      return out
    end,
    GetTreeNodes = function(treeId)
      if treeId ~= 777 then return {} end
      local ids = {}
      for i, n in ipairs(nodes) do ids[i] = n[1] end
      ids[#ids + 1] = 599 -- a node the client hides
      return ids
    end,
    GetNodeInfo = function(configId, nodeId)
      if nodeId == 599 then return { ID = 599, isVisible = false, groupIDs = { 31 }, maxRanks = 1 } end
      for _, n in ipairs(nodes) do
        if n[1] == nodeId then
          local rank = n[5]
          if configId == 4954926 then rank = (n[2] == 32) and n[6] or 0 end
          return { ID = n[1], posX = n[3], posY = n[4], groupIDs = { n[2] }, activeRank = rank,
            ranksPurchased = rank, currentRank = rank, maxRanks = n[6], isVisible = true,
            activeEntry = { entryID = n[7], rank = rank }, entryIDs = { n[7] } }
        end
      end
    end,
    GetEntryInfo = function(_, entryId) return { definitionID = entryId + 1000 } end,
    GetDefinitionInfo = function(defId)
      local entry = defId - 1000
      if entry == 903 then return { spellID = 14523, overrideName = "Divine Spirit" } end
      return { spellID = 14521 + (entry - 901) }
    end,
  }
end

talentClient()
ns.rec = {}
S.ScanSpecs()
local specs = ns.rec.specs
check(type(specs) == "table", "specs recorded")
eq(specs.active, 1, "active spec group")
eq(specs.count, 1, "one spec group before dual spec")
eq(#specs.list, 1, "one spec read")
local spec = specs.list[1]
eq(spec.group, 1, "the active one first")
eq(#spec.trees, 3, "three trees, in the client's order")
local disc = spec.trees[1]
eq(disc.id .. "|" .. disc.name .. "|" .. disc.points, "31|Discipline|14", "a tree: id, name, points")
eq(#disc.talents, 3, "every visible node of the tree, taken or not; the hidden one left out")
local t1 = disc.talents[1]
eq(t1.node .. "|" .. t1.spellId .. "|" .. t1.name .. "|" .. t1.rank .. "|" .. t1.max .. "|" .. t1.row .. "|" .. t1.col,
  "501|14521|Meditation|2|3|1|2", "a talent: node, spell, name, rank, max, row, column")
eq(disc.talents[2].name .. "|" .. disc.talents[2].row .. "|" .. disc.talents[2].col, "Divine Spirit|1|3",
  "the override name wins; by row then column")
eq(disc.talents[3].name .. "|" .. disc.talents[3].rank .. "|" .. disc.talents[3].row, "Inner Focus|0|2",
  "an untaken talent is kept at rank 0")
eq(spec.trees[3].points, 0, "a tree with no points: 0")
eq(spec.trees[2].talents[1].col, 2, "columns are shared across the class tree")
eq(ns.rec.talents, nil, "the talents text is Character.lua's, untouched here")

-- Dual spec: spec 2 active, spec 1 read through its config.
talentClient({ active = 2, count = 2 })
ns.rec = {}
S.ScanSpecs()
specs = ns.rec.specs
eq(specs.active .. "|" .. specs.count .. "|" .. #specs.list, "2|2|2", "dual spec: both read")
eq(specs.list[1].group, 2, "the active spec first")
eq(specs.list[2].group, 1, "then the other")

-- The other spec's config can't be read: left out.
talentClient({ active = 1, count = 2, otherConfig = false })
ns.rec = {}
S.ScanSpecs()
eq(#ns.rec.specs.list, 1, "an unreadable other spec is left out")
eq(ns.rec.specs.count, 2, "but the count says there are two")

-- A secret tree name: that tree left out, never compared.
talentClient({ secretName = true })
ns.rec = {}
run("secret tree", S.ScanSpecs)
eq(#ns.rec.specs.list[1].trees, 2, "a secret tree name: that tree left out")

-- A secret rank: the node keeps rank 0 rather than a guess; a secret position: no row/col.
talentClient({ nodes = { { 501, 31, SECRET, 100, SECRET, 3, 901 } } })
ns.rec = {}
run("secret node", S.ScanSpecs)
local only = ns.rec.specs.list[1].trees[1].talents[1]
eq(only.rank .. "|" .. tostring(only.col) .. "|" .. only.row, "0|nil|1", "secret values in a node are left out")

-- The config not loaded yet: the record keeps what it had.
talentClient({ activeConfig = 1 })
_G.C_SpecializationInfo.GetCombatConfigIDForSpecGroup = function() return nil end
ns.rec = { specs = kept.specs }
S.ScanSpecs()
check(ns.rec.specs == kept.specs, "no readable config: the last specs stay")
check(#errors == 0, "talents: no errors (" .. table.concat(errors, "; ") .. ")")
clearClient()

-- Spells -----------------------------------------------------------------------------------------------
local function spellClient(opts)
  opts = opts or {}
  _G.Enum = { SpellBookSpellBank = { Player = 0, Pet = 1 },
    SpellBookItemType = { Spell = 1, FutureSpell = 2, Flyout = 4 } }
  local lines = {
    { name = "General", itemIndexOffset = 0, numSpellBookItems = 2, shouldHide = false, isGuild = false },
    { name = "Holy", itemIndexOffset = 2, numSpellBookItems = 3, shouldHide = false, isGuild = false },
    { name = "Guild", itemIndexOffset = 5, numSpellBookItems = 1, shouldHide = false, isGuild = true },
    { name = "Hidden", itemIndexOffset = 6, numSpellBookItems = 1, shouldHide = true, isGuild = false },
  }
  local items = {
    { spellID = 6603, actionID = 6603, itemType = 1, name = "Auto Attack", subName = "", isPassive = false },
    { spellID = 81, actionID = 81, itemType = 1, name = "Dodge", subName = "Passive", isPassive = true },
    { spellID = 2054, actionID = 2054, itemType = 1, name = "Heal", subName = "Rank 2", isPassive = false },
    { spellID = 2060, actionID = 2060, itemType = 2, name = "Greater Heal", subName = "Rank 1" }, -- not learned
    { spellID = 585, actionID = 585, itemType = 1, name = opts.secretName and SECRET or "Smite", subName = "" },
    { spellID = 9999, actionID = 9999, itemType = 1, name = "Guild Perk", subName = "" },
    { spellID = 9998, actionID = 9998, itemType = 1, name = "Hidden Spell", subName = "" },
  }
  _G.C_SpellBook = {
    GetNumSpellBookSkillLines = function() return #lines end,
    GetSpellBookSkillLineInfo = function(i) return lines[i] end,
    GetSpellBookItemInfo = function(slot, bank)
      if bank ~= 0 then return nil end
      return items[slot]
    end,
    GetSpellBookItemLevelLearned = function(slot)
      if slot == 3 then return 22 end
      return 0
    end,
  }
  _G.C_Spell = { GetSpellSubtext = function(id)
    if id == 585 and opts.subLater then return "Rank 3" end
    return nil
  end }
end

spellClient()
ns.rec = {}
S.ScanSpells()
local spells = ns.rec.spells
check(type(spells) == "table" and spells.at == 1800000000, "spells recorded, with when")
eq(#spells.list, 4, "the player's learned spells only: no future spell, guild perk or hidden tab")
local heal = spells.list[3]
eq(heal.id .. "|" .. heal.name .. "|" .. heal.rank .. "|" .. heal.sub .. "|" .. heal.tab .. "|"
  .. tostring(heal.passive) .. "|" .. heal.level, "2054|Heal|2|Rank 2|Holy|false|22",
  "a spell: id, name, rank, sub, tab, passive, level")
local auto = spells.list[1]
eq(tostring(auto.rank) .. "|" .. tostring(auto.sub) .. "|" .. tostring(auto.level), "nil|nil|nil",
  "no subtext: no rank and no sub; level 0: none")
eq(spells.list[2].passive, true, "passive")
eq(spells.list[2].rank, nil, "'Passive' has no number: no rank")
eq(S.subMissing, true, "a subtext not loaded yet is noted")
debounced["sheet-spells"] = nil
fire("SPELL_TEXT_UPDATE")
check(debounced["sheet-spells"] == S.ScanSpells, "SPELL_TEXT_UPDATE reads the spellbook again")

spellClient({ subLater = true })
ns.rec = {}
S.ScanSpells()
eq(ns.rec.spells.list[4].rank, 3, "the subtext through C_Spell.GetSpellSubtext: 'Rank 3' is rank 3")

spellClient({ secretName = true })
ns.rec = {}
run("secret spell", S.ScanSpells)
eq(#ns.rec.spells.list, 3, "a secret spell name: that spell left out")

eq(S.Rank("Rank 3"), 3, "rank parsed from 'Rank 3'")
eq(S.Rank("Rang 12"), 12, "the first number, whatever the language")
eq(S.Rank("Passive"), nil, "no number: no rank")
eq(S.Rank(SECRET), nil, "a secret subtext: no rank")
check(#errors == 0, "spells: no errors (" .. table.concat(errors, "; ") .. ")")
clearClient()

-- The trainer ------------------------------------------------------------------------------------------
local services = {
  { "Lesser Heal", "used", 1, 4, "Rank 2", "", 100 },
  { "Lesser Heal", "available", 1, 10, "Rank 3", "", 300 },
  { "Smite", "unavailable", 1, 14, "Rank 3", "", 800 },
  { "Holy", "header", 1, 0, "", "", 0 },
}
local listed = 0
local function trainerClient(kind)
  _G.Enum = { TrainerType = { General = 0, Tradeskills = 2, Pet = 3 } }
  _G.C_Trainer = { GetTrainerType = function() return kind or 0 end }
  _G.UnitName = function(unit) if unit == "npc" then return "Brother Joshua" end end
  _G.GetNumTrainerServices = function() return listed end
  _G.GetTrainerServiceInfo = function(i)
    local sv = services[i]
    return sv[1], sv[2], sv[3], sv[4], sv[5], sv[6]
  end
  _G.GetTrainerServiceCost = function(i) return services[i][7], false end
end

trainerClient()
ns.rec = {}
listed = 0
fire("TRAINER_SHOW")
eq(ns.rec.trainer, nil, "TRAINER_SHOW with the list not there yet: nothing written")
listed = #services
debounced["sheet-trainer-update"] = nil
fire("TRAINER_UPDATE")
check(debounced["sheet-trainer-update"] == S.ScanTrainer, "TRAINER_UPDATE reads the list")
debounced["sheet-trainer-update"]()
local trainer = ns.rec.trainer
check(type(trainer) == "table", "the late list is read")
eq(trainer.name .. "|" .. trainer.at .. "|" .. #trainer.services, "Brother Joshua|1800000000|3",
  "the trainer: name, when, services (no header rows)")
local sv = trainer.services[2]
eq(sv.name .. "|" .. sv.sub .. "|" .. sv.rank .. "|" .. sv.level .. "|" .. sv.cost .. "|" .. sv.state,
  "Lesser Heal|Rank 3|3|10|300|available", "a service: name, sub, rank, level, cost, state")
eq(trainer.services[1].state, "used", "used services kept")

-- Or a retry a second later picks it up, without TRAINER_UPDATE.
ns.rec = {}
listed = 0
timers = {}
fire("TRAINER_SHOW")
listed = #services
runTimers()
check(type(ns.rec.trainer) == "table", "a retry after TRAINER_SHOW reads the list once it is there")
-- Closed before it came: nothing more.
ns.rec = {}
listed = 0
timers = {}
fire("TRAINER_SHOW")
fire("TRAINER_CLOSED")
listed = #services
runTimers()
eq(ns.rec.trainer, nil, "closed before the list came: no read")
debounced["sheet-trainer-update"] = nil
fire("TRAINER_UPDATE")
eq(debounced["sheet-trainer-update"], nil, "TRAINER_UPDATE with no trainer open: ignored")

-- A profession trainer (or a pet trainer) never replaces the class trainer's list.
trainerClient(2)
ns.rec = { trainer = { name = "class" } }
listed = #services
fire("TRAINER_SHOW")
eq(ns.rec.trainer.name, "class", "a profession trainer: skipped")
trainerClient(0)
_G.IsTradeskillTrainer = function() return true end
fire("TRAINER_SHOW")
eq(ns.rec.trainer.name, "class", "IsTradeskillTrainer: skipped")
fire("TRAINER_CLOSED")
check(#errors == 0, "trainer: no errors (" .. table.concat(errors, "; ") .. ")")
clearClient()

-- Stats ------------------------------------------------------------------------------------------------
local combat = false
local function statClient(opts)
  opts = opts or {}
  _G.InCombatLockdown = function() return combat end
  _G.UnitHealthMax = function() return 1240 end
  _G.UnitPowerMax = function() return 1830 end
  _G.UnitPowerType = function() return 0, opts.power or "MANA" end
  _G.UnitStat = function(_, i) return 10 * i, ({ 28, 31, 62, 88, opts.secretSpirit and SECRET or 95 })[i], 0, 0 end
  _G.UnitArmor = function() return 200, 240, 240, 0 end
  _G.UnitResistance = function(_, i) return 0, 0, i == 2 and 5 or 0, 0 end
  _G.UnitAttackPower = function() return 50, 15, -5 end
  _G.UnitRangedAttackPower = function() return 0, 0, 0 end
  _G.GetSpellBonusDamage = function(school) return school == 2 and 44 or 12 end
  _G.GetSpellBonusHealing = function() return 61 end
  _G.GetCritChance = function() return 3.1234 end
  _G.GetRangedCritChance = function() return 0 end
  _G.GetSpellCritChance = function(school) return school == 2 and 6.4 or 5 end
  _G.GetDodgeChance = function() return 3.2 end
  _G.GetParryChance = function() return 0 end
  _G.GetBlockChance = function() return 0 end
  _G.GetManaRegen = function() return 4.28, 1.22 end
end

statClient()
ns.rec = {}
S.ScanStats()
local st = ns.rec.stats
check(type(st) == "table" and st.at == 1800000000, "stats recorded, with when")
eq(st.health .. "|" .. st.power .. "|" .. st.powerType, "1240|1830|MANA", "health, power, power type")
local a = st.attributes
eq(a.strength .. "|" .. a.agility .. "|" .. a.stamina .. "|" .. a.intellect .. "|" .. a.spirit, "28|31|62|88|95",
  "attributes: UnitStat's effective value")
eq(st.armor, 240, "armor: the effective armor")
eq(st.resistances.fire .. "|" .. st.resistances.holy, "5|0", "resistances by school")
eq(st.attackPower .. "|" .. st.rangedAttackPower, "60|0", "attack power: base plus buffs minus debuffs")
eq(st.spellPower.holy .. "|" .. st.spellPower.arcane .. "|" .. st.healing, "44|12|61", "spell power and healing")
eq(st.crit.melee .. "|" .. st.crit.ranged .. "|" .. st.crit.spell, "3.12|0|6.4", "crit: melee, ranged, spell's highest")
eq(st.dodge .. "|" .. st.parry .. "|" .. st.block, "3.2|0|0", "avoidance")
eq(st.manaRegen.idle .. "|" .. st.manaRegen.casting, "21.4|6.1", "mana regen per 5 s")

-- No mana: no regen.
statClient({ power = "RAGE" })
ns.rec = {}
S.ScanStats()
eq(ns.rec.stats.powerType .. "|" .. tostring(ns.rec.stats.manaRegen), "RAGE|nil", "rage: no mana regen")

-- A secret value: that stat left out, the rest read.
statClient({ secretSpirit = true })
ns.rec = {}
run("secret stat", S.ScanStats)
eq(ns.rec.stats.attributes.spirit, nil, "a secret spirit: left out")
eq(ns.rec.stats.attributes.intellect, 88, "the others read")

-- In combat: nothing read, the last stats stay, and leaving combat reads them.
statClient()
combat = true
ns.rec = { stats = kept.stats }
S.ScanStats()
check(ns.rec.stats == kept.stats, "in combat: the last stats stay")
eq(S.statsPending, true, "in combat: pending")
combat = false
debounced["sheet-stats"] = nil
fire("PLAYER_REGEN_ENABLED")
check(debounced["sheet-stats"] == S.ScanStats, "PLAYER_REGEN_ENABLED reads the stats")
debounced["sheet-stats"]()
check(ns.rec.stats ~= kept.stats and ns.rec.stats.health == 1240, "read out of combat")
debounced["sheet-stats"] = nil
fire("PLAYER_REGEN_ENABLED")
eq(debounced["sheet-stats"], nil, "nothing pending: leaving combat reads nothing")
debounced["sheet-stats"] = nil
fire("UNIT_STATS", "target")
eq(debounced["sheet-stats"], nil, "another unit's stats: ignored")
fire("UNIT_STATS", "player")
check(debounced["sheet-stats"] == S.ScanStats, "the player's: read again")

-- A negative attack power (debuffs) is never sent below 0.
statClient()
_G.UnitAttackPower = function() return 10, 0, -30 end
ns.rec = {}
S.ScanStats()
eq(ns.rec.stats.attackPower, 0, "attack power is never below 0")
check(#errors == 0, "stats: no errors (" .. table.concat(errors, "; ") .. ")")
clearClient()

-- Skills and currencies ----------------------------------------------------------------------------------
_G.C_SkillInfo = {
  GetNumSkillLines = function() return 5 end,
  GetSkillLineInfo = function(i)
    return ({
      { name = "Weapon Skills", isHeader = true },
      { name = "Staves", isHeader = false, rank = 105, maxRank = 115 },
      { name = "Maces", isHeader = false, rank = SECRET, maxRank = 115 },
      { name = "Languages", isHeader = true },
      { name = "Common", isHeader = false, rank = 300, maxRank = 300 },
    })[i]
  end,
}
ns.rec = {}
S.ScanSkills()
local sk = ns.rec.skills
eq(#sk, 3, "skills: every line that isn't a header")
eq(sk[1].group .. "|" .. sk[1].name .. "|" .. sk[1].rank .. "|" .. sk[1].max, "Weapon Skills|Staves|105|115",
  "a skill: group, name, rank, max")
eq(tostring(sk[2].rank) .. "|" .. sk[2].max, "nil|115", "a secret rank: left out")
eq(sk[3].group, "Languages", "under the header above it")

_G.C_CurrencyInfo = {
  GetCurrencyListSize = function() return 4 end,
  GetCurrencyListInfo = function(i)
    return ({
      { name = "Player vs. Player", isHeader = true, isHeaderExpanded = true },
      { name = "Honor Points", isHeader = false, currencyID = 1901, quantity = 75, maxQuantity = 0 },
      { name = "Dungeon and Raid", isHeader = true, isHeaderExpanded = false },
      { name = "Badge", isHeader = false, quantity = 3, maxQuantity = 50 },
    })[i]
  end,
  GetCurrencyListLink = function(i) if i == 4 then return "|cff|Hcurrency:42:0|h[Badge]|h|r" end end,
}
ns.rec = {}
S.ScanCurrencies()
local cu = ns.rec.currencies
eq(#cu, 2, "currencies: the listed ones")
eq(cu[1].id .. "|" .. cu[1].name .. "|" .. cu[1].quantity .. "|" .. cu[1].max .. "|" .. cu[1].group,
  "1901|Honor Points|75|0|Player vs. Player", "a currency: id, name, quantity, max, group")
eq(cu[2].id, 42, "an id from the currency's link when the info has none")
check(#errors == 0, "skills and currencies: no errors (" .. table.concat(errors, "; ") .. ")")
clearClient()

-- Odds and ends ------------------------------------------------------------------------------------------
_G.GetXPExhaustion = function() return nil end
_G.GetBindLocation = function() return "Stormwind City" end
_G.GetPVPLifetimeStats = function() return 12, 0, 0 end
ns.rec = {}
S.ScanExtras()
eq(ns.rec.restedXp .. "|" .. ns.rec.hearth .. "|" .. ns.rec.pvp.honorableKills, "0|Stormwind City|12",
  "no rest: 0; the hearth; honourable kills")
_G.GetXPExhaustion = function() return 12000 end
_G.GetPVPLifetimeStats = function() return SECRET end
ns.rec.pvp = { honorableKills = 5 }
S.ScanExtras()
eq(ns.rec.restedXp, 12000, "rested experience")
eq(ns.rec.pvp.honorableKills, 5, "a secret kill count: the last stays")
for _, event in ipairs({ "UPDATE_EXHAUSTION", "HEARTHSTONE_BOUND" }) do
  debounced["sheet-extras"] = nil
  fire(event)
  check(debounced["sheet-extras"] == S.ScanExtras, event .. " reads them again")
end
_G.GetXPExhaustion = function() return 9000 end
fire("PLAYER_XP_UPDATE")
eq(ns.rec.restedXp, 9000, "PLAYER_XP_UPDATE reads rested experience at once")
clearClient()

-- Durability on the gear rows ------------------------------------------------------------------------------
_G.GetInventoryItemLink = function(_, slot)
  if slot == 1 then return "|cff|Hitem:100::|h[Cap]|h|r" end
  if slot == 13 then return "|cff|Hitem:200::|h[Charm]|h|r" end
end
_G.GetInventoryItemDurability = function(slot)
  if slot == 1 then return 30, 40 end
  if slot == 13 then return nil end
end
ns.rec = {}
ns.Character.ScanGear()
eq(#ns.rec.gear, 2, "gear read")
eq(ns.rec.gear[1].dur .. "/" .. ns.rec.gear[1].durMax, "30/40", "a slot's durability")
eq(ns.rec.gear[2].dur, nil, "a slot with none: absent")
_G.GetInventoryItemDurability = function(slot) if slot == 1 then return 12, 40 end end
debounced["sheet-durability"] = nil
fire("UPDATE_INVENTORY_DURABILITY")
debounced["sheet-durability"]()
eq(ns.rec.gear[1].dur, 12, "UPDATE_INVENTORY_DURABILITY updates it in place")
_G.GetInventoryItemDurability = function() return SECRET, 40 end
S.ScanDurability()
eq(ns.rec.gear[1].dur, nil, "a secret durability: left out")
_G.GetInventoryItemLink = nil
clearClient()

-- Carried forward at login --------------------------------------------------------------------------------
local GUID = "Player-91-0000000A"
_G.UnitGUID = function() return GUID end
_G.UnitName = function() return "Brennic" end
_G.GetMoney = function() return 100 end
local sheet = { specs = { active = 1 }, spells = { list = {} }, trainer = { services = {} }, stats = { health = 1 },
  skills = { {} }, currencies = { {} }, restedXp = 7, hearth = "Goldshire", pvp = { honorableKills = 1 } }
local prev = { guid = GUID, talents = "Holy 3" }
for k, v in pairs(sheet) do prev[k] = v end
DB.characters[GUID] = prev
local rec = ns.Character.Login()
for k, v in pairs(sheet) do check(rec[k] == v, "login carries " .. k .. " forward") end
eq(rec.talents, "Holy 3", "and the talents text as it was")
DB.characters[GUID] = { guid = GUID, specs = "junk", restedXp = "x" }
rec = ns.Character.Login()
check(rec.specs == nil and rec.restedXp == nil, "a part of the wrong type isn't carried")

-- Events --------------------------------------------------------------------------------------------------
for event, key in pairs({ TRAIT_CONFIG_UPDATED = "sheet-specs", ACTIVE_TALENT_GROUP_CHANGED = "sheet-specs",
  SPELLS_CHANGED = "sheet-spells", LEARNED_SPELL_IN_TAB = "sheet-spells", SKILL_LINES_CHANGED = "sheet-skills",
  CURRENCY_DISPLAY_UPDATE = "sheet-currencies", PLAYER_EQUIPMENT_CHANGED = "sheet-stats" }) do
  debounced[key] = nil
  fire(event, "player")
  check(debounced[key] ~= nil, event .. " schedules " .. key)
end

check(#chat == 0, "nothing in chat")
check(#errors == 0, "no handler raised: " .. table.concat(errors, "; "))
print(string.format("sheet: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
