"""Command line: python -m portal_bridge <command>."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import __version__
from .bridge import Bridge, TRAVEL_RE
from .build import build
from .config import ConfigError, load_config
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
    problems = 0

    def check(ok: bool, label: str, hint: str = "") -> None:
        nonlocal problems
        print(f"  [{'ok' if ok else '!!'}] {label}")
        if not ok:
            problems += 1
            if hint:
                print(f"       -> {hint}")

    if not sys.platform.startswith("win"):
        for tool in ("pgrep", "pkill"):
            check(shutil.which(tool) is not None, f"`{tool}` is installed", "install procps (procps-ng)")

    for game, cfg in config.games.items():
        print(f"{cfg.label} ({game})")
        game_dir = launcher.game_dir(game)
        check(bool(game_dir) and Path(game_dir).is_dir(), f"game_dir {game_dir}",
              "set games.%s.game_dir in config/bridge.local.json" % game)

        command = launcher.build_command(game, "MAP")
        if command and _looks_like_path(command[0]):
            check(Path(command[0]).is_file(), f"launcher {command[0]}")
        elif command:
            check(shutil.which(command[0]) is not None, f"`{command[0]}` is on PATH")
        for arg in command[1:]:
            if arg.lower().endswith(".exe") and _looks_like_path(arg):
                check(Path(arg).is_file(), f"game exe {arg}")

        for key, value in launcher.build_env(game).items():
            if _looks_like_path(value):
                check(Path(value).exists(), f"env {key}={value}",
                      "for STEAM_COMPAT_DATA_PATH, start the game from Steam once so Proton creates it")

        mod = Path(game_dir) / "mods" / "portal_bridge" if game_dir else None
        if mod is not None:
            has_mod = (mod / "mod.ff").is_file()
            print(f"  [{'ok' if has_mod else '--'}] built mod.ff in {mod}"
                  + ("" if has_mod else "  (fine if you use the Plutonium route instead)"))

        logs = launcher.log_paths(game)
        existing = [p for p in logs if p.is_file()]
        for p in logs:
            print(f"  [{'ok' if p.is_file() else '--'}] log {p}")
        if not existing:
            print("       -> no console.log yet; that's normal before the first launch with the mod.")
            print("          After one, if it still isn't listed, find it with:")
            print("          find ~ /mnt /media -name console.log -path '*portal_bridge*' 2>/dev/null"
                  if not sys.platform.startswith("win") else
                  "          dir /s /b %LOCALAPPDATA%\\console.log")

    print("no problems found" if problems == 0 else f"{problems} problem(s) found")
    return 0 if problems == 0 else 1


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
