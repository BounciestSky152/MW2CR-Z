"""Command line: python -m portal_bridge <command>."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import __version__
from .bridge import Bridge, TRAVEL_RE
from .build import PLUTONIUM_SCRIPT_DIRS, PLUTONIUM_SCRIPTDATA, build
from .config import GAMES, ConfigError, load_config
from .launcher import GameLauncher
from .patcher import PatchError, patch_file


def _cmd_maps(config, args) -> int:
    for game, cfg in config.games.items():
        print(f"{cfg.label} ({game}):")
        for m in config.maps:
            if m.game == game:
                flag = "" if m.enabled else "  [disabled]"
                print(f"  {m.key:<32} {m.name}{flag}")
    return 0


def _cmd_build(config, args) -> int:
    for path in build(config, args.out):
        print(f"wrote {path}")
    return 0


def _cmd_patch(config, args) -> int:
    try:
        changed = patch_file(args.file)
    except PatchError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    print(f"patched {args.file} (backup saved as .bak)" if changed else f"{args.file} already has the hook")
    return 0


def _cmd_launch(config, args) -> int:
    entry = config.parse_map_ref(args.map)
    GameLauncher(config, dry_run=args.dry_run).launch(entry.game, entry.id)
    return 0


def _cmd_run(config, args) -> int:
    bridge = Bridge(config, GameLauncher(config, dry_run=args.dry_run))
    if args.start:
        bridge.start(config.parse_map_ref(args.start))
    try:
        bridge.run_forever()
    except KeyboardInterrupt:
        print("\nbye")
    return 0


def _looks_like_path(value: str) -> bool:
    return value.startswith(("/", "~")) or (len(value) > 2 and value[1] == ":")


def _cmd_doctor(config, args) -> int:
    """Check every path in the config and say what's wrong."""
    import shutil

    launcher = GameLauncher(config, dry_run=True)
    windows = sys.platform.startswith("win")
    problems = 0

    def check(ok: bool, label: str, hint: str = "") -> None:
        nonlocal problems
        print(f"  [{'ok' if ok else '!!'}] {label}")
        if not ok:
            problems += 1
            if hint:
                print(f"       -> {hint}")

    for game, cfg in config.games.items():
        print(f"{cfg.label} ({game})")
        game_dir = launcher.game_dir(game)
        check(bool(game_dir) and Path(game_dir).is_dir(), f"game_dir {game_dir}",
              f"set games.{game}.game_dir in config/bridge.local.json"
              + ("" if windows else " (or run: python -m portal_bridge linux-setup)"))

        cwd = launcher.cwd(game)
        if cwd and cwd != game_dir:
            check(Path(cwd).is_dir(), f"working directory {cwd}")

        command = launcher.build_command(game, "MAP")
        if command and _looks_like_path(command[0]):
            check(Path(command[0]).is_file(), f"launcher {command[0]}")
        elif command:
            check(shutil.which(command[0]) is not None, f"`{command[0]}` is on PATH")
        for arg in command[1:]:
            if arg.lower().endswith((".exe", "_v2-entry-point", "/proton")) and _looks_like_path(arg):
                check(Path(arg).is_file(), f"{arg}")

        for key, value in launcher.build_env(game).items():
            if _looks_like_path(value) and ":" not in value[2:]:
                check(Path(value).exists(), f"env {key}={value}",
                      "start the game from Steam once so Proton creates its prefix" if "compatdata" in value else "")

        pluto = launcher.var(game, "pluto_dir")
        if pluto:
            script = Path(pluto) / PLUTONIUM_SCRIPT_DIRS[game] / "portal_bridge.gsc"
            check(script.is_file(), f"Plutonium script {script}", "run: python -m portal_bridge install-plutonium")
            data = Path(pluto) / PLUTONIUM_SCRIPTDATA[game]
            check(data.is_dir(), f"Plutonium scriptdata folder {data}", "run: python -m portal_bridge install-plutonium")

        args_file = launcher.args_file(game)
        if args_file is not None:
            wrapper = args_file.parent / "pb-wrap.sh"
            check(wrapper.is_file(), f"Steam launch wrapper {wrapper}", "re-run: python -m portal_bridge linux-setup")

        for p in launcher.signal_paths(game):
            print(f"  [{'ok' if p.is_file() else '--'}] signal file {p}  (appears after your first portal trip)")
        logs = launcher.log_paths(game)
        for p in logs:
            print(f"  [{'ok' if p.is_file() else '--'}] log {p}")
        if logs and not any(p.is_file() for p in logs):
            print("       -> no console.log yet; that's normal before the first launch with the mod.")
            print("          After one, if none is listed, find it and add it to games.%s.logs:" % game)
            print("          find ~ /mnt /media /run/media -iname 'console*.log' -mmin -60 2>/dev/null"
                  if not windows else
                  "          dir /s /b \"%LOCALAPPDATA%\\console.log\"")

    print("no problems found" if problems == 0 else f"{problems} problem(s) found")
    return 0 if problems == 0 else 1


def _cmd_linux_setup(config, args) -> int:
    import json

    from .linux_setup import plan_linux_setup, write_plan

    methods = {g: m for g, m in (("waw", args.waw), ("bo1", args.bo1)) if m != "skip"}
    plan = plan_linux_setup(
        methods,
        plutonium_dir=args.plutonium_dir,
        steam_dir=args.steam_dir,
        player_name=args.name,
    )
    for note in plan.notes:
        print(f"* {note}")
    for problem in plan.problems:
        print(f"! {problem}", file=sys.stderr)
    if not plan.games:
        print("nothing to write", file=sys.stderr)
        return 1
    if args.print:
        print(json.dumps(plan.local_config(), indent=2))
        return 1 if plan.problems else 0
    target = write_plan(plan, args.config_dir)
    print(f"wrote {target} ({', '.join(plan.games)})")
    if plan.wrapper_dir is not None:
        print(f"installed {plan.wrapper_dir / 'pb-wrap.sh'}")
    print("next: python -m portal_bridge install-plutonium   (Plutonium method)"
          if any(m == "plutonium" for m in methods.values()) else
          "next: build and install mod.ff - see docs/LINUX.md")
    print("then: python -m portal_bridge doctor")
    return 1 if plan.problems else 0


def _cmd_install_plutonium(config, args) -> int:
    """Copy the Plutonium bundles into Plutonium's storage folder(s)."""
    import os
    import shutil
    import tempfile

    launcher = GameLauncher(config, dry_run=True)
    games = list(GAMES) if args.game == "all" else [args.game]
    with tempfile.TemporaryDirectory() as tmp:
        build(config, tmp)
        installed = 0
        for game in games:
            pluto = args.plutonium_dir or launcher.var(game, "pluto_dir")
            if not pluto and sys.platform.startswith("win"):
                pluto = os.path.expandvars("%LOCALAPPDATA%/Plutonium")
            if not pluto:
                print(f"{game}: no Plutonium folder configured (run linux-setup, or pass --plutonium-dir)", file=sys.stderr)
                continue
            pluto = Path(pluto)
            if not (pluto / "storage").is_dir() and not (pluto / "bin").is_dir():
                print(f"{game}: {pluto} doesn't look like a Plutonium folder (no bin/ or storage/)", file=sys.stderr)
                continue
            src = Path(tmp) / game / "plutonium" / PLUTONIUM_SCRIPT_DIRS[game] / "portal_bridge.gsc"
            dest = pluto / PLUTONIUM_SCRIPT_DIRS[game] / "portal_bridge.gsc"
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dest)
            (pluto / PLUTONIUM_SCRIPTDATA[game]).mkdir(parents=True, exist_ok=True)
            print(f"{game}: installed {dest}")
            installed += 1
            # A same-named script elsewhere in the virtual scripts/ folder would
            # shadow or double-load this one.
            storage = PLUTONIUM_SCRIPT_DIRS[game].split("/")[1]
            for stale in (pluto / "storage" / storage).glob("**/scripts/**/portal_bridge.gsc"):
                if stale != dest:
                    stale.unlink()
                    print(f"{game}: removed old copy {stale}")
    return 0 if installed == len(games) else 1


def _cmd_simulate(config, args) -> int:
    """Feed one console-log line through the bridge without touching any game."""
    line = args.line
    if not TRAVEL_RE.search(line):
        line = f"[PORTAL_BRIDGE] TRAVEL {line}"
    bridge = Bridge(config, GameLauncher(config, dry_run=True))
    return 0 if bridge.handle_line(line) else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="portal_bridge",
        description="Portal travel between Call of Duty: World at War and Black Ops zombies maps.",
    )
    parser.add_argument("--version", action="version", version=__version__)
    parser.add_argument("--config-dir", type=Path, help="directory holding bridge.json, maps.json, weapons.json")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("maps", help="list every portal destination").set_defaults(func=_cmd_maps)

    p = sub.add_parser("build", help="generate the in-game scripts into dist/")
    p.add_argument("--out", type=Path, default=Path("dist"))
    p.set_defaults(func=_cmd_build)

    p = sub.add_parser("patch-zombiemode", help="add the hook to your mod's copy of maps/_zombiemode.gsc")
    p.add_argument("file", type=Path)
    p.set_defaults(func=_cmd_patch)

    p = sub.add_parser("launch", help="start a zombies map with the mod loaded")
    p.add_argument("map", help="game:map_id, e.g. waw:nazi_zombie_factory")
    p.add_argument("--dry-run", action="store_true", help="print the command instead of running it")
    p.set_defaults(func=_cmd_launch)

    p = sub.add_parser("run", help="watch for portals and swap games when one is used")
    p.add_argument("--start", metavar="GAME:MAP", help="launch this map first")
    p.add_argument("--dry-run", action="store_true", help="log what would happen instead of starting/killing games")
    p.set_defaults(func=_cmd_run)

    sub.add_parser("doctor", help="check game paths, launchers and log locations").set_defaults(func=_cmd_doctor)

    p = sub.add_parser("linux-setup", help="detect Steam, Proton and Plutonium and write config/bridge.local.json")
    p.add_argument("--waw", choices=("plutonium", "proton", "steam", "skip"), default="plutonium",
                   help="how to run World at War (default: plutonium)")
    p.add_argument("--bo1", choices=("plutonium", "proton", "skip"), default="plutonium",
                   help="how to run Black Ops (default: plutonium)")
    p.add_argument("--plutonium-dir", type=Path, help="Plutonium folder (the one containing bin/ and storage/)")
    p.add_argument("--steam-dir", type=Path, help="Steam folder (the one containing steamapps/)")
    p.add_argument("--name", default="Player", help="in-game player name for Plutonium LAN mode")
    p.add_argument("--print", action="store_true", help="show the generated config instead of writing it")
    p.set_defaults(func=_cmd_linux_setup)

    p = sub.add_parser("install-plutonium", help="copy the in-game script into Plutonium's storage folder")
    p.add_argument("--game", choices=("waw", "bo1", "all"), default="all")
    p.add_argument("--plutonium-dir", type=Path, help="override the folder from bridge.local.json")
    p.set_defaults(func=_cmd_install_plutonium)

    p = sub.add_parser("simulate", help="process one travel request as if the game had printed it")
    p.add_argument("line", help="a PB1|... state string or a full console log line")
    p.set_defaults(func=_cmd_simulate)

    args = parser.parse_args(argv)
    try:
        config = load_config(args.config_dir)
        return args.func(config, args)
    except (ConfigError, FileNotFoundError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
