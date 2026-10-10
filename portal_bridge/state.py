"""Travel state codec - must stay in sync with pb_encode_state / pb_decode_state
in gsc/shared/maps/_portal_bridge.gsc.

    PB1|n=<nonce>|src=<game>:<map>|dst=<game>:<map>|r=<round>|p0=<player>|p1=...
    <player>  = <score>~<perks>~<weapons>~<current>
    <perks>   = perk.perk...                          ("-" when empty)
    <weapons> = name[:alt...]@clip@stock.name@...     ("-" when empty)
    <current> = name[:alt...]                         ("-" when empty)

The alphabet is deliberately tiny: the string is passed on the game's command
line (`+set pb_state ...`), where spaces, quotes, `;` and `//` would be
interpreted by the engine's console parser.
"""
from __future__ import annotations

from dataclasses import dataclass, field

from .config import NAME_RE

VERSION = "PB1"


class StateError(ValueError):
    pass


@dataclass
class WeaponState:
    candidates: list[str]
    clip: int = 0
    stock: int = 0


@dataclass
class PlayerState:
    score: int = 500
    perks: list[str] = field(default_factory=list)
    weapons: list[WeaponState] = field(default_factory=list)
    current: list[str] = field(default_factory=list)


@dataclass
class TravelState:
    src_game: str
    src_map: str
    dst_game: str
    dst_map: str
    round: int = 1
    nonce: str = "0"
    players: dict[int, PlayerState] = field(default_factory=dict)


def _tok(text: str, sep: str) -> list[str]:
    # GSC's strTok drops empty tokens; match it so both sides agree.
    return [t for t in text.split(sep) if t]


def _int(text: str, what: str) -> int:
    try:
        return int(text)
    except ValueError:
        raise StateError(f"{what} is not a number: {text!r}") from None


def _name(text: str, what: str) -> str:
    if not NAME_RE.match(text):
        raise StateError(f"invalid {what}: {text!r}")
    return text


def _names(values: list[str], what: str) -> list[str]:
    return [_name(v, what) for v in values]


def _dash(text: str) -> str:
    return text if text else "-"


def encode_player(p: PlayerState) -> str:
    perks = ".".join(_names(p.perks, "perk"))
    weapons = ".".join(
        f"{':'.join(_names(w.candidates, 'weapon'))}@{int(w.clip)}@{int(w.stock)}"
        for w in p.weapons
        if w.candidates
    )
    current = ":".join(_names(p.current, "weapon"))
    return f"{int(p.score)}~{_dash(perks)}~{_dash(weapons)}~{_dash(current)}"


def encode(state: TravelState) -> str:
    parts = [
        VERSION,
        f"n={_name(str(state.nonce), 'nonce')}",
        f"src={_name(state.src_game, 'game')}:{_name(state.src_map, 'map')}",
        f"dst={_name(state.dst_game, 'game')}:{_name(state.dst_map, 'map')}",
        f"r={int(state.round)}",
    ]
    for index in sorted(state.players):
        parts.append(f"p{int(index)}={encode_player(state.players[index])}")
    return "|".join(parts)


def decode_player(text: str) -> PlayerState:
    fields = _tok(text, "~")
    if len(fields) < 4:
        raise StateError(f"player block needs 4 fields: {text!r}")
    score, perks, weapons, current = fields[:4]

    player = PlayerState(score=_int(score, "score"))
    if perks != "-":
        player.perks = _names(_tok(perks, "."), "perk")
    if weapons != "-":
        for item in _tok(weapons, "."):
            bits = _tok(item, "@")
            if len(bits) != 3:
                raise StateError(f"weapon entry needs name@clip@stock: {item!r}")
            player.weapons.append(
                WeaponState(
                    candidates=_names(_tok(bits[0], ":"), "weapon"),
                    clip=_int(bits[1], "clip"),
                    stock=_int(bits[2], "stock"),
                )
            )
    if current != "-":
        player.current = _names(_tok(current, ":"), "weapon")
    return player


def _game_map(value: str, what: str) -> tuple[str, str]:
    bits = _tok(value, ":")
    if len(bits) != 2:
        raise StateError(f"{what} must be game:map, got {value!r}")
    return _name(bits[0], "game"), _name(bits[1], "map")


def decode(text: str) -> TravelState:
    parts = _tok(text.strip(), "|")
    if not parts or parts[0] != VERSION:
        raise StateError(f"not a {VERSION} travel state: {text[:40]!r}")

    values: dict[str, str] = {}
    players: dict[int, PlayerState] = {}
    for part in parts[1:]:
        kv = _tok(part, "=")
        if len(kv) != 2:
            raise StateError(f"bad field {part!r}")
        key, value = kv
        if key.startswith("p") and key[1:].isdigit():
            players[int(key[1:])] = decode_player(value)
        else:
            values[key] = value

    if "src" not in values or "dst" not in values:
        raise StateError("travel state is missing src or dst")
    src_game, src_map = _game_map(values["src"], "src")
    dst_game, dst_map = _game_map(values["dst"], "dst")

    return TravelState(
        src_game=src_game,
        src_map=src_map,
        dst_game=dst_game,
        dst_map=dst_map,
        round=max(1, _int(values.get("r", "1"), "round")),
        nonce=values.get("n", "0"),
        players=players,
    )
