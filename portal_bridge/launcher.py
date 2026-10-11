"""Starts and stops World at War / Black Ops (natively on Windows, through
Proton/Wine on Linux)."""
from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Callable

from .config import Config, expand


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
        log: Callable[[str], None] = print,
    ):
        self.config = config
        self.dry_run = dry_run
        self._popen = popen
        self._run = run
        self._sleep = sleep
        self._clock = clock
        self._platform = platform
        self._log = log
        self._procs: dict[str, subprocess.Popen] = {}

    @property
    def _windows(self) -> bool:
        return self._platform.startswith("win")

    def game_dir(self, game: str) -> str:
        return expand(self.config.games[game].game_dir)

    def build_command(self, game: str, map_id: str, state: str | None = None) -> list[str]:
        cfg = self.config.games[game]
        if not cfg.launch:
            raise ValueError(f"games.{game}.launch is empty in bridge.json")
        command: list[str] = []
        for arg in cfg.launch:
            if arg == "{state_args}":
                if state:
                    command += ["+set", "pb_state", state]
                continue
            command.append(expand(arg, cfg.game_dir, map_id))
        return command

    def build_env(self, game: str) -> dict[str, str]:
        """Extra environment for the game, e.g. Proton's STEAM_COMPAT_DATA_PATH."""
        cfg = self.config.games[game]
        return {key: expand(value, cfg.game_dir) for key, value in cfg.env}

    def log_paths(self, game: str) -> list[Path]:
        cfg = self.config.games[game]
        return [Path(expand(t, cfg.game_dir)) for t in cfg.logs]

    def launch(self, game: str, map_id: str, state: str | None = None) -> None:
        command = self.build_command(game, map_id, state)
        extra_env = self.build_env(game)
        cwd = self.game_dir(game) or None

        shown = " ".join(f"{k}={v}" for k, v in extra_env.items())
        self._log(f"launching {game} {map_id}: {shown + ' ' if shown else ''}{subprocess.list2cmdline(command)}")
        if self.dry_run:
            return
        if cwd and not Path(cwd).is_dir():
            raise FileNotFoundError(
                f"games.{game}.game_dir {cwd!r} doesn't exist - set it in config/bridge.local.json"
            )
        env = {**os.environ, **extra_env} if extra_env else None
        # The engine resolves its data files relative to the working directory.
        self._procs[game] = self._popen(command, cwd=cwd, env=env)

    def is_running(self, game: str) -> bool:
        for name in self.config.games[game].process_names:
            if self._windows:
                result = self._run(
                    ["tasklist", "/FI", f"IMAGENAME eq {name}", "/NH"],
                    capture_output=True, text=True, check=False,
                )
                if name.lower() in (result.stdout or "").lower():
                    return True
            else:
                # Under Proton/Wine the Windows exe name is part of the command line.
                result = self._run(["pgrep", "-f", name], capture_output=True, text=True, check=False)
                if result.returncode == 0:
                    return True
        return False

    def stop(self, game: str) -> None:
        cfg = self.config.games[game]
        self._log(f"closing {game}")
        if self.dry_run:
            return

        proc = self._procs.pop(game, None)
        if proc is not None and proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()

        # Also catch instances the bridge didn't start itself (or that a
        # launcher such as `steam -applaunch` started on its behalf).
        for name in cfg.process_names:
            cmd = ["taskkill", "/F", "/IM", name] if self._windows else ["pkill", "-f", name]
            self._run(cmd, capture_output=True, text=True, check=False)

        deadline = self._clock() + float(self.config.bridge.get("kill_timeout_seconds", 15.0))
        while self.is_running(game):
            if self._clock() > deadline:
                self._log(f"warning: {game} still seems to be running; launching anyway")
                break
            self._sleep(0.5)

        # Give Steam / Proton a moment to notice the game is gone.
        self._sleep(float(self.config.bridge.get("kill_wait_seconds", 3.0)))
