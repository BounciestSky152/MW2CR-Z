# Nacht der Untoten for MW2 Campaign Remastered

A mod for [h2-mod](https://github.com/alicealys/h2-mod) that builds Nacht der Untoten's layout out of props
already loaded in an MW2CR level and runs a Nacht-style zombies mode in it.

- **Menu:** a NACHT DER UNTOTEN button on the campaign main menu, with a level picker.
- **Building:** start room, Help room behind its debris door, stairs blocked by debris, two rooms upstairs,
  boarded windows.
- **Zombies:** endless rounds, more and tougher each round. Zombies come to the windows, tear the boards
  off and climb in. Hold Use near a window to rebuild it (+10 per board).
- **Points:** 500 to start, +10 per hit, +60 per kill, +100 headshot kill, +130 knife kill.
- **Buying:** four wall weapons (200 / 600 / 1200 / 1200, half price for ammo), Help door and stairs debris
  (1000 each), mystery box (950).
- **Power-ups:** Max Ammo, Double Points, Insta-Kill and Kaboom (kills everything, +400).
- **Getting hit:** a jolt toward the zombie, screen shake and a red flash.

MW2CR has no zombie models, so the zombies are the level's own soldiers told to ignore everything and rush
you; they only hurt you up close. The weapons are whatever that level has loaded, so they differ per level.

## Install (Windows)

1. Install h2-mod: put `h2-mod.exe` in your MW2CR folder and run it once (say Yes to updates).
2. Copy `mod/nacht` into your MW2CR folder's `mods` folder, so you have `mods/nacht/scripts/nacht.gsc`.
3. Start h2-mod, open **Mods** on the main menu and load **Nacht der Untoten** (the game restarts).
4. Pick **NACHT DER UNTOTEN** on the main menu, then a level. Once the level lets you move, Nacht is built
   around you and round 1 starts.

Console alternatives (`~`): `set nacht_play 1` builds and starts here, `set nacht_build 1` only builds,
`set nacht_clear 1` stops and removes everything.

## If something's wrong

Everything the mod does is printed to the console with `[nacht]` in front: the props it picked, how many
pieces it placed, the weapons and spawners it found. Send those lines along with what you saw.

Known limits: zombies don't know about Nacht's walls (the level's path network doesn't include them), so
the mod nudges stuck zombies toward you and puts badly stuck ones back at a window. Levels whose start is
a cutscene or vehicle won't work from the menu.

## Changing it

Edit `layout.py` (rooms, windows, doors, wall-buy spots) or `nacht_template.gsc` (builder and zombies
mode), then run `python3 mw2cr_nacht/layout.py` to regenerate `mod/nacht/scripts/nacht.gsc`. The menu is
`mod/nacht/ui_scripts/nacht/__init__.lua`.
