# MW2CR Zombies

A zombies mode for **Call of Duty: Modern Warfare 2 Campaign Remastered**, made with
[h2-mod](https://github.com/alicealys/h2-mod). You start inside **Nate's Sports Bar & Grill** on Wolverines!, you
can't leave, and zombies come in endless rounds.

## What's in it

- **Main menu:** an MW2CR ZOMBIES button on the campaign menu with PLAY (shows your best round), SET UP NATE'S
  AGAIN and HOW TO PLAY.
- **Rooms:** you start in Nate's dining area. A barricade of chairs in the kitchen doorway costs 3000 to clear.
- **Rounds:** endless, more and tougher zombies each round, a short break between rounds.
- **Zombies:** the level's Russian soldiers, walking (runners run) straight at you without ducking, taking
  cover or shooting, guns hidden. Walkers first, runners from round 3, tough brutes from round 6. They spawn
  out of sight outside Nate's and come in through the doors; if they can't find a way in, they climb in
  somewhere you aren't looking.
- **Getting hit:** three hits and you're down (a brute's hit counts double); four seconds without a hit and
  you've recovered. Each hit jolts you, shakes the screen and flashes it red.
- **Points:** 500 to start, +10 per hit, +60 per kill, +100 headshot kill, +130 knife kill.
- **Starting pistol:** the M1911 if the game has one (MW2CR doesn't seem to), otherwise the level's M9; it hits
  half again as hard as normal.
- **Dining area:** a FAL lying on a table (1250) and Quick Revive (1500: the hit that would take you down revives
  you instead, once per purchase).
- **Kitchen:** three more wall weapons (1000 / 1200 / 1500), the ammo crate (1000, refills everything including
  grenades) and the mystery box (950). Weapons for sale are outlined; buying one you have refills its ammo for
  half price.
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
3. Start `h2-mod.exe`, open **Mods**, load **MW2CR Zombies** (the game restarts).
4. **MW2CR ZOMBIES → PLAY.**

The level starts you inside Nate's automatically. No console commands are needed. The first game asks for two
quick steps (look at the table for the FAL and hold Use; stand in the kitchen doorway facing the kitchen and hold
Use); after that it remembers. The console then shows a `[zombies] LAYOUT ...` line: send it and it gets built in.

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
