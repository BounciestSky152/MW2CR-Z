# MW2CR Zombies

A zombies mode for **Call of Duty: Modern Warfare 2 Campaign Remastered**, made with
[h2-mod](https://github.com/alicealys/h2-mod). You start inside **Nate's Sports Bar & Grill** on Wolverines!, you
can't leave, and zombies come in endless rounds.

## What's in it

- **Main menu:** an MW2CR ZOMBIES button on the campaign menu with PLAY (shows your best round), BUILD MODE (Nate's
  without zombies, for placing things in peace) and HOW TO PLAY.
- **Build menu (you design Nate's):** nothing is for sale until you place it. In game press Esc and pick
  **BUILD MENU**:
  - **PLACE A WEAPON:** pick any weapon the level has loaded and a price (250-5000), then aim. A live preview
    follows your aim: on a wall it hangs upright along it, on a table or the floor it lies flat. Fire or Use
    places it, Aim turns it 15 degrees, Melee cancels.
  - **PLACE A BARRIER:** pick a price, then aim through a doorway. The preview is a pile of chairs that sizes
    itself to the doorway. Once the zombies are on, you can't get past it until you buy it.
  - **MOVE SOMETHING / REMOVE SOMETHING:** aim at something you placed (it lights up), then Fire or Use.
  - **STARTING WEAPON:** what you start with (it hits half again as hard as normal).
  - **REMOVE EVERYTHING**, and in build mode **START ZOMBIES**.

  Everything you place is saved in your config and comes back next game.
- **Rounds:** endless, more and tougher zombies each round, a short break between rounds.
- **Zombies:** the level's Russian soldiers with their guns hidden and a knife in hand (if the game has a knife
  model loaded). They walk upright (runners run) straight at you and are re-aimed at you four times a second.
  Walkers first, runners from round 3, tough brutes from round 6. A zombie that's stuck for 4 seconds, or can't
  find a way in, climbs in somewhere you aren't looking.
- **Getting hit:** three hits and you're down (a brute's hit counts double); four seconds without a hit and
  you've recovered.
- **Points:** 500 to start, +10 per hit, +60 per kill, +100 headshot kill, +130 knife kill.
- **Starting pistol:** MW2CR has no M1911 (it was never in MW2), so it's the USP .45 if the level has it,
  otherwise the M9, unless you pick another in the build menu.
- **Power-ups:** Max Ammo, Double Points, Insta-Kill, Kaboom (kills every zombie) and Bonus Points.
- **No loading video:** the Wolverines! loading video and its sound are skipped (h2-mod's plain loading screen
  shows instead) and the level starts by itself once loaded.
- **Best round** is saved.

The level's own soldiers, vehicles and loose weapons are removed. There are no perks.

## Install (Windows)

1. Get h2-mod: put `h2-mod.exe` in your MW2CR folder (next to `MW2CR.exe`) and run it once, saying Yes to
   updates.
2. Double-click `install.bat` (or drag your MW2CR folder onto it). It copies the mod to `mods\zombies` and
   removes the old `mods\nacht`.
3. Start `h2-mod.exe`, open **Mods**, load **MW2CR Zombies** (the game restarts).
4. **MW2CR ZOMBIES → PLAY.**

The level starts you inside Nate's automatically. No console commands are needed. Start with **BUILD MODE** to
place your wall weapons and barriers, then pick START ZOMBIES in the build menu.

## If something's wrong

Everything the mod does is printed to the console (`~`) with `[zombies]` in front: the weapons and spawners it
found, Nate's outline and how many indoor spots it has, the streamed zones it loads around Nate's, and what you
placed. Send those lines with what you saw.

## Files

- `mod/zombies/scripts/zombies.gsc` - the game mode
- `mod/zombies/ui_scripts/zombies/__init__.lua` - the menu
- `mod/zombies/info.json` - name in h2-mod's Mods list
- `install.bat` - the installer
- `test_zombies.py` - `python3 -m pytest mw2cr_zombies` checks every engine call against MW2CR's function lists
