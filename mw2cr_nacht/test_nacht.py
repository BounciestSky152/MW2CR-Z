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
# (h2_func.cpp / h2_meth.cpp) and h2-mod's extensions (print, executecommand). Functions and
# methods are separate: calling a function as a method fails to compile.
H2_FUNCTIONS = {
    "anglestoforward", "executecommand", "getallnodes", "getdvar", "gettime", "sighttracepassed",
    "abs", "bullettrace", "bullettracepassed", "ceil", "distance", "earthquake", "getaiarray", "getdvarint",
    "getentarray", "getspawnerarray", "getspawnerteamarray", "getsubstr", "getweaponmodel", "int", "iprintln", "iprintlnbold",
    "isalive", "issubstr", "length", "newhudelem", "precacheshader", "print", "randomint", "setdvar",
    "setdvarifuninitialized", "spawn", "spawnstruct", "strtok", "tolower", "vectornormalize", "vectortoangles",
    "weaponclass", "weaponinventorytype",
}
H2_METHODS = {
    "clonebrushmodeltoscriptmodel", "delete", "destroy", "dodamage", "fadeovertime", "forceteleport",
    "getcurrentweapon", "getpointinbounds", "getweaponslistall", "getweaponslistprimaries", "givemaxammo", "islinked",
    "giveweapon", "hasweapon", "hide", "notsolid", "rotateyaw", "setgoalentity", "setgoalpos", "setmodel",
    "setnormalhealth", "setorigin", "setspawnerteam", "setplayerangles", "setshader", "settext", "setvalue", "show", "solid",
    "stalingradspawn", "switchtoweapon", "takeallweapons", "takeweapon", "usebuttonpressed", "viewkick",
}
KEYWORDS = {"if", "for", "while", "foreach", "return", "isdefined", "wait", "endon", "notify", "waittill",
            "thread", "else", "in"}


def code():
    src = (ROOT / "mod/nacht/scripts/nacht.gsc").read_text()
    src = re.sub(r"//[^\n]*", "", src)
    return re.sub(r'"(?:[^"\\]|\\.)*"', '""', src)


def test_generated_script_is_up_to_date():
    assert (ROOT / "mod/nacht/scripts/nacht.gsc").read_text() == layout.generate()


def calls():
    """(name, is_method) for every call; a method has its object on the same line."""
    c = code()
    defs = set(re.findall(r"^([a-z_0-9]+)\s*\(", c, re.M))
    out = set()
    for m in re.finditer(r"\b([a-z_0-9]+)\s*\(", c):
        name = m.group(1)
        line_start = c.rfind("\n", 0, m.start()) + 1
        if name in KEYWORDS or name in defs or m.start() == line_start:
            continue
        before = c[line_start:m.start()].rstrip(" \t")
        word = re.search(r"(\w+)$", before)
        is_method = bool(re.search(r"[\w\])]$", before)) and not (word and word.group(1) in KEYWORDS)
        out.add((name, is_method))
    return out


def test_every_call_is_defined_or_an_h2_builtin():
    found = calls()
    assert {n for n, m in found if m} <= H2_METHODS
    assert {n for n, m in found if not m} <= H2_FUNCTIONS


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


def test_no_function_defined_twice():
    names = re.findall(r"^([a-z_0-9]+)\s*\(", code(), re.M)
    assert len(names) == len(set(names)), sorted({n for n in names if names.count(n) > 1})
