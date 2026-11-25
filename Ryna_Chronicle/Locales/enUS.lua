-- English (enUS): every string Chronicle by Ryna shows, keyed by the English text itself. `true` means "the
-- text is the key"; ns.L returns the key for anything no locale file translates, so English is
-- always the fallback. The other Locales/*.lua files are templates for translators, generated from
-- this one: after adding, changing or removing a string here, run (from the repository root)
--
--   node cores/wow/addon/tools/strings.mjs --templates
--
-- which rewrites them with the same keys, keeping every translation already in them. Without
-- --templates it only checks that this list matches what the code uses (L["..."] and N("...")).
-- Debug lines (ns.Debug) are English on purpose and are not listed. A key the core addon's
-- Locales/enUS.lua already has ("on", "never", ...) isn't repeated here: Chronicle's L falls back to it.

local _, ns = ...
if ns.off then return end
local L = ns.L

-- Status.lua
-- The status tab's census line: whether the census setting is on.
L["Census: on"] = true
L["Census: off"] = true
L["Character: %s, level %s"] = true
L["Character: not loaded yet"] = true
-- The panel's status: "Recorded: 212 items in bags and bank, 17 equipped, 12 quests in the log,
-- 340 completed, 48 guild members". The %s slots are the pairs below, in that order.
L["Recorded: %s, %d equipped, %s, %d completed, %s"] = true
L["%d item in bags and bank"] = true
L["%d items in bags and bank"] = true
L["%d quest in the log"] = true
L["%d quests in the log"] = true
L["%d guild member"] = true
L["%d guild members"] = true
-- The status tab's Chronicle line: "Chronicle: 41 creatures, 112 items" (kinds of creature killed and
-- kinds of item looted, lifetime, this character). %s: the pairs below.
L["Chronicle: %s, %s"] = true
L["Chronicle: off"] = true
L["%d creature"] = true
L["%d creatures"] = true
L["%d item"] = true
L["%d items"] = true
-- Name, level, class token, realm, realm id.
L["%s, level %s %s, realm %s (%s)"] = true
L["recorded: %d gear, %s (bank as of %s), %d active / %d completed quests"] = true
L["%d container slot"] = true
L["%d container slots"] = true
-- "2 professions, 9 reputations, played 41h, guild <name>".
L["%s, %s, played %s, guild %s"] = true
L["%d profession"] = true
L["%d professions"] = true
L["%d reputation"] = true
L["%d reputations"] = true
-- Played time in hours, and "played pending" before /played answers; "guild none".
L["%dh"] = true
L["pending"] = true
L["none"] = true
-- "3 characters, 1 guild on this account".
L["%s, %s on this account"] = true
L["%d character"] = true
L["%d characters"] = true
L["%d guild"] = true
L["%d guilds"] = true

-- Tooltip.lua: lines added to creature and item tooltips, the player's own numbers.
-- "Ryna: killed 43 (40 yours), last Elwynn Forest 2 hours ago": %d kills, %d my killing blows,
-- then the zone and how long ago ("%d hours ago", Status.lua). The second has no zone.
L["Ryna: killed %d (%d yours), last %s %s"] = true
L["Ryna: killed %d (%d yours), last %s"] = true
-- "Linen Cloth: 22 of 38 corpses (58%)": an item, how many corpses dropped it, corpses looted, percent.
L["%s: %d of %d corpses (%d%%)"] = true
-- "Ryna: looted 30 times (45), mostly from Kobold Vermin (22)": "%d times" (below), pieces in all,
-- the biggest source and how many times it dropped from there.
L["Ryna: looted %s (%d), mostly from %s (%d)"] = true
L["Ryna: looted %s (%d)"] = true
L["%d time"] = true
L["%d times"] = true
-- Under either, for a creature or item counted in more than one zone (or not where you are now):
-- "12 here (Westfall) · 43 in all": the count in the zone you're in, that zone, the count in all zones.
L["%d here (%s) · %d in all"] = true
-- Loot sources without a name of their own (%s: the game's id for it).
L["fishing"] = true
L["a container"] = true
L["creature %s"] = true
L["object %s"] = true
L["item %s"] = true

-- Tabs.lua
L["Recording"] = true
L["Census"] = true
-- The Census tab's first line.
L["Ryna never sends /who itself. When you type /who, the results are recorded as "
  .. "sightings, like players you see on nameplates or in chat."] = true
L["Record who I see in chat"] = true
L["Only who spoke, never what they said or in which channel."] = true
L["Take part in the census"] = true
L["Records other players you see (nearby, in chat, your group and your guild). "
  .. "Off: Ryna records only your own characters."] = true
L["Record other players in my group"] = true
L["Who was in your groups."] = true
L["Record players I see nearby"] = true
L["Players whose nameplates, target or mouseover you see: their level, class and guild, and where."] = true
-- Under "Record players I see nearby"; Shift+V is the game's default key for friendly nameplates.
L["The game shows nameplates for enemies only unless friendly nameplates are on "
  .. "(Shift+V). Ryna only sees nameplates the game draws."] = true
-- A button that turns the game's friendly nameplates on, and its text once they are on.
L["Turn friendly nameplates on"] = true
L["Friendly nameplates are on"] = true
L["About your own characters, Ryna records their gear, bags and bank, quests, "
  .. "professions, reputations, gold and played time, your guild's roster, and a 30-day journal of what "
  .. "you do. Other players are the Census tab's."] = true
L["The census keeps who was seen, never what they said. "
  .. "Its data is never sold or used for advertising."] = true
L["Record kills and loot"] = true
L["Counts the creatures you and your group kill, the experience they give and what you loot from them, "
  .. "as running totals on the character (not journal events). Off: nothing is counted, and the totals so "
  .. "far are kept."] = true
L["Show my numbers on tooltips"] = true
L["Adds your own kills and drops to creature and item tooltips: how many you killed, what they dropped "
  .. "for you and how often."] = true
L["Record the merchants I visit"] = true
L["When you open a merchant, records what that NPC sells and for how much, once per NPC each time you "
  .. "log in, for vendor prices on ryna.io. Merchants are NPCs: nothing here is about a player."] = true

-- Session.lua, Strip.lua, Window.lua: the session strip and the Chronicle window.
-- Durations: "under a minute", "2d 3h" (days, hours), "1h 12m" (hours, minutes), "12m" (minutes).
L["under a minute"] = true
L["%dd %dh"] = true
L["%dh %dm"] = true
L["%dm"] = true
-- The Status tab's session line: "Session: 42 kills, 3,120 XP/h" (experience per hour), or not started.
L["Session: not started"] = true
L["Session: %s, %s XP/h"] = true
L["%d kill"] = true
L["%d kills"] = true
-- The session strip, one line joined by " · ": "Kills 42 · 3,120 XP/h · 1g 20s/h · 2 quests · 1h 12m".
-- "%s/h" is an amount of money per hour ("1g 20s/h"); keep it short, the strip is one line.
L["Kills %s"] = true
L["%s XP/h"] = true
L["%s/h"] = true
L["%d quest"] = true
L["%d quests"] = true
-- The strip's tooltip: its title, then "Since 14:02 (1h 12m)" (the clock time the session started,
-- how long ago), then label / value rows ("Kills: 42 (35/h)").
L["Chronicle: this session"] = true
L["Since %s (%s)"] = true
L["Kills"] = true
L["%s (%s/h)"] = true
L["Experience"] = true
L["Levels gained"] = true
-- Money: the net change this session; "Gained / spent": "3g 10s / 1g 50s".
L["Money"] = true
L["Gained / spent"] = true
L["%s / %s"] = true
L["Quests turned in"] = true
L["Items looted"] = true
L["Deaths"] = true
-- The tooltip's list of creatures killed most this session: "Kobold Vermin   12 (480 XP)".
L["Top kills this session"] = true
L["%s (%s XP)"] = true
L["Click: Ryna's window. Right-click: lock or unlock."] = true
L["Shift-drag to move."] = true
-- Printed in chat ("Ryna: the session strip is locked. ...") when the strip is right-clicked.
L["the session strip is locked. Right-click it to unlock."] = true
L["the session strip is unlocked: Shift-drag to move it."] = true
-- The Recording tab: a heading over the strip and window settings, then those settings.
L["In game"] = true
L["Show the session strip"] = true
L["One line on screen with this session's kills, experience and money per hour, quests and time. "
  .. "Hover it for more; click it for Ryna's window."] = true
L["Lock the strip"] = true
L["Unlocked, Shift-drag moves it. Right-clicking the strip locks or unlocks it too."] = true
-- A button: the strip back to its default place (top of the screen).
L["Reset position"] = true
-- The Recording tab's button that opens Ryna's window (the core's one window, where Chronicle's
-- sections are), and the line under it.
L["Open Ryna's window"] = true
L["Also /chronicle. Your session, your characters, everything in their bags and banks, "
  .. "your kills with their drops, your loot and your levels."] = true
-- The Recording tab's setting for the tooltip line naming your other characters that hold an item.
-- The names in the example are made up.
L["Show which of my characters hold an item"] = true
L["One more line on item tooltips naming your other characters that hold it, and how many, in their "
  .. "bags or the bank, from your saved file: \"Alyra: 120 in the bank · Brennic: 34\"."] = true
-- Chronicle's sections in Ryna's window (its rail, under Me).
L["Session"] = true
L["Characters"] = true
L["Items"] = true
L["Loot"] = true
L["History"] = true
-- The Session section: the column heading over its numbers, "Since" (when the session started), and
-- the heading over this session's kills.
L["This session"] = true
L["Since"] = true
L["Kills this session"] = true
-- The Kills section's tiles (how many kinds of creature) and columns: creature, kills, experience,
-- the zone of the last kill, when ("2 hours ago").
L["Creatures"] = true
L["Creature"] = true
L["Last zone"] = true
L["Last"] = true
-- A creature row's tooltip: "Killed: 42 (30 yours)", "Last: Westfall, 2 hours ago", "Corpses looted: 40",
-- then "Drops" and per item "12 of 40 (30%)" (how many corpses dropped it; %% prints one %).
L["Killed"] = true
L["%s (%s yours)"] = true
L["%s, %s"] = true
L["Corpses looted"] = true
L["Drops"] = true
L["%d of %d (%d%%)"] = true
-- The Loot section's columns (and tiles): item, times looted, how many in all, where from, when.
L["Item"] = true
L["Looted"] = true
L["Count"] = true
L["From"] = true
-- Where loot came from, besides a creature's name and fishing: a chest, vein, herb or pool, or a
-- container item (a bag or box opened).
L["object"] = true
L["container"] = true
L["From: %s"] = true
-- The History section's columns (and tiles): the level, the date it was reached, the time played at it, and the total
-- played time when it was reached. "before the journal": reached more than 30 days ago (no date).
L["Level"] = true
L["Reached"] = true
L["Time at the level"] = true
L["Played when reached"] = true
L["before the journal"] = true
-- History's tiles: the time played in all, "pending" (core) until /played answers.
L["Played"] = true
-- The footers: where the numbers came from and how old they are. %s: a character's name, then
-- "2 hours ago".
L["Counted in game since you logged in; a /reload keeps it."] = true
L["Counted in game for %s, the character you're on."] = true
L["From your saved file: %s as of %s, its last logout."] = true
L["an unknown time"] = true
L["From the journal's level-ups (it keeps 30 days) and /played."] = true
-- History's two views (its picker): Levels (the levels table) and Play (when the character played), and
-- the header's title with a view picked, "History › Play".
L["Levels"] = true
L["Play"] = true
L["%s › %s"] = true
-- History › Play: its columns (the day, the time played that day over a bar, how many sessions), the
-- days ("Today", "Yesterday", else "Thursday, 2026-11-13"), a day with no play inside the 30 days, and a
-- time played: "3h 05m" (hours, then minutes as two digits).
L["Day"] = true
L["Sessions"] = true
L["Today"] = true
L["Yesterday"] = true
L["not played"] = true
L["%dh %02dm"] = true
-- The weekdays, where the client has no name of its own for one (Monday first: the hours grid's rows).
L["Monday"] = true
L["Tuesday"] = true
L["Wednesday"] = true
L["Thursday"] = true
L["Friday"] = true
L["Saturday"] = true
L["Sunday"] = true
-- The hours grid: its heading, and the hours of the day on a 12-hour clock ("12 AM" is midnight, "12 PM"
-- noon, "6 AM", "6 PM"), under the grid and in "around 6 AM".
L["When you play, by hour"] = true
L["12 AM"] = true
L["12 PM"] = true
L["%d AM"] = true
L["%d PM"] = true
-- History › Play's tiles: the time played this week (since Monday) and how many sessions; the last 30
-- days and on how many days; the busiest weekday "around 6 AM"; the longest sitting and its day.
L["This week"] = true
L["%d session"] = true
L["%d sessions"] = true
L["Last 30 days"] = true
L["on %d day"] = true
L["on %d days"] = true
L["Busiest"] = true
L["around %s"] = true
L["Longest sitting"] = true
L["From the journal in your saved file, which keeps 30 days; times are on this computer's clock."] = true
-- /chronicle with a core too old for the window (printed only when typed).
L["the Ryna addon here is too old for its window. Update it from the Ryna companion app."] = true
-- /ryna help's line for the window's command. Keep /ryna chronicle, /chronicle and the section words
-- (session, characters, items, kills, loot, zones, history, levels, play) in English: they are what the
-- player types. Levels and Play are History's two views.
L["/ryna chronicle (or /chronicle): Ryna's window; /chronicle session, characters, items, "
  .. "kills, loot, zones or history opens that section, and levels or play History's view"] = true
-- Chronicle by zone. The zone picker on Kills and Loot: every zone, the zone you're in ("This zone
-- (Westfall)"; plain "This zone" when the game hasn't said), each zone, and "Earlier travels": what
-- was counted before Ryna kept zones (a lifetime of places you went before).
L["All zones"] = true
L["This zone (%s)"] = true
L["This zone"] = true
L["Earlier travels"] = true
-- Earlier travels explained (a tooltip). The second once something was counted in more than the eight
-- zones Ryna keeps per creature or item, whose smallest zones then join the earlier ones.
L["counted before Ryna kept zones"] = true
L["counted before Ryna kept zones, or in other zones"] = true
-- Kills and Loot with a zone picked: the footer's first sentence (%s: a date and time, or "not yet"),
-- or Earlier travels' own footer.
L["Counted by zone since %s."] = true
L["not yet"] = true
L["Earlier travels: counted before Ryna kept zones, or in zones past the eight it keeps."] = true
-- Kills with a zone picked: the column with the creature's kills in all zones; a tile with the kills
-- placed in this zone from the player's own combat logs (by the Ryna companion app).
L["In all"] = true
L["From your combat logs"] = true
-- A creature's or item's tooltip: "By zone", then per zone "12 (4 placed from your combat logs)", or
-- for loot "22 (31 pieces)": times looted, then how many in all.
L["By zone"] = true
L["%s (%s placed from your combat logs)"] = true
L["%s (%s pieces)"] = true
-- The Zones section: its columns (the zone, kills, kinds of creature killed, items looted, pieces
-- looted, quests turned in, deaths, time spent there), its tiles, a row's tooltip ("First here: <date>",
-- "Last here: 2 hours ago") and its click, and its footer (%s: dates, or "not yet").
L["Zones"] = true
L["Pieces"] = true
L["Quests"] = true
L["Time"] = true
L["Time spent"] = true
L["Quests done"] = true
L["First here"] = true
L["Last here"] = true
L["Click to see its kills."] = true
L["Time, quests and deaths since %s; kills and loot by zone since %s."] = true

-- Characters.lua
-- The Characters section: its columns over every character, its tiles, "now" (the character you're
-- on, as "last seen"), and "Mining 75" (a profession and its rank).
L["Character"] = true
L["Gold"] = true
L["Professions"] = true
L["Last seen"] = true
L["now"] = true
L["%s %s"] = true
-- All characters: the played column's text with the character's share of the account's time played,
-- "1d 4h · 73%" (%% prints one %); the tiles' small lines: "highest level 17", "all on Maddiep" (all the
-- gold is on that character; %s is its first name) and "across 3 characters" (time played).
L["%s · %d%%"] = true
L["highest level %d"] = true
L["all on %s"] = true
L["across %d characters"] = true
-- One character's detail: the headings of its groups and the rows under "Character".
L["Class"] = true
L["Guild"] = true
L["Zone"] = true
L["Talents"] = true
L["Gear"] = true
L["Reputations"] = true
L["None recorded yet."] = true
-- A tile: the time played at the current level ("3h 12m at this level"); a tooltip's "Level 17 Paladin".
L["%s at this level"] = true
L["Level %s %s"] = true
L["Click for this character's gear, professions and reputations."] = true
L["From your saved file: each character as of its last logout; the one you're on is live."] = true
-- One character's Quests (the detail's picker: Character, Quests): the column heading's counts, "14 active
-- · 4 ready to turn in"; the Progress column; a heading row with its count, "Zephras Isle (6)"; the last
-- group, quests saved before the addon recorded each quest's heading; "ready" on a full progress bar (every
-- objective done); a quest with no title saved, "quest 86012"; an empty log.
L["%d active · %d ready to turn in"] = true
L["Progress"] = true
L["%s (%d)"] = true
L["Picked up before this was recorded"] = true
L["ready"] = true
L["quest %s"] = true
L["Unknown quest"] = true
L["No quests in this character's log."] = true
-- A quest row's tooltip: "Level 10"; an objective with no text saved, "Objective 2"; a done objective,
-- "Kobold Vermin slain: 10/10 (done)"; and the line under them.
L["Level %s"] = true
L["Objective %d"] = true
L["%s (done)"] = true
L["Every objective is done: ready to turn in."] = true
L["No objectives to count were saved for this quest."] = true
-- The Quests footer for another character: "From your saved file, as Alyra-Dawnmere last logged out, 4 days
-- ago." (%s: the character, then how long ago); when that time isn't known.
L["From your saved file, as %s last logged out, %s."] = true
L["an unknown time ago"] = true
-- Equipment slots, where the client has no name of its own for one.
L["Ammo"] = true
L["Head"] = true
L["Neck"] = true
L["Shoulder"] = true
L["Shirt"] = true
L["Chest"] = true
L["Waist"] = true
L["Legs"] = true
L["Feet"] = true
L["Wrist"] = true
L["Hands"] = true
L["Finger"] = true
L["Trinket"] = true
L["Back"] = true
L["Main Hand"] = true
L["Off Hand"] = true
L["Ranged"] = true
L["Tabard"] = true

-- Items.lua
-- The tooltip line naming your other characters that hold an item: "Alyra: 120 in the bank · Brennic:
-- 34 · 2 more". Each part is "<name>: <how many>"; "154 (120 in the bank)" when some are in bags too.
L["%s: %s"] = true
L["%s (%s in the bank)"] = true
L["%s in the bank"] = true
L["%d more"] = true
-- The Items section: columns, tiles, the tooltip's "34 in bags · 120 in the bank (as of 2 days ago)".
L["Total"] = true
L["In bags"] = true
L["In the bank"] = true
L["%s in bags"] = true
L["%s in the bank (as of %s)"] = true
L["Kinds of item"] = true
L["Bank read"] = true
L["Nothing in the bags or bank yet. Each character's are recorded at login."] = true
-- Its footers. %s: how long ago ("2 days ago"), a character's name, or "never: open the bank once".
L["From your saved file: bags as of each character's last login, the bank as of its last visit."] = true
L["never: open the bank once"] = true
L["Bags as they are now; the bank as of your last visit (%s)."] = true
L["From your saved file: %s's bags as of %s, the bank as of %s."] = true
-- One character's sheet (the detail's picker: Character, Talents, Spells, Stats, Quests). Talents: a spec's
-- heading ("Spec 1 (active)", "Spec 2"), joined to a tree's ("Spec 1 (active) · Discipline · 14 points"); a
-- talent with no name saved, "spell 14521"; the columns; a tree with none taken; the record's talent text
-- before the sheet was recorded, and the line under it; a character whose sheet isn't recorded yet.
L["Spells"] = true
L["Stats"] = true
L["Spec %s (active)"] = true
L["Spec %s"] = true
L["%s · %s points"] = true
L["%s · %s"] = true
L["No talents taken."] = true
L["spell %s"] = true
L["Talent"] = true
L["Rank"] = true
L["Each talent shows once this character logs in with this version of Chronicle."] = true
L["Not recorded yet: log in on this character to read its sheet."] = true
-- Spells: a spell's rank column when it has no rank but is passive; the trainer's group, "At the trainer:
-- Brother Joshua, 2 days ago" (who, how long ago), or "the class trainer" when its name wasn't saved; the
-- trainer's group with nothing left to learn, or never visited; the columns (a spell or service, its rank,
-- the level it's learned at, its cost).
L["Passive"] = true
L["At the trainer"] = true
L["At the trainer: %s, %s"] = true
L["the class trainer"] = true
L["Nothing left to learn there on that visit."] = true
L["Visit your class trainer to see what you can learn next."] = true
L["Spell"] = true
L["Cost"] = true
-- Stats: the character frame's stats ("Fire resistance", "Fire spell damage"; a percentage "6.4%"; mana
-- regen "21 per 5 s", per five seconds), then the groups after them, and durability's "lowest: Linen Boots".
L["Strength"] = true
L["Agility"] = true
L["Stamina"] = true
L["Intellect"] = true
L["Spirit"] = true
L["Holy"] = true
L["Fire"] = true
L["Nature"] = true
L["Frost"] = true
L["Shadow"] = true
L["Arcane"] = true
L["Power"] = true
L["Health"] = true
L["Armor"] = true
L["%s resistance"] = true
L["Attack power"] = true
L["Ranged attack power"] = true
L["%s spell damage"] = true
L["Healing"] = true
L["Melee crit"] = true
L["Ranged crit"] = true
L["Spell crit"] = true
L["Dodge"] = true
L["Parry"] = true
L["Block"] = true
L["%s%%"] = true
L["Mana regen (casting)"] = true
L["Mana regen (not casting)"] = true
L["%s per 5 s"] = true
L["Not recorded yet: stats are read out of combat, on this character."] = true
L["Skills"] = true
L["Currencies"] = true
L["Other"] = true
L["Rested experience"] = true
L["Hearthstone"] = true
L["Honorable kills"] = true
L["Durability"] = true
L["lowest: %s"] = true

-- Dungeon runs (RunView.lua, RunDisplay.lua, RunSummary.lua, Dungeons.lua, Tabs.lua). "%sk" and "%sm" are
-- thousands and millions ("21.4k"); a run's clock is "24:10"; "%s paused" follows it.
L["Runs"] = true
L["Time inside"] = true
L["Worth"] = true
L["Click to close its runs."] = true
L["Click to see its runs."] = true
L["Click for its summary."] = true
L["Dungeon"] = true
L["Fastest"] = true
L["Median"] = true
L["Fastest against median"] = true
L["XP an hour"] = true
L["Last run"] = true
L["Dungeons"] = true
L["No dungeon runs recorded yet. A run is recorded each time this character enters a dungeon or raid."] = true
L["From your saved file. Runs are kept from the Chronicle release that adds them; the newest 100 "
  .. "per character, older ones as totals."] = true
L["The live run display is now: %s."] = true
L["The live run display is off: choose /ryna runs strip or /ryna runs card first."] = true
L["The run display is showing an example: drag it where you want it, then type /ryna runs test again."] = true
L["The example run is gone."] = true
L["The run display can't be drawn on this client."] = true
L["/ryna runs: your dungeon runs; /ryna runs strip, card or off: the live display; "
  .. "/ryna runs test: place it; /ryna runs new: end this run and start a new one; "
  .. "/ryna runs forget split or all: forget saved runs"] = true
-- The run display's right-click menu, its tooltip line, and /ryna runs new.
L["Start a new run"] = true
L["Right-click: start a new run."] = true
L["Right-click the run again within %d seconds to end it and start a new one."] = true
L["That run is closed. A new one starts here, or when you next walk in."] = true
L["No dungeon run is open."] = true
L["/ryna runs forget split: the pieces an old version cut off a visit (its last part stays); "
  .. "/ryna runs forget all: every saved run of this character"] = true
L["No run here looks like part of a visit that was cut up."] = true
L["This character has no saved runs."] = true
L["Forgot %s. What ryna.io already has stays there."] = true
L["This forgets %s saved for this character, for good. Type it again within %d seconds to do it."] = true
L["%d run"] = true
L["%d runs"] = true
L["The Deadmines (an example)"] = true
L["Open in Ryna"] = true
L["Ryna can track this run"] = true
L["Time, experience, kills, bosses and what the loot is worth. Show it while you play?"] = true
L["Change it any time in /ryna, on the Recording tab, or with /ryna runs strip, card or off."] = true
L["%sk"] = true
L["%sm"] = true
L["%d of %d bosses"] = true
L["%d boss"] = true
L["%d bosses"] = true
L["instance %s"] = true
L["%s paused"] = true
L["Back inside within %s to carry on"] = true
L["%d drop"] = true
L["%d drops"] = true
L["%s xp/hr"] = true
L["Level %d · %d%% · +%d%% this run"] = true
L["none at the level cap"] = true
L["not counted at the level cap"] = true
L["%s · %s/hr"] = true
L["In combat"] = true
L["%s of %s"] = true
L["coin · vendor · auction"] = true
L["boss %s"] = true
L["wipe"] = true
L["fighting"] = true
L["best %s"] = true
L["Your first run here. Bosses are listed as you meet them."] = true
L["No full clear here yet to compare with."] = true
L["solo"] = true
L["%d player"] = true
L["%d players"] = true
L["run %d · %s"] = true
L["so far · %s"] = true
L["best · was %s"] = true
L["best"] = true
L["%s on your best"] = true
L["left early"] = true
L["no experience at the level cap"] = true
L["%s/hr"] = true
L["median %s"] = true
L["no auction prices"] = true
L["not counted"] = true
L["no wipes"] = true
L["%d wipe"] = true
L["%d wipes"] = true
L["You did"] = true
L["healing · %s damage"] = true
L["healing"] = true
L["damage · %s healing"] = true
L["damage"] = true
L["%s x%d"] = true
L["%s auction"] = true
L["%s vendor"] = true
L["%d more drop"] = true
L["%d more drops"] = true
L["level %d to %d"] = true
L["%d quest turned in"] = true
L["%d quests turned in"] = true
L["wear %d%%"] = true
L["Go back in within %s and this run carries on."] = true
L["Dungeon runs"] = true
L["Record dungeon runs"] = true
L["Each time you enter a dungeon or raid: the time inside, experience, kills, bosses, loot and what it "
  .. "was worth, deaths and wear, kept per character for Dungeons in Ryna's window. Needs kills and loot on."] = true
L["While inside, show the run as:"] = true
L["Drag it where you want it. /ryna runs test shows it with example numbers, to place it outside a dungeon."] = true
L["Show a summary when I leave"] = true
L["Each time you walk out of the instance, the run so far against your earlier runs there. It goes "
  .. "when you go back in."] = true
L["My damage and healing on the summary"] = true
L["Your own damage done and healing done over the run, from the game's damage meter."] = true
-- The live display's three choices (the first-time notice's buttons and the setting).
L["A thin strip"] = true
L["A card"] = true
L["Neither"] = true
-- Loot rolls on a run (RunView.lua, RunSummary.lua): under each boss, the item and who won it with
-- their choice and roll ("Sam Hammiche · Need 23"); on hover, every roll. The six choices are the
-- game's loot roll buttons'; "No roll yet" is someone who hasn't chosen.
L["Need"] = true
L["Off-spec"] = true
L["Transmog"] = true
L["Greed"] = true
L["No roll yet"] = true
L["Pass"] = true
-- A player's own roll: "Brennic (you)"; "You" when the game gave no name.
L["%s (you)"] = true
L["You"] = true
L["Someone"] = true
L["Won"] = true
L["Everyone passed"] = true
L["Rolling"] = true
L["No winner recorded"] = true
L["%d more item rolled for"] = true
L["%d more items rolled for"] = true
