"""Nacht der Untoten floor plan for the MW2CR (h2-mod) replica, and the
generator that bakes it into mod/nacht/scripts/nacht.gsc.

Units are game units (1 unit ~ 1 inch). The origin is the south-west inside
corner of the start room at floor level; x runs east, y north, z up. The
in-game builder places this origin relative to where the player stands.

The plan follows Nacht's rooms (start room, Help room, two rooms upstairs,
debris on the Help door and the stairs, boarded windows), not its exact
measurements, which aren't public.

Run:  python3 mw2cr_nacht/layout.py   (rewrites the .gsc)
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

HERE = Path(__file__).resolve().parent
TEMPLATE = HERE / "nacht_template.gsc"
OUTPUT = HERE / "mod" / "nacht" / "scripts" / "nacht.gsc"
MARK = "// @LAYOUT@"

T = 16        # wall / slab thickness
H = 144       # storey height (floor to ceiling)
UP = H + T    # upstairs floor level

KINDS = ("wall", "floor", "stair", "window", "debris", "rail")


@dataclass(frozen=True)
class Box:
    x0: int
    y0: int
    z0: int
    x1: int
    y1: int
    z1: int
    kind: str
    tag: str = ""

    def valid(self) -> bool:
        return self.x1 > self.x0 and self.y1 > self.y0 and self.z1 > self.z0 and self.kind in KINDS


def wall(axis: str, fixed0: int, fixed1: int, a0: int, a1: int, z0: int, z1: int,
         holes: list[tuple[int, int, int, int, str, str]] = ()) -> list[Box]:
    """A wall running along `axis` ("x" or "y") from a0 to a1, `fixed0..fixed1`
    thick on the other axis. Each hole (h0, h1, hz0, hz1, kind, tag) is cut out
    of the wall and, unless kind is "", filled with its own box (window boards,
    debris)."""
    def mk(b0, b1, c0, c1, kind, tag=""):
        if axis == "x":
            return Box(b0, fixed0, c0, b1, fixed1, c1, kind, tag)
        return Box(fixed0, b0, c0, fixed1, b1, c1, kind, tag)

    out: list[Box] = []
    holes = sorted(holes)
    cursor = a0
    for h0, h1, hz0, hz1, kind, tag in holes:
        assert a0 <= cursor <= h0 < h1 <= a1 and z0 <= hz0 < hz1 <= z1, (h0, h1)
        if h0 > cursor:
            out.append(mk(cursor, h0, z0, z1, "wall"))
        if hz0 > z0:
            out.append(mk(h0, h1, z0, hz0, "wall"))
        if hz1 < z1:
            out.append(mk(h0, h1, hz1, z1, "wall"))
        if kind:
            out.append(mk(h0, h1, hz0, hz1, kind, tag))
        cursor = h1
    if cursor < a1:
        out.append(mk(cursor, a1, z0, z1, "wall"))
    return out


def window(h0: int, h1: int, tag: str, upstairs: bool = False) -> tuple:
    base = UP if upstairs else 0
    return (h0, h1, base + 40, base + 112, "window", tag)


def nacht() -> list[Box]:
    b: list[Box] = []
    # Footprint: start room x 0..640, Help room x -400..-16 (west of it),
    # both y 0..448. Upstairs sits over the start room only.
    W0, W1 = -400 - T, 640 + T          # outer x of the whole building
    S0, S1 = -T, 448 + T                # outer y

    # --- ground floor -------------------------------------------------
    b.append(Box(W0, S0, -T, W1, S1, 0, "floor"))
    b += wall("x", -T, 0, W0, W1, 0, H, [
        window(-288, -192, "help_south"),
        window(96, 192, "start_south_w"),
        window(448, 544, "start_south_e"),
    ])
    b += wall("x", 448, 448 + T, W0, W1, 0, H, [
        window(-288, -192, "help_north"),
        window(96, 192, "start_north"),
    ])
    b += wall("y", 640, 640 + T, 0, 448, 0, H, [window(176, 272, "start_east")])
    b += wall("y", W0, W0 + T, 0, 448, 0, H, [window(176, 272, "help_west")])
    # Start room / Help room divider with the "Help" debris door.
    b += wall("y", -T, 0, 0, 448, 0, H, [(176, 288, 0, 112, "debris", "help_door")])

    # Stairs along the start room's north wall, climbing east to the upstairs
    # floor; the bottom is blocked by the upstairs debris.
    steps = UP // 16
    run0, run1 = 360, 640
    depth = (run1 - run0) // steps
    for i in range(steps):
        b.append(Box(run0 + depth * i, 352, 16 * i, run1, 448, 16 * (i + 1), "stair"))
    b.append(Box(296, 352, 0, run0, 448, 96, "debris", "stairs"))
    # Side wall so the steps can't be climbed from the room, only past the debris.
    b.append(Box(run0, 336, 0, run1, 352, H, "wall"))

    # --- slabs ----------------------------------------------------------
    b.append(Box(W0, S0, H, -T, S1, UP, "floor"))                 # Help room roof
    hole_x0, hole_y0 = 352, 352                                    # stairwell
    b.append(Box(-T, S0, H, W1, hole_y0, UP, "floor"))
    b.append(Box(-T, hole_y0, H, hole_x0, S1, UP, "floor"))
    b.append(Box(hole_x0, 448, H, W1, S1, UP, "floor"))
    b.append(Box(640, hole_y0, H, W1, 448, UP, "floor"))

    # --- upstairs ---------------------------------------------------------
    top = UP + H
    b += wall("x", -T, 0, -T, W1, UP, top, [
        window(96, 192, "up_south_w", True),
        window(448, 544, "up_south_e", True),
    ])
    b += wall("x", 448, 448 + T, -T, W1, UP, top, [window(96, 192, "up_north", True)])
    b += wall("y", 640, 640 + T, 0, 448, UP, top, [window(176, 272, "up_east", True)])
    b += wall("y", -T, 0, 0, 448, UP, top, [window(176, 272, "up_west", True)])
    # Wall splitting the upper floor into two rooms, with an open doorway.
    b += wall("y", 304, 304 + T, 0, 448, UP, top, [(160, 256, UP, UP + 112, "", "")])
    # Railing along the stairwell, open at the east end where the stairs arrive.
    b.append(Box(hole_x0, hole_y0 - 8, UP, 600, hole_y0, UP + 36, "rail"))

    b.append(Box(-T, S0, top, W1, S1, top + T, "floor"))           # roof
    return b


# Points of interest for the zombies mode: (x, y, z, yaw). Wall buys hang on
# the inside of a wall facing into the room; yaw is the way the weapon faces.
POINTS = {
    "player_start": (320, 160, 8, 90),
    "box": (560, 48, 0, 90),
    "wallbuy_rifle": (320, 4, 56, 90),            # start room, south wall (Kar98k)
    "wallbuy_carbine": (636, 96, 56, 180),        # start room, east wall (M1 Carbine)
    "wallbuy_smg": (-100, 4, 56, 90),             # Help room, south wall (Thompson)
    "wallbuy_shotgun": (240, 4, UP + 56, 90),     # upstairs, south wall (double barrel)
    "stairs_top": (626, 400, UP + 8, 270),        # where stuck zombies reappear upstairs
}

# Which debris must be bought before a window can spawn zombies.
WINDOW_NEEDS = {
    "help_south": "help_door",
    "help_north": "help_door",
    "help_west": "help_door",
}


def gsc_layout(boxes: list[Box]) -> str:
    lines = ["nacht_boxes()", "{", "\tb = [];"]
    for x in boxes:
        lines.append(
            f'\tb[ b.size ] = nacht_box( {x.x0}, {x.y0}, {x.z0}, {x.x1}, {x.y1}, {x.z1}, "{x.kind}", "{x.tag}" );'
        )
    lines += ["\treturn b;", "}", "", "nacht_points()", "{", "\tp = [];"]
    for name, (x, y, z, yaw) in POINTS.items():
        lines.append(f'\tp[ "{name}" ] = nacht_point( {x}, {y}, {z}, {yaw} );')
    lines += ["\treturn p;", "}", "", "nacht_window_needs()", "{", "\tn = [];"]
    for window, debris in WINDOW_NEEDS.items():
        lines.append(f'\tn[ "{window}" ] = "{debris}";')
    lines += ["\treturn n;", "}", ""]
    return "\n".join(lines)


def generate() -> str:
    template = TEMPLATE.read_text(encoding="utf-8")
    assert MARK in template
    return template.replace(MARK, gsc_layout(nacht()))


if __name__ == "__main__":
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(generate(), encoding="utf-8", newline="\n")
    boxes = nacht()
    print(f"wrote {OUTPUT} ({len(boxes)} boxes)")
