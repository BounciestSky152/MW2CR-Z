# Portal Bridge on Linux

World at War and Black Ops are Windows games, so on Linux they run under **Proton** (Steam's Wine). The Portal
Bridge app is plain Python and runs natively. It starts and stops the games through Proton for you.

This works on any desktop distro and on the **Steam Deck** (in Desktop Mode). The bridge needs **Python 3.9 or
newer** and nothing else; there's nothing to install with pip.

> **Status:** the Linux tooling (Steam detection, launch commands, process handling, config generation) is covered
> by automated tests against a fake Steam install. Nobody has run the whole thing on a real Linux machine with the
> games yet. The steps below follow how Proton, Steam and Plutonium are documented to behave. Anything not
> confirmed is marked *(unverified)*, and [What's verified](#whats-verified) lists them all in one place.

## Contents

1. [Pick a method](#1-pick-a-method)
2. [Prepare the games (every method)](#2-prepare-the-games-every-method)
3. [Plutonium method (recommended)](#3-plutonium-method-recommended)
4. [Proton method (Mod Tools build)](#4-proton-method-mod-tools-build)
5. [Steam method (Flatpak or Snap Steam)](#5-steam-method-flatpak-or-snap-steam)
6. [Playing](#6-playing)
7. [Steam Deck](#7-steam-deck)
8. [Troubleshooting](#8-troubleshooting)
9. [What's verified](#whats-verified)

---

## 1. Pick a method

|  | **Plutonium** (default) | **Proton** | **Steam** |
|---|---|---|---|
| Games | WaW and BO1 | WaW, and BO1 only with LinkerMod's `game_mod` | WaW only |
| Mod Tools / building `mod.ff` | Not needed | Needed | Needed |
| Steam must be running while you play | No | Yes (the game exes use Steam DRM) | Yes |
| Works with Flatpak/Snap Steam | Yes | Probably not (see §5) | Yes |
| What starts the game | the bridge, via `proton run` | the bridge, via Proton inside Steam's runtime container | Steam, via `steam -applaunch` |

**Use Plutonium unless you have a reason not to.** It needs no build step. It loads a single script file, and it
runs both games in LAN (offline, solo) mode without the Steam client.

You can mix methods, for example Steam for WaW and Plutonium for BO1. Plain Steam can't load mods into stock Black
Ops at all, which is why BO1 can't use the Steam method.

## 2. Prepare the games (every method)

1. **Install the games in Steam.** World at War is Steam app `10090` and Black Ops is `42700`. You need the
   singleplayer/zombies app, not *Black Ops - Multiplayer* (42710).
2. **Pick a Proton version.** Go to each game's *Properties → Compatibility → Force the use of a specific Steam
   Play compatibility tool*. GE-Proton or Proton 9/10 are good choices. Community reports rate both games
   *Gold* on ProtonDB *(unverified: ProtonDB couldn't be checked directly)*.
3. **Start each game once from Steam,** get to the main menu, then quit. This creates its Proton prefix (the fake
   Windows drive under `steamapps/compatdata/<appid>/`), which `linux-setup` needs.
4. **Install XACT audio**, or some sounds (barrier repairs, the mystery box, some guns) will be missing:

   ```bash
   protontricks 10090 xact
   protontricks 42700 xact
   # Flatpak protontricks:
   flatpak run com.github.Matoking.protontricks 10090 xact
   ```

5. **Get the bridge:**

   ```bash
   git clone https://github.com/BounciestSky152/WAW-BO1-Portal-Bridge.git
   cd WAW-BO1-Portal-Bridge
   python3 --version   # needs 3.9+
   ```

All commands below are run from this folder.

## 3. Plutonium method (recommended)

[Plutonium](https://plutonium.pw) is a community client for WaW (T4) and BO1 (T5). It loads the Portal Bridge as a
loose script. Plutonium officially supports Windows only, but running it under Proton/Wine is common and
community-supported. The bridge always starts it with `-lan`, which needs no Plutonium account and keeps
anti-cheat out of the picture.

### 3.1 Install Plutonium inside World at War's Proton prefix

The easiest route is the native Linux updater, which downloads Plutonium's files without running its Windows
launcher:

```bash
# 1. Get the updater (https://github.com/mxve/plutonium-updater.rs)
curl -LO https://github.com/mxve/plutonium-updater.rs/releases/latest/download/plutonium-updater-x86_64-unknown-linux-gnu.tar.gz
tar xf plutonium-updater-x86_64-unknown-linux-gnu.tar.gz

# 2. Find WaW's prefix. It's in the library WaW is installed in; for the default library:
PFX=~/.local/share/Steam/steamapps/compatdata/10090/pfx
#    (Steam Deck SD card: /run/media/deck/<card>/steamapps/compatdata/10090/pfx
#     Flatpak Steam:      ~/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/compatdata/10090/pfx)

# 3. Download Plutonium into it
mkdir -p "$PFX/drive_c/users/steamuser/AppData/Local/Plutonium"
./plutonium-updater -d "$PFX/drive_c/users/steamuser/AppData/Local/Plutonium"
```

One Plutonium install serves **both** games, so you don't need a second copy for Black Ops. If you already have
Plutonium somewhere else, `linux-setup` searches the usual places: any Steam prefix, `~/.wine`, `~/Games/*`,
Lutris prefixes and Bottles. You can also point it at a folder with `--plutonium-dir`.

### 3.2 Configure and install the script

```bash
python3 -m portal_bridge linux-setup
python3 -m portal_bridge install-plutonium
python3 -m portal_bridge doctor
```

- **`linux-setup`** finds Steam, the games, their prefixes, the Proton each one uses, and Plutonium. It writes all
  of that to `config/bridge.local.json` and prints anything still missing. Add `--print` to see the config
  without writing it, or `--name YourName` to set your in-game name.
- **`install-plutonium`** builds the script and copies it to the two places Plutonium loads zombies scripts from:
  - WaW: `Plutonium/storage/t4/raw/scripts/sp/portal_bridge.gsc`
  - BO1: `Plutonium/storage/t5/scripts/sp/zom/portal_bridge.gsc`. The `zom` folder means it only runs in zombies,
    not on the menu or in the campaign.

  It also creates the `scriptdata` folders the script writes travel requests to.
- **`doctor`** checks every path and tells you what's wrong.

That's it. Go to [Playing](#6-playing).

<details>
<summary>What the generated launch looks like</summary>

```text
cwd: …/compatdata/10090/pfx/drive_c/users/steamuser/AppData/Local/Plutonium
env: STEAM_COMPAT_DATA_PATH=…/compatdata/10090  STEAM_COMPAT_CLIENT_INSTALL_PATH=~/.local/share/Steam
…/Proton 9.0 (Beta)/proton run …/Plutonium/bin/plutonium-bootstrapper-win32.exe t4sp \
    'Z:\home\you\.local\share\Steam\steamapps\common\Call of Duty World at War' \
    -token <random> -lan +name Player +set pb_state PB1|… +devmap nazi_zombie_factory
```

The Proton script needs both `STEAM_COMPAT_*` variables even for a non-Steam program. The game folder is passed as
a Wine `Z:\…` path because Plutonium runs from inside the prefix's `C:` drive. The bootstrapper only works when
started from its own folder.
</details>

## 4. Proton method (Mod Tools build)

Use this if you'd rather run the stock Steam games with a compiled `mod.ff`. You need the Steam client running,
because both exes use Steam DRM, and you need to build the mod yourself.

```bash
python3 -m portal_bridge linux-setup --waw proton --bo1 proton
```

The bridge then runs the game the way Steam does: inside the Steam Linux Runtime container
(`SteamLinuxRuntime_sniper` for Proton 8–10, `SteamLinuxRuntime_4` for Proton 11), with `SteamAppId` and
`SteamGameId` set. Proton only performs the game's Steam DRM handshake when those are set *(unverified for these
two exes)*.

### Building `mod.ff` for WaW

1. `python3 -m portal_bridge build`
2. Install the WaW Mod Tools into the game folder (`steamapps/common/Call of Duty World at War`). They aren't on
   Steam; extract the official zips there.
3. Copy `dist/waw/mods/portal_bridge/` to `<WaW>/mods/portal_bridge/`. Copy the stock `raw/maps/_zombiemode.gsc`
   into `<WaW>/mods/portal_bridge/maps/` and add the hook:
   `python3 -m portal_bridge patch-zombiemode "<WaW>/mods/portal_bridge/maps/_zombiemode.gsc"`
4. Run the linker through Proton *(unverified under Proton; the same linker works under Wine for CoD4)*:

   ```bash
   WAW="$HOME/.local/share/Steam/steamapps/common/Call of Duty World at War"
   cp "$WAW/mods/portal_bridge/mod.csv" "$WAW/zone_source/mod.csv"
   cd "$WAW/bin"
   STEAM_COMPAT_DATA_PATH="$HOME/.local/share/Steam/steamapps/compatdata/10090" \
   STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.local/share/Steam" \
     "$HOME/.local/share/Steam/steamapps/common/Proton 9.0 (Beta)/proton" run \
     linker_pc.exe -nopause -language english -moddir portal_bridge mod
   ```

5. WaW only loads mods from its AppData folder, so copy the result there:

   ```bash
   DEST="$HOME/.local/share/Steam/steamapps/compatdata/10090/pfx/drive_c/users/steamuser/AppData/Local/Activision/CoDWaW/mods/portal_bridge"
   mkdir -p "$DEST" && cp "$WAW/zone/english/mod.ff" "$DEST/"
   ```

[OpenAssetTools](https://github.com/Laupetin/OpenAssetTools) has a native Linux linker that supports T4/T5
fastfiles, if you'd rather not run `linker_pc` under Proton.

### Black Ops

Stock `BlackOps.exe` **can't load mods**. You need LinkerMod's `game_mod`, which provides `launcher_ldr.exe` and
`game_mod.dll` in `<BO1>/bin`. The bridge starts it as
`launcher_ldr.exe game_mod.dll ../BlackOps.exe …` from that folder. Build `mod.ff` with the Black Ops Mod Tools
(Steam app 42740, the output lands in `zone/English/`) and put it in `<BO1>/mods/portal_bridge/`. None of this is
verified under Proton, so **Plutonium is strongly recommended for BO1.**

### Where the console log ends up

The Mod Tools route reports travel through the console log. It's undocumented where the stock games write
`console.log` under Proton, so the bridge watches every likely spot (the game folder and the prefix's AppData).
After your first launch, `doctor` shows which one exists. If none does, find it and add it to
`games.<game>.logs` in `config/bridge.local.json`:

```bash
find ~ /mnt /media /run/media -iname 'console*.log' -mmin -60 2>/dev/null
```

## 5. Steam method (Flatpak or Snap Steam)

Flatpak Steam runs in a sandbox with its own shared memory. A game the bridge starts from outside that sandbox
most likely can't reach the Steam client for its DRM check *(unverified, but expected)*. In that case, let Steam
start the game:

```bash
python3 -m portal_bridge linux-setup --waw steam --bo1 plutonium
```

This installs a small wrapper script and prints one line to paste into **Steam → Call of Duty: World at War →
Properties → General → Launch Options**. It looks like:

```text
"/home/you/.var/app/com.valvesoftware.Steam/portal_bridge/pb-wrap.sh" waw %command%
```

When you step through a portal, the bridge writes the next launch's arguments to a file next to the wrapper and
runs `steam -applaunch 10090` (or `flatpak run com.valvesoftware.Steam -applaunch 10090`). The wrapper appends
those arguments to the game's command line and deletes the file. The travel state contains `|`, which Steam's
shell-built launch command would turn into a pipe, so it can't go through Steam directly. A normal launch from your
library, with no file present, starts the plain game.

- If Steam asks **Play** or **Multiplayer**, choose Play and tick *remember*. Otherwise portal trips wait on that
  dialog.
- You still need `mod.ff` for WaW (see §4).

## 6. Playing

```bash
python3 -m portal_bridge run --start waw:nazi_zombie_factory
```

Leave that terminal open. Game output goes to `~/.cache/portal_bridge/<game>.log`, so the terminal only shows
the bridge's own messages.

Then, in game:

| Action | How |
|---|---|
| Open the console | The **`~`** key (on the Steam Deck, see §7) |
| Bind a portal key (once) | `bind p "set pb_open 1"` in the console |
| Open a portal | Press your key, or hold **USE + MELEE** for one second |
| Change destination | Stand near the portal and tap **USE** |
| Travel | Walk through it |

When you step through, the screen fades to portal-blue. The bridge closes the current game, waits for Proton to
shut it down completely (a few seconds), then starts the destination. You arrive with your round, points, perks
and guns.

## 7. Steam Deck

- **Run the bridge from Desktop Mode.** Open Konsole and run the commands above. SteamOS already has `python3`;
  don't use `pacman` or `pip`, because the bridge doesn't need either and the system partition is read-only.
- Games on the SD card are found automatically through Steam's library list.
- **Console key:** in the game's *Controller Settings → Edit Layout*, bind a back button (L4/L5/R4/R5) or a
  trackpad region to *Keyboard → `~`*. Open the console with it once and run `bind p "set pb_open 1"`. Or just use
  hold **USE + MELEE**, which needs no keyboard at all.
- Game Mode: whether the bridge keeps running after you switch from Desktop to Game Mode, and whether a game it
  starts comes to the front there, is *(unverified)*. Desktop Mode works the same as any Linux desktop.

## 8. Troubleshooting

**Start with `python3 -m portal_bridge doctor`.** It checks every path the bridge uses.

**Nothing happens when I walk through the portal**
- Plutonium: after a portal trip, a file should appear at
  `…/Plutonium/storage/t4/raw/scriptdata/portal_bridge_travel.txt` (`t5` for BO1). If no portal opens at all, the
  script didn't load. Check Plutonium's log for a compile error:
  `…/Plutonium/storage/t5/main/console.log` (BO1) or `…/storage/t4/main/console.log` (WaW, *unverified path*).
- Mod Tools route: see [Where the console log ends up](#where-the-console-log-ends-up).
- The game says *"is the Portal Bridge app running?"* after 20 seconds: the bridge didn't see the request. Check it
  is running and watching the right files (it lists them when it starts).

**The game doesn't start**
- Run `python3 -m portal_bridge launch waw:nazi_zombie_factory --dry-run` to see the exact command, then run it
  yourself to see errors. The game's output is in `~/.cache/portal_bridge/<game>.log`.
- For the proton and steam methods, make sure Steam is running and logged in.
- For more Proton detail, add `"PROTON_LOG": "1"` to `games.<game>.env` in `config/bridge.local.json`. That writes
  `~/steam-<appid>.log`, but only when `SteamGameId` is set, so the Plutonium method doesn't produce one.

**Plutonium starts but doesn't load the map**: passing `+devmap <map>` on Plutonium's command line is
*(unverified)* for T4/T5. Try `"+map"` instead in `games.<game>.game_args` in `config/bridge.local.json`.

**Black Ops hangs, shows a black screen, or stutters**: on kernels older than 6.14, `linux-setup` already adds
`PROTON_NO_ESYNC=1` and `PROTON_NO_FSYNC=1`. Community reports also suggest `"PROTON_USE_WINED3D": "1"` in
`games.bo1.env`.

**Steam says the game is already running**: the bridge waits up to 20 seconds for Steam's `reaper` process to exit
before relaunching. If Steam still thinks the game is running, wait a moment or click *Stop* in Steam.

**Never "fix" a stuck game with `pkill -f CoDWaW.exe`.** That also matches Proton's wrapper processes and Steam's
reaper. The bridge matches the exact process name plus the game's Wine prefix instead. To clean up a stuck prefix
by hand:

```bash
WINEPREFIX="$HOME/.local/share/Steam/steamapps/compatdata/10090/pfx" \
  "$HOME/.local/share/Steam/steamapps/common/Proton 9.0 (Beta)/files/bin/wineserver" -k
```

## What's verified

Each item below says where the information comes from.

**Verified by tests in this repo**
- Steam and library discovery, `appmanifest` / `config.vdf` / `config_info` parsing, Proton selection, and finding
  the runtime container.
- Plutonium discovery and the generated launch commands for all three methods.
- Process matching through `/proc`, the kill and wait sequence, signal-file and log watching, and the Steam
  wrapper script.

**Taken from source code or official documentation**
- Proton's required environment variables and that it passes arguments through unchanged.
- Wine's process naming.
- The Steam app ids.
- That stock BO1 doesn't load mods without `game_mod`.
- That WaW loads mods from AppData.

**From community projects (DeckOps, ZPause, ZShare)**
- Plutonium's script folders and its `scriptdata` file API.
- Launching Plutonium with `-lan -token` under Proton.

**Not verified at all**
- Where the stock games write `console.log` under Proton.
- The Steam-DRM'd exes running under a bridge-started Proton.
- `+devmap` on Plutonium's command line.
- `linker_pc` under Proton.
- Steam Deck Game Mode.
- The in-game script itself on real hardware. That applies on Windows too; see the main README.
