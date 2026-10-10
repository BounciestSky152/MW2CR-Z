"""The bridge loop: watch for travel requests, swap games, hand the state over."""
from __future__ import annotations

import re
import threading
import time
from typing import Callable

from .config import Config, MapEntry
from .launcher import GameLauncher
from .logwatch import LogTailer
from .state import StateError, TravelState, decode, encode
from .translate import WeaponTranslator

TRAVEL_RE = re.compile(r"\[PORTAL_BRIDGE\] TRAVEL (PB1\|[^\s\"]+)")


class Bridge:
    def __init__(
        self,
        config: Config,
        launcher: GameLauncher,
        *,
        translator: WeaponTranslator | None = None,
        tailer: LogTailer | None = None,
        log: Callable[[str], None] = print,
    ):
        self.config = config
        self.launcher = launcher
        self.translator = translator or WeaponTranslator(config.weapons)
        self.tailer = tailer or LogTailer()
        self._log = log
        self._seen_nonces: set[str] = set()
        for game in config.games:
            for path in launcher.log_paths(game):
                self.tailer.add(path)

    def start(self, entry: MapEntry) -> None:
        self._launch(entry, None)

    def handle_line(self, line: str) -> bool:
        match = TRAVEL_RE.search(line)
        if not match:
            return False
        try:
            state = decode(match.group(1))
        except StateError as e:
            self._log(f"ignoring malformed travel request: {e}")
            return False
        if state.nonce in self._seen_nonces:
            return False
        self._seen_nonces.add(state.nonce)
        return self.travel(state)

    def travel(self, state: TravelState) -> bool:
        dest = self.config.find_map(state.dst_game, state.dst_map)
        if dest is None or not dest.enabled:
            self._log(f"travel request for unknown or disabled map {state.dst_game}:{state.dst_map}; ignoring")
            return False

        limit = int(self.config.bridge.get("max_weapon_candidates", 6))
        translated = self.translator.translate_state(state, limit)
        payload = encode(translated)

        self._log(
            f"portal: {state.src_game}:{state.src_map} -> {dest.key} "
            f"(round {state.round}, {len(state.players)} player(s))"
        )
        self.launcher.stop(state.src_game)
        if dest.game != state.src_game:
            self.launcher.stop(dest.game)
        self._launch(dest, payload)
        return True

    def _launch(self, entry: MapEntry, payload: str | None) -> None:
        # Ignore whatever the destination's log already holds.
        self.tailer.prime(self.launcher.log_paths(entry.game))
        self.launcher.launch(entry.game, entry.id, payload)

    def poll_once(self) -> int:
        handled = 0
        for line in self.tailer.poll():
            if self.handle_line(line):
                handled += 1
        return handled

    def run_forever(self, stop: threading.Event | None = None) -> None:
        stop = stop or threading.Event()
        interval = float(self.config.bridge.get("poll_interval", 0.25))
        self.tailer.prime()
        self._log("Portal Bridge is watching for portals. Ctrl+C to quit.")
        for path in self.tailer.paths:
            self._log(f"  watching {path}")
        while not stop.is_set():
            self.poll_once()
            time.sleep(interval)
