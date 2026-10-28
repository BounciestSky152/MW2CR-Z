"""Static checks on the MW2CR Zombies mod. There's no MW2CR compiler
here, so these catch what the game's compiler would reject: engine calls that
don't exist (or are functions called as methods), reserved words used as
names, indexing a call result, duplicate functions, unbalanced brackets."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MOD = ROOT / "mod" / "zombies"

# H2 (MW2CR) builtins the script uses, checked against gsc-tool's h2 tables
# (h2_func.cpp / h2_meth.cpp) and h2-mod's extensions (print, executecommand,
# assetexists).
H2_FUNCTIONS = {
    "assetexists", "cos", "istransientloaded", "loadtransient", "sin",
    "abs", "anglestoforward", "bullettrace", "bullettracepassed", "distance", "distance2d", "earthquake",
    "executecommand", "getaiarray", "getallnodes", "getdvar", "getdvarint", "getentarray", "getspawnerarray",
    "getsubstr", "gettime", "getweaponmodel", "int", "iprintln", "iprintlnbold", "isalive", "issubstr",
    "newhudelem", "precacheshader", "print", "randomint", "setdvarifuninitialized", "sighttracepassed",
    "spawn", "spawnstruct", "strtok", "tolower", "vectortoangles", "weaponclass", "weaponinventorytype",
}
H2_METHODS = {
    "enablehealthshield", "hidepart", "hudoutlineenable", "kill", "playerclearstreamorigin", "playersetstreamorigin",
    "setgoalpos", "setplayerangles", "geteye", "getplayerangles",
    "getpointinbounds",
    "delete", "disableinvulnerability", "dodamage", "enableinvulnerability", "enableweapons", "fadeovertime",
    "forceteleport", "freezecontrols", "getcurrentweapon", "getweaponslistall", "getweaponslistoffhands",
    "getweaponslistprimaries", "givemaxammo", "giveweapon", "hasweapon", "hide", "islinked", "notsolid",
    "rotateyaw", "setgoalentity", "setmodel", "setmovespeedscale", "setnormalhealth", "setorigin", "setshader",
    "setspawnerteam", "settext", "setvalue", "stalingradspawn", "switchtoweapon", "takeallweapons",
    "takeweapon", "unlink", "usebuttonpressed", "viewkick",
}
KEYWORDS = {"if", "for", "while", "foreach", "return", "isdefined", "wait", "endon", "notify", "waittill",
            "thread", "else", "in"}


def code():
    src = (MOD / "scripts" / "zombies.gsc").read_text()
    src = re.sub(r"//[^\n]*", "", src)
    return re.sub(r'"(?:[^"\\]|\\.)*"', '""', src)


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


def test_every_zm_function_called_exists():
    c = code()
    defs = set(re.findall(r"^([a-z_0-9]+)\s*\(", c, re.M))
    used = set(re.findall(r"\b(zm_[a-z_0-9]+)\s*\(", c))
    assert used <= defs


def test_no_function_defined_twice():
    names = re.findall(r"^([a-z_0-9]+)\s*\(", code(), re.M)
    assert len(names) == len(set(names))


def test_brackets_balance():
    stack = []
    for ch in code():
        if ch in "([{":
            stack.append(ch)
        elif ch in ")]}":
            assert stack and stack.pop() == {")": "(", "]": "[", "}": "{"}[ch]
    assert not stack


def test_no_reserved_words_or_call_indexing():
    """MW2CR's compiler rejects `size` as a name, `x.size[i]` and `f()[1]`."""
    c = code()
    for word in ("size", "call", "default", "case", "game", "anim", "do", "assert", "istrue", "thisthread"):
        assert not re.search(r"(?<![\w.])%s\b" % word, c), word
    assert not re.search(r"\.size\s*\[", c)
    assert not re.search(r"\)\s*\[", c)


def test_only_runs_on_wolverines():
    src = (MOD / "scripts" / "zombies.gsc").read_text()
    assert 'if( getdvar( "mapname" ) != "invasion" )\n\t\treturn;' in src


def test_menu_and_mod_info():
    lua = (MOD / "ui_scripts" / "zombies" / "__init__.lua").read_text()
    assert 'LUI.addmenubutton("main_campaign"' in lua and '"invasion"' in lua
    assert lua.count("registerType(") == 2
    info = json.loads((MOD / "info.json").read_text())
    assert info["name"] == "MW2CR Zombies"


def test_installer_uses_windows_line_endings():
    data = (ROOT / "install.bat").read_bytes()
    assert b"\r\n" in data and b"\n" not in data.replace(b"\r\n", b"")
    assert b"mods\\zombies" in data
