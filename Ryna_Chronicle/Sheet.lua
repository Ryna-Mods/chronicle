-- Sheet: the character sheet (docs/wow.md section 19.1), the parts of the character record beyond its
-- summary: every talent with its rank, per spec (`specs`), the spellbook (`spells`), the class
-- trainer's list as of the last visit (`trainer`), stats read out of combat (`stats`), skills,
-- currencies, rested experience, the hearthstone's place, lifetime honourable kills, and each gear
-- row's durability (`dur`, `durMax`). Character.lua builds the record and carries these forward from
-- the last session; this file reads them. The Characters window shows them (Characters.lua).
--
-- None of it has been checked in the live game yet, so every read fails soft: a function the client
-- doesn't have, an error, a secret value or an odd shape leaves that part out (the record keeps what
-- it had), and never stops another part or another scan. A value is checked with ns.IsSecret before
-- it is compared, indexed or added to anything. The calls and their shapes are Blizzard's own Forever
-- UI's (Blizzard_PlayerSpells Camelot ClassTalents, Blizzard_TrainerUI, PaperDollFrame Camelot,
-- SkillsFrame Camelot, Blizzard_TokenUI) and its API docs; ryna_agent docs/forever-client-api.md
-- keeps what the team checked.

local _, ns = ...
if ns.off then return end

local S = {}
ns.Sheet = S

local NonEmpty = ns.NonEmpty

-- The contract's limits (docs/wow.md 19.1): past these the API drops the whole part, so the addon
-- never sends more.
S.MAX_SPECS, S.MAX_TREES, S.MAX_TALENTS = 2, 6, 120
S.MAX_SPELLS, S.MAX_SERVICES, S.MAX_SKILLS, S.MAX_CURRENCIES = 600, 600, 120, 200
S.MAX_NAME = 200

local function changed()
  if ns.Character and ns.Character.Changed then ns.Character.Changed() end
end

-- A number the API takes: plain (not secret), finite and not below 0; nil otherwise.
local function count(v)
  if ns.IsSecret(v) or type(v) ~= "number" then return nil end
  if v ~= v or v == math.huge or v < 0 then return nil end
  return v
end
S.Count = count

-- Rounded to `places` decimals (percentages and regen read as floats).
local function round(v, places)
  if v == nil then return nil end
  local m = 10 ^ (places or 0)
  local r = math.floor(v * m + 0.5) / m
  if r == math.floor(r) then return math.floor(r) end -- a whole number saves as one ("0", not "0.0")
  return r
end

-- A name the API takes: plain, not empty, at most 200 characters.
local function name(s)
  s = NonEmpty(s)
  if not s then return nil end
  if #s > S.MAX_NAME then s = s:sub(1, S.MAX_NAME) end
  return s
end

-- The rank in a subtext: its first number ("Rank 3" is 3), nil when it has none.
function S.Rank(sub)
  sub = NonEmpty(sub)
  if not sub then return nil end
  return tonumber(sub:match("(%d+)"))
end

local function inCombat()
  if ns.Try(ns.Fn("InCombatLockdown")) == true then return true end
  return ns.Try(ns.Fn("UnitAffectingCombat"), "player") == true
end
S.InCombat = inCombat

local function spellName(spellId)
  if not count(spellId) then return nil end
  local n = NonEmpty(ns.Try(ns.Fn("C_Spell", "GetSpellName"), spellId))
  if n then return n end
  local info = ns.Try(ns.Fn("C_Spell", "GetSpellInfo"), spellId)
  if type(info) == "table" then
    n = NonEmpty(info.name)
    if n then return n end
  end
  return NonEmpty((ns.Try(ns.Fn("GetSpellInfo"), spellId)))
end

-- Talents --------------------------------------------------------------------------------------------

-- 1-based places of each distinct value, lowest first (a node's row from its posY, column from posX).
local function places(values)
  local set, list = {}, {}
  for _, v in pairs(values) do
    if not set[v] then
      set[v] = true
      list[#list + 1] = v
    end
  end
  table.sort(list)
  local at = {}
  for i, v in ipairs(list) do at[v] = i end
  return at
end

-- A node's talent: its definition's spell and name (the override name, else the spell's).
local function nodeTalent(configId, info)
  local entryId = type(info.activeEntry) == "table" and count(info.activeEntry.entryID) or nil
  if not entryId and type(info.entryIDs) == "table" then entryId = count(info.entryIDs[1]) end
  if not entryId then return nil, nil end
  local entry = ns.Try(ns.Fn("C_Traits", "GetEntryInfo"), configId, entryId)
  local defId = type(entry) == "table" and count(entry.definitionID) or nil
  if not defId then return nil, nil end
  local def = ns.Try(ns.Fn("C_Traits", "GetDefinitionInfo"), defId)
  if type(def) ~= "table" then return nil, nil end
  local spellId = count(def.spellID)
  return spellId, name(def.overrideName) or name(spellName(spellId))
end

-- One spec's trees from its trait config: { { id, name, points, talents }, ... } or nil.
function S.ReadTrees(configId)
  configId = count(configId)
  if not configId then return nil end
  local config = ns.Try(ns.Fn("C_Traits", "GetConfigInfo"), configId)
  local treeId = type(config) == "table" and type(config.treeIDs) == "table" and count(config.treeIDs[1])
  if not treeId then return nil end
  local groups = ns.Try(ns.Fn("C_Traits", "GetGroupDisplayInfoByTreeID"), treeId)
  if type(groups) ~= "table" then return nil end

  local trees, byGroup, ids = {}, {}, {}
  for _, g in ipairs(groups) do
    local id = type(g) == "table" and count(g.groupID)
    local n = id and name(g.displayName)
    if id and n and #trees < S.MAX_TREES then
      local tree = { id = id, name = n, talents = {} }
      trees[#trees + 1] = tree
      byGroup[id] = tree
      ids[#ids + 1] = id
    end
  end
  if #trees == 0 then return nil end

  local infos = ns.Try(ns.Fn("C_Traits", "GetGroupCurrencyInfo"), configId, ids)
  if type(infos) == "table" then
    for _, info in ipairs(infos) do
      local group = type(info) == "table" and count(info.traitNodeGroupID)
      local currency = group and type(info.currencyInfos) == "table" and info.currencyInfos[1]
      local spent = type(currency) == "table" and count(currency.spent)
      if spent and byGroup[group] then byGroup[group].points = spent end
    end
  end

  local nodes = ns.Try(ns.Fn("C_Traits", "GetTreeNodes"), treeId)
  local getNode = ns.Fn("C_Traits", "GetNodeInfo")
  local xs, ys = {}, {}
  for _, nodeId in ipairs(type(nodes) == "table" and nodes or {}) do
    nodeId = count(nodeId)
    local info = nodeId and ns.Try(getNode, configId, nodeId)
    if type(info) == "table" and info.isVisible ~= false then
      local tree
      for _, gid in ipairs(type(info.groupIDs) == "table" and info.groupIDs or {}) do
        gid = count(gid)
        if gid and byGroup[gid] then
          tree = byGroup[gid]
          break
        end
      end
      local rank = count(info.activeRank) or count(info.ranksPurchased) or count(info.currentRank)
      local max = count(info.maxRanks)
      if tree and #tree.talents < S.MAX_TALENTS and max and max > 0 then
        local spellId, n = nodeTalent(configId, info)
        local x, y = count(info.posX), count(info.posY)
        local t = { node = nodeId, spellId = spellId, name = n, rank = rank or 0, max = max, x = x, y = y }
        tree.talents[#tree.talents + 1] = t
        if x then xs[#xs + 1] = x end
        if y then ys[#ys + 1] = y end
      end
    end
  end

  -- Rows and columns are the distinct positions ranked across the whole class tree, so the three
  -- trees share a grid; within a tree, by row then column.
  local rowOf, colOf = places(ys), places(xs)
  for _, tree in ipairs(trees) do
    for _, t in ipairs(tree.talents) do
      t.row, t.col = t.y and rowOf[t.y] or nil, t.x and colOf[t.x] or nil
      t.x, t.y = nil, nil
    end
    table.sort(tree.talents, function(a, b)
      local ra, rb = a.row or math.huge, b.row or math.huge
      if ra ~= rb then return ra < rb end
      local ca, cb = a.col or math.huge, b.col or math.huge
      if ca ~= cb then return ca < cb end
      return a.node < b.node
    end)
    tree.points = tree.points or 0
  end
  return trees
end

-- specs: the active spec group always, the other when its config can be read.
function S.ScanSpecs()
  local rec = ns.rec
  if not rec then return end
  local active = count(ns.Try(ns.Fn("C_SpecializationInfo", "GetActiveSpecGroup")))
    or count(ns.Try(ns.Fn("GetActiveTalentGroup"))) or 1
  local n = count(ns.Try(ns.Fn("GetNumSpecGroups"))) or 1
  if n < active then n = active end
  local configOf = ns.Fn("C_SpecializationInfo", "GetCombatConfigIDForSpecGroup")
  local list = {}
  local activeConfig = ns.Try(ns.Fn("C_ClassTalents", "GetActiveConfigID")) or ns.Try(configOf, active)
  local trees = S.ReadTrees(activeConfig)
  if not trees then
    ns.DebugChanged("sheet-specs", "sheet: talents not readable yet")
    return
  end
  list[1] = { group = active, trees = trees }
  for group = 1, math.min(n, S.MAX_SPECS) do
    if group ~= active and #list < S.MAX_SPECS then
      local other = S.ReadTrees(ns.Try(configOf, group))
      if other then list[#list + 1] = { group = group, trees = other } end
    end
  end
  rec.specs = { active = active, count = n, list = list }
  changed()
  ns.DebugChanged("sheet-specs", "sheet: talents for %d of %d specs", #list, n)
end

-- Spells ---------------------------------------------------------------------------------------------

local function enum(group, key, default)
  local e = _G.Enum
  local v = type(e) == "table" and type(e[group]) == "table" and e[group][key]
  return count(v) or default
end

-- The spellbook's own spells (no pet, no guild perks, no other spec's, no flyouts or future spells).
-- S.subMissing is set when a spell's subtext wasn't loaded yet, so SPELL_TEXT_UPDATE reads again.
function S.ScanSpells()
  local rec = ns.rec
  if not rec then return end
  local numLines = count(ns.Try(ns.Fn("C_SpellBook", "GetNumSpellBookSkillLines")))
  local lineInfo = ns.Fn("C_SpellBook", "GetSpellBookSkillLineInfo")
  local itemInfo = ns.Fn("C_SpellBook", "GetSpellBookItemInfo")
  if not (numLines and lineInfo and itemInfo) then return end
  local levelOf = ns.Fn("C_SpellBook", "GetSpellBookItemLevelLearned")
  local bank = enum("SpellBookSpellBank", "Player", 0)
  local spellType = enum("SpellBookItemType", "Spell", 1)
  local list, missing = {}, false
  for i = 1, numLines do
    local line = ns.Try(lineInfo, i)
    if type(line) == "table" and line.shouldHide ~= true and line.isGuild ~= true and line.offSpecID == nil then
      local tab = name(line.name)
      local offset, n = count(line.itemIndexOffset), count(line.numSpellBookItems)
      for slot = (offset or 0) + 1, (offset or 0) + (n or 0) do
        if #list >= S.MAX_SPELLS then break end
        local item = ns.Try(itemInfo, slot, bank)
        if type(item) == "table" and count(item.itemType) == spellType and item.isOffSpec ~= true then
          local id = count(item.spellID) or count(item.actionID)
          local n2 = name(item.name)
          if id and n2 then
            local sub = name(item.subName)
            if not sub then
              sub = name(ns.Try(ns.Fn("C_Spell", "GetSpellSubtext"), id))
              if not sub then missing = true end
            end
            local level = count(ns.Try(levelOf, slot, bank))
            list[#list + 1] = { id = id, name = n2, rank = S.Rank(sub), sub = sub, tab = tab,
              passive = item.isPassive == true, level = level and level > 0 and level or nil }
          end
        end
      end
    end
  end
  S.subMissing = missing
  if #list == 0 then return end
  rec.spells = { at = ns.Now(), list = list }
  changed()
  ns.DebugChanged("sheet-spells", "sheet: %d spells%s", #list, missing and " (some subtexts not loaded yet)" or "")
end

-- The trainer -----------------------------------------------------------------------------------------

local STATES = { available = true, unavailable = true, used = true }

local function isClassTrainer()
  if ns.Try(ns.Fn("IsTradeskillTrainer")) == true then return false end
  local kind = count(ns.Try(ns.Fn("C_Trainer", "GetTrainerType")))
  if kind and (kind == enum("TrainerType", "Tradeskills", 2) or kind == enum("TrainerType", "Pet", 3)) then
    return false
  end
  return true
end

-- The open trainer's list. At TRAINER_SHOW the count can be 0 until the list arrives (docs/forever-
-- client-api.md "Trainers"): then nothing is written and TRAINER_UPDATE (or a retry) reads it.
-- -> true when a list was written.
function S.ScanTrainer()
  local rec = ns.rec
  if not rec or not isClassTrainer() then return false end
  local n = count(ns.Try(ns.Fn("GetNumTrainerServices")))
  local info = ns.Fn("GetTrainerServiceInfo")
  if not n or n == 0 or not info then return false end
  local costOf = ns.Fn("GetTrainerServiceCost")
  local services = {}
  for i = 1, n do
    if #services >= S.MAX_SERVICES then break end
    local serviceName, kind, _, reqLevel, subText = ns.Try(info, i)
    local n2 = name(serviceName)
    kind = NonEmpty(kind)
    if n2 and kind and STATES[kind] then
      local sub = name(subText)
      local level = count(reqLevel)
      services[#services + 1] = { name = n2, sub = sub, rank = S.Rank(sub),
        level = level and level > 0 and level or nil, cost = count((ns.Try(costOf, i))), state = kind }
    end
  end
  if #services == 0 then return false end
  rec.trainer = { at = ns.Now(), name = name(ns.Try(ns.Fn("UnitName"), "npc")), services = services }
  changed()
  ns.Debug("sheet: trainer %s, %d services", tostring(rec.trainer.name), #services)
  return true
end

S.trainerOpen, S.trainerToken = false, 0

-- At TRAINER_SHOW: read now, and again a few times a second apart until the list has come.
function S.OnTrainerShow()
  S.trainerOpen = true
  S.trainerToken = S.trainerToken + 1
  local token = S.trainerToken
  local tries = 0
  local function try()
    if not S.trainerOpen or token ~= S.trainerToken then return end
    if S.ScanTrainer() then return end
    tries = tries + 1
    if tries < 4 then ns.After(1, "sheet-trainer", try) end
  end
  try()
end

function S.OnTrainerClosed()
  S.trainerOpen = false
  S.trainerToken = S.trainerToken + 1
end

-- Stats -----------------------------------------------------------------------------------------------

local ATTRIBUTES = { "strength", "agility", "stamina", "intellect", "spirit" }
local SCHOOLS = { "holy", "fire", "nature", "frost", "shadow", "arcane" } -- resistance 1..6, spell school 2..7

local function fill(t, key, v)
  if v ~= nil then
    t[key] = v
    return 1
  end
  return 0
end

local function second(_, b) return b end

-- Stats, read out of combat only (in combat, S.statsPending reads them at PLAYER_REGEN_ENABLED).
function S.ScanStats()
  local rec = ns.rec
  if not rec then return end
  if inCombat() then
    S.statsPending = true
    return
  end
  S.statsPending = false
  local st, got = { at = ns.Now() }, 0
  got = got + fill(st, "health", count(ns.Try(ns.Fn("UnitHealthMax"), "player")))
  got = got + fill(st, "power", count(ns.Try(ns.Fn("UnitPowerMax"), "player")))
  local powerToken = NonEmpty(second(ns.Try(ns.Fn("UnitPowerType"), "player")))
  fill(st, "powerType", powerToken)

  local statFn, attrs, a = ns.Fn("UnitStat"), {}, 0
  for i, key in ipairs(ATTRIBUTES) do a = a + fill(attrs, key, count(second(ns.Try(statFn, "player", i)))) end
  if a > 0 then st.attributes, got = attrs, got + a end

  got = got + fill(st, "armor", count(second(ns.Try(ns.Fn("UnitArmor"), "player"))))
  local resFn, res, r = ns.Fn("UnitResistance"), {}, 0
  for i, key in ipairs(SCHOOLS) do
    local _, real, effective = ns.Try(resFn, "player", i)
    r = r + fill(res, key, count(effective) or count(real))
  end
  if r > 0 then st.resistances, got = res, got + r end

  local function power(fnName)
    local base, pos, neg = ns.Try(ns.Fn(fnName), "player")
    base, pos, neg = count(base), (not ns.IsSecret(pos) and type(pos) == "number") and pos or 0,
      (not ns.IsSecret(neg) and type(neg) == "number") and neg or 0
    if not base then return nil end
    local total = base + pos + neg
    if total ~= total then return nil end
    return total > 0 and total or 0
  end
  got = got + fill(st, "attackPower", power("UnitAttackPower"))
  got = got + fill(st, "rangedAttackPower", power("UnitRangedAttackPower"))

  local bonusFn, sp, s = ns.Fn("GetSpellBonusDamage"), {}, 0
  local critFn, spellCrit = ns.Fn("GetSpellCritChance"), nil
  for i, key in ipairs(SCHOOLS) do
    s = s + fill(sp, key, count(ns.Try(bonusFn, i + 1)))
    local c = count(ns.Try(critFn, i + 1))
    if c and (spellCrit == nil or c > spellCrit) then spellCrit = c end
  end
  if s > 0 then st.spellPower, got = sp, got + s end
  got = got + fill(st, "healing", count(ns.Try(ns.Fn("GetSpellBonusHealing"))))

  local crit, c = {}, 0
  c = c + fill(crit, "melee", round(count(ns.Try(ns.Fn("GetCritChance"))), 2))
  c = c + fill(crit, "ranged", round(count(ns.Try(ns.Fn("GetRangedCritChance"))), 2))
  c = c + fill(crit, "spell", round(spellCrit, 2))
  if c > 0 then st.crit, got = crit, got + c end
  got = got + fill(st, "dodge", round(count(ns.Try(ns.Fn("GetDodgeChance"))), 2))
  got = got + fill(st, "parry", round(count(ns.Try(ns.Fn("GetParryChance"))), 2))
  got = got + fill(st, "block", round(count(ns.Try(ns.Fn("GetBlockChance"))), 2))

  if powerToken == "MANA" then
    local base, casting = ns.Try(ns.Fn("GetManaRegen"))
    base, casting = count(base), count(casting)
    if base or casting then
      st.manaRegen = { idle = base and round(base * 5, 1), casting = casting and round(casting * 5, 1) }
      got = got + 1
    end
  end

  if got == 0 then return end
  rec.stats = st
  changed()
  ns.DebugChanged("sheet-stats", "sheet: %d stats read", got)
end

function S.OnRegenEnabled()
  if S.statsPending then ns.Debounce("sheet-stats", 2, S.ScanStats) end
end

-- Skills and currencies --------------------------------------------------------------------------------

-- Every skill line that isn't a header, under the header above it. Collapsed headers hide their
-- lines; they aren't expanded (as with reputations), so what's listed is what the skills pane shows.
function S.ScanSkills()
  local rec = ns.rec
  if not rec then return end
  local rows, header = {}, nil
  local n = count(ns.Try(ns.Fn("C_SkillInfo", "GetNumSkillLines")))
  local infoFn = ns.Fn("C_SkillInfo", "GetSkillLineInfo")
  if n and infoFn then
    for i = 1, n do
      if #rows >= S.MAX_SKILLS then break end
      local d = ns.Try(infoFn, i)
      local n2 = type(d) == "table" and name(d.name)
      if n2 then
        if d.isHeader == true then
          header = n2
        else
          rows[#rows + 1] = { group = header, name = n2, rank = count(d.rank), max = count(d.maxRank) }
        end
      end
    end
  else
    n = count(ns.Try(ns.Fn("GetNumSkillLines")))
    infoFn = ns.Fn("GetSkillLineInfo")
    for i = 1, (n and infoFn) and n or 0 do
      if #rows >= S.MAX_SKILLS then break end
      local skillName, isHeader, _, rank, _, _, max = ns.Try(infoFn, i)
      local n2 = name(skillName)
      if n2 then
        if isHeader == true then
          header = n2
        else
          rows[#rows + 1] = { group = header, name = n2, rank = count(rank), max = count(max) }
        end
      end
    end
  end
  if #rows == 0 then return end
  rec.skills = rows
  changed()
  ns.DebugChanged("sheet-skills", "sheet: %d skills", #rows)
end

-- The currency list (the token pane's), each under the header above it. Collapsed headers aren't
-- expanded, as with skills.
function S.ScanCurrencies()
  local rec = ns.rec
  if not rec then return end
  local n = count(ns.Try(ns.Fn("C_CurrencyInfo", "GetCurrencyListSize")))
  local infoFn = ns.Fn("C_CurrencyInfo", "GetCurrencyListInfo")
  if not (n and infoFn) then return end
  local linkFn = ns.Fn("C_CurrencyInfo", "GetCurrencyListLink")
  local rows, header = {}, nil
  for i = 1, n do
    if #rows >= S.MAX_CURRENCIES then break end
    local d = ns.Try(infoFn, i)
    local n2 = type(d) == "table" and name(d.name)
    if n2 then
      if d.isHeader == true then
        header = n2
      else
        local id = count(d.currencyID)
        if not id then
          local link = NonEmpty(ns.Try(linkFn, i))
          id = link and tonumber(link:match("currency:(%d+)")) or nil
        end
        rows[#rows + 1] = { id = id, name = n2, quantity = count(d.quantity), max = count(d.maxQuantity),
          group = header }
      end
    end
  end
  if #rows == 0 then return end
  rec.currencies = rows
  changed()
  ns.DebugChanged("sheet-currencies", "sheet: %d currencies", #rows)
end

-- Odds and ends ----------------------------------------------------------------------------------------

-- Rested experience: 0 when none (GetXPExhaustion answers nil), kept as it was when unreadable.
function S.UpdateRested()
  local rec = ns.rec
  local exhaustion = ns.Fn("GetXPExhaustion")
  if not rec or not exhaustion then return end
  local ok, v = pcall(exhaustion)
  if not ok then return end
  if v == nil then
    rec.restedXp = 0
  else
    rec.restedXp = count(v) or rec.restedXp
  end
end

-- Rested experience, the hearthstone's place and lifetime honourable kills.
function S.ScanExtras()
  local rec = ns.rec
  if not rec then return end
  S.UpdateRested()
  rec.hearth = name(ns.Try(ns.Fn("GetBindLocation"))) or rec.hearth
  local kills = count((ns.Try(ns.Fn("GetPVPLifetimeStats"))))
  if kills then rec.pvp = { honorableKills = kills } end
  changed()
end

-- Durability ----------------------------------------------------------------------------------------

-- A slot's durability, or nil, nil when it has none (or it can't be read).
function S.Durability(slot)
  local dur, max = ns.Try(ns.Fn("GetInventoryItemDurability"), slot)
  dur, max = count(dur), count(max)
  if not dur or not max or max <= 0 then return nil, nil end
  return dur, max
end

-- Durability on the record's gear rows, in place (UPDATE_INVENTORY_DURABILITY).
function S.ScanDurability()
  local rec = ns.rec
  if not rec or type(rec.gear) ~= "table" then return end
  for _, g in ipairs(rec.gear) do
    if type(g) == "table" and count(g.slot) then g.dur, g.durMax = S.Durability(g.slot) end
  end
  changed()
end

-- Everything, a few seconds after login (Init.lua): each part on its own, so one failing leaves the rest.
function S.ScanAll()
  ns.Run("sheet specs", S.ScanSpecs)
  ns.Run("sheet spells", S.ScanSpells)
  ns.Run("sheet stats", S.ScanStats)
  ns.Run("sheet skills", S.ScanSkills)
  ns.Run("sheet currencies", S.ScanCurrencies)
  ns.Run("sheet extras", S.ScanExtras)
  ns.Run("sheet durability", S.ScanDurability)
end

-- Events. ns.On skips an event this client doesn't have (registering an unknown one errors on Forever).
for _, event in ipairs({ "TRAIT_CONFIG_UPDATED", "TRAIT_CONFIG_LIST_UPDATED", "PLAYER_TALENT_UPDATE",
  "ACTIVE_TALENT_GROUP_CHANGED", "CHARACTER_POINTS_CHANGED" }) do
  ns.On(event, function() ns.Debounce("sheet-specs", 2, S.ScanSpecs) end)
end
for _, event in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE" }) do
  ns.On(event, function() ns.Debounce("sheet-spells", 3, S.ScanSpells) end)
end
ns.On("SPELL_TEXT_UPDATE", function()
  if S.subMissing then ns.Debounce("sheet-spells", 5, S.ScanSpells) end
end)
ns.On("TRAINER_SHOW", function() S.OnTrainerShow() end)
ns.On("TRAINER_UPDATE", function()
  if S.trainerOpen then ns.Debounce("sheet-trainer-update", 1, S.ScanTrainer) end
end)
ns.On("TRAINER_CLOSED", function() S.OnTrainerClosed() end)
-- Stats move with gear, buffs, level and talents; read 10 seconds after the last change, out of combat.
for _, event in ipairs({ "UNIT_STATS", "UNIT_MAXHEALTH", "UNIT_MAXPOWER", "UNIT_RESISTANCES", "UNIT_ATTACK_POWER",
  "UNIT_RANGED_ATTACK_POWER", "PLAYER_DAMAGE_DONE_MODS", "COMBAT_RATING_UPDATE", "PLAYER_EQUIPMENT_CHANGED",
  "PLAYER_LEVEL_UP" }) do
  ns.On(event, function(_, unit)
    if type(unit) == "string" and event:find("^UNIT_") and unit ~= "player" then return end
    ns.Debounce("sheet-stats", 10, S.ScanStats)
  end)
end
ns.On("PLAYER_REGEN_ENABLED", function() S.OnRegenEnabled() end)
ns.On("SKILL_LINES_CHANGED", function() ns.Debounce("sheet-skills", 3, S.ScanSkills) end)
ns.On("CURRENCY_DISPLAY_UPDATE", function() ns.Debounce("sheet-currencies", 3, S.ScanCurrencies) end)
for _, event in ipairs({ "UPDATE_EXHAUSTION", "HEARTHSTONE_BOUND", "PLAYER_PVP_KILLS_CHANGED" }) do
  ns.On(event, function() ns.Debounce("sheet-extras", 2, S.ScanExtras) end)
end
-- Experience spends rest: read it at once (one call, no timer beside the window's redraw).
ns.On("PLAYER_XP_UPDATE", function() S.UpdateRested() end)
ns.On("UPDATE_INVENTORY_DURABILITY", function() ns.Debounce("sheet-durability", 2, S.ScanDurability) end)
