# Wolverines! Zombies

A zombies mode for **Call of Duty: Modern Warfare 2 Campaign Remastered**, made with
[h2-mod](https://github.com/alicealys/h2-mod). You start inside **Nate's Sports Bar & Grill** on Wolverines!, you
can't leave, and zombies come in endless rounds.

## What's in it

- **Main menu:** a ZOMBIES button on the campaign menu with PLAY (shows your best round), HOW TO PLAY and
  RESET START SPOT.
- **Rounds:** endless, more and tougher zombies each round, a short break between rounds.
- **Zombies:** walkers, faster runners from round 3, and tough brutes that hit harder from round 6. They spawn
  out of sight outside and come in through Nate's real doors.
- **Points:** 500 to start, +10 per hit, +60 per kill, +100 headshot kill, +130 knife kill.
- **Wall weapons:** four guns hung on Nate's walls (200 / 600 / 1200 / 1200; half price for ammo).
- **Perks:** Juggernog (2500, 2.5x health), Stamin-Up (2000, faster movement), Double Tap (2000, more damage),
  Quick Revive (1500, survive one killing hit).
- **Ammo crate** (1000, refills everything including grenades) and **mystery box** (950).
- **Power-ups:** Max Ammo, Double Points, Insta-Kill, Kaboom (kills every zombie) and Bonus Points.
- **Getting hit:** a jolt, screen shake and a red flash.
- **Best round** is saved.

The level's own soldiers and vehicles are removed. MW2CR has no zombie models, so the zombies are the level's
Russian soldiers told to ignore everything and rush you; they only hurt you up close. The guns are whatever
Wolverines! has loaded.

## Install (Windows)

1. Get h2-mod: put `h2-mod.exe` in your MW2CR folder (next to `MW2CR.exe`) and run it once, saying Yes to
   updates.
2. Double-click `install.bat` (or drag your MW2CR folder onto it). It copies the mod to `mods\zombies` and
   removes the old `mods\nacht`.
3. Start `h2-mod.exe`, open **Mods**, load **Wolverines! Zombies** (the game restarts).
4. **ZOMBIES → PLAY.**

The very first game, the mod doesn't know where Nate's is yet: walk into Nate's and hold **Use** for 2
seconds where you want to start. From then on you start there. No console commands are needed.

## If something's wrong

Everything the mod does is printed to the console (`~`) with `[zombies]` in front: the weapons and spawners it
found, how big Nate's came out, where each wall weapon, perk, the ammo crate and the box went. Send those
lines with what you saw. The first game also prints `[zombies] NATES x y z`: send that line and it can be
built into the mod so the walk-in step goes away for everyone.

## Files

- `mod/zombies/scripts/zombies.gsc` - the game mode
- `mod/zombies/ui_scripts/zombies/__init__.lua` - the menu
- `mod/zombies/info.json` - name in h2-mod's Mods list
- `install.bat` - the installer
- `test_zombies.py` - `python3 -m pytest mw2cr_zombies` checks every engine call against MW2CR's function lists
