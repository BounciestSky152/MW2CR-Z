"""Translates weapon names between World at War and Black Ops using config/weapons.json."""
from __future__ import annotations

import copy
from typing import Any

from .state import TravelState, WeaponState


def _dedupe(names: list[str]) -> list[str]:
    seen: set[str] = set()
    out = []
    for n in names:
        if n not in seen:
            seen.add(n)
            out.append(n)
    return out


class WeaponTranslator:
    def __init__(self, weapons_cfg: dict[str, Any]):
        self.groups: list[dict[str, Any]] = weapons_cfg.get("groups", [])
        self.rules: dict[str, dict[str, str]] = weapons_cfg.get("upgrade_rules", {})

    def _rules(self, game: str) -> list[dict[str, str]]:
        return self.rules.get(game, {}).get("rules", [])

    def split_upgrade(self, name: str, game: str) -> tuple[str, bool]:
        """"ray_gun_upgraded_zm" -> ("ray_gun_zm", True) in BO1."""
        for base, upgraded in self.rules.get(game, {}).get("exceptions", {}).items():
            if name == upgraded:
                return base, True
        for rule in self._rules(game):
            up = rule.get("upgraded_suffix", "")
            if (name.startswith(rule.get("prefix", "")) and up and name.endswith(up)
                    and len(name) > len(up)):
                return name[: -len(up)] + rule.get("base_suffix", ""), True
        return name, False

    def make_upgraded(self, base: str, game: str) -> str | None:
        """The Pack-a-Punched name of `base` in `game`, or None if it has none."""
        cfg = self.rules.get(game, {})
        if base in cfg.get("no_upgrade", []):
            return None
        if base in cfg.get("exceptions", {}):
            return cfg["exceptions"][base]
        for rule in self._rules(game):
            suffix = rule.get("base_suffix", "")
            if not base.startswith(rule.get("prefix", "")):
                continue
            if suffix and not base.endswith(suffix):
                continue
            stem = base[: -len(suffix)] if suffix else base
            return stem + rule.get("upgraded_suffix", "")
        return None

    def find_group(self, name: str, game: str) -> dict[str, Any] | None:
        """The group listing `name` as a real weapon of `game`, preferring the
        group where it is the primary (first) name."""
        best = None
        best_index = None
        for group in self.groups:
            names = group.get(game, [])
            if name in names:
                index = names.index(name)
                if best_index is None or index < best_index:
                    best, best_index = group, index
        return best

    def translate(self, name: str, src: str, dst: str, limit: int = 6) -> list[str]:
        """Candidate names in `dst`, best first. The game uses the first one
        the destination map has registered."""
        base, upgraded = self.split_upgrade(name, src)
        group = self.find_group(base, src)

        if group is not None:
            names = list(group.get(dst, [])) + list(group.get(f"{dst}_fallback", []))
            if src == dst:
                names.insert(0, base)
        else:
            # Unknown weapon - the same name might still exist on the other side
            # (e.g. zombie_cymbal_monkey); the game validates it.
            names = [base]

        if upgraded:
            names = [u for u in (self.make_upgraded(n, dst) for n in names) if u] + names

        return _dedupe(names)[:limit]

    def translate_candidates(self, candidates: list[str], src: str, dst: str, limit: int = 6) -> list[str]:
        out: list[str] = []
        for c in candidates:
            out.extend(self.translate(c, src, dst, limit))
        return _dedupe(out)[:limit]

    def translate_state(self, state: TravelState, limit: int = 6) -> TravelState:
        out = copy.deepcopy(state)
        src, dst = state.src_game, state.dst_game
        for player in out.players.values():
            player.weapons = [
                WeaponState(self.translate_candidates(w.candidates, src, dst, limit), w.clip, w.stock)
                for w in player.weapons
            ]
            player.current = self.translate_candidates(player.current, src, dst, limit)
        return out

    def aliases(self, game: str) -> list[list[str]]:
        """Groups of names that are the same weapon within one game, used by the
        in-game fallback when travelling between maps of the same game."""
        return [list(g[game]) for g in self.groups if len(g.get(game, [])) >= 2]
