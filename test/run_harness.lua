-- The setup the dungeon run view tests share (run_views_test.lua, run_frames_test.lua,
-- run_failsoft_test.lua): the fake client with a character inside or outside an instance, the real
-- core addon, then Chronicle in its TOC order, logged in. Not a test itself (only *_test.lua files
-- run); dofile it from the repository root:
--
--   local H = dofile("test/run_harness.lua")
--   H.Load({ beforeChronicle = function(core) ... end })   -> H.F, H.ns, H.core
--   H.Enter(H.DM); H.Leave(); H.Later(seconds)
-- luacheck: ignore 1

local CORE = (os.getenv("RYNA_CORE") or ".core/Ryna_Core") .. "/"
local CHRON = "Ryna_Chronicle/"
local F = dofile("test/fake_client.lua")

local H = { F = F, failures = 0, checks = 0 }

function H.check(cond, what)
  H.checks = H.checks + 1
  if not cond then
    H.failures = H.failures + 1
    print("FAIL: " .. what)
  end
end

function H.eq(got, want, what)
  H.check(got == want, what .. ": got " .. tostring(got) .. ", want " .. tostring(want))
end

function H.done(name)
  print(string.format("%s: %d checks, %d failed", name, H.checks, H.failures))
  os.exit(H.failures == 0 and 0 or 1)
end

H.ME = "Player-91-0000000A"
H.ALT = "Player-91-0000000B"
H.DM = { mapId = 36, name = "The Deadmines", kind = "party" }
H.SFK = { mapId = 33, name = "Shadowfang Keep", kind = "party" }
H.player = { xp = 1200, xpMax = 4800, level = 17 }

local inst = nil

function H.Install()
  F.Install()
  _G.UnitGUID = function(unit) if unit == "player" then return H.ME end end
  _G.UnitName = function(unit) if unit == "player" then return "Brennic" end end
  _G.UnitFullName = function(unit) if unit == "player" then return "Brennic", "Ashgrove" end end
  _G.GetNormalizedRealmName = function() return "91" end
  _G.UnitClass = function() return "Paladin", "PALADIN" end
  _G.UnitRace = function() return "Human", "Human" end
  _G.UnitFactionGroup = function() return "Alliance" end
  _G.UnitSex = function() return 3 end
  _G.UnitLevel = function(unit) if unit == "player" then return H.player.level end return 17 end
  _G.UnitXP = function() return H.player.xp end
  _G.UnitXPMax = function() return H.player.xpMax end
  _G.GetMaxPlayerLevel = function() return 60 end
  _G.GetMoney = function() return 123456 end
  _G.GetRealZoneText = function() return inst and inst.name or "Westfall" end
  _G.GetSubZoneText = function() return "" end
  _G.GetInventoryItemLink = function() return nil end
  _G.IsInInstance = function()
    if inst then return true, inst.kind end
    return false, "none"
  end
  _G.GetInstanceInfo = function()
    if inst then return inst.name, inst.kind, 1, "Normal", 5, 0, false, inst.mapId, 5, nil, false end
    return "Eastern Kingdoms", "none", 0, "", 0, 0, false, 0, 0, nil, false
  end
  _G.InCombatLockdown = function() return H.inCombat == true end
  _G.C_Item.GetItemInfo = function(id)
    local names = { [5191] = { "Cookie's Stirring Rod", 3 }, [5196] = { "Smite's Mighty Hammer", 2 } }
    local e = names[id]
    if e then return e[1], "link", e[2], 20, 1, "Weapon", "Mace", 1, "", 0, id == 5196 and 3400 or 2000 end
  end
  local function tocVersion(folder, name)
    return assert(io.open(folder .. name .. ".toc")):read("*a"):match("## Version:%s*(%S+)")
  end
  local TOC = { Ryna_Core = tocVersion(CORE, "Ryna_Core"), Ryna_Chronicle = tocVersion(CHRON, "Ryna_Chronicle") }
  _G.C_AddOns = { GetAddOnMetadata = function(name, field) if field == "Version" then return TOC[name] end end }
end

-- opts: { db (RynaDB), beforeChronicle(core) (to take things away from the core) }
function H.Load(opts)
  opts = opts or {}
  H.Install()
  _G.RynaDB = opts.db or { schema = 1, settings = {}, journal = {}, characters = {
    [H.ALT] = { guid = H.ALT, fullName = "Alyra-Dawnmere", firstName = "Alyra", class = "MAGE", level = 22,
      lastSeen = F.now - 86400 },
  } }
  local core = {}
  F.LoadAddon(CORE, "Ryna_Core", core)
  F.Fire("ADDON_LOADED", "Ryna_Core")
  if opts.beforeChronicle then opts.beforeChronicle(core) end
  local ns = {}
  F.LoadAddon(CHRON, "Ryna_Chronicle", ns)
  F.Fire("ADDON_LOADED", "Ryna_Chronicle")
  F.Fire("PLAYER_LOGIN")
  F.Fire("PLAYER_ENTERING_WORLD", true, false)
  F.DropTimers() -- the deferred login scans: not these tests'
  H.ns, H.core = ns, core
  return ns, core
end

-- Walking in and out (the zone event Runs.lua checks on), then the half-second notices.
function H.Enter(where)
  inst = where
  F.Fire("ZONE_CHANGED_NEW_AREA")
  F.RunTimers()
end

function H.Leave()
  inst = nil
  F.Fire("ZONE_CHANGED_NEW_AREA")
  F.RunTimers()
end

function H.Later(seconds)
  F.now = F.now + seconds
  F.clock = F.clock + seconds
end

-- Chat lines since `from` (an index into F.chat).
function H.Said(from, text)
  for i = (from or 0) + 1, #F.chat do
    if F.chat[i]:find(text, 1, true) then return true end
  end
  return false
end

return H
