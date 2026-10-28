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
    "abs", "bullettrace", "bullettracepassed", "ceil", "clonebrushmodeltoscriptmodel", "delete", "destroy",
    "distance", "dodamage", "earthquake", "fadeovertime", "forceteleport", "getaiarray", "getcurrentweapon",
    "getdvarint", "getentarray", "getpointinbounds", "getspawnerteamarray", "getsubstr", "getweaponmodel",
    "getweaponslistall", "getweaponslistprimaries", "givemaxammo", "giveweapon", "hasweapon", "hide", "int",
    "iprintln", "iprintlnbold", "isalive", "issubstr", "length", "newhudelem", "notsolid", "precacheshader",
    "print", "randomint", "rotateyaw", "setdvar", "setdvarifuninitialized", "setgoalentity", "setgoalpos",
    "setmodel", "setnormalhealth", "setorigin", "setplayerangles", "setshader", "settext", "setvalue", "show",
    "solid", "spawn", "spawnstruct", "stalingradspawn", "strtok", "switchtoweapon", "takeallweapons",
    "takeweapon", "tolower", "usebuttonpressed", "vectornormalize", "vectortoangles", "viewkick",
    "weaponclass", "weaponinventorytype",
}
KEYWORDS = {"if", "for", "while", "foreach", "return", "isdefined", "wait", "endon", "notify", "waittill"}


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


def test_menu_script_and_mod_info():
    import json
    lua = (ROOT / "mod/nacht/ui_scripts/nacht/__init__.lua").read_text()
    assert 'LUI.addmenubutton("main_campaign"' in lua and "nacht_autostart" in lua
    info = json.loads((ROOT / "mod/nacht/info.json").read_text())
    assert info["name"]


def test_no_reserved_words_or_call_indexing():
    """MW2CR's compiler rejects `x.size[i]` on structs, `size` as a name, and
    indexing a call result like `f()[1]`."""
    c = code()
    for word in ("size", "call", "default", "case", "game", "anim", "do", "assert", "istrue", "thisthread"):
        assert not re.search(r"(?<![\w.])%s\b" % word, c), word
    assert not re.search(r"\.size\s*\[", c)
    assert not re.search(r"\)\s*\[", c)
