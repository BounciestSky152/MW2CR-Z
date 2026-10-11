"""Finding and stopping game processes on Linux by reading /proc directly.

Under Wine/Proton every Windows process gets its exe basename as its Linux
process name (truncated to 15 bytes, the kernel's comm limit), so we match
that exactly instead of `pkill -f`, which would also hit Proton's wrapper
processes, Steam's reaper and anything else with the exe path in its argv.
Matches can be narrowed to one Wine prefix via /proc/<pid>/environ.
"""
from __future__ import annotations

import os
import signal
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable

COMM_MAX = 15


@dataclass(frozen=True)
class Proc:
    pid: int
    comm: str
    cmdline: tuple[str, ...]
    wineprefix: str | None


def _norm_prefix(prefix: str | None) -> str | None:
    if not prefix:
        return None
    return os.path.normpath(prefix)


def _read(path: Path) -> bytes | None:
    try:
        return path.read_bytes()
    except OSError:
        return None


def list_procs(proc_root: Path = Path("/proc")) -> list[Proc]:
    procs: list[Proc] = []
    try:
        entries = list(proc_root.iterdir())
    except OSError:
        return procs
    for entry in entries:
        if not entry.name.isdigit():
            continue
        comm = _read(entry / "comm")
        if comm is None:
            continue
        cmdline = _read(entry / "cmdline") or b""
        environ = _read(entry / "environ") or b""
        wineprefix = None
        for var in environ.split(b"\0"):
            if var.startswith(b"WINEPREFIX="):
                wineprefix = var[len(b"WINEPREFIX="):].decode("utf-8", "replace")
                break
        procs.append(
            Proc(
                pid=int(entry.name),
                comm=comm.decode("utf-8", "replace").strip(),
                cmdline=tuple(a.decode("utf-8", "replace") for a in cmdline.split(b"\0") if a),
                wineprefix=wineprefix,
            )
        )
    return procs


def find_game(procs: Iterable[Proc], names: Iterable[str], wineprefix: str | None = None) -> list[Proc]:
    """Processes whose name is one of `names` (Windows exe names are fine; they
    are truncated like the kernel does) and, if given, that run in `wineprefix`."""
    wanted = {n[:COMM_MAX] for n in names}
    prefix = _norm_prefix(wineprefix)
    out = []
    for p in procs:
        if p.comm not in wanted:
            continue
        if prefix and _norm_prefix(p.wineprefix) != prefix:
            continue
        out.append(p)
    return out


def find_in_prefix(procs: Iterable[Proc], wineprefix: str) -> list[Proc]:
    """Everything still running in a Wine prefix (wineserver, services.exe, ...)."""
    prefix = _norm_prefix(wineprefix)
    return [p for p in procs if p.wineprefix and _norm_prefix(p.wineprefix) == prefix]


def find_steam_launch(procs: Iterable[Proc], app_id: str) -> list[Proc]:
    """Steam's `reaper SteamLaunch AppId=<id> -- ...` process. Steam shows the
    game as running (and won't start it again) until this exits."""
    out = []
    for p in procs:
        args = p.cmdline
        if "SteamLaunch" in args and f"AppId={app_id}" in args:
            out.append(p)
    return out


def send(pids: Iterable[int], sig: int, kill: Callable[[int, int], None] = os.kill) -> None:
    for pid in pids:
        try:
            kill(pid, sig)
        except (ProcessLookupError, PermissionError):
            pass


SIGTERM = signal.SIGTERM
SIGKILL = getattr(signal, "SIGKILL", signal.SIGTERM)
