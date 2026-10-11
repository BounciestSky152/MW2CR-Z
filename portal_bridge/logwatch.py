"""Tails the games' console logs for lines written by pb_emit()."""
from __future__ import annotations

from pathlib import Path


class LogTailer:
    def __init__(self, paths: list[Path] | None = None):
        self.paths: list[Path] = []
        self._offsets: dict[Path, int] = {}
        self._ids: dict[Path, tuple[int, int]] = {}
        self._partial: dict[Path, bytes] = {}
        for p in paths or []:
            self.add(p)

    def add(self, path: Path) -> None:
        path = Path(path)
        if path not in self.paths:
            self.paths.append(path)

    def prime(self, paths: list[Path] | None = None) -> None:
        """Skip whatever is already in the files, so stale requests from an
        earlier session are never replayed."""
        for path in paths if paths is not None else self.paths:
            path = Path(path)
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
        return lines

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
