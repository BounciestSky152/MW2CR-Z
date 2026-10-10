"""Starts and stops World at War / Black Ops."""
from __future__ import annotations

import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Callable

from .config import Config
from .logwatch import expand_path


class GameLauncher:
    def __init__(
        self,
        config: Config,
        *,
        dry_run: bool = False,
        popen: Callable[..., subprocess.Popen] = subprocess.Popen,
        run: Callable[..., object] = subprocess.run,
        sleep: Callable[[float], None] = time.sleep,
        platform: str = sys.platform,
        log: Callable[[str], None] = print,
    ):
        self.config = config
        self.dry_run = dry_run
        self._popen = popen
        self._run = run
        self._sleep = sleep
        self._platform = platform
        self._log = log
        self._procs: dict[str, subprocess.Popen] = {}

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
            arg = arg.replace("{game_dir}", cfg.game_dir).replace("{map}", map_id)
            command.append(os.path.expandvars(arg))
        return command

    def log_paths(self, game: str) -> list[Path]:
        cfg = self.config.games[game]
        return [expand_path(t, cfg.game_dir) for t in cfg.logs]

    def launch(self, game: str, map_id: str, state: str | None = None) -> None:
        command = self.build_command(game, map_id, state)
        cwd = self.config.games[game].game_dir or None
        self._log(f"launching {game} {map_id}: {subprocess.list2cmdline(command)}")
        if self.dry_run:
            return
        if cwd and not Path(cwd).is_dir():
            raise FileNotFoundError(
                f"games.{game}.game_dir {cwd!r} doesn't exist - set it in config/bridge.local.json"
            )
        # The engine resolves its data files relative to the working directory.
        self._procs[game] = self._popen(command, cwd=cwd)

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

        # Also catch instances the bridge didn't start itself.
        for name in cfg.process_names:
            if self._platform.startswith("win"):
                cmd = ["taskkill", "/F", "/IM", name]
            else:
                cmd = ["pkill", "-f", name]
            self._run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)

        self._sleep(float(self.config.bridge.get("kill_wait_seconds", 3.0)))
