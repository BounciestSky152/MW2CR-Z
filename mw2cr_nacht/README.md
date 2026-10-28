# Wolverines! Zombies for MW2 Campaign Remastered

A mod for [h2-mod](https://github.com/alicealys/h2-mod): endless Nacht-style zombie rounds on Wolverines! (level
`invasion`). You start inside Nate's Sports Bar & Grill and can't leave it, except to go to CRB Financial.

- **Menu:** a WOLVERINES! ZOMBIES button on the campaign main menu, with PLAY and SET UP AGAIN.
- **The level:** Wolverines! is emptied of its soldiers and vehicles. Zombies appear out of sight around the
  buildings and walk in through the real doors.
- **Play area:** Nate's, CRB Financial and the route you walked between them. Walking out anywhere else
  puts you back.
- **Points:** 500 to start, +10 per hit, +60 per kill, +100 headshot kill, +130 knife kill.
- **Buying:** four wall weapons hung on the buildings' walls (200 / 600 / 1200 / 1200, half price for ammo)
  and a mystery box in Nate's (950). The box also gets every weapon the zombies carry.
- **Power-ups:** Max Ammo, Double Points, Insta-Kill and Kaboom (kills everything, +400).
- **Getting hit:** a jolt toward the zombie, screen shake and a red flash.

MW2CR has no zombie models, so the zombies are the level's own Russian soldiers told to ignore everything
and rush you; they only hurt you up close.

## Install (Windows)

1. Install h2-mod: put `h2-mod.exe` in your MW2CR folder and run it once (say Yes to updates).
2. Copy `mod/nacht` into your MW2CR folder's `mods` folder, so you have `mods/nacht/scripts/nacht.gsc`.
3. Start h2-mod, open **Mods** on the main menu and load **Wolverines! Zombies** (the game restarts).
4. **WOLVERINES! ZOMBIES → PLAY.** The first time, the level is emptied and you set up the play area:
   go inside Nate's Sports Bar & Grill, hold Use for 2 seconds where you want to start, then walk to
   CRB Financial the way you want to be allowed to go and hold Use for 2 seconds inside. That's saved;
   later games start you in Nate's straight away. If the way is blocked, the level runs with cheats on,
   so `noclip` in the console (`~`) lets you fly there.

Console: `set nacht_here 1` starts zombies in the building you're standing in (any level),
`set nacht_clear 1` stops. The older prop-built Nacht replica is still there: `set nacht_play 1`.

## If something's wrong

Everything the mod does is printed to the console with `[nacht]` in front: the weapons and spawners it
found, how big the play area came out, where the wall buys and box went. After setting up, the console
also prints a `[nacht] SETUP invasion ...` line: send that one and it can be built into the mod, so nobody
has to set up again.

## Changing it

The game script is generated: edit `nacht_template.gsc` (and `layout.py` for the replica's rooms), then run
`python3 mw2cr_nacht/layout.py` to regenerate `mod/nacht/scripts/nacht.gsc`. The menu is
`mod/nacht/ui_scripts/nacht/__init__.lua`. `python3 -m pytest mw2cr_nacht` checks every engine call against
MW2CR's function lists.
