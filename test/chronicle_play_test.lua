-- History › Play: Play.lua (sessions -> sittings -> per-day and per-weekday-hour seconds and the tiles'
-- numbers) against a made-up time zone, then the view in Ryna's window against the fake client
-- (fake_client.lua). The zone is six hours behind UTC and moves forward an hour one night and back an
-- hour another, so the days and hours are checked across both daylight-saving changes without
-- depending on this computer's own zone. From the repository root, with Lua 5.1 (what the game runs)
-- or later:
--
--   lua5.1 test/chronicle_play_test.lua
--
-- This proves the logic; how the view looks in the default UI and in ElvUI is the game's to show.
-- luacheck: ignore 1

local CORE = (os.getenv("RYNA_CORE") or ".core/Ryna_Core") .. "/"
local CHRON = "Ryna_Chronicle/"
local F = dofile("test/fake_client.lua")

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

-- Unix seconds for a UTC date and time (Howard Hinnant's days_from_civil; no os.time, which is local).
local function utc(y, m, d, h, mi)
  y = m <= 2 and y - 1 or y
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local mp = (m + 9) % 12
  local doy = math.floor((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  local days = era * 146097 + doe - 719468
  return days * 86400 + (h or 0) * 3600 + (mi or 0) * 60
end

-- The made-up zone: UTC-6, UTC-5 from SPRING (02:00 local becomes 03:00) until FALL (02:00 local
-- becomes 01:00 again). Local fields come from UTC fields of the shifted time, as date("*t") gives them.
local SPRING = utc(2026, 3, 8, 8)    -- Sunday 8 March, 02:00 at UTC-6
local FALL = utc(2026, 11, 1, 7)     -- Sunday 1 November, 02:00 at UTC-5
local function offset(t)
  if t >= SPRING and t < FALL then return -5 * 3600 end
  return -6 * 3600
end
local function parts(t)
  local p = os.date("!*t", t + offset(t))
  p.isdst = nil
  return p
end
-- Unix seconds for a local date and time in that zone (the earlier one when it happens twice).
local function at(y, m, d, h, mi)
  local guess = utc(y, m, d, h, mi) + 6 * 3600
  if parts(guess - 3600).hour == h and parts(guess - 3600).min == (mi or 0) then return guess - 3600 end
  return guess
end

-- The pure part, loaded alone. -----------------------------------------------------------------------
_G.date = os.date
local ns = {}
assert(loadfile(CHRON .. "Play.lua"))("Ryna_Chronicle", ns)
local P = ns.Play
check(type(P) == "table", "Play.lua loads on its own")

local ME, ALT = "Player-91-0000000A", "Player-91-0000000B"
local function ev(session, t, kind, typ, char)
  return { session = session, at = t, char = char or ME, type = typ or "session", kind = kind }
end

-- A local Wednesday, 2026-11-18, 20:00: the week started Monday the 16th.
local NOW = at(2026, 11, 18, 20, 0)
eq(P.Weekday(parts(NOW)), 3, "Wednesday is weekday 3 (Monday first)")
local function hm(h, m) return h * 3600 + (m or 0) * 60 end

-- A session across midnight: Monday 23:30 to Tuesday 01:15.
local S1 = "1795300000-0000000A"
local journal = {
  ev(S1, at(2026, 11, 16, 23, 30), "login"),
  ev(S1, at(2026, 11, 17, 0, 40), nil, "zone"),
  ev(S1, at(2026, 11, 17, 1, 15), "logout"),
}
local sit = P.Sittings(journal, ME, nil, NOW)
eq(#sit, 1, "one sitting")
eq(sit[1].stop - sit[1].start, hm(1, 45), "1h 45m long")
local t = P.Tally(sit, { now = NOW, parts = parts, oldest = at(2026, 11, 15, 10, 0) })
eq(#t.days, 4, "the days: today back to the oldest event's (Sunday): four")
eq(parts(t.days[1].start).day .. " " .. parts(t.days[4].start).day, "18 15", "newest first")
eq(parts(t.days[1].start).hour, 0, "a day starts at local midnight")
eq(t.days[3].seconds, hm(0, 30), "Monday: the half hour before midnight")
eq(t.days[2].seconds, hm(1, 15), "Tuesday: the 1h 15m after it")
eq(t.days[3].sessions .. " " .. t.days[2].sessions, "1 1", "the session is counted on both days it covers")
eq(t.days[1].seconds .. " " .. t.days[4].seconds, "0 0", "days inside the range with no play: 0")
eq(t.hours[1][24], hm(0, 30), "Monday 11 PM: 30m")
eq(t.hours[2][1], hm(1, 0), "Tuesday 12 AM: an hour")
eq(t.hours[2][2], hm(0, 15), "Tuesday 1 AM: 15m")
eq(t.month.seconds .. " " .. t.month.sessions .. " " .. t.month.days, hm(1, 45) .. " 1 2",
  "30 days: 1h 45m, one sitting, two days")
eq(t.week.seconds .. " " .. t.week.sessions, hm(1, 45) .. " 1", "this week (since Monday): all of it")
eq(t.longest.seconds, hm(1, 45), "the longest sitting")
eq(t.busiest.weekday .. " " .. t.busiest.hour, "2 0", "the busiest weekday-hour: Tuesday 12 AM")
eq(t.busiestDay .. " " .. t.busiestHour, "2 0", "the busiest day: Tuesday, around 12 AM")
local shares = P.Shares(t, 1)
eq(#shares, 24, "a weekday's strip has 24 shares")
eq(shares[24], 0.5, "Monday 11 PM: half the busiest hour")
eq(P.Shares(t, 2)[1], 1, "the busiest hour: 1")

-- A session with no logout ends at its last event; another character's are not counted; a session
-- whose login fell out of the journal starts at the time in its id.
local S2, S3, S4 = "1795400000-0000000A", "1795500000-0000000B", tostring(at(2026, 11, 15, 9, 0)) .. "-0000000A"
journal = {
  ev(S2, at(2026, 11, 17, 10, 0), "login"),
  ev(S2, at(2026, 11, 17, 10, 20), nil, "zone"),
  ev(S2, at(2026, 11, 17, 10, 50), nil, "questDone"),
  ev(S3, at(2026, 11, 17, 9, 0), "login", "session", ALT),
  ev(S3, at(2026, 11, 17, 18, 0), "logout", "session", ALT),
  ev(S4, at(2026, 11, 15, 9, 40), nil, "zone"),
  ev(S4, at(2026, 11, 15, 10, 0), "logout"),
}
sit = P.Sittings(journal, ME, nil, NOW)
eq(#sit, 2, "two sittings of this character")
eq(sit[1].stop - sit[1].start, hm(1, 0), "no login event: from the time in the session's id (an hour)")
eq(sit[2].stop - sit[2].start, hm(0, 50), "no logout: it ends at its last event (50m)")
-- The session under way ends now.
sit = P.Sittings({ ev(S2, NOW - hm(2, 0), "login"), ev(S2, NOW - hm(1, 30), nil, "zone") }, ME, S2, NOW)
eq(sit[1].stop - sit[1].start, hm(2, 0), "the running session ends now, not at its last event")

-- A /reload (logout, then a new session a few seconds later) is one sitting.
local R1, R2, R3 = "1795600000-0000000A", "1795600100-0000000A", "1795600200-0000000A"
journal = {
  ev(R1, at(2026, 11, 18, 14, 0), "login"), ev(R1, at(2026, 11, 18, 15, 0), "logout"),
  ev(R2, at(2026, 11, 18, 15, 0) + 20, "login"), ev(R2, at(2026, 11, 18, 16, 0), "logout"),
  ev(R3, at(2026, 11, 18, 17, 0), "login"), ev(R3, at(2026, 11, 18, 17, 30), "logout"),
}
sit = P.Sittings(journal, ME, nil, NOW)
eq(#sit, 2, "a reload joins two sessions; an hour's gap doesn't")
eq(sit[1].sessions .. " " .. (sit[1].stop - sit[1].start), "2 " .. hm(2, 0), "the joined sitting: 2 sessions, 2h")
t = P.Tally(sit, { now = NOW, parts = parts, oldest = at(2026, 11, 18, 14, 0) })
eq(#t.days, 1, "the journal starts today: one day")
eq(t.days[1].sessions, 2, "two sittings today")
eq(t.longest.seconds, hm(2, 0), "the longest sitting runs across the reload")
eq(t.busiest.hour, 14, "busiest hour 2 PM (the first of the equal hours)")

-- An empty journal: nothing breaks, nothing is made up.
sit = P.Sittings({}, ME, nil, NOW)
eq(#sit, 0, "no sittings")
t = P.Tally(sit, { now = NOW, parts = parts, oldest = P.Oldest({}) })
eq(#t.days, 1, "just today")
eq(t.days[1].seconds .. " " .. t.week.seconds .. " " .. t.month.seconds, "0 0 0", "nothing played")
eq(t.busiest, nil, "no busiest hour")
eq(t.busiestDay, nil, "no busiest day")
eq(t.longest, nil, "no longest sitting")
eq(P.Shares(t, 1)[1], 0, "the strip is all 0")
eq(#P.Sittings(nil, ME), 0, "no journal at all: nothing")
eq(P.Oldest({ { at = 5 }, { at = 3 }, { nope = true }, { at = 0 / 0 } }), 3, "the oldest event")

-- The week: Monday's midnight to now. A Sunday sitting isn't this week's.
journal = {
  ev(S1, at(2026, 11, 15, 20, 0), "login"), ev(S1, at(2026, 11, 15, 21, 0), "logout"),
  ev(S2, at(2026, 11, 16, 0, 0), "login"), ev(S2, at(2026, 11, 16, 0, 30), "logout"),
}
t = P.Tally(P.Sittings(journal, ME, nil, NOW), { now = NOW, parts = parts, oldest = at(2026, 11, 1, 12, 0) })
eq(t.week.seconds .. " " .. t.week.sessions, hm(0, 30) .. " 1", "this week: only Monday's")
eq(t.month.seconds, hm(1, 30), "30 days: both")
eq(#t.days, 18, "18 days back to the 1st")
eq(t.busiestDay, 7, "busiest weekday: Sunday")

-- Daylight saving, forward: 01:30 to 03:30 local on 8 March is one real hour; 2 AM never happens.
local SNOW = at(2026, 3, 9, 12, 0)
local start, stop = at(2026, 3, 8, 1, 30), at(2026, 3, 8, 3, 30)
eq(stop - start, hm(1, 0), "the clock went forward: an hour passed")
t = P.Tally({ { start = start, stop = stop, sessions = 1 } }, { now = SNOW, parts = parts, oldest = start })
eq(#t.days, 2, "two days")
eq(t.days[2].seconds, hm(1, 0), "Sunday the 8th: one hour")
eq(t.hours[7][2] .. " " .. t.hours[7][3] .. " " .. t.hours[7][4], "1800 0 1800", "1 AM 30m, 2 AM nothing, 3 AM 30m")
eq(t.days[1].start - t.days[2].start, hm(23, 0), "that day was 23 hours long")
eq(parts(t.days[1].start).hour .. " " .. parts(t.days[2].start).hour, "0 0", "both days start at local midnight")
eq(P.StartOfDay(at(2026, 3, 8, 3, 30), parts), at(2026, 3, 8, 0, 0), "the day's start from after the change")

-- Daylight saving, back: 00:30 to 02:30 local on 1 November is three real hours; 1 AM happens twice.
local FNOW = at(2026, 11, 2, 12, 0)
start = at(2026, 11, 1, 0, 30)
stop = FALL + hm(0, 30) -- 02:30 local, after the clock went back
eq(parts(stop).hour .. ":" .. parts(stop).min, "1:30", "(that's the second 1:30)")
stop = stop + hm(1, 0)
eq(stop - start, hm(3, 0), "the clock went back: three hours passed")
t = P.Tally({ { start = start, stop = stop, sessions = 1 } }, { now = FNOW, parts = parts, oldest = start })
eq(t.days[2].seconds, hm(3, 0), "Sunday the 1st: three hours")
eq(t.hours[7][1] .. " " .. t.hours[7][2] .. " " .. t.hours[7][3], "1800 7200 1800",
  "12 AM 30m, 1 AM twice (2h), 2 AM 30m")
eq(t.days[1].start - t.days[2].start, hm(25, 0), "that day was 25 hours long")
eq(P.StartOfDay(stop, parts), at(2026, 11, 1, 0, 0), "the day's start from after the change")
-- A session across midnight on a change night stays on its days.
t = P.Tally({ { start = at(2026, 10, 31, 23, 0), stop = FALL + hm(0, 10), sessions = 1 } },
  { now = FNOW, parts = parts, oldest = at(2026, 10, 31, 0, 0) })
eq(t.days[3].seconds .. " " .. t.days[2].seconds, hm(1, 0) .. " " .. hm(2, 10), "Saturday 1h, Sunday 2h 10m")

-- The view in Ryna's window. ---------------------------------------------------------------------------
F.Install()
_G.UnitGUID = function(unit) if unit == "player" then return ME end end
_G.UnitName = function(unit) if unit == "player" then return "Brennic" end end
_G.UnitFullName = function(unit) if unit == "player" then return "Brennic", "Ashgrove" end end
_G.GetNormalizedRealmName = function() return "91" end
_G.UnitClass = function() return "Paladin", "PALADIN" end
_G.UnitRace = function() return "Human", "Human" end
_G.UnitFactionGroup = function() return "Alliance" end
_G.UnitSex = function() return 3 end
_G.UnitLevel = function() return 17 end
_G.UnitXP = function() return 1200 end
_G.UnitXPMax = function() return 4800 end
_G.GetMoney = function() return 100 end
_G.GetRealZoneText = function() return "Westfall" end
_G.GetSubZoneText = function() return "" end
_G.GetInventoryItemLink = function() return nil end
_G.C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() return nil end }
_G.C_AddOns = { GetAddOnMetadata = function() return "0.0.0" end }

local DAY = 86400
local N0 = F.now
local OLD = "1000-0000000A"
_G.RynaDB = {
  schema = 1, settings = {}, characters = {},
  journal = {
    { type = "level", char = ME, level = 17, at = N0 - DAY, playedTotal = 36000, session = OLD },
    -- Three days ago: a 2h 05m session; two days ago, one with no logout (40m to its last event).
    { type = "session", kind = "login", char = ME, at = N0 - 3 * DAY, session = "A-0000000A" },
    { type = "session", kind = "logout", char = ME, at = N0 - 3 * DAY + 2 * 3600 + 300, session = "A-0000000A" },
    { type = "session", kind = "login", char = ME, at = N0 - 2 * DAY, session = "B-0000000A" },
    { type = "zone", char = ME, at = N0 - 2 * DAY + 2400, session = "B-0000000A" },
    { type = "session", kind = "login", char = ALT, at = N0 - 2 * DAY, session = "C-0000000B" },
    { type = "session", kind = "logout", char = ALT, at = N0 - 2 * DAY + 9000, session = "C-0000000B" },
  },
}
_G.date = os.date -- this computer's zone: the checks below hold in any

local core = {}
F.LoadAddon(CORE, "Ryna_Core", core)
F.Fire("ADDON_LOADED", "Ryna_Core")
local cns = {}
F.LoadAddon(CHRON, "Ryna_Chronicle", cns)
F.Fire("ADDON_LOADED", "Ryna_Chronicle")
F.Fire("PLAYER_LOGIN")
F.Fire("PLAYER_ENTERING_WORLD", true, false)
F.DropTimers()

local Wn = core.Window
SlashCmdList.RYNACHRONICLE("history")
local f = Wn.frame
eq(Wn.Selected(), "history", "History")
eq(f.title:GetText(), "History", "on Levels its title is History")
check(f.filter:IsShown(), "History has a view picker")
eq(f.filter:GetText(), "Levels", "Levels first")
eq(f.rows[1].cols[1]:GetText(), "17", "Levels as before")

SlashCmdList.RYNACHRONICLE("play")
eq(Wn.Selected(), "history", "/chronicle play opens History")
eq(Wn.ctx.filter, "play", "on Play")
eq(f.title:GetText(), "History › Play", "the title says the view")
eq(f.filter:GetText(), "Play", "the picker says Play")
eq(f.headCells[1]:GetText() .. "|" .. f.headCells[2]:GetText() .. "|" .. f.headCells[3]:GetText(),
  "Day|Played|Sessions", "Play's columns")

local rows = Wn.views.history.rows
eq(rows[1].cells[1], "Today", "the first day: today")
eq(rows[2].cells[1], "Yesterday", "then yesterday")
check(rows[3].cells[1]:find(", %d%d%d%d%-%d%d%-%d%d$") ~= nil,
  "then the weekday and date: " .. tostring(rows[3].cells[1]))
local days, total, sessions = 0, 0, 0
local heading, weekdays, axis
for i, r in ipairs(rows) do
  if r.day then
    days = days + 1
    total = total + r.day.seconds
    sessions = sessions + r.day.sessions
    if r.day.seconds == 0 then eq(r.cells[2], "not played", "a day with no play says so") end
    check(r.bars and r.bars[2] and r.bars[2].max > 0, "every day has a drawable bar")
  elseif r.header then
    heading = i
  elseif r.weekday then
    weekdays = (weekdays or 0) + 1
    eq(#r.strips[2].values, 24, Wn.Strip(r.cells[1]) .. ": 24 hours")
  elseif r.axis then
    axis = r
  end
end
check(days >= 4 and days <= 5, "today back to the journal's oldest day (" .. days .. " days)")
eq(total, 2 * 3600 + 300 + 2400, "the days hold both sessions of this character, and no one else's")
check(sessions >= 2 and sessions <= 3, "two sessions (three if one crossed midnight here)")
eq(rows[heading].cells[1], "When you play, by hour", "the heading over the hours")
eq(weekdays, 7, "seven weekday rows")
eq(rows[heading + 1].cells[1], "Monday", "Monday first")
eq(rows[heading + 7].cells[1], "Sunday", "Sunday last")
eq(axis.strips[2].labels[1] .. " " .. axis.strips[2].labels[7] .. " " .. axis.strips[2].labels[13] .. " "
  .. axis.strips[2].labels[19], "12 AM 6 AM 12 PM 6 PM", "the hours under the blocks")
local maxShare = 0
for _, r in ipairs(rows) do
  if r.weekday then for _, v in ipairs(r.strips[2].values) do if v > maxShare then maxShare = v end end end
end
eq(maxShare, 1, "the busiest weekday-hour is a full block")

-- What is drawn: a day's bar, and a weekday's strip in the same column.
local dayRow = f.rows[4]
check(dayRow.bars[2]:IsShown(), "a day row draws its bar")
local function drawnRow(pred)
  for r = 1, Wn.visible do
    if f.rows[r]:IsShown() and f.rows[r].data and pred(f.rows[r].data) then return f.rows[r] end
  end
end
Wn.state.offset = heading - 2
Wn.Draw()
local monday = drawnRow(function(d) return d.weekday == 1 end)
check(monday and monday.strips and monday.strips[2]:IsShown(), "Monday's strip is drawn")
check(monday and not monday.bars[2]:IsShown(), "and no bar on it")
local axisRow = drawnRow(function(d) return d.axis end)
eq(axisRow and axisRow.strips[2].labels[7]:GetText(), "6 AM", "the hours row is drawn under them")
Wn.state.offset = 0
Wn.Draw()

-- The tiles and the footer.
eq(f.tiles[1].label:GetText(), "This week", "tile 1: this week")
eq(f.tiles[2].label:GetText() .. " " .. f.tiles[2].value:GetText(), "Last 30 days 2h 45m", "tile 2: the 30 days")
eq(f.tiles[3].label:GetText(), "Busiest", "tile 3: busiest")
check(f.tiles[3].sub:GetText():find("^around %d+ [AP]M$") ~= nil, "around an hour: " .. f.tiles[3].sub:GetText())
eq(f.tiles[4].label:GetText() .. " " .. f.tiles[4].value:GetText(), "Longest sitting 2h 05m", "tile 4: the longest")
eq(f.footer:GetText(), "From the journal in your saved file, which keeps 30 days; times are on this computer's clock.",
  "the footer")
eq(cns.Window.PlayedText(3 * 3600 + 300), "3h 05m", "hours and two-digit minutes")
eq(cns.Window.PlayedText(42 * 60), "42m", "minutes alone")
eq(cns.Window.HourName(0) .. " " .. cns.Window.HourName(12) .. " " .. cns.Window.HourName(18), "12 AM 12 PM 6 PM",
  "the hours' names")

-- The rows rebuild as the session under way counts on (the minute), and Levels comes back.
local builds = Wn.views.history.builds
F.clock = F.clock + 60
Wn.Draw()
eq(Wn.views.history.builds, builds + 1, "a minute later Play is rebuilt")
SlashCmdList.RYNACHRONICLE("levels")
eq(Wn.ctx.filter, nil, "/chronicle levels: back on Levels")
eq(f.title:GetText(), "History", "the title too")

check(#F.chat == 0, "nothing in chat: " .. table.concat(F.chat, " / "))
check(core.errors.count == 0, "no errors caught: " .. tostring(core.errors.last))
print(string.format("chronicle play: %d checks, %d failed", checks, failures))
os.exit(failures == 0 and 0 or 1)
