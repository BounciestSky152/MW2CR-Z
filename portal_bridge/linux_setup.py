"""Builds config/bridge.local.json for Linux from what's installed.

Methods per game:
  plutonium  Plutonium T4/T5 run through Proton (or Wine) in LAN mode. No Mod
             Tools build, no Steam client needed. Default.
  proton     The Steam game exe run directly through Proton, with the Mod Tools
             mod.ff. Steam must be running (the exes are Steam-DRM'd). BO1
             additionally needs LinkerMod's game_mod loader.
  steam      `steam -applaunch` with a wrapper script set as the game's Launch
             Options. For Flatpak/Snap Steam, where the host can't run Steam's
             Proton itself. WaW only (stock BO1 can't load mods).
"""
from __future__ import annotations

import hashlib
import json
import os
import platform as _platform
import shutil
from dataclasses import dataclass, field
from pathlib import Path

from . import steam as st
from .config import DEFAULT_CONFIG_DIR, REPO_ROOT, deep_merge

METHODS = ("plutonium", "proton", "steam")
PLUTONIUM_GAME_IDS = {"waw": "t4sp", "bo1": "t5sp"}
PLUTONIUM_STORAGE = {"waw": "t4", "bo1": "t5"}
# Where Plutonium loads loose zombies scripts from (T4: raw/scripts/sp,
# T5: raw/scripts/sp too, since scripts/sp/zom needs the menu's zombies mode).
PLUTONIUM_SCRIPT_DIRS = {"waw": "storage/t4/raw/scripts/sp", "bo1": "storage/t5/raw/scripts/sp"}
SIGNAL_FILE = "portal_bridge_travel.txt"
WRAPPER = REPO_ROOT / "scripts" / "pb-wrap.sh"


@dataclass
class Plan:
    games: dict[str, dict] = field(default_factory=dict)
    bridge: dict = field(default_factory=dict)
    notes: list[str] = field(default_factory=list)
    problems: list[str] = field(default_factory=list)
    wrapper_dir: Path | None = None

    def local_config(self) -> dict:
        return {"games": self.games, "bridge": self.bridge}


def plutonium_signal_file(game: str) -> str:
    return f"{{pluto_dir}}/storage/{PLUTONIUM_STORAGE[game]}/raw/scriptdata/{SIGNAL_FILE}"


def mod_tools_logs(game: str) -> list[str]:
    """console.log candidates for the Mod Tools route. Where the stock exes put
    it under Proton isn't documented, so watch every plausible spot."""
    if game == "waw":
        appdata = "{prefix}/drive_c/users/steamuser/AppData/Local/Activision"
        return [
            "{game_dir}/mods/portal_bridge/console.log",
            "{game_dir}/main/console.log",
            f"{appdata}/CoDWaW/mods/portal_bridge/console.log",
            f"{appdata}/CodWaW/mods/portal_bridge/console.log",
        ]
    return ["{game_dir}/mods/portal_bridge/console.log", "{game_dir}/main/console.log"]


def _find(steams: list[st.SteamInstall], game: str) -> tuple[st.SteamInstall | None, st.GameInstall | None]:
    for s in steams:
        g = st.find_game(s, game)
        if g:
            return s, g
    return (steams[0] if steams else None), None


def plan_linux_setup(
    methods: dict[str, str],
    *,
    home: Path | None = None,
    env: dict[str, str] | None = None,
    kernel_release: str | None = None,
    os_release: str | None = None,
    plutonium_dir: Path | None = None,
    steam_dir: Path | None = None,
    player_name: str = "Player",
) -> Plan:
    home = home or Path.home()
    env = dict(os.environ) if env is None else dict(env)
    if steam_dir:
        env["PORTAL_BRIDGE_STEAM_DIR"] = str(steam_dir)
    kernel_release = kernel_release if kernel_release is not None else _platform.release()
    if os_release is None:
        try:
            os_release = Path("/etc/os-release").read_text()
        except OSError:
            os_release = ""

    plan = Plan(bridge={
        "kill_timeout_seconds": 20.0,
        "kill_wait_seconds": 1.0,
        "game_log_dir": "~/.cache/portal_bridge",
    })
    steams = st.find_steam_roots(home, env)
    if not steams:
        plan.problems.append(
            "Couldn't find Steam. Install WaW/BO1 through Steam first, or pass --steam-dir "
            "(the folder that contains steamapps/)."
        )
        return plan

    installs = {g: _find(steams, g) for g in methods}
    found_games = [g for _, g in installs.values() if g]
    pluto_candidates = [plutonium_dir] if plutonium_dir else st.plutonium_candidates(home, steams, found_games)

    for game, method in methods.items():
        steam, inst = installs[game]
        label = "World at War" if game == "waw" else "Black Ops"
        if inst is None:
            plan.problems.append(f"{label} (Steam app {st.APP_IDS[game]}) isn't installed in any Steam library.")
            continue
        protons = st.find_protons(steam, env)
        proton = st.pick_proton(steam, protons, inst.app_id, inst.compatdata)
        no_ntsync = not st.kernel_has_ntsync(kernel_release)

        if method == "plutonium":
            cfg = _plan_plutonium(plan, game, label, steam, inst, proton, pluto_candidates, player_name, protons)
        elif method == "proton":
            cfg = _plan_proton(plan, game, label, steam, inst, proton)
        elif method == "steam":
            cfg = _plan_steam(plan, game, label, steam, inst, home)
        else:
            plan.problems.append(f"unknown method {method!r} for {game}; pick one of {', '.join(METHODS)}")
            continue
        if cfg is None:
            continue

        if game == "bo1" and no_ntsync and method != "steam":
            # Esync/fsync make BO1 hang or stutter without the kernel's NTSync
            # (Linux < 6.14); Steam launch options don't apply to our launches.
            cfg.setdefault("env", {}).update({"PROTON_NO_ESYNC": "1", "PROTON_NO_FSYNC": "1"})
        plan.games[game] = cfg

        if method in ("plutonium", "proton") and not inst.has_prefix:
            plan.problems.append(
                f"{label} has no Proton prefix yet ({inst.prefix}). Start it once from Steam, quit, then re-run linux-setup."
            )
        if method != "steam":
            plan.notes.append(
                f"{label}: install the XACT sound library once or some sounds are missing: protontricks "
                f"{Path(cfg.get('env', {}).get('STEAM_COMPAT_DATA_PATH', inst.compatdata)).name} xact"
            )

    if any(m in ("proton", "steam") for m in methods.values()):
        plan.notes.append("The proton/steam methods run the Steam-DRM'd game exes: keep Steam running and logged in.")
    if st.is_steam_deck(os_release):
        plan.notes.append(
            "Steam Deck: run the bridge from Konsole in Desktop Mode. Bind a back button to the ` key "
            "(Controller Settings > Edit Layout > Keyboard) so you can open the console and `bind` a portal key."
        )
    return plan


def _plan_plutonium(plan, game, label, steam, inst, proton, candidates, player_name, protons=()) -> dict | None:
    own = [c for c in candidates if inst.prefix in c.parents]
    pluto = (own or candidates or [None])[0]
    if pluto is None:
        plan.problems.append(
            f"{label}: Plutonium isn't installed. Get it into the game's own Proton prefix with the native updater:\n"
            f"    mkdir -p '{inst.prefix}/drive_c/users/steamuser/AppData/Local/Plutonium'\n"
            f"    ./plutonium-updater -d '{inst.prefix}/drive_c/users/steamuser/AppData/Local/Plutonium'\n"
            "  (plutonium-updater: https://github.com/mxve/plutonium-updater.rs/releases) then re-run linux-setup,"
            " or pass --plutonium-dir."
        )
        return None

    prefix = st.wine_prefix_of(pluto)
    compat = st.compatdata_of(prefix) if prefix else None
    env: dict[str, str] = {}
    if prefix is None:
        # Plutonium outside any prefix (e.g. ~/.local/share/Plutonium): borrow the game's.
        prefix, compat = inst.prefix, inst.compatdata
    if compat is not None:
        # Use the Proton that built Plutonium's prefix; another one "upgrades" it.
        proton = st.proton_from_prefix(compat, list(protons)) or proton
        if proton is None:
            plan.problems.append(f"{label}: no Proton found. Install one in Steam (Proton 9 or GE-Proton) and re-run.")
            return None
        runner = [str(proton.script), "run"]
        env = {"STEAM_COMPAT_DATA_PATH": str(compat), "STEAM_COMPAT_CLIENT_INSTALL_PATH": str(steam.root)}
    else:
        runner = ["wine"]
        env = {"WINEPREFIX": str(prefix)}

    plan.notes.append(f"{label}: Plutonium at {pluto} (prefix {prefix})")
    return {
        "game_dir": str(inst.game_dir),
        # A fixed LAN token per player name: a fresh one each launch looks like
        # a new player, so WaW never finds the profile it made last time.
        "vars": {"pluto_dir": str(pluto), "token": hashlib.sha256(player_name.encode()).hexdigest()[:16],
                 **({"devmap_wait": "600"} if game == "waw" else {})},
        # The bootstrapper refuses to start from anywhere else.
        "cwd": "{pluto_dir}",
        "launch": runner + [
            "{pluto_dir}/" + st.PLUTONIUM_BOOTSTRAPPER,
            PLUTONIUM_GAME_IDS[game],
            "{game_dir_win}",
            "-token", "{token}",
            "-lan",
            "{game_args}",
        ],
        # BO1 runs campaign-only setup in zombies unless zombiemode is 1.
        # WaW: pick Plutonium's default profile ($$$) up front, so a cold launch
        # straight into a map doesn't stop at "create a profile".
        "game_args": ["+name", player_name]
        + (["+set", "zombiemode", "1"] if game == "bo1" else [])
        + ["{state_args}"]
        # WaW: a +devmap that runs before the menu has signed the player in
        # makes the client connect twice ("Duplicate qport on server"), which
        # drops it to the menu's profile prompt. Hold the map back some frames.
        + (["+wait", "{devmap_wait}"] if game == "waw" else [])
        + ["+devmap", "{map}"],
        "env": env,
        # The bootstrapper relaunches itself as the game process; t4sp.exe/t5sp.exe
        # are listed in case a build names it after the game binary instead.
        "process_names": ["plutonium-bootstrapper-win32.exe", f"{PLUTONIUM_GAME_IDS[game]}.exe"],
        "logs": [],
        "signal_files": [plutonium_signal_file(game)],
        "wineprefix": str(prefix),
        "args_file": "",
        "steam_app_id": "",
    }


def _plan_proton(plan, game, label, steam, inst, proton) -> dict | None:
    if proton is None:
        plan.problems.append(f"{label}: no Proton found. Install one in Steam and re-run.")
        return None
    entry = st.runtime_entry_point(steam, proton)
    if entry:
        runner = [str(entry), "--verb=waitforexitandrun", "--", str(proton.script), "waitforexitandrun"]
    else:
        runner = [str(proton.script), "run"]
        plan.notes.append(
            f"{label}: Steam Linux Runtime for {proton.display_name} not found; running Proton without its container."
        )
    env = {
        "STEAM_COMPAT_DATA_PATH": str(inst.compatdata),
        "STEAM_COMPAT_CLIENT_INSTALL_PATH": str(steam.root),
        "STEAM_COMPAT_INSTALL_PATH": str(inst.game_dir),
        "STEAM_COMPAT_LIBRARY_PATHS": ":".join(str(lib) for lib in steam.libraries),
        "STEAM_COMPAT_APP_ID": inst.app_id,
        # Required: Proton only sets up Steam DRM for the game when these are set.
        "SteamAppId": inst.app_id,
        "SteamGameId": inst.app_id,
    }
    if steam.flatpak:
        plan.notes.append(
            f"{label}: you use Flatpak Steam; a game started outside the sandbox may fail its Steam DRM check. "
            "If it does, switch to --waw steam."
        )
    common = {
        "game_dir": str(inst.game_dir),
        "vars": {"prefix": str(inst.prefix)},
        "env": env,
        "logs": mod_tools_logs(game),
        "signal_files": [],
        "wineprefix": str(inst.prefix),
        "args_file": "",
        "steam_app_id": "",
    }
    if game == "waw":
        plan.notes.append(f"{label}: build mod.ff and put it in {inst.prefix}/drive_c/users/steamuser/AppData/Local/Activision/CoDWaW/mods/portal_bridge/ (docs/LINUX.md).")
        return {**common, "cwd": "{game_dir}", "launch": runner + ["{game_dir}/CoDWaW.exe", "{game_args}"],
                "process_names": ["CoDWaW.exe"]}
    plan.notes.append(f"{label}: needs LinkerMod's game_mod (launcher_ldr.exe + game_mod.dll) in {inst.game_dir}/bin, and mod.ff in {inst.game_dir}/mods/portal_bridge/.")
    return {**common, "cwd": "{game_dir}/bin",
            "launch": runner + ["{game_dir}/bin/launcher_ldr.exe", "game_mod.dll", "../BlackOps.exe", "{game_args}"],
            "process_names": ["BlackOps.exe", "launcher_ldr.exe"]}


def wrapper_dir_for(steam: st.SteamInstall, home: Path) -> Path:
    # Flatpak Steam can't see most of $HOME; its own data dir is visible at the
    # same path inside and outside the sandbox.
    if steam.flatpak:
        return home / f".var/app/{st.FLATPAK_ID}/portal_bridge"
    if steam.kind == "snap":
        return home / "snap/steam/common/portal_bridge"
    return home / ".local/share/portal_bridge"


def _plan_steam(plan, game, label, steam, inst, home) -> dict | None:
    if game == "bo1":
        plan.problems.append(
            "Black Ops: the steam method isn't supported - Steam starts the stock BlackOps.exe, which can't load mods. "
            "Use --bo1 plutonium."
        )
        return None
    wdir = wrapper_dir_for(steam, home)
    plan.wrapper_dir = wdir
    plan.notes.append(
        f"{label}: in Steam > {label} > Properties > General > Launch Options, enter exactly:\n"
        f"    \"{wdir / 'pb-wrap.sh'}\" {game} %command%\n"
        "  and pick 'Play Call of Duty: World at War' (not Multiplayer) as the launch option if Steam asks."
    )
    return {
        "game_dir": str(inst.game_dir),
        "vars": {"prefix": str(inst.prefix)},
        "cwd": "",
        "launch": steam.launch_prefix() + ["-applaunch", inst.app_id],
        "env": {},
        "process_names": [inst.exe],
        "logs": mod_tools_logs(game),
        "signal_files": [],
        "args_file": str(wdir / f"next_args_{game}"),
        "steam_app_id": inst.app_id,
        "wineprefix": str(inst.prefix),
    }


def write_plan(plan: Plan, config_dir: Path | None = None) -> Path:
    config_dir = Path(config_dir) if config_dir else DEFAULT_CONFIG_DIR
    target = config_dir / "bridge.local.json"
    existing: dict = {}
    if target.exists():
        existing = json.loads(target.read_text(encoding="utf-8"))
        shutil.copy2(target, target.with_suffix(".json.bak"))
    merged = deep_merge(existing, {"bridge": plan.bridge})
    merged.setdefault("games", {})
    for game, cfg in plan.games.items():
        merged["games"][game] = cfg  # replace wholesale so switching methods leaves nothing stale
    target.write_text(json.dumps(merged, indent=2) + "\n", encoding="utf-8")

    if plan.wrapper_dir is not None:
        plan.wrapper_dir.mkdir(parents=True, exist_ok=True)
        dest = plan.wrapper_dir / "pb-wrap.sh"
        shutil.copy2(WRAPPER, dest)
        dest.chmod(0o755)
    return target
