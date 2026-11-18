-- Play: when a character played, from the journal's sessions in the saved file (no new record): the
-- pure part of History › Play (Window.lua draws it). Nothing here calls the client; the local
-- calendar comes in as `parts`, a function(t) -> date("*t", t), so a test can give it any time zone.
--
-- Sessions. Every journal event carries its session ("<login unix>-<GUID hex>", one per PLAYER_LOGIN,
-- so a /reload starts a new one) and `at` (unix seconds). Chronicle writes a `session` event of kind
-- `login` at the start and `logout` at PLAYER_LOGOUT. A session runs from its login (else the time in
-- its id when that is within a day before its first event, else its first event) to its logout; the
-- game closed without one (a crash, a lost connection) ends it at its last event, and the session
-- under way now ends now. Sessions of the same character less than JOIN_GAP apart (a /reload, a quick
-- relog) are one sitting.
--
-- Days and hours are this computer's: each sitting is cut at every local hour boundary (the next one is
-- at t + 3600 - minutes and seconds past the hour, which holds across a daylight-saving change, since
-- those move the clock a whole hour at an hour boundary), and each piece is counted on its local day
-- and on its weekday and hour. A day is from its local midnight to the next (23 or 25 hours on the
-- days the clock changes); on the night the clock goes back the repeated hour is counted twice under
-- that hour, and on the night it goes forward the skipped hour has nothing. No offset is assumed: every
-- local field comes from `parts`.

local _, ns = ...
if ns.off then return end

local P = {}
ns.Play = P

P.JOIN_GAP = 120     -- seconds between one session's end and the next one's start that still join them
P.DAYS = 31          -- at most this many day rows (the journal keeps 30 days, plus today)

local function localParts(t)
  local ok, p = pcall(date, "*t", t)
  if ok and type(p) == "table" then return p end
  return nil
end
P.LocalParts = localParts

-- Monday 1 .. Sunday 7, from Lua's wday (Sunday 1 .. Saturday 7).
function P.Weekday(p)
  return ((tonumber(p.wday) or 1) + 5) % 7 + 1
end

-- The unix time of the local midnight that starts the day holding t. Starts from t less the hours,
-- minutes and seconds past midnight, then corrects by what that time reads as (on the day the clock
-- changes the first guess is an hour off: 23:00 the day before, or 01:00).
function P.StartOfDay(t, parts)
  parts = parts or localParts
  local p = parts(t)
  if not p then return nil end
  local function past(q) return (q.hour or 0) * 3600 + (q.min or 0) * 60 + (q.sec or 0) end
  local guess = t - past(p)
  for _ = 1, 4 do
    local q = parts(guess)
    if not q then return guess end
    if q.day ~= p.day then
      guess = guess + 86400 - past(q) -- still the day before: on to its end
    elseif past(q) ~= 0 then
      guess = guess - past(q)         -- past midnight already
    else
      return guess
    end
  end
  return guess
end

-- The local midnight starting the day before the one starting at `dayStart`.
function P.DayBefore(dayStart, parts)
  return P.StartOfDay(dayStart - 1, parts)
end

-- The time in a session id ("1762464000-0000000A"), or nil.
local function idTime(id)
  return tonumber(type(id) == "string" and id:match("^(%d+)%-") or nil)
end

-- A character's sittings from a journal: { { start, stop, sessions } } by start. `current` is the
-- running session's id (it ends at `now`).
function P.Sittings(journal, guid, current, now)
  local byId, order = {}, {}
  if type(journal) ~= "table" or guid == nil then return {} end
  for i = 1, #journal do
    local e = journal[i]
    if type(e) == "table" and e.char == guid and type(e.at) == "number" and e.at == e.at and e.session ~= nil then
      local id = e.session
      local s = byId[id]
      if not s then
        s = { id = id, first = e.at, last = e.at }
        byId[id] = s
        order[#order + 1] = s
      end
      if e.at < s.first then s.first = e.at end
      if e.at > s.last then s.last = e.at end
      if e.type == "session" then
        if e.kind == "login" and (s.login == nil or e.at < s.login) then s.login = e.at end
        if e.kind == "logout" and (s.logout == nil or e.at > s.logout) then s.logout = e.at end
      end
    end
  end
  local list = {}
  for _, s in ipairs(order) do
    local start = s.login
    if not start then
      -- The login event fell out of the journal (or was never written): the id's time, when it is a
      -- plausible login for this session (no more than a day before its first event).
      local t = idTime(s.id)
      start = (t and t <= s.first and s.first - t <= 86400) and t or s.first
    end
    local stop = s.logout or s.last
    if s.id == current and type(now) == "number" and now > stop then stop = now end
    if stop >= start then list[#list + 1] = { start = start, stop = stop, sessions = 1 } end
  end
  table.sort(list, function(a, b) return a.start < b.start end)
  local out = {}
  for _, s in ipairs(list) do
    local prev = out[#out]
    if prev and s.start - prev.stop <= P.JOIN_GAP then
      if s.stop > prev.stop then prev.stop = s.stop end
      prev.sessions = prev.sessions + 1
    else
      out[#out + 1] = s
    end
  end
  return out
end

-- Calls fn(from, to, p, dayStart) for each piece of [start, stop) inside one local hour, in order.
function P.Pieces(start, stop, parts, fn)
  parts = parts or localParts
  local t = start
  local guard = 0
  while t < stop and guard < 24 * 400 do
    guard = guard + 1
    local p = parts(t)
    if not p then return end
    local nextHour = t + 3600 - ((p.min or 0) * 60 + (p.sec or 0))
    if nextHour <= t then nextHour = t + 3600 end
    local to = math.min(stop, nextHour)
    fn(t, to, p, P.StartOfDay(t, parts))
    t = to
  end
end

-- Everything History › Play shows, from a character's sittings:
--   opts = { now, parts (default the computer's), oldest (the journal's oldest event: where the days
--   start) }
-- -> {
--   days = { { start (local midnight), parts, seconds, sessions } }, newest first, today back to the
--          day of `oldest` (at most P.DAYS);
--   hours = { [weekday 1..7] = { [hour+1] = seconds } }, over those days;
--   busiest = { seconds, weekday, hour } (the busiest weekday-hour), or nil;
--   busiestDay = the weekday with the most seconds, busiestHour = that weekday's busiest hour (0..23);
--   week = { seconds, sessions } since Monday's midnight; month = { seconds, sessions, days } over the
--   days; longest = { seconds, start } (the longest sitting, the part of it inside the days), or nil;
--   maxDay = the most seconds in a day }
function P.Tally(sittings, opts)
  opts = opts or {}
  local parts = opts.parts or localParts
  local now = opts.now or 0
  local today = P.StartOfDay(now, parts)
  local out = { days = {}, hours = {}, week = { seconds = 0, sessions = 0 },
    month = { seconds = 0, sessions = 0, days = 0 }, maxDay = 0 }
  for wd = 1, 7 do
    out.hours[wd] = {}
    for h = 1, 24 do out.hours[wd][h] = 0 end
  end
  if not today then return out end
  local first = P.StartOfDay(math.min(tonumber(opts.oldest) or now, now), parts) or today
  local byStart = {}
  local d = today
  for _ = 1, P.DAYS do
    local entry = { start = d, parts = parts(d), seconds = 0, sessions = 0 }
    out.days[#out.days + 1] = entry
    byStart[d] = entry
    if d <= first then break end
    d = P.DayBefore(d, parts)
    if not d then break end
  end
  local rangeStart = out.days[#out.days].start
  -- Monday's midnight of this week.
  local weekStart = today
  local wdToday = P.Weekday(parts(today) or { wday = 2 })
  for _ = 2, wdToday do weekStart = P.DayBefore(weekStart, parts) or weekStart end

  for _, s in ipairs(sittings) do
    local start, stop = math.max(s.start, rangeStart), math.min(s.stop, now)
    if stop > start then
      local touched, inWeek = {}, false
      P.Pieces(start, stop, parts, function(from, to, p, dayStart)
        local secs = to - from
        local day = byStart[dayStart]
        if day then
          day.seconds = day.seconds + secs
          if not touched[dayStart] then
            touched[dayStart] = true
            day.sessions = day.sessions + 1
          end
        end
        local wd, h = P.Weekday(p), (p.hour or 0) + 1
        out.hours[wd][h] = out.hours[wd][h] + secs
        out.month.seconds = out.month.seconds + secs
        if from >= weekStart then
          out.week.seconds = out.week.seconds + secs
          inWeek = true
        end
      end)
      out.month.sessions = out.month.sessions + 1
      if inWeek then out.week.sessions = out.week.sessions + 1 end
      local length = stop - start
      if not out.longest or length > out.longest.seconds then
        out.longest = { seconds = length, start = start }
      end
    end
  end
  for _, day in ipairs(out.days) do
    if day.seconds > 0 then out.month.days = out.month.days + 1 end
    if day.seconds > out.maxDay then out.maxDay = day.seconds end
  end
  local bestDay, bestDaySecs = nil, 0
  for wd = 1, 7 do
    local total = 0
    for h = 1, 24 do
      local secs = out.hours[wd][h]
      total = total + secs
      if secs > 0 and (not out.busiest or secs > out.busiest.seconds) then
        out.busiest = { seconds = secs, weekday = wd, hour = h - 1 }
      end
    end
    if total > bestDaySecs then bestDay, bestDaySecs = wd, total end
  end
  if bestDay then
    out.busiestDay = bestDay
    local bestHour, bestSecs = 0, -1
    for h = 1, 24 do
      if out.hours[bestDay][h] > bestSecs then bestHour, bestSecs = h - 1, out.hours[bestDay][h] end
    end
    out.busiestHour = bestHour
  end
  return out
end

-- A weekday's 24 shares for its strip: each hour's seconds over the busiest weekday-hour's.
function P.Shares(tally, weekday)
  local max = tally.busiest and tally.busiest.seconds or 0
  local out = {}
  for h = 1, 24 do
    local secs = tally.hours[weekday] and tally.hours[weekday][h] or 0
    out[h] = max > 0 and secs / max or 0
  end
  return out
end

-- The oldest `at` in a journal (any character: where the journal's days start), or nil.
function P.Oldest(journal)
  local oldest
  if type(journal) ~= "table" then return nil end
  for i = 1, #journal do
    local e = journal[i]
    if type(e) == "table" and type(e.at) == "number" and e.at == e.at and (oldest == nil or e.at < oldest) then
      oldest = e.at
    end
  end
  return oldest
end
