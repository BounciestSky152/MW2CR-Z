"""Loads config/bridge.json, config/maps.json and config/weapons.json."""
from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CONFIG_DIR = REPO_ROOT / "config"
GAMES = ("waw", "bo1")

# Map ids and weapon names travel through dvars and console commands, so they
# must stay free of separators, quotes and anything the engine tokenizes.
NAME_RE = re.compile(r"^[A-Za-z0-9_]+$")
# Display names end up inside GSC string literals.
DISPLAY_RE = re.compile(r"^[A-Za-z0-9 '()\-.:!&,]+$")


class ConfigError(ValueError):
    pass


def wine_path(path: str) -> str:
    """/home/me/Games/WaW -> Z:\\home\\me\\Games\\WaW (Wine maps Z: to /)."""
    if len(path) >= 2 and path[1] == ":":
        return path.replace("/", "\\")
    return "Z:" + path.replace("/", "\\")


def expand(template: str, game_dir: str = "", map_id: str = "") -> str:
    """Fill {game_dir} / {game_dir_win} / {map}, then expand ~ and $VARS
    (%VARS% too on Windows)."""
    game_dir = os.path.expanduser(os.path.expandvars(game_dir))
    out = (
        template.replace("{game_dir_win}", wine_path(game_dir))
        .replace("{game_dir}", game_dir)
        .replace("{map}", map_id)
    )
    return os.path.expanduser(os.path.expandvars(out))


@dataclass(frozen=True)
class MapEntry:
    game: str
    id: str
    name: str
    enabled: bool = True

    @property
    def key(self) -> str:
        return f"{self.game}:{self.id}"


@dataclass(frozen=True)
class GameConfig:
    id: str
    label: str
    game_dir: str
    launch: tuple[str, ...]
    process_names: tuple[str, ...]
    logs: tuple[str, ...]
    env: tuple[tuple[str, str], ...] = ()


@dataclass
class Config:
    games: dict[str, GameConfig]
    maps: list[MapEntry]
    weapons: dict[str, Any]
    bridge: dict[str, Any]
    gameplay: dict[str, Any]

    def enabled_maps(self) -> list[MapEntry]:
        return [m for m in self.maps if m.enabled]

    def find_map(self, game: str, map_id: str) -> MapEntry | None:
        for m in self.maps:
            if m.game == game and m.id == map_id:
                return m
        return None

    def parse_map_ref(self, ref: str) -> MapEntry:
        """Resolve "game:map" or a bare map id that is unique across games."""
        if ":" in ref:
            game, map_id = ref.split(":", 1)
            entry = self.find_map(game, map_id)
        else:
            matches = [m for m in self.maps if m.id == ref]
            entry = matches[0] if len(matches) == 1 else None
        if entry is None:
            raise ConfigError(f"unknown map {ref!r}; run `python -m portal_bridge maps` to list them")
        return entry


def deep_merge(base: dict, override: dict) -> dict:
    merged = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def _read_json(path: Path) -> dict:
    try:
        with path.open(encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        raise ConfigError(f"missing config file {path}") from None
    except json.JSONDecodeError as e:
        raise ConfigError(f"{path}: {e}") from None


def _check_name(value: str, what: str) -> None:
    if not isinstance(value, str) or not NAME_RE.match(value):
        raise ConfigError(f"{what} {value!r} may only contain letters, digits and underscores")


def load_config(config_dir: Path | str | None = None) -> Config:
    config_dir = Path(config_dir) if config_dir else DEFAULT_CONFIG_DIR

    bridge_raw = _read_json(config_dir / "bridge.json")
    local = config_dir / "bridge.local.json"
    if local.exists():
        bridge_raw = deep_merge(bridge_raw, _read_json(local))

    games: dict[str, GameConfig] = {}
    for game_id in GAMES:
        raw = bridge_raw.get("games", {}).get(game_id)
        if raw is None:
            raise ConfigError(f"bridge.json has no games.{game_id} section")
        games[game_id] = GameConfig(
            id=game_id,
            label=raw.get("label", game_id.upper()),
            game_dir=raw.get("game_dir", ""),
            launch=tuple(raw.get("launch", [])),
            process_names=tuple(raw.get("process_names", [])),
            logs=tuple(raw.get("logs", [])),
            env=tuple((str(k), str(v)) for k, v in raw.get("env", {}).items()),
        )

    maps: list[MapEntry] = []
    seen: set[str] = set()
    for raw in _read_json(config_dir / "maps.json").get("maps", []):
        entry = MapEntry(raw["game"], raw["id"], raw["name"], bool(raw.get("enabled", True)))
        if entry.game not in GAMES:
            raise ConfigError(f"map {entry.id!r} has unknown game {entry.game!r}")
        _check_name(entry.id, "map id")
        if not DISPLAY_RE.match(entry.name):
            raise ConfigError(f"map name {entry.name!r} contains characters the in-game HUD can't show")
        if entry.key in seen:
            raise ConfigError(f"map {entry.key} is listed twice")
        seen.add(entry.key)
        maps.append(entry)

    weapons = _read_json(config_dir / "weapons.json")
    for group in weapons.get("groups", []):
        for game_id in GAMES:
            for key in (game_id, f"{game_id}_fallback"):
                for name in group.get(key, []):
                    _check_name(name, f"weapon in group {group.get('id')!r}")

    gameplay = bridge_raw.get("gameplay", {})
    custom_fx = gameplay.get("custom_fx", "")
    if custom_fx and not re.match(r"^[A-Za-z0-9_/]+$", custom_fx):
        raise ConfigError("gameplay.custom_fx must be an fx path like fx/portal_bridge/portal")

    return Config(
        games=games,
        maps=maps,
        weapons=weapons,
        bridge=bridge_raw.get("bridge", {}),
        gameplay=gameplay,
    )
