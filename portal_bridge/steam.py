"""Finds Steam, its libraries, installed games, Proton builds and Plutonium on
Linux, so `python -m portal_bridge linux-setup` can write bridge.local.json.

Layout facts used here (Valve's steam.sh / bin_steam.sh, protontricks,
steamlocate): ~/.steam/steam and ~/.steam/root are symlinks to the real Steam
directory; libraries are listed in steamapps/libraryfolders.vdf; a game's
Proton prefix lives in steamapps/compatdata/<appid> of the library the game is
installed in (stale copies can exist elsewhere - the newest pfx.lock wins).
"""
from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from pathlib import Path

APP_IDS = {"waw": "10090", "bo1": "42700"}
EXES = {"waw": "CoDWaW.exe", "bo1": "BlackOps.exe"}
FLATPAK_ID = "com.valvesoftware.Steam"

_TOKEN_RE = re.compile(r'"((?:[^"\\]|\\.)*)"|([{}])|//[^\n]*')
_ESCAPES = {"\\\\": "\\", '\\"': '"', "\\n": "\n", "\\t": "\t"}


class VdfError(ValueError):
    pass


def _unescape(raw: str) -> str:
    return re.sub(r'\\[\\"nt]', lambda m: _ESCAPES[m.group(0)], raw)


def parse_vdf(text: str) -> dict:
    """Parse Valve's text KeyValues format (libraryfolders.vdf, *.acf,
    config.vdf, compatibilitytool.vdf, toolmanifest.vdf)."""
    tokens: list[str] = []
    for m in _TOKEN_RE.finditer(text):
        if m.group(1) is not None:
            tokens.append(_unescape(m.group(1)))
        elif m.group(2):
            tokens.append(m.group(2) + "\0")  # mark braces so a quoted "{" stays a string

    pos = 0

    def parse_block() -> dict:
        nonlocal pos
        out: dict = {}
        while pos < len(tokens):
            tok = tokens[pos]
            if tok == "}\0":
                pos += 1
                return out
            if tok == "{\0":
                raise VdfError("unexpected '{'")
            key = tok
            pos += 1
            if pos >= len(tokens) or tokens[pos] == "}\0":
                raise VdfError(f"key {key!r} has no value")
            if tokens[pos] == "{\0":
                pos += 1
                out[key] = parse_block()
            else:
                out[key] = tokens[pos]
                pos += 1
        return out

    return parse_block()


def read_vdf(path: Path) -> dict | None:
    try:
        return parse_vdf(path.read_text(encoding="utf-8", errors="replace"))
    except (OSError, VdfError):
        return None


def get_ci(d, key: str):
    """Case-insensitive lookup; Steam isn't consistent about key casing."""
    if not isinstance(d, dict):
        return None
    for k, v in d.items():
        if k.lower() == key.lower():
            return v
    return None


def steamapps_dir(root: Path) -> Path | None:
    """<root>/steamapps, accepting the old "SteamApps" spelling."""
    try:
        for child in root.iterdir():
            if child.name.lower() == "steamapps" and child.is_dir():
                return child
    except OSError:
        pass
    return None


@dataclass
class SteamInstall:
    root: Path
    kind: str = "native"  # native | flatpak | snap
    libraries: list[Path] = field(default_factory=list)

    @property
    def flatpak(self) -> bool:
        return self.kind == "flatpak"

    def launch_prefix(self) -> list[str]:
        """Command that hands `-applaunch ...` to this Steam client."""
        if self.kind == "flatpak":
            return ["flatpak", "run", FLATPAK_ID]
        if self.kind == "snap":
            return ["snap", "run", "steam"]
        return ["steam"]


@dataclass
class GameInstall:
    game: str
    app_id: str
    library: Path
    game_dir: Path
    compatdata: Path

    @property
    def prefix(self) -> Path:
        return self.compatdata / "pfx"

    @property
    def has_prefix(self) -> bool:
        return self.prefix.is_dir()

    @property
    def exe(self) -> str:
        return EXES[self.game]


@dataclass
class ProtonInstall:
    name: str          # internal name used in config.vdf, e.g. "proton_9" / "GE-Proton9-20"
    display_name: str
    path: Path         # directory holding the `proton` script

    @property
    def script(self) -> Path:
        return self.path / "proton"


def root_candidates(home: Path, env: dict[str, str]) -> list[tuple[str, str]]:
    xdg = env.get("XDG_DATA_HOME") or str(home / ".local/share")
    snap = env.get("SNAP_USER_DATA") or str(home / "snap")
    cands = []
    for var in ("PORTAL_BRIDGE_STEAM_DIR", "STEAM_DIR"):
        if env.get(var):
            cands.append((env[var], "native"))
    cands += [
        (f"{xdg}/Steam", "native"),
        (str(home / ".steam/steam"), "native"),
        (str(home / ".steam/root"), "native"),
        (str(home / ".steam/debian-installation"), "native"),
        (str(home / "Steam"), "native"),
        # Flatpak: probe the real directory, never the sandbox's ~/.steam symlinks.
        (str(home / f".var/app/{FLATPAK_ID}/.local/share/Steam"), "flatpak"),
        (str(home / f".var/app/{FLATPAK_ID}/data/Steam"), "flatpak"),
        (f"{snap}/steam/common/.local/share/Steam", "snap"),
        (str(home / ".snap/data/steam/common/.local/share/Steam"), "snap"),
    ]
    return cands


def find_steam_roots(home: Path | None = None, env: dict[str, str] | None = None) -> list[SteamInstall]:
    home = home or Path.home()
    env = dict(os.environ) if env is None else env
    found: list[SteamInstall] = []
    seen: set[Path] = set()
    for candidate, kind in root_candidates(home, env):
        path = Path(candidate)
        if steamapps_dir(path) is None:
            continue
        real = path.resolve()
        if real in seen:
            continue
        seen.add(real)
        install = SteamInstall(root=real, kind=kind)
        install.libraries = library_folders(install, home)
        found.append(install)
    return found


def library_folders(steam: SteamInstall, home: Path | None = None) -> list[Path]:
    home = home or Path.home()
    libs = [steam.root]  # the old format doesn't list the main install
    sa = steamapps_dir(steam.root)
    data = None
    for vdf in ([sa / "libraryfolders.vdf"] if sa else []) + [steam.root / "config" / "libraryfolders.vdf"]:
        data = get_ci(read_vdf(vdf), "libraryfolders") if vdf.is_file() else None
        if data:
            break
    for key, value in (data or {}).items():
        if not key.isdigit():
            continue
        # New format: "0" { "path" "..." }. Old format: "1" "/path".
        path = get_ci(value, "path") if isinstance(value, dict) else value
        if not path:
            continue
        p = Path(path)
        if steam.flatpak and (p == home / ".local/share/Steam" or home / ".local/share/Steam" in p.parents):
            # Paths written inside the sandbox; protontricks remaps them the same way.
            p = home / f".var/app/{FLATPAK_ID}/.local/share/Steam" / p.relative_to(home / ".local/share/Steam")
        libs.append(p)
    out: list[Path] = []
    for lib in libs:
        real = lib.resolve() if lib.exists() else lib
        if real not in out:
            out.append(real)
    return out


def _installed(state: dict) -> bool:
    flags = get_ci(state, "StateFlags")
    try:
        flags = int(flags)
    except (TypeError, ValueError):
        return True  # be lenient with odd manifests
    return bool(flags & 4) and not flags & 1


def find_compatdata(steam: SteamInstall, app_id: str, preferred: Path | None = None) -> Path | None:
    """The prefix Steam actually uses for `app_id`: the game's own library
    first, otherwise whichever library's copy was launched most recently."""
    found = []
    for lib in steam.libraries:
        sa = steamapps_dir(lib)
        if sa is None:
            continue
        cd = sa / "compatdata" / app_id
        if (cd / "pfx").is_dir():
            lock = cd / "pfx.lock"
            mtime = lock.stat().st_mtime if lock.exists() else 0.0
            found.append((lib == preferred, mtime, cd))
    if not found:
        return None
    return max(found, key=lambda t: (t[0], t[1]))[2]


def find_game(steam: SteamInstall, game: str) -> GameInstall | None:
    app_id = APP_IDS[game]
    for lib in steam.libraries:
        sa = steamapps_dir(lib)
        if sa is None:
            continue
        state = get_ci(read_vdf(sa / f"appmanifest_{app_id}.acf"), "AppState")
        if not state or not _installed(state):
            continue
        installdir = get_ci(state, "installdir")
        if not installdir:
            continue
        compat = find_compatdata(steam, app_id, preferred=lib) or (sa / "compatdata" / app_id)
        return GameInstall(game=game, app_id=app_id, library=lib,
                           game_dir=sa / "common" / installdir, compatdata=compat)
    return None


def _compat_tool_dirs(steam: SteamInstall, env: dict[str, str]) -> list[Path]:
    dirs = [Path("/usr/share/steam/compatibilitytools.d"), Path("/usr/local/share/steam/compatibilitytools.d")]
    dirs += [Path(p) for p in env.get("STEAM_EXTRA_COMPAT_TOOLS_PATHS", "").split(":") if p]
    dirs.append(steam.root / "compatibilitytools.d")
    return dirs


def find_protons(steam: SteamInstall, env: dict[str, str] | None = None) -> list[ProtonInstall]:
    env = dict(os.environ) if env is None else env
    candidates: list[Path] = []
    for lib in steam.libraries:
        sa = steamapps_dir(lib)
        common = sa / "common" if sa else None
        if common and common.is_dir():
            candidates += sorted(p for p in common.iterdir() if p.name.lower().startswith("proton"))
    for d in _compat_tool_dirs(steam, env):
        if d.is_dir():
            candidates += sorted(p for p in d.iterdir() if p.is_dir())

    found: list[ProtonInstall] = []
    for d in candidates:
        if not (d / "proton").is_file():
            continue
        name, display = d.name, d.name
        tools = get_ci(get_ci(read_vdf(d / "compatibilitytool.vdf"), "compatibilitytools"), "compat_tools")
        if isinstance(tools, dict):
            for internal, info in tools.items():
                name = internal
                display = get_ci(info, "display_name") or display
                break
        found.append(ProtonInstall(name=name, display_name=display, path=d))
    return found


def compat_tool_for(steam: SteamInstall, app_id: str) -> str | None:
    """The tool picked for this game in Steam's settings (or the global default)."""
    node = read_vdf(steam.root / "config" / "config.vdf")
    for key in ("InstallConfigStore", "Software", "Valve", "Steam", "CompatToolMapping"):
        node = get_ci(node, key)
        if node is None:
            return None
    for key in (app_id, "0"):
        name = get_ci(get_ci(node, key), "name")
        if name:
            return name
    return None


def _match_tool_name(name: str, protons: list[ProtonInstall]) -> ProtonInstall | None:
    for p in protons:
        if p.name == name or p.path.name == name:
            return p
    # Valve's own builds don't ship compatibilitytool.vdf; their internal names
    # map to directory names like this.
    if name == "proton_experimental":
        return next((p for p in protons if p.path.name == "Proton - Experimental"), None)
    m = re.fullmatch(r"proton_(\d+)", name)
    if m:
        digits = m.group(1)
        for prefix in (f"Proton {digits}", f"Proton {digits[0]}.{digits[1:]}" if len(digits) > 1 else None):
            if prefix:
                hit = next((p for p in protons if re.match(re.escape(prefix) + r"(\b|\.|$)", p.path.name)), None)
                if hit:
                    return hit
    return None


def proton_from_prefix(compatdata: Path, protons: list[ProtonInstall]) -> ProtonInstall | None:
    """compatdata/<id>/config_info line 2 is '<proton dir>/files/share/fonts/'
    for the Proton that last set the prefix up."""
    try:
        lines = (compatdata / "config_info").read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return None
    if len(lines) < 2:
        return None
    m = re.match(r"(.*?)/(files|dist)/share/fonts/?$", lines[1].strip())
    if not m:
        return None
    path = Path(m.group(1))
    for p in protons:
        if p.path.resolve() == path.resolve():
            return p
    if (path / "proton").is_file():
        return ProtonInstall(name=path.name, display_name=path.name, path=path)
    return None


def _version_key(p: ProtonInstall) -> tuple:
    nums = [int(n) for n in re.findall(r"\d+", p.display_name)]
    return ("experimental" not in p.display_name.lower(), nums)


def pick_proton(steam: SteamInstall, protons: list[ProtonInstall], app_id: str,
                compatdata: Path | None = None) -> ProtonInstall | None:
    if compatdata is not None:
        used = proton_from_prefix(compatdata, protons)
        if used:
            return used
    wanted = compat_tool_for(steam, app_id)
    if wanted:
        hit = _match_tool_name(wanted, protons)
        if hit:
            return hit
    return max(protons, key=_version_key) if protons else None


def runtime_entry_point(steam: SteamInstall, proton: ProtonInstall) -> Path | None:
    """The Steam Linux Runtime container Steam wraps this Proton in (sniper for
    Proton 8-10, SteamLinuxRuntime_4 for 11+), via toolmanifest.vdf."""
    manifest = None
    for name in ("toolmanifest.vdf", "toolmanifest_x86_64.vdf"):
        manifest = get_ci(read_vdf(proton.path / name), "manifest")
        if manifest:
            break
    tool_id = get_ci(manifest, "require_tool_appid")
    if not tool_id:
        return None
    for lib in steam.libraries:
        sa = steamapps_dir(lib)
        if sa is None:
            continue
        state = get_ci(read_vdf(sa / f"appmanifest_{tool_id}.acf"), "AppState")
        installdir = get_ci(state, "installdir")
        if installdir:
            entry = sa / "common" / installdir / "_v2-entry-point"
            if entry.is_file():
                return entry
    return None


# -- Plutonium -------------------------------------------------------------

PLUTONIUM_BOOTSTRAPPER = "bin/plutonium-bootstrapper-win32.exe"


def plutonium_candidates(home: Path, steams: list[SteamInstall], games: list[GameInstall]) -> list[Path]:
    """Places people install Plutonium on Linux (DeckOps, ZShareT4/ZPauseT4
    installers): inside each game's own Proton prefix first."""
    cands: list[Path] = []
    for g in games:
        cands += sorted((g.prefix / "drive_c" / "users").glob("*/AppData/Local/Plutonium"))
    for s in steams:
        for lib in s.libraries:
            sa = steamapps_dir(lib)
            if sa:
                cands += sorted((sa / "compatdata").glob("*/pfx/drive_c/users/*/AppData/Local/Plutonium"))
    for pattern in (
        ".wine/drive_c/users/*/AppData/Local/Plutonium",
        "Games/*/drive_c/users/*/AppData/Local/Plutonium",
        ".local/share/lutris/prefixes/*/drive_c/users/*/AppData/Local/Plutonium",
        ".local/share/bottles/bottles/*/drive_c/users/*/AppData/Local/Plutonium",
        ".local/share/wineprefixes/*/drive_c/users/*/AppData/Local/Plutonium",
    ):
        cands += sorted(home.glob(pattern))
    cands += [home / ".local/share/Plutonium", home / "Plutonium"]
    out = []
    for c in cands:
        if (c / PLUTONIUM_BOOTSTRAPPER).is_file() and c not in out:
            out.append(c)
    return out


def wine_prefix_of(path: Path) -> Path | None:
    """/x/pfx/drive_c/users/... -> /x/pfx"""
    parts = path.parts
    if "drive_c" not in parts:
        return None
    return Path(*parts[: parts.index("drive_c")])


def compatdata_of(prefix: Path) -> Path | None:
    """Proton prefixes are <compatdata>/<id>/pfx; STEAM_COMPAT_DATA_PATH is the parent."""
    if prefix.name == "pfx" and prefix.parent.parent.name == "compatdata":
        return prefix.parent
    return None


def kernel_has_ntsync(release: str) -> bool:
    """NTSync (kernel >= 6.14) makes BO1's esync/fsync workarounds unnecessary."""
    m = re.match(r"(\d+)\.(\d+)", release)
    return bool(m) and (int(m.group(1)), int(m.group(2))) >= (6, 14)


def is_steam_deck(os_release: str) -> bool:
    return "ID=steamos" in os_release and "VARIANT_ID=steamdeck" in os_release
