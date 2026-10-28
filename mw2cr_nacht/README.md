# Nacht der Untoten replica for MW2 Campaign Remastered

A script mod for [h2-mod](https://github.com/fedddddd/h2-mod) that builds Nacht der Untoten's layout out of props
and collision already loaded in whatever MW2CR level you're on: start room, Help room behind its debris
door, stairs blocked by debris, two rooms upstairs, and boarded windows.

This is step one: the building only. Zombies, points, wall buys and the box come next.

## Install

1. Copy `mod/nacht` into your MW2CR folder's `mods` folder so you have `mods/nacht/scripts/nacht.gsc`.
2. Start MW2CR through h2-mod, load the mod (Mods menu, or console: `loadmod mods/nacht`).
3. Start any campaign level and stand somewhere flat and open.
4. Open the console (`~`) and type `set nacht_build 1`. You're moved into the start room.
   `set nacht_clear 1` removes it.

## What to expect

It only uses what the level has loaded, so it looks different on each level and won't look like the
original's textures or lighting. The console prints which prop it picked for the walls, how many pieces it
spawned, and whether the walls are solid. If something's wrong, send that output.

Enemies on the level will still attack while you build; `notarget` / `god` in the console help if cheats
are allowed.

## Changing the layout

Edit `layout.py` (rooms, windows, doors) or `nacht_template.gsc` (the builder), then run
`python3 mw2cr_nacht/layout.py` to regenerate `mod/nacht/scripts/nacht.gsc`.
