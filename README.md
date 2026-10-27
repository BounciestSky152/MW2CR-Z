# BO1 Zombies Portal

Open a Portal-style portal in any **Call of Duty: Black Ops** zombies map, walk through it, and come out in
another zombies map. Your round, points, perks and guns come with you.

```
 ┌──────────────────────────── Black Ops zombies ────────────────────────────┐
 │ Kino der Toten, round 12                                                  │
 │  hold USE+MELEE ─► portal opens                                           │
 │  walk through   ─► state saved in the pb_state dvar, changelevel          │
 │ Moon (or Five, Ascension, Call of the Dead, Shangri-La, a remake …)       │
 │  pb_state read on load ─► round / points / perks / guns restored,         │
 │  portal flash fades out                                                   │
 └───────────────────────────────────────────────────────────────────────────┘
```

## Read this first: what "seamless" means here

Travel happens inside the running game. When you step through, the script saves your state and changes the map
with `changelevel`: no restart, no profile check, and it takes as long as a normal level load. The Portal Bridge
app (`run`, below) is only needed for the launch/watch workflow, not for travel itself.

**This hasn't been run in-game yet.** Every stock function, field and weapon name the scripts use was checked
against dumps of the real BO1 zombies scripts, with file and line numbers. Those dumps are
[plutoniummod/t5-scripts](https://github.com/plutoniummod/t5-scripts). The Python side has tests, and the GSC is
statically checked for balanced brackets, functions that don't exist, and syntax the T5 compiler can't handle. The
first time you load it, watch for compile errors. The calls most likely to need adjusting are listed under
[Troubleshooting](#troubleshooting).

## What carries over

| Carries over | How |
|---|---|
| Round | The new map starts straight at your round. The round is set in the few seconds before round 1's first zombie spawns, the same way the game's own difficulty settings start later rounds. Zombie health, speed and spawn rate match that round. If that window is missed, round 1 is ended early instead. Dog and monkey rounds, which the game checks for an exact round number, are rescheduled so they still happen. |
| Points | Exact. |
| Perks | Given back if the destination map has that perk's machine and the game knows the perk. |
| Weapons + ammo | Mapped by `config/weapons.json` to what the destination map has: the exact counterpart first (e.g. `zombie_thompson`), then a look-alike (Thompson → AK-74u on Kino). Pack-a-Punched guns stay upgraded when the destination has the upgraded version. Any gun with no match is refunded (1000 points by default). |
| Not carried | Grenades, monkeys, equipment, the knife, and map progress (power, doors, Easter eggs). |

Co-op: every connected player's state is saved, but it's really meant for solo play.

## Requirements

- **Windows**, or **Linux / Steam Deck** through Proton. **On Linux, follow [docs/LINUX.md](docs/LINUX.md)
  instead of the install steps below.** It has a `linux-setup` command that detects Steam, Proton and Plutonium
  and writes the config for you.
- Black Ops. The Steam version is assumed; other installs just need different paths.
- Python 3.9 or newer. No extra packages are needed.
- One of these:
  - **Plutonium** (T5). It loads a single script file with no build step. This is the easiest route, and it
    reports travel through a small file instead of the console log.
  - **Mod Tools** (Black Ops Mod Tools). Black Ops also needs
    [LinkerMod](https://github.com/Nukem9/LinkerMod)'s `game_mod`, because stock `BlackOps.exe` doesn't load mods.

## Install (Windows)

### 1. Generate the scripts

```bat
python -m portal_bridge build
```

This writes `dist/bo1/`, containing a Mod Tools layout (`mods/portal_bridge/`) and a Plutonium layout
(`plutonium/storage/...`). The map list, weapon aliases and gameplay settings are baked in from `config/`, so run
it again whenever you change those files.

### 2a. Plutonium route

```bat
python -m portal_bridge install-plutonium
```

This copies the script to the folder Plutonium loads zombies scripts from, under `%LOCALAPPDATA%\Plutonium`, and
creates the `scriptdata` folder it writes to. Use `--plutonium-dir` if Plutonium is installed somewhere else.

| Script | Travel requests appear in |
|---|---|
| `storage\t5\raw\scripts\sp\portal_bridge.gsc` | `storage\t5\raw\scriptdata\portal_bridge_travel.txt` |

Maps you don't own are left out of the in-game destination list, and `install-plutonium` prints which ones it hid
(see [Configuration](#configuration)).

Then point the bridge at Plutonium in `config/bridge.local.json` (see step 3).

### 2b. Mod Tools route

1. Copy `dist/bo1/mods/portal_bridge/` into the game's `mods/` folder
   (e.g. `...\Call of Duty Black Ops\mods\portal_bridge\`).
2. Copy the stock `raw\maps\_zombiemode.gsc` from your Mod Tools install into `mods\portal_bridge\maps\`, then add
   the hook (all BO1 maps share one `_zombiemode.gsc`):
   ```bat
   python -m portal_bridge patch-zombiemode "C:\...\mods\portal_bridge\maps\_zombiemode.gsc"
   ```
   This adds `maps\_portal_bridge::main();` as the first line of `main()` and keeps a `.bak` copy of the original.
3. Open the Mod Tools **Launcher → Mod Builder**, pick `portal_bridge`, tick **Build mod.ff**, and build. The
   generated `mod.csv` already lists the files.
4. Install LinkerMod's `game_mod` (`launcher_ldr.exe` and `game_mod.dll` in `<BO1>\bin`). The default config
   starts BO1 through it.

### 3. Point the bridge at your game

Create `config/bridge.local.json`. Git ignores it, and it's merged over `bridge.json`:

```json
{
  "games": {
    "bo1": { "game_dir": "D:/SteamLibrary/steamapps/common/Call of Duty Black Ops" }
  }
}
```

Plutonium example:

```json
{
  "games": {
    "bo1": {
      "game_dir": "D:/SteamLibrary/steamapps/common/Call of Duty Black Ops",
      "vars": { "pluto_dir": "%LOCALAPPDATA%/Plutonium" },
      "cwd": "{pluto_dir}",
      "launch": ["{pluto_dir}/bin/plutonium-bootstrapper-win32.exe", "t5sp", "{game_dir}",
                 "-token", "{token}", "-lan", "{game_args}"],
      "game_args": ["+name", "Player", "+set", "zombiemode", "1", "{state_args}", "+devmap", "{map}"],
      "process_names": ["plutonium-bootstrapper-win32.exe"],
      "logs": [],
      "signal_files": ["{pluto_dir}/storage/t5/raw/scriptdata/portal_bridge_travel.txt"]
    }
  }
}
```

Run `python -m portal_bridge doctor` to check every path. On the Mod Tools route, if the bridge never notices your
portals, the game is writing `console.log` somewhere other than the paths in `games.bo1.logs`. Search for
`console.log` after a session and add that path.

## Play

```bat
python -m portal_bridge run --start bo1:zombie_theater
```

This starts the map with the mod loaded and keeps watching the game. Travel itself happens inside the game and
doesn't need it.

| Action | Control |
|---|---|
| Open a portal in front of you | Hold **USE + MELEE** for 1 second, or bind a key once in the console: `bind p "set pb_open 1"` |
| Open a portal aimed at a specific map | `set pb_open zombie_moon` in the console |
| Change destination | Stand near the portal and tap **USE** |
| Travel | Walk through the portal |

The portal stays open for 90 seconds. Opening a new one replaces your old one. If the in-game map change can't run
(for example `same_game_changelevel` is off) and the app isn't running, the game unfreezes 10 seconds after you
step through and tells you so.

Other commands:

```bat
python -m portal_bridge maps                         :: list destinations
python -m portal_bridge launch bo1:zombie_theater    :: just start a map with the mod
python -m portal_bridge run --dry-run                :: log what would happen without closing/starting games
python -m portal_bridge simulate "PB1|n=1|src=bo1:zombie_theater|dst=bo1:zombie_moon|r=10|p0=5000~-~zombie_thompson@20@140~zombie_thompson"
```

## Configuration

`config/maps.json` lists every destination: Kino der Toten, Five, Ascension, Call of the Dead, Shangri-La, Moon
and the four Rezurrection remakes (`zombie_cod5_*`). Maps you don't own (no `<map>.ff` anywhere under the game's
`zone/` folder) are left out of the in-game destination list, and `install-plutonium` prints which ones it hid. If
the game folder can't be read, all maps are listed. You can also set `"enabled": false` on a map to drop it
yourself. Custom maps work if they load `maps\_zombiemode` (so the hook runs) and you add them to this file.

`config/weapons.json` holds the weapon name table. `bo1` is a gun's real internal names, and `bo1_fallback`
entries are look-alikes to use when the destination map doesn't have it.

The `gameplay` section of `config/bridge.json` is baked into the scripts by `build`:

| Key | Default | |
|---|---|---|
| `portal_cost` | 0 | Points it costs to open a portal |
| `portal_duration` | 90 | Seconds before an unused portal fizzles (0 = never) |
| `weapon_refund` | 1000 | Points per gun that has no equivalent at the destination |
| `perks_require_machine` | true | Only return perks whose machine exists on the destination map |
| `same_game_changelevel` | true | Trips change the map in place (no restart, no profile prompt). Set false to always go through the bridge |
| `allow_combo` | true | Allow the USE + MELEE gesture (the `pb_open` dvar always works) |
| `portal_fx_points` | 24 | Points in the portal's oval ring |
| `custom_fx` | "" | Path of your own portal effect (e.g. `fx/portal_bridge/portal_blue`) if you make one in the effects editor. Without it the ring uses BO1's blue power-up glow, or the green one if the map doesn't load the blue. |
| `portal_width` / `portal_height` / `portal_distance` / `enter_radius` / `bridge_timeout` | | Portal size, spawn distance, walk-through radius, and how long to wait for the bridge |

## How it works

- `gsc/shared/maps/_portal_bridge.gsc` is the core script. It handles opening the portal (an upright, non-spinning
  oval ring of FX on entities), the HUD, encoding and decoding state, and applying round, points, perks and
  weapons on arrival.
- `gsc/bo1/maps/_portal_bridge_game.gsc` holds the BO1-specific parts: how to give a perk, which perks exist, and
  special-round bookkeeping.
- `build` generates two more files:
  - `maps/_portal_bridge_catalog.gsc`: the map list and settings, from `config/`. Maps you don't own are left out.
  - `maps/_portal_bridge_platform.gsc`: what differs between the Mod Tools and Plutonium builds. The Mod Tools
    build calls the stock zombies scripts directly and reports travel with `println`. The Plutonium build looks
    stock functions up at runtime with `getFunction`, since a loose script is compiled before any map's zombies
    scripts exist, and reports travel through Plutonium's `fs_*` file API.
- On a trip the script puts the state in the `pb_state` dvar and calls `changelevel`; the new map reads it on load.
  `portal_bridge/` is the Python app that launches the game and watches for `[PORTAL_BRIDGE] TRAVEL PB1|…` in the
  console log or the signal file. The script only writes that line when the in-game map change can't be used. The
  app then translates the weapons, closes the game, and relaunches the destination with `+set pb_state "PB1|…"`.
  The state format is documented in `portal_bridge/state.py`. It sticks to characters the engine's console parser
  leaves alone (no spaces, quotes, `;` or `//`).

On the Mod Tools route the game can't write files or open sockets, so it reports through `println`. That's why the
default Mod Tools launch arguments turn on `developer`, `developer_script` and `logfile`. A side effect is that
developer mode shows script errors from *any* script as pop-ups. Plutonium doesn't need any of that.

## Troubleshooting

- **Compile error about an unknown function.** The engine and stock-script calls I'm least sure of are:
  - `changelevel` in the generated platform file. If it errors, change `pb_engine_changelevel` in
    `portal_bridge/build.py` to `return false;`. Travel then goes through the bridge app instead.
  - The stock functions listed in `STOCK_CALLS` in `portal_bridge/build.py`, mainly `give_perk`. Open the stock
    `_zombiemode_perks.gsc` and match whatever it calls after the perk-bottle animation. On Plutonium a missing
    stock function is skipped instead of breaking the build.
- **Portal opens but is invisible.** That map doesn't load the `powerup_on_solo` or `powerup_on` effect. Add
  another loaded effect key to `pb_portal_fx_keys()` in the adapter, or set `custom_fx`.
- **Arrived with the starting pistol only.** None of the weapon candidates exist on that map. Check the map's
  `include_weapon(...)` list and add the real names to `config/weapons.json`.

## Development

```bash
python -m pytest
```
