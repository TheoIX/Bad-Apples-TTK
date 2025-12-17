# Bad Apples TTK

**Bad Apples TTK (BadApplesTTK)** is a lightweight boss kill-timer addon for the Vanilla/Turtle WoW (1.12 / Interface 11200) client.

It tracks your guild’s historical kill times per boss, shows an **internal countdown** based on your saved average, and (optionally) blends that with the live estimate from the **TimeToKill** addon.

---

## What it shows (4 rows)

When a tracked boss fight starts:

1. **Boss name**
2. **Last kill time** (and kill count `N`)
3. **Internal timer** (countdown from your saved average kill time)
4. **Blend timer** (average of internal remaining time + TimeToKill’s `GetTTK()` estimate, smoothed)

When the boss dies, it records that duration and updates:
- `lastKill`
- `avgKill` (running average, seeded by the default value)
- `kills` (count)

---

## Requirements

- ✅ Works standalone (internal timer only)
- ⭐ Optional: **TimeToKill** installed  
  If present, BadApplesTTK will call `TimeToKill.GetTTK()` and compute the blended ETA.  
  If not present (or no valid estimate yet), the Blend row will fall back to the internal timer.

---

## Installation

1. Download / clone this repo.
2. Place the folder into:

World of Warcraft\Interface\AddOns\BadApplesTTK\

markdown
Copy code

3. Ensure the folder contains:

BadApplesTTK.toc
BadApplesTTK.lua

markdown
Copy code

4. Restart the game (or `/reload`).

---

## How encounter detection works

BadApplesTTK uses a BigWigs-style engage scan:

- On entering combat (`PLAYER_REGEN_DISABLED`), it scans every **0.5s** for a boss from the internal database by checking:
- your `target`
- `raid1target` … `raid40target`
- or `party1target` … `party4target` (if not in a raid)

It only starts an encounter if the matching unit is **actually in combat** (`UnitAffectingCombat(unit)`).

A kill is recorded when the combat log announces the boss death (common “dies.” / “You have slain …!” formats).

---

## Slash commands

All commands use `/battk`:

- `/battk`  
Shows help

### Visibility
- `/battk show`
- `/battk hide`
- `/battk combathide on`  *(show only while in combat)*
- `/battk combathide off`

### Lock / move
- `/battk lock`   *(click-through / no dragging)*
- `/battk unlock` *(Shift-drag to move)*

### Toggle rows
- `/battk boss on|off`
- `/battk last on|off`
- `/battk internal on|off`
- `/battk blend on|off`

### Blend smoothing
- `/battk smooth <0.05-0.5>`  
Controls how “stable” the blended ETA is (default: `0.15`)

---

## Adding / editing bosses

Bosses are defined inside `BadApplesTTK.lua` in the `BossDefaults` table:

```lua
local BossDefaults = {
["Anub'Rekhan"] = 42,
["Patchwerk"] = 97,
...
}
Values are seconds.

These values act as seed averages (so your first recorded kill doesn’t start from zero).

Aliases (multi-boss encounters)
Some encounters have multiple “boss unit names” that should map into one timer (example: Four Horsemen).
These are handled in EncounterAlias:

lua
Copy code
local EncounterAlias = {
  ["Lady Blaumeux"] = "The Four Horsemen",
  ...
}
SavedVariables
This addon stores data in:

BadApplesTTKDB.Settings
lock/hide toggles + row visibility + smoothing

BadApplesTTKDB.Position
frame position

BadApplesTTKDB.BossStats[bossName]
per-boss stats:

kills

lastKill

avgKill

If you want to reset your data, delete the addon’s SavedVariables file for your character/account (standard WoW SavedVariables location).

Tips / troubleshooting
Timer not starting?

Make sure the boss name matches exactly what the game reports (UnitName) and exists in BossDefaults.

Ensure someone in the raid is targeting the boss during pull (scan uses raid targets).

Blend row empty?

TimeToKill isn’t installed, or it hasn’t produced a valid estimate yet (early in the fight it may be nil/0).

Frame won’t move?

Use /battk unlock, then Shift-drag the frame.

Roadmap ideas (optional)
Monster yell engage triggers (BigWigs-style RP pulls)

Zone-based auto enabling / disabling

Export/import boss averages

Per-difficulty or per-raid-size splits (if applicable on your server)

Credits / disclaimer
Inspired by the structure/patterns used in addons like TimeToKill and BigWigs.



