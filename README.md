# Chronicle by Ryna

A mod of [Ryna](https://github.com/Ryna-Mods/ryna) for World of Warcraft: Forever. Records your characters for [ryna.io](https://ryna.io/wow): gear, bags and bank, quests, professions,
reputations, gold and played time, your guild's roster, the players you see, and your kills and loot.

- **It only records.** The Ryna app reads what it saved when you log out or `/reload`, and sends a
  summary to ryna.io, where you can look at it.
- **Every kind of record has its own setting** in Ryna's settings.
- A Chronicle section in Ryna's window shows what it has, in the game.

Nothing in chat, nothing done for you. It is the one Ryna mod that is on by default.

## Installing

Chronicle needs **Ryna Core** (the folder `Ryna_Core`). Get both one of these ways:

- **With the Ryna app** ([download](https://github.com/MaddisonM79/ryna_agent/releases/latest)),
  which installs them and keeps them up to date.
- **The bundle**: every Ryna addon in one zip, from
  [Ryna-Mods/ryna](https://github.com/Ryna-Mods/ryna/releases/latest).
- **By hand**: this repository's releases hold `Ryna_Chronicle-<version>.zip`; unzip it into
  `Interface/AddOns` beside `Ryna_Core`.

## Working on it

`Ryna_Chronicle/` is the addon. Its tests (`test/`) run it against a fake client and the real core
addon, the oldest one Chronicle claims to work with ([`core.json`](core.json)), which
`node scripts/core.mjs` fetches into `.core/`.

`test/fake_client.lua` is the fake client every Ryna addon's tests run against; the other
repositories carry copies of it.

```bash
scripts/check.sh
```

That is everything CI runs: luacheck, the strings (`tools/strings.mjs`: every string the code uses
is in `Locales/enUS.lua` and in each locale's template) and the tests. It needs Lua (5.1 is what the
game runs), [luacheck](https://github.com/lunarmodules/luacheck) and Node.

The core API level Chronicle needs is `## X-Ryna-API` in [`Ryna_Chronicle.toc`](Ryna_Chronicle/Ryna_Chronicle.toc);
its version is `## Version` there, and nowhere else. A release is a signed tag `vX.Y.Z` that matches
it; the bundle then names that release in its `bundle.json`
([how](https://github.com/Ryna-Mods/ryna/blob/main/RELEASING.md)).

## Where it came from

Chronicle was written in [MaddisonM79/ryna_agent](https://github.com/MaddisonM79/ryna_agent)
(`mods/wow/chronicle`), and its history up to 0.5.0 is there. Bugs and requests go to
[ryna_agent's issues](https://github.com/MaddisonM79/ryna_agent/issues).

## Licence

MIT.
