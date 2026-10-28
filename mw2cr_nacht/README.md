# Burger Town Zombies for MW2 Campaign Remastered

A mod for [h2-mod](https://github.com/alicealys/h2-mod): endless Nacht-style zombie rounds inside Burger Town on
Wolverines! (level `invasion`).

- **Menu:** a BURGER TOWN ZOMBIES button on the campaign main menu, with PLAY and FORGET SAVED SPOT.
- **The level:** Wolverines! is emptied of its soldiers and vehicles. Zombies appear out of sight around
  Burger Town and walk in through its real doors.
- **Points:** 500 to start, +10 per hit, +60 per kill, +100 headshot kill, +130 knife kill.
- **Buying:** four wall weapons hung on Burger Town's walls (200 / 600 / 1200 / 1200, half price for ammo)
  and a mystery box (950). The box also gets every weapon the zombies carry.
- **Power-ups:** Max Ammo, Double Points, Insta-Kill and Kaboom (kills everything, +400).
- **Getting hit:** a jolt toward the zombie, screen shake and a red flash.

MW2CR has no zombie models, so the zombies are the level's own Russian soldiers told to ignore everything
and rush you; they only hurt you up close.

## Install (Windows)

1. Install h2-mod: put `h2-mod.exe` in your MW2CR folder and run it once (say Yes to updates).
2. Copy `mod/nacht` into your MW2CR folder's `mods` folder, so you have `mods/nacht/scripts/nacht.gsc`.
3. Start h2-mod, open **Mods** on the main menu and load **Burger Town Zombies** (the game restarts).
4. **BURGER TOWN ZOMBIES → PLAY.** The first time, walk into Burger Town and hold Use for 2 seconds where
   you want to start; that spot is saved and later games start you there. If the way is blocked, the level
   runs with cheats on, so `noclip` in the console (`~`) lets you fly there.

Console: `set nacht_here 1` starts zombies in the building you're standing in (any level),
`set nacht_clear 1` stops. The older prop-built Nacht replica is still there: `set nacht_play 1`.

## If something's wrong

Everything the mod does is printed to the console with `[nacht]` in front: the weapons and spawners it
found, how many indoor and spawn spots it found around you, where the wall buys and box went. Send those
lines along with what you saw.

## Changing it

The game script is generated: edit `nacht_template.gsc` (and `layout.py` for the replica's rooms), then run
`python3 mw2cr_nacht/layout.py` to regenerate `mod/nacht/scripts/nacht.gsc`. The menu is
`mod/nacht/ui_scripts/nacht/__init__.lua`. `python3 -m pytest mw2cr_nacht` checks every engine call against
MW2CR's function lists.
