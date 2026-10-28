# Wolverines! Zombies

A zombies mode for **Call of Duty: Modern Warfare 2 Campaign Remastered**, made with
[h2-mod](https://github.com/alicealys/h2-mod). You start inside **Nate's Sports Bar & Grill** on Wolverines!, you
can't leave, and zombies come in endless rounds.

## What's in it

- **Main menu:** a ZOMBIES button on the campaign menu with PLAY (shows your best round) and HOW TO PLAY.
- **Rounds:** endless, more and tougher zombies each round, a short break between rounds.
- **Zombies:** the level's Russian soldiers, walking (runners run) straight at you without ducking, taking
  cover or shooting, guns hidden. Walkers first, runners from round 3, tough brutes from round 6. They spawn
  out of sight outside Nate's and come in through the doors; if they can't find a way in, they climb in
  somewhere you aren't looking.
- **Getting hit:** three hits and you're down (a brute's hit counts double); four seconds without a hit and
  you've recovered. Each hit jolts you, shakes the screen and flashes it red.
- **Points:** 500 to start, +10 per hit, +60 per kill, +100 headshot kill, +130 knife kill.
- **Starting pistol:** the level's pistol (the M9 on Wolverines!), hitting half again as hard as normal.
- **Wall weapons:** four guns hung on Nate's walls with an outline (200 / 600 / 1200 / 1200; half price for
  ammo).
- **Quick Revive** (1500): the hit that would take you down revives you instead, once per purchase.
- **Ammo crate** (1000, refills everything including grenades) and **mystery box** (950).
- **Power-ups:** Max Ammo, Double Points, Insta-Kill, Kaboom (kills every zombie) and Bonus Points.
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

The level starts you inside Nate's automatically. No console commands are needed.

## If something's wrong

Everything the mod does is printed to the console (`~`) with `[zombies]` in front: the weapons and spawners it
found, Nate's outline and how many indoor spots it has, where each wall weapon, perk, the ammo crate and the
box went. Send those lines with what you saw.

## Files

- `mod/zombies/scripts/zombies.gsc` - the game mode
- `mod/zombies/ui_scripts/zombies/__init__.lua` - the menu
- `mod/zombies/info.json` - name in h2-mod's Mods list
- `install.bat` - the installer
- `test_zombies.py` - `python3 -m pytest mw2cr_zombies` checks every engine call against MW2CR's function lists
