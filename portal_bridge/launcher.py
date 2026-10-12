"""Starts and stops World at War / Black Ops: natively on Windows, through
Proton, Wine or Plutonium on Linux, or via `steam -applaunch` plus a wrapper
script that reads its arguments from a file."""
from __future__ import annotations

import os
import secrets
import subprocess
import sys
import time
from pathlib import Path
from typing import Callable

from . import procs as procmod
from .config import Config, GameConfig, expand


class GameLauncher:
    def __init__(
        self,
        config: Config,
        *,
        dry_run: bool = False,
        popen: Callable[..., subprocess.Popen] = subprocess.Popen,
        run: Callable[..., subprocess.CompletedProcess] = subprocess.run,
        sleep: Callable[[float], None] = time.sleep,
        clock: Callable[[], float] = time.monotonic,
        platform: str = sys.platform,
        list_procs: Callable[[], list[procmod.Proc]] = procmod.list_procs,
        kill: Callable[[int, int], None] = os.kill,
        token: Callable[[], str] = lambda: secrets.token_hex(8),
        log: Callable[[str], None] = print,
    ):
        self.config = config
        self.dry_run = dry_run
        self._popen = popen
        self._run = run
        self._sleep = sleep
        self._clock = clock
        self._platform = platform
        self._list_procs = list_procs
        self._kill = kill
        self._token = token
        self._log = log
        self._procs: dict[str, subprocess.Popen] = {}

    @property
    def _windows(self) -> bool:
        return self._platform.startswith("win")

    # -- expansion ---------------------------------------------------------

    def _vars(self, cfg: GameConfig, token: str = "") -> dict[str, str]:
        values = {"token": token}
        # vars may refer to {game_dir} and to earlier vars.
        for key, value in cfg.vars:
            values[key] = expand(value, cfg.game_dir, extra=values)
        return values

    def _expand(self, cfg: GameConfig, template: str, map_id: str = "", token: str = "") -> str:
        return expand(template, cfg.game_dir, map_id, self._vars(cfg, token))

    def var(self, game: str, name: str) -> str | None:
        """An expanded entry from games.<game>.vars, e.g. pluto_dir."""
        cfg = self.config.games[game]
        if name not in dict(cfg.vars):
            return None
        return self._vars(cfg)[name]

    def game_dir(self, game: str) -> str:
        return expand(self.config.games[game].game_dir)

    def cwd(self, game: str) -> str:
        cfg = self.config.games[game]
        return self._expand(cfg, cfg.cwd) if cfg.cwd else ""

    def build_game_args(self, game: str, map_id: str, state: str | None = None, token: str = "") -> list[str]:
        cfg = self.config.games[game]
        args: list[str] = []
        for arg in cfg.game_args:
            if arg == "{state_args}":
                if state:
                    args += ["+set", "pb_state", state]
                continue
            args.append(self._expand(cfg, arg, map_id, token))
        return args

    def build_command(self, game: str, map_id: str, state: str | None = None, token: str = "") -> list[str]:
        cfg = self.config.games[game]
        if not cfg.launch:
            raise ValueError(f"games.{game}.launch is empty in bridge.json")
        command: list[str] = []
        for arg in cfg.launch:
            if arg == "{game_args}":
                command += self.build_game_args(game, map_id, state, token)
            elif arg == "{state_args}":  # older configs put the args straight in `launch`
                if state:
                    command += ["+set", "pb_state", state]
            else:
                command.append(self._expand(cfg, arg, map_id, token))
        return command

    def build_env(self, game: str) -> dict[str, str]:
        """Extra environment for the game, e.g. Proton's STEAM_COMPAT_DATA_PATH."""
        cfg = self.config.games[game]
        return {key: self._expand(cfg, value) for key, value in cfg.env}

    def log_paths(self, game: str) -> list[Path]:
        cfg = self.config.games[game]
        return [Path(self._expand(cfg, t)) for t in cfg.logs]

    def signal_paths(self, game: str) -> list[Path]:
        cfg = self.config.games[game]
        return [Path(self._expand(cfg, t)) for t in cfg.signal_files]

    def args_file(self, game: str) -> Path | None:
        cfg = self.config.games[game]
        return Path(self._expand(cfg, cfg.args_file)) if cfg.args_file else None

    def wineprefix(self, game: str) -> str | None:
        """The Wine prefix the game runs in, used to tell its processes apart
        from anything else with the same exe name."""
        cfg = self.config.games[game]
        if cfg.wineprefix:
            return self._expand(cfg, cfg.wineprefix)
        env = self.build_env(game)
        if env.get("WINEPREFIX"):
            return env["WINEPREFIX"]
        if env.get("STEAM_COMPAT_DATA_PATH"):
            # Proton sets WINEPREFIX=<compatdata>/pfx/ for everything it starts.
            return os.path.join(env["STEAM_COMPAT_DATA_PATH"].rstrip("/"), "pfx")
        return None

    # -- launching ---------------------------------------------------------

    def launch(self, game: str, map_id: str, state: str | None = None) -> None:
        token = self._token()
        command = self.build_command(game, map_id, state, token)
        extra_env = self.build_env(game)
        cwd = self.cwd(game) or None
        args_file = self.args_file(game)

        shown = " ".join(f"{k}={v}" for k, v in extra_env.items())
        self._log(f"launching {game} {map_id}: {shown + ' ' if shown else ''}{subprocess.list2cmdline(command)}")
        if args_file is not None:
            game_args = self.build_game_args(game, map_id, state, token)
            self._log(f"  game arguments via {args_file}: {subprocess.list2cmdline(game_args)}")
        if self.dry_run:
            return

        if cwd and not Path(cwd).is_dir():
            hint = "check config/bridge.local.json" if self._windows else \
                "run: python3 -m portal_bridge linux-setup  (needed again after every fresh download)"
            raise FileNotFoundError(f"games.{game} working directory {cwd!r} doesn't exist - {hint}")
        if args_file is not None:
            # Read (and deleted) by scripts/pb-wrap.sh, set as the game's Steam
            # launch options; nothing goes through Steam's shell-built command line.
            args_file.parent.mkdir(parents=True, exist_ok=True)
            args_file.write_text("".join(a + "\n" for a in game_args), encoding="utf-8")

        env = {**os.environ, **extra_env} if extra_env else None
        kwargs = {"cwd": cwd, "env": env}
        log_dir = self.config.bridge.get("game_log_dir")
        if log_dir:
            # Wine/Proton are chatty; keep their output out of the bridge's terminal.
            path = Path(expand(log_dir)) / f"{game}.log"
            path.parent.mkdir(parents=True, exist_ok=True)
            out = path.open("ab")
            kwargs.update(stdout=out, stderr=subprocess.STDOUT)
            self._log(f"  game output -> {path}")
        if not self._windows:
            # Keep the game alive if the bridge's terminal goes away, and out of
            # the bridge's Ctrl+C.
            kwargs["start_new_session"] = True
        try:
            self._procs[game] = self._popen(command, **kwargs)
        finally:
            if "stdout" in kwargs:
                kwargs["stdout"].close()  # the child keeps its own copy

    # -- stopping ----------------------------------------------------------

    def running_pids(self, game: str) -> list[int]:
        cfg = self.config.games[game]
        if self._windows:
            for name in cfg.process_names:
                result = self._run(
                    ["tasklist", "/FI", f"IMAGENAME eq {name}", "/NH"],
                    capture_output=True, text=True, check=False,
                )
                if name.lower() in (result.stdout or "").lower():
                    return [-1]  # tasklist doesn't need parsing for a yes/no
            return []
        return [p.pid for p in procmod.find_game(self._list_procs(), cfg.process_names, self.wineprefix(game))]

    def is_running(self, game: str) -> bool:
        return bool(self.running_pids(game))

    def _still_tearing_down(self, game: str) -> bool:
        if self._windows:
            return self.is_running(game)
        cfg = self.config.games[game]
        current = self._list_procs()
        if procmod.find_game(current, cfg.process_names, self.wineprefix(game)):
            return True
        prefix = self.wineprefix(game)
        if prefix and procmod.find_in_prefix(current, prefix):
            return True  # wineserver lingers ~3 s after the last client
        if cfg.steam_app_id and procmod.find_steam_launch(current, cfg.steam_app_id):
            return True  # Steam won't relaunch the app until its reaper exits
        return False

    def stop(self, game: str) -> None:
        cfg = self.config.games[game]
        self._log(f"closing {game}")
        if self.dry_run:
            return

        proc = self._procs.pop(game, None)
        if proc is not None and proc.poll() is None:
            proc.terminate()

        if self._windows:
            for name in cfg.process_names:
                self._run(["taskkill", "/F", "/IM", name], capture_output=True, text=True, check=False)
        else:
            # Wine has no SIGTERM handler, so this ends the game immediately.
            procmod.send(self.running_pids(game), procmod.SIGTERM, self._kill)

        deadline = self._clock() + float(self.config.bridge.get("kill_timeout_seconds", 20.0))
        escalated = False
        while self._still_tearing_down(game):
            if self._clock() > deadline:
                if self._windows or escalated:
                    self._log(f"warning: {game} still seems to be running; launching anyway")
                    break
                # Last resort: everything left in the game's prefix.
                prefix = self.wineprefix(game)
                leftovers = self.running_pids(game)
                if prefix:
                    leftovers += [p.pid for p in procmod.find_in_prefix(self._list_procs(), prefix)]
                procmod.send(leftovers, procmod.SIGKILL, self._kill)
                escalated = True
                deadline = self._clock() + 5.0
            self._sleep(0.25)

        if proc is not None:
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()

        # Give Steam / Proton a moment to notice the game is gone.
        self._sleep(float(self.config.bridge.get("kill_wait_seconds", 3.0)))
