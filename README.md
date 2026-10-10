# WaW ⇄ BO1 Portal Bridge

Open a Portal-style portal in any **Call of Duty: World at War** or **Black Ops** zombies map, walk through it, and
come out in another zombies map, in either game. Your round, points, perks and guns come with you.

```
 ┌──────────── World at War ────────────┐                 ┌───────────── Black Ops ──────────────┐
 │ Der Riese, round 12                  │                 │ Kino der Toten, round 12             │
 │  hold USE+MELEE ─► portal opens      │                 │  pb_state dvar read on load          │
 │  walk through   ─► state encoded     │                 │  round / points / perks / guns       │
 │  println("[PORTAL_BRIDGE] TRAVEL …") │                 │  restored, portal flash fades out    │
 └──────────────┬───────────────────────┘                 └──────────────▲───────────────────────┘
                │ console.log                                            │ BlackOps.exe +set pb_state … +devmap zombie_theater
                ▼                                                        │
        ┌─────────────────────────── Portal Bridge app (python) ─────────┴──┐
        │ tails both games' logs ─► translates weapon names ─► closes WaW ─► │
        │ launches BO1 with the state on the command line                   │
        └───────────────────────────────────────────────────────────────────┘
```

## Read this first: what "seamless" means here

WaW and BO1 are two separate programs, and no script can move a running match from one into the other. The
bridge gets as close as it can:

- **Between the two games:** the screen fades to portal-blue, the bridge closes one game and launches the other
  straight into the destination map, and your loadout is restored on arrival. You don't touch a menu, but you do
  sit through the game's normal startup and loading screen.
- **Between maps of the same game:** this goes through the bridge the same way by default. If you set
  `"same_game_changelevel": true`, the game swaps maps itself without restarting (see
  [Configuration](#configuration)).

**I haven't been able to test this in-game.** The scripts were written from knowledge of the stock zombies
scripts. The Python side has tests, and the GSC is statically checked for balanced brackets, functions that
don't exist, and syntax the T4/T5 compilers can't handle. The first time you build the mod, watch for compile
errors. The engine calls most likely to need adjusting are listed under
[Troubleshooting](#troubleshooting).

## What carries over

| Carries over | How |
|---|---|
| Round | The new map starts round 1, which then ends at once and rolls over into your round, with zombie health set to match. Dog, monkey and thief rounds are rescheduled after the jump. |
| Points | Exact. |
| Perks | Given back if the destination map has that perk's machine and the game knows the perk. PhD Flopper doesn't exist in WaW, so it's lost going BO1→WaW. |
| Weapons + ammo | Translated by `config/weapons.json`: the exact counterpart first (Thompson → `thompson_zm`), then a look-alike (Thompson → AK-74u on Kino). Pack-a-Punched guns stay upgraded when the destination has the upgraded version. Any gun with no match is refunded (1000 points by default). |
| Not carried | Grenades, monkeys, equipment, the knife, and map progress (power, doors, Easter eggs). |

Co-op: every connected player's state is saved, but the bridge can only relaunch the game on **your** PC, so it's
really meant for solo play.

## Requirements

- Windows, with WaW and/or BO1 installed (Steam versions are assumed; other installs just need different paths).
- Python 3.9 or newer. No extra packages are needed.
- One of these for each game:
  - **Mod Tools** (official WaW Mod Tools / Black Ops Mod Tools), or
  - **Plutonium** (T4 for WaW, T5 for BO1), which loads loose script files without building anything.

## Install

### 1. Generate the scripts

```bat
python -m portal_bridge build
```

This writes `dist/waw/` and `dist/bo1/`, each containing a Mod Tools layout and a Plutonium bundle. The map list,
weapon aliases and gameplay settings are baked in from `config/`, so run it again whenever you change those files.

### 2a. Mod Tools route (do this once per game)

1. Copy `dist/<game>/mods/portal_bridge/` into the game's `mods/` folder
   (e.g. `...\Call of Duty World at War\mods\portal_bridge\`).
2. Copy the stock `raw\maps\_zombiemode.gsc` from your Mod Tools install into `mods\portal_bridge\maps\`, then add
   the hook:
   ```bat
   python -m portal_bridge patch-zombiemode "C:\...\mods\portal_bridge\maps\_zombiemode.gsc"
   ```
   This adds `maps\_portal_bridge::main();` as the first line of `main()` and keeps a `.bak` copy of the original.
3. Open the Mod Tools **Launcher → Mod Builder**, pick `portal_bridge`, tick **Build mod.ff**, and build. The
   generated `mod.csv` already lists the files.

### 2b. Plutonium route

Copy `dist/<game>/plutonium/scripts/sp/portal_bridge.gsc` into Plutonium's script folder for that game. At the
time of writing that's `%LOCALAPPDATA%\Plutonium\storage\t4\scripts\sp\` for WaW and `...\storage\t5\scripts\sp\`
for BO1, but check Plutonium's docs because the path has changed before. Then switch the launch command in your
`bridge.local.json` to the bootstrapper (example below).

### 3. Point the bridge at your games

Create `config/bridge.local.json`. Git ignores it, and it's merged over `bridge.json`:

```json
{
  "games": {
    "waw": { "game_dir": "D:/SteamLibrary/steamapps/common/Call of Duty World at War" },
    "bo1": { "game_dir": "D:/SteamLibrary/steamapps/common/Call of Duty Black Ops" }
  }
}
```

Plutonium example. The bootstrapper's arguments may differ between Plutonium versions:

```json
{
  "games": {
    "waw": {
      "launch": ["%LOCALAPPDATA%/Plutonium/bin/plutonium-bootstrapper-win32.exe", "t4sp", "{game_dir}", "-lan",
                 "+set", "developer_script", "1", "+set", "logfile", "2", "{state_args}", "+devmap", "{map}"],
      "process_names": ["plutonium-bootstrapper-win32.exe"]
    }
  }
}
```

If the bridge never notices your portals, the game is writing `console.log` somewhere other than the paths in
`games.<game>.logs`. Search your drive for `console.log` after a session and add that path.

## Play

```bat
python -m portal_bridge run --start waw:nazi_zombie_factory
```

Leave that window open while you play.

| Action | Control |
|---|---|
| Open a portal in front of you | Hold **USE + MELEE** for 1 second, or bind a key once in the console: `bind p "set pb_open 1"` |
| Open a portal aimed at a specific map | `set pb_open zombie_moon` in the console |
| Change destination | Stand near the portal and tap **USE** |
| Travel | Walk through the portal |

The portal stays open for 90 seconds. Opening a new one replaces your old one. If nothing happens 20 seconds after
you step through, the game unfreezes and tells you the bridge isn't running.

Other commands:

```bat
python -m portal_bridge maps                         :: list destinations
python -m portal_bridge launch bo1:zombie_theater    :: just start a map with the mod
python -m portal_bridge run --dry-run                :: log what would happen without closing/starting games
python -m portal_bridge simulate "PB1|n=1|src=waw:nazi_zombie_factory|dst=bo1:zombie_moon|r=10|p0=5000~-~zombie_thompson@20@140~zombie_thompson"
```

## Configuration

`config/maps.json` lists every destination. Set `"enabled": false` on DLC you don't own. Custom maps work if they
load `maps\_zombiemode` (so the hook runs) and you add them to this file.

`config/weapons.json` holds the weapon name translation table. `waw` / `bo1` are a gun's real internal names, and
`*_fallback` entries are look-alikes to use when the destination map doesn't have it.

The `gameplay` section of `config/bridge.json` is baked into the scripts by `build`:

| Key | Default | |
|---|---|---|
| `portal_cost` | 0 | Points it costs to open a portal |
| `portal_duration` | 90 | Seconds before an unused portal fizzles (0 = never) |
| `weapon_refund` | 1000 | Points per gun that has no equivalent at the destination |
| `perks_require_machine` | true | Only return perks whose machine exists on the destination map |
| `same_game_changelevel` | false | Same-game trips use the engine's `changelevel` instead of a restart |
| `allow_combo` | true | Allow the USE + MELEE gesture (the `pb_open` dvar always works) |
| `custom_fx` | "" | Path of your own portal effect (e.g. `fx/portal_bridge/portal_blue`) if you make one in the effects editor. Without it the ring uses the stock power-up glow. |
| `portal_width` / `portal_height` / `portal_fx_points` / `portal_distance` / `enter_radius` / `bridge_timeout` | | Portal size, ring density, spawn distance, walk-through radius, and how long to wait for the bridge |

## How it works

- `gsc/shared/maps/_portal_bridge.gsc` is the core script, identical in both games. It handles opening the portal
  (a ring of FX on entities linked to a spinning hub), the HUD, encoding and decoding state, and applying round,
  points, perks and weapons on arrival.
- `gsc/<game>/maps/_portal_bridge_game.gsc` holds the parts that differ per game: how to give a perk, which perks
  exist, score functions, and special-round bookkeeping.
- `maps/_portal_bridge_catalog.gsc` is generated from `config/`.
- `portal_bridge/` is the Python app. It tails the console logs for `[PORTAL_BRIDGE] TRAVEL PB1|…`, translates the
  weapons, kills the current game, and launches the destination with `+set pb_state "PB1|…"`. The state format is
  documented in `portal_bridge/state.py`. It sticks to characters the engine's console parser leaves alone (no
  spaces, quotes, `;` or `//`).

The game has no way to write files or open sockets, so it reports through `println`. That's why the default launch
arguments turn on `developer`, `developer_script` and `logfile`. A side effect is that developer mode shows script
errors from *any* script as pop-ups.

## Troubleshooting

- **Compile error about an unknown function.** The engine and stock-script calls I'm least sure of are:
  - `changelevel` in each adapter's `pb_engine_changelevel`. If it errors, delete that line; it's only used when
    `same_game_changelevel` is on.
  - `perk_hud_create` / `perk_think` (WaW adapter) and `give_perk` (BO1 adapter). Open the stock
    `_zombiemode_perks.gsc` and match whatever it calls after the perk-bottle animation.
- **Portal opens but is invisible.** That map doesn't load the `powerup_on` effect. Add another loaded effect key to
  `pb_portal_fx_keys()` in the adapter, or set `custom_fx`.
- **Arrived with the starting pistol only.** None of the weapon candidates exist on that map. Check the map's
  `include_weapon(...)` list and add the real names to `config/weapons.json`.

## Development

```bash
python -m pytest
```
