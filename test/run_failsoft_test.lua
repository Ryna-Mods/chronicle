-- Dungeon runs' views on a client that can't make them: a core from before Ryna's window (no
-- Ryna.Window) and a client whose frames for the strip, the card, the summary and the notice lack a
-- method they need. Runs are still recorded; each view is absent, never an error; Dungeons registers
-- no section; /ryna runs answers what it can when typed, and nothing is said unasked. From the
-- repository root:
--
--   lua5.1 test/run_failsoft_test.lua
-- luacheck: ignore 1

local H = dofile("test/run_harness.lua")
local check, eq = H.check, H.eq
local F = H.F

local ns, core = H.Load({ beforeChronicle = function()
  _G.Ryna.Window = nil
  -- The run frames come without CreateTexture (a trimmed client): building them fails part way.
  local create = _G.CreateFrame
  _G.CreateFrame = function(kind, name, parent, template)
    local f = create(kind, name, parent, template)
    if type(name) == "string" and name:find("^RynaChronicleRun") then rawset(f, "CreateTexture", false) end
    return f
  end
end })
local chatAtStart = #F.chat

check(not ns.off and ns.Runs and ns.RunDisplay and ns.RunSummary and ns.Dungeons, "everything loads")
check(ns.Window.available == false and ns.Window.keys.dungeons == nil, "no window: no Dungeons section")

RynaDB.settings.runDisplay = "card"
H.Enter(H.DM)
check(ns.Runs.Current() ~= nil, "the run is recorded")
check(ns.RunDisplay.frame == nil and ns.RunDisplay.failed, "the display is absent")
H.Leave()
check(ns.Runs.Current().paused, "walking out pauses it")
check(ns.RunSummary.frame == nil and ns.RunSummary.failed, "the summary is absent")
H.Enter(H.DM)

-- The notice, on a fresh account: absent too, and not remembered as shown.
RynaDB.settings.runDisplay = nil
H.Leave()
H.Later(31 * 60)
H.Enter(H.SFK)
check(ns.RunNotice.frame == nil and ns.RunNotice.failed, "the notice is absent")
check(RynaDB.chronicle.runsNoticeSeen ~= true, "a notice never shown isn't remembered as shown")
eq(#F.chat, chatAtStart, "nothing in chat unasked")

-- Typed: answers.
SlashCmdList.RYNA("runs")
check(H.Said(chatAtStart, "too old for its window"), "/ryna runs: the core is too old for the window")
SlashCmdList.RYNA("runs strip")
eq(RynaDB.settings.runDisplay, "strip", "/ryna runs strip still sets it")
local before = #F.chat
SlashCmdList.RYNA("runs test")
check(H.Said(before, "can't be drawn on this client"), "/ryna runs test: says it can't be drawn")
check(ns.RunDisplay.example == nil, "and keeps no example")
check(#ns.Runs.List() == 1, "the first run closed into the list")

check(core.errors.count == 0, "no errors caught: " .. tostring(core.errors.last))
H.done("run fail-soft")
