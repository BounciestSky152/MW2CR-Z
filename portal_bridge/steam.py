"""Finds Steam, its libraries, installed games and Proton builds on Linux, so
`python -m portal_bridge linux-setup` can write bridge.local.json for you."""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

APP_IDS = {"waw": "10090", "bo1": "42700"}

# Native installs first, then Flatpak and Snap. ~/.steam/steam and ~/.steam/root
# are usually symlinks to ~/.local/share/Steam; duplicates are dropped by resolve().
STEAM_ROOT_CANDIDATES = (
    "~/.steam/steam",
    "~/.steam/root",
    "~/.local/share/Steam",
    "~/.var/app/com.valvesoftware.Steam/.local/share/Steam",
    "~/.var/app/com.valvesoftware.Steam/data/Steam",
    "~/snap/steam/common/.local/share/Steam",
)

_TOKEN_RE = re.compile(r'"((?:[^"\\]|\\.)*)"|([{}])|//[^\n]*')


class VdfError(ValueError):
    pass


_ESCAPES = {"\\\\": "\\", '\\"': '"', "\\n": "\n", "\\t": "\t"}


def _unescape(raw: str) -> str:
    return re.sub(r'\\[\\"nt]', lambda m: _ESCAPES[m.group(0)], raw)


def parse_vdf(text: str) -> dict:
    """Parse Valve's text KeyValues format (libraryfolders.vdf, *.acf,
    config.vdf, compatibilitytool.vdf). Keys are case-sensitive as written."""
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
            if pos >= len(tokens):
                raise VdfError(f"key {key!r} has no value")
            if tokens[pos] == "{\0":
                pos += 1
                out[key] = parse_block()
            elif tokens[pos] == "}\0":
                raise VdfError(f"key {key!r} has no value")
            else:
                out[key] = tokens[pos]
                pos += 1
        return out

    return parse_block()


def _get_ci(d: dict, key: str):
    """Case-insensitive lookup; Steam isn't consistent about key casing."""
    for k, v in d.items():
        if k.lower() == key.lower():
            return v
    return None


@dataclass
class SteamInstall:
    root: Path
    flatpak: bool = False
    libraries: list[Path] = field(default_factory=list)


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


@dataclass
class ProtonInstall:
    name: str          # internal name used in config.vdf, e.g. "proton_9"
    display_name: str
    path: Path         # directory holding the `proton` script

    @property
    def script(self) -> Path:
        return self.path / "proton"


def find_steam_roots(home: Path | None = None) -> list[SteamInstall]:
    home = home or Path.home()
    found: list[SteamInstall] = []
    seen: set[Path] = set()
    for candidate in STEAM_ROOT_CANDIDATES:
        path = Path(candidate.replace("~", str(home), 1))
        if not (path / "steamapps").is_dir():
            continue
        real = path.resolve()
        if real in seen:
            continue
        seen.add(real)
        install = SteamInstall(root=real, flatpak="com.valvesoftware.Steam" in candidate)
        install.libraries = library_folders(real)
        found.append(install)
    return found


def library_folders(steam_root: Path) -> list[Path]:
    libs = [steam_root]
    vdf = steam_root / "steamapps" / "libraryfolders.vdf"
    if vdf.is_file():
        try:
            data = _get_ci(parse_vdf(vdf.read_text(encoding="utf-8", errors="replace")), "libraryfolders") or {}
        except VdfError:
            data = {}
        for key, value in data.items():
            if not key.isdigit():
                continue
            # New format: "0" { "path" "..." }. Old format: "1" "/path".
            path = _get_ci(value, "path") if isinstance(value, dict) else value
            if path:
                libs.append(Path(path))
    out: list[Path] = []
    for lib in libs:
        real = lib.resolve() if lib.exists() else lib
        if real not in out:
            out.append(real)
    return out


def find_game(steam: SteamInstall, game: str) -> GameInstall | None:
    app_id = APP_IDS[game]
    for lib in steam.libraries:
        manifest = lib / "steamapps" / f"appmanifest_{app_id}.acf"
        if not manifest.is_file():
            continue
        try:
            state = _get_ci(parse_vdf(manifest.read_text(encoding="utf-8", errors="replace")), "AppState") or {}
        except VdfError:
            continue
        installdir = _get_ci(state, "installdir")
        if not installdir:
            continue
        return GameInstall(
            game=game,
            app_id=app_id,
            library=lib,
            game_dir=lib / "steamapps" / "common" / installdir,
            # Steam creates the prefix in the library the game is installed to.
            compatdata=lib / "steamapps" / "compatdata" / app_id,
        )
    return None


def find_protons(steam: SteamInstall) -> list[ProtonInstall]:
    dirs: list[Path] = []
    for lib in steam.libraries:
        common = lib / "steamapps" / "common"
        if common.is_dir():
            dirs += sorted(p for p in common.iterdir() if p.name.lower().startswith("proton"))
    tools = steam.root / "compatibilitytools.d"
    if tools.is_dir():
        dirs += sorted(p for p in tools.iterdir() if p.is_dir())

    found: list[ProtonInstall] = []
    for d in dirs:
        if not (d / "proton").is_file():
            continue
        name, display = d.name, d.name
        manifest = d / "compatibilitytool.vdf"
        if manifest.is_file():
            try:
                tools_block = _get_ci(parse_vdf(manifest.read_text(encoding="utf-8", errors="replace")), "compatibilitytools") or {}
                compat = _get_ci(tools_block, "compat_tools") or {}
                for internal, info in compat.items():
                    name = internal
                    if isinstance(info, dict):
                        display = _get_ci(info, "display_name") or display
                    break
            except VdfError:
                pass
        found.append(ProtonInstall(name=name, display_name=display, path=d))
    return found


def compat_tool_for(steam: SteamInstall, app_id: str) -> str | None:
    """The Proton the user picked for this game in Steam (or the global default)."""
    cfg = steam.root / "config" / "config.vdf"
    if not cfg.is_file():
        return None
    try:
        data = parse_vdf(cfg.read_text(encoding="utf-8", errors="replace"))
    except VdfError:
        return None
    node = data
    for key in ("InstallConfigStore", "Software", "Valve", "Steam", "CompatToolMapping"):
        node = _get_ci(node, key) if isinstance(node, dict) else None
        if node is None:
            return None
    for key in (app_id, "0"):
        entry = node.get(key)
        if isinstance(entry, dict) and _get_ci(entry, "name"):
            return _get_ci(entry, "name")
    return None


def _version_key(p: ProtonInstall) -> tuple:
    nums = [int(n) for n in re.findall(r"\d+", p.display_name)]
    experimental = "experimental" in p.display_name.lower()
    return (not experimental, nums)


def pick_proton(steam: SteamInstall, protons: list[ProtonInstall], app_id: str) -> ProtonInstall | None:
    wanted = compat_tool_for(steam, app_id)
    if wanted:
        for p in protons:
            if p.name == wanted or p.path.name == wanted:
                return p
    # Fall back to the newest numbered Valve/GE build.
    return max(protons, key=_version_key) if protons else None


def proton_game_config(game: str, install: GameInstall, steam: SteamInstall, proton: ProtonInstall, exe: str, extra_args: list[str]) -> dict:
    """bridge.local.json section that runs the game through `proton run`."""
    return {
        "game_dir": str(install.game_dir),
        "launch": [str(proton.script), "run", f"{{game_dir}}/{exe}", *extra_args],
        "env": {
            "STEAM_COMPAT_DATA_PATH": str(install.compatdata),
            "STEAM_COMPAT_CLIENT_INSTALL_PATH": str(steam.root),
            "SteamAppId": install.app_id,
            "SteamGameId": install.app_id,
        },
        "process_names": [exe],
    }


def prefix_appdata(install: GameInstall) -> Path:
    return install.prefix / "drive_c" / "users" / "steamuser" / "AppData" / "Local"
