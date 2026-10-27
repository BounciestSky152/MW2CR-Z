# Portal Bridge on Linux

Black Ops is a Windows game, so on Linux it runs under **Proton** (Steam's Wine). The Portal Bridge app is plain
Python and runs natively. It starts and stops the game through Proton for you.

This works on any desktop distro and on the **Steam Deck** (in Desktop Mode). The bridge needs **Python 3.9 or
newer** and nothing else; there's nothing to install with pip.

> **Status:** the Linux tooling (Steam detection, launch commands, process handling, config generation) is covered
> by automated tests against a fake Steam install. Nobody has run the whole thing on a real Linux machine with the
> game yet. The steps below follow how Proton, Steam and Plutonium are documented to behave. Anything not
> confirmed is marked *(unverified)*, and [What's verified](#whats-verified) lists them all in one place.

## Contents

1. [Pick a method](#1-pick-a-method)
2. [Prepare the game (every method)](#2-prepare-the-game-every-method)
3. [Plutonium method (recommended)](#3-plutonium-method-recommended)
4. [Proton method (Mod Tools build)](#4-proton-method-mod-tools-build)
5. [Playing](#5-playing)
6. [Steam Deck](#6-steam-deck)
7. [Troubleshooting](#7-troubleshooting)
8. [What's verified](#whats-verified)

---

## 1. Pick a method

|  | **Plutonium** (default) | **Proton** |
|---|---|---|
| Mod Tools / building `mod.ff` | Not needed | Needed, plus LinkerMod's `game_mod` |
| Steam must be running while you play | No | Yes (the game exe uses Steam DRM) |
| Works with Flatpak/Snap Steam | Yes | Probably not (the game may fail its Steam DRM check) |
| What starts the game | the bridge, via `proton run` | the bridge, via Proton inside Steam's runtime container |

**Use Plutonium unless you have a reason not to.** It needs no build step. It loads a single script file, and it
runs the game in LAN (offline, solo) mode without the Steam client. Stock Black Ops can't load mods at all, which
is why the Proton method needs `game_mod`.

## 2. Prepare the game (every method)

1. **Install Black Ops in Steam.** It is Steam app `42700`. You need the singleplayer/zombies app, not *Black Ops -
   Multiplayer* (42710).
2. **Pick a Proton version.** Go to the game's *Properties → Compatibility → Force the use of a specific Steam
   Play compatibility tool*. GE-Proton or Proton 9/10 are good choices. Community reports rate the game *Gold* on
   ProtonDB *(unverified: ProtonDB couldn't be checked directly)*.
3. **Start the game once from Steam,** get to the main menu, then quit. This creates its Proton prefix (the fake
   Windows drive under `steamapps/compatdata/42700/`), which `linux-setup` needs.
4. **Install XACT audio**, or some sounds (barrier repairs, the mystery box, some guns) will be missing:

   ```bash
   protontricks 42700 xact
   # Flatpak protontricks:
   flatpak run com.github.Matoking.protontricks 42700 xact
   ```

5. **Get the bridge:**

   ```bash
   git clone https://github.com/BounciestSky152/WAW-BO1-Portal-Bridge.git
   cd WAW-BO1-Portal-Bridge
   python3 --version   # needs 3.9+
   ```

All commands below are run from this folder.

## 3. Plutonium method (recommended)

[Plutonium](https://plutonium.pw) is a community client for BO1 (T5). It loads the Portal Bridge as a loose
script. Plutonium officially supports Windows only, but running it under Proton/Wine is common and
community-supported. The bridge always starts it with `-lan`, which needs no Plutonium account and keeps
anti-cheat out of the picture.

### 3.1 Install Plutonium in a Proton prefix

Plutonium can live in any Proton prefix. The easiest route is the native Linux updater, which downloads
Plutonium's files without running its Windows launcher:

```bash
# 1. Get the updater (https://github.com/mxve/plutonium-updater.rs)
curl -LO https://github.com/mxve/plutonium-updater.rs/releases/latest/download/plutonium-updater-x86_64-unknown-linux-gnu.tar.gz
tar xf plutonium-updater-x86_64-unknown-linux-gnu.tar.gz

# 2. Pick a prefix. Black Ops' own is the simplest; for the default library:
PFX=~/.local/share/Steam/steamapps/compatdata/42700/pfx
#    (Steam Deck SD card: /run/media/deck/<card>/steamapps/compatdata/42700/pfx
#     Flatpak Steam:      ~/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/compatdata/42700/pfx)

# 3. Download Plutonium into it
mkdir -p "$PFX/drive_c/users/steamuser/AppData/Local/Plutonium"
./plutonium-updater -d "$PFX/drive_c/users/steamuser/AppData/Local/Plutonium"
```

If you already have Plutonium in some other prefix, `linux-setup` searches the usual places: every Steam
`compatdata` prefix, `~/.wine`, `~/Games/*`, Lutris prefixes and Bottles. You can also point it at a folder with
`--plutonium-dir`.

### 3.2 Configure and install the script

```bash
python3 -m portal_bridge linux-setup
python3 -m portal_bridge install-plutonium
python3 -m portal_bridge doctor
```

- **`linux-setup`** finds Steam, the game, its prefix, the Proton it uses, and Plutonium. It writes all of that to
  `config/bridge.local.json` and prints anything still missing. Add `--print` to see the config without writing
  it, or `--name YourName` to set your in-game name. `--bo1 plutonium|proton` picks the method (default
  `plutonium`).
- **`install-plutonium`** builds the script and copies it to `Plutonium/storage/t5/raw/scripts/sp/portal_bridge.gsc`,
  where Plutonium loads zombies scripts from. It also creates the `Plutonium/storage/t5/raw/scriptdata` folder the
  script writes travel requests to.

  Maps you don't own (no `<map>.ff` anywhere under the game's `zone/` folder) are left out of the in-game
  destination list, and `install-plutonium` prints which ones it hid. If it can't read the game folder, all maps
  are listed.
- **`doctor`** checks every path and tells you what's wrong.

That's it. Go to [Playing](#5-playing).

<details>
<summary>What the generated launch looks like</summary>

```text
cwd: …/compatdata/42700/pfx/drive_c/users/steamuser/AppData/Local/Plutonium
env: STEAM_COMPAT_DATA_PATH=…/compatdata/42700  STEAM_COMPAT_CLIENT_INSTALL_PATH=~/.local/share/Steam
…/Proton 9.0 (Beta)/proton run …/Plutonium/bin/plutonium-bootstrapper-win32.exe t5sp \
    'Z:\home\you\.local\share\Steam\steamapps\common\Call of Duty Black Ops' \
    -token <token> -lan +name Player +set zombiemode 1 +set pb_state PB1|… +devmap zombie_theater
```

The Proton script needs both `STEAM_COMPAT_*` variables even for a non-Steam program. The game folder is passed as
a Wine `Z:\…` path because Plutonium runs from inside the prefix's `C:` drive. The bootstrapper only works when
started from its own folder.
</details>

## 4. Proton method (Mod Tools build)

> **Skip this section if you used Plutonium (§3).** It is an alternative, not an extra step. Running it anyway can
> switch your Steam prefix to a different Proton.

Use this if you'd rather run the stock Steam game with a compiled `mod.ff`. You need the Steam client running,
because the exe uses Steam DRM, and you need to build the mod yourself.

```bash
python3 -m portal_bridge linux-setup --bo1 proton
```

The bridge then runs the game the way Steam does: inside the Steam Linux Runtime container
(`SteamLinuxRuntime_sniper` for Proton 8–10, `SteamLinuxRuntime_4` for Proton 11), with `SteamAppId` and
`SteamGameId` set. Proton only performs the game's Steam DRM handshake when those are set *(unverified for this
exe)*.

If you use Flatpak Steam, a game started outside the sandbox may fail its Steam DRM check *(unverified, but
expected)*. In that case, use `--bo1 plutonium`.

### Building `mod.ff`

Stock `BlackOps.exe` **can't load mods**. You need LinkerMod's `game_mod`, which provides `launcher_ldr.exe` and
`game_mod.dll` in `<BO1>/bin`. The bridge starts it as
`launcher_ldr.exe game_mod.dll ../BlackOps.exe …` from that folder. Generate and patch the scripts the way the
README's Mod Tools route does (`build`, then `patch-zombiemode`), build `mod.ff` with the Black Ops Mod Tools
(Steam app 42740, the output lands in `zone/English/`) and put it in `<BO1>/mods/portal_bridge/`.
[OpenAssetTools](https://github.com/Laupetin/OpenAssetTools) has a native Linux linker that supports T5
fastfiles, if you'd rather not run the Mod Tools linker under Proton. None of this is verified under Proton, so
**Plutonium is strongly recommended.**

### Where the console log ends up

The Mod Tools route reports travel through the console log. It's undocumented where the stock game writes
`console.log` under Proton, so the bridge watches every likely spot (the game folder's `mods/portal_bridge/` and
`main/` folders). After your first launch, `doctor` shows which one exists. If none does, find it and add it to
`games.bo1.logs` in `config/bridge.local.json`:

```bash
find ~ /mnt /media /run/media -iname 'console*.log' -mmin -60 2>/dev/null
```

## 5. Playing

Run this from the `WAW-BO1-Portal-Bridge` folder; elsewhere Python reports `No module named portal_bridge`.

```bash
python3 -m portal_bridge run --start bo1:zombie_theater
```

Leave that terminal open. Travel itself happens inside the game, so portals don't depend on it. Game output goes
to `~/.cache/portal_bridge/bo1.log`, so the terminal only shows the bridge's own messages.

Then, in game:

| Action | How |
|---|---|
| Open the console | The **`~`** key (on the Steam Deck, see §6) |
| Bind a portal key (once) | `bind p "set pb_open 1"` in the console |
| Open a portal | Press your key, or hold **USE + MELEE** for one second |
| Change destination | Stand near the portal and tap **USE** |
| Travel | Walk through it |

When you step through, the screen fades to portal-blue and the game changes the map in place, with no restart. You
arrive with your round, points, perks and guns.

## 6. Steam Deck

- **Run the bridge from Desktop Mode.** Open Konsole and run the commands above. SteamOS already has `python3`;
  don't use `pacman` or `pip`, because the bridge doesn't need either and the system partition is read-only.
- A game on the SD card is found automatically through Steam's library list.
- **Console key:** in the game's *Controller Settings → Edit Layout*, bind a back button (L4/L5/R4/R5) or a
  trackpad region to *Keyboard → `~`*. Open the console with it once and run `bind p "set pb_open 1"`. Or just use
  hold **USE + MELEE**, which needs no keyboard at all.
- Game Mode: whether the bridge keeps running after you switch from Desktop to Game Mode, and whether a game it
  starts comes to the front there, is *(unverified)*. Desktop Mode works the same as any Linux desktop.

## 7. Troubleshooting

**Start with `python3 -m portal_bridge doctor`.** It checks every path the bridge uses.

**Nothing happens when I walk through the portal**
- Plutonium: if no portal opens at all, the script didn't load. Check Plutonium's log for a compile error:
  `…/Plutonium/storage/t5/main/console.log`.
- If the in-game map change can't run, the script asks the bridge instead, and a file should appear at
  `…/Plutonium/storage/t5/raw/scriptdata/portal_bridge_travel.txt`.
- Mod Tools route: see [Where the console log ends up](#where-the-console-log-ends-up).
- The game says *"is the Portal Bridge app running?"* after 10 seconds: the in-game map change didn't run and the
  bridge didn't see the request. Check it is running and watching the right files (it lists them when it starts).

**The game doesn't start**
- Run `python3 -m portal_bridge launch bo1:zombie_theater --dry-run` to see the exact command, then run it
  yourself to see errors. The game's output is in `~/.cache/portal_bridge/bo1.log`.
- For the Proton method, make sure Steam is running and logged in.
- For more Proton detail, add `"PROTON_LOG": "1"` to `games.bo1.env` in `config/bridge.local.json`. That writes
  `~/steam-<appid>.log`, but only when `SteamGameId` is set, so the Plutonium method doesn't produce one.

**Plutonium starts but doesn't load the map**: passing `+devmap <map>` on Plutonium's command line is
*(unverified)* for T5. Try `"+map"` instead in `games.bo1.game_args` in `config/bridge.local.json`.

**Black Ops hangs, shows a black screen, or stutters**: on kernels older than 6.14, `linux-setup` already adds
`PROTON_NO_ESYNC=1` and `PROTON_NO_FSYNC=1`. Community reports also suggest `"PROTON_USE_WINED3D": "1"` in
`games.bo1.env`.

**Steam says the game is already running**: the bridge waits up to 20 seconds for Steam's `reaper` process to exit
before relaunching. If Steam still thinks the game is running, wait a moment or click *Stop* in Steam.

**Never "fix" a stuck game with `pkill -f BlackOps.exe`.** That also matches Proton's wrapper processes and Steam's
reaper. The bridge matches the exact process name plus the game's Wine prefix instead. To clean up a stuck prefix
by hand:

```bash
WINEPREFIX="$HOME/.local/share/Steam/steamapps/compatdata/42700/pfx" \
  "$HOME/.local/share/Steam/steamapps/common/Proton 9.0 (Beta)/files/bin/wineserver" -k
```

## What's verified

Each item below says where the information comes from.

**Verified by tests in this repo**
- Steam and library discovery, `appmanifest` / `config.vdf` / `config_info` parsing, Proton selection, and finding
  the runtime container.
- Plutonium discovery and the generated launch commands for both methods.
- Process matching through `/proc`, the kill and wait sequence, and signal-file and log watching.

**Taken from source code or official documentation**
- Proton's required environment variables and that it passes arguments through unchanged.
- Wine's process naming.
- The Steam app id.
- That stock BO1 doesn't load mods without `game_mod`.

**From community projects (DeckOps, ZPause, ZShare)**
- Plutonium's script folders and its `scriptdata` file API.
- Launching Plutonium with `-lan -token` under Proton.

**Not verified at all**
- Where the stock game writes `console.log` under Proton.
- The Steam-DRM'd exe running under a bridge-started Proton.
- `+devmap` on Plutonium's command line.
- Building `mod.ff` under Proton.
- Steam Deck Game Mode.
- The in-game script itself on real hardware. That applies on Windows too; see the main README.
