"""Static checks on the MW2CR Nacht replica (no MW2CR compiler here)."""
import importlib.util
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("nacht_layout", ROOT / "layout.py")
layout = importlib.util.module_from_spec(spec)
sys.modules["nacht_layout"] = layout
spec.loader.exec_module(layout)

# H2 (MW2CR) builtins the script uses, checked against gsc-tool's h2 tables
# and h2-mod's script extensions (print).
H2_BUILTINS = {
    "ceil", "clonebrushmodeltoscriptmodel", "delete", "getdvarint", "getentarray", "getpointinbounds",
    "int", "iprintln", "issubstr", "notsolid", "print", "setdvar", "setdvarifuninitialized", "setmodel",
    "setorigin", "setplayerangles", "solid", "spawn", "spawnstruct", "strtok", "tolower",
}
KEYWORDS = {"if", "for", "while", "foreach", "return", "isdefined", "wait"}


def code():
    src = (ROOT / "mod/nacht/scripts/nacht.gsc").read_text()
    src = re.sub(r"//[^\n]*", "", src)
    return re.sub(r'"(?:[^"\\]|\\.)*"', '""', src)


def test_generated_script_is_up_to_date():
    assert (ROOT / "mod/nacht/scripts/nacht.gsc").read_text() == layout.generate()


def test_every_call_is_defined_or_an_h2_builtin():
    c = code()
    defs = set(re.findall(r"^([a-z_0-9]+)\s*\(", c, re.M))
    calls = set(re.findall(r"(?<![\w.])([a-z_0-9]+)\s*\(", c))
    assert calls - defs - KEYWORDS <= H2_BUILTINS


def test_brackets_balance():
    c, stack = code(), []
    for ch in c:
        if ch in "([{":
            stack.append(ch)
        elif ch in ")]}":
            assert stack and stack.pop() == {")": "(", "]": "[", "}": "{"}[ch]
    assert not stack


def test_layout_has_nacht_rooms_and_entrances():
    boxes = layout.nacht()
    assert all(b.valid() for b in boxes)
    tags = {b.tag for b in boxes}
    assert {"help_door", "stairs"} <= tags
    assert sum(b.kind == "window" for b in boxes) >= 9
    # The stairs reach the upstairs floor.
    assert max(b.z1 for b in boxes if b.kind == "stair") == layout.UP
