"""Watches for lines written by pb_emit(): appended to a console log (Mod
Tools route) or written as a small file the game rewrites each time
(Plutonium's fs_* API, the "signal file")."""
from __future__ import annotations

import time
from pathlib import Path

# A signal file without a trailing newline counts as complete once it has
# stopped changing for this long.
SETTLE_NS = 1_000_000_000


class LogTailer:
    def __init__(self, paths: list[Path] | None = None):
        self.paths: list[Path] = []
        self._offsets: dict[Path, int] = {}
        self._ids: dict[Path, tuple[int, int]] = {}
        self._partial: dict[Path, bytes] = {}
        self.signals: list[Path] = []
        self._signal_stamp: dict[Path, tuple | None] = {}
        for p in paths or []:
            self.add(p)

    def add_signal(self, path: Path) -> None:
        path = Path(path)
        if path not in self.signals:
            self.signals.append(path)

    @staticmethod
    def _stamp(path: Path) -> tuple | None:
        try:
            st = path.stat()
        except OSError:
            return None
        return (st.st_dev, st.st_ino, st.st_size, st.st_mtime_ns)

    def add(self, path: Path) -> None:
        path = Path(path)
        if path not in self.paths:
            self.paths.append(path)

    def prime(self, paths: list[Path] | None = None) -> None:
        """Skip whatever is already in the files, so stale requests from an
        earlier session are never replayed."""
        if paths is None:
            for sig in self.signals:
                self._signal_stamp[sig] = self._stamp(sig)
        for path in paths if paths is not None else self.paths:
            path = Path(path)
            if path in self.signals:
                self._signal_stamp[path] = self._stamp(path)
                continue
            self.add(path)
            try:
                st = path.stat()
            except OSError:
                self._offsets[path] = 0
                self._ids.pop(path, None)
            else:
                self._offsets[path] = st.st_size
                self._ids[path] = (st.st_dev, st.st_ino)
            self._partial[path] = b""

    def poll(self) -> list[str]:
        lines: list[str] = []
        for path in self.paths:
            lines.extend(self._poll_one(path))
        for path in self.signals:
            lines.extend(self._poll_signal(path))
        return lines

    def _poll_signal(self, path: Path) -> list[str]:
        stamp = self._stamp(path)
        if stamp is None or stamp == self._signal_stamp.get(path):
            return []
        try:
            data = path.read_bytes()
        except OSError:
            return []
        # Only remember the stamp once a full line is there, in case we caught
        # the game halfway through writing.
        if not data.endswith(b"\n") and stamp[3] > time.time_ns() - SETTLE_NS:
            return []
        self._signal_stamp[path] = stamp
        text = data.decode("utf-8", "replace")
        return [line.rstrip("\r") for line in text.split("\n") if line.strip()]

    def _poll_one(self, path: Path) -> list[str]:
        try:
            st = path.stat()
        except OSError:
            return []

        ident = (st.st_dev, st.st_ino)
        offset = self._offsets.get(path, 0)
        # The game truncates or recreates the log on every launch.
        if st.st_size < offset or (path in self._ids and self._ids[path] != ident):
            offset = 0
            self._partial[path] = b""
        self._ids[path] = ident

        if st.st_size == offset:
            return []

        try:
            with path.open("rb") as f:
                f.seek(offset)
                chunk = f.read()
        except OSError:
            return []

        self._offsets[path] = offset + len(chunk)
        data = self._partial.get(path, b"") + chunk
        *complete, rest = data.split(b"\n")
        self._partial[path] = rest
        return [line.decode("utf-8", "replace").rstrip("\r") for line in complete]
