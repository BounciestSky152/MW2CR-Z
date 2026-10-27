"""Static checks on the GSC. There's no WaW/BO1 compiler available outside the
games, so this catches the mistakes a compiler would: unbalanced brackets,
calls to functions that don't exist in one of the games, and syntax the T4/T5
compilers don't support."""
import re

import pytest

from portal_bridge.build import GSC_DIR, ROUTES, build, bundle, generate_catalog, generate_platform
from portal_bridge.config import GAMES, load_config
from portal_bridge.patcher import HOOK, patch_text

CORE = (GSC_DIR / "shared" / "maps" / "_portal_bridge.gsc").read_text()
ADAPTERS = {g: (GSC_DIR / g / "maps" / "_portal_bridge_game.gsc").read_text() for g in GAMES}

FUNC_DEF_RE = re.compile(r"^([A-Za-z_]\w*)\s*\(([^)]*)\)\s*$", re.MULTILINE)
PB_CALL_RE = re.compile(r"(?<![\w\\:])(pb_\w+)\s*\(")


def strip_comments_and_strings(src: str) -> str:
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.DOTALL)
    src = re.sub(r"//[^\n]*", "", src)
    return re.sub(r'"(?:[^"\\]|\\.)*"', '""', src)


def defined_functions(src: str) -> set[str]:
    return {m.group(1) for m in FUNC_DEF_RE.finditer(strip_comments_and_strings(src))}


def all_sources(game, route="modtools"):
    return [CORE, ADAPTERS[game], generate_catalog(load_config(), game), generate_platform(game, route)]


COMBOS = [(g, r) for g in GAMES for r in ROUTES]


@pytest.mark.parametrize("game,route", COMBOS)
def test_brackets_balance(game, route):
    for src in all_sources(game, route):
        code = strip_comments_and_strings(src)
        stack = []
        pairs = {")": "(", "]": "[", "}": "{"}
        for ch in code:
            if ch in "([{":
                stack.append(ch)
            elif ch in pairs:
                assert stack and stack[-1] == pairs[ch], "unbalanced brackets"
                stack.pop()
        assert not stack


@pytest.mark.parametrize("game,route", COMBOS)
def test_every_pb_call_is_defined(game, route):
    defined = set()
    for src in all_sources(game, route):
        defined |= defined_functions(src)
    called = set()
    for src in all_sources(game, route):
        called |= set(PB_CALL_RE.findall(strip_comments_and_strings(src)))
    assert called - defined == set()


def test_both_adapters_provide_everything_the_core_needs_from_them():
    core_calls = set(PB_CALL_RE.findall(strip_comments_and_strings(CORE))) - defined_functions(CORE)
    shared = set()
    for game in GAMES:
        shared |= defined_functions(generate_catalog(load_config(), game))
        for route in ROUTES:
            shared |= defined_functions(generate_platform(game, route))
    needed = core_calls - shared
    assert needed  # sanity: the core does rely on the adapters
    for game in GAMES:
        assert needed <= defined_functions(ADAPTERS[game]), game


@pytest.mark.parametrize("game,route", COMBOS)
def test_no_unsupported_syntax(game, route):
    for src in all_sources(game, route):
        code = strip_comments_and_strings(src)
        assert not re.search(r"\bforeach\b", code), "T4 has no foreach"
        assert "?" not in code, "GSC has no ternary operator"
        # `game` is the engine's global array; shadowing it breaks scripts.
        assert not re.search(r"(?<![.\w])game\s*=", code)


@pytest.mark.parametrize("game,route", COMBOS)
def test_statements_end_with_semicolons(game, route):
    for src in all_sources(game, route):
        for raw in strip_comments_and_strings(src).splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or line in ("{", "}"):
                continue
            if re.match(r"^(if|else|for|while)\b", line) or FUNC_DEF_RE.match(line):
                continue
            assert line.endswith((";", "{", "}")), f"missing semicolon: {line!r}"


def test_bundle_is_self_contained():
    out = bundle(all_sources("bo1", "plutonium"))
    assert not re.search(r"#include\s+maps\\_portal_bridge", out)
    assert out.count("#include maps\\_utility;") == 1
    assert "pb_give_perk" in out and "pb_catalog_maps" in out


@pytest.mark.parametrize("game", GAMES)
def test_plutonium_build_never_references_zombiemode_scripts_directly(game):
    """Plutonium compiles loose scripts before any map's zombiemode scripts are
    loaded, so a direct maps\\_zombiemode_*:: reference stops the game at boot."""
    code = strip_comments_and_strings(bundle(all_sources(game, "plutonium")))
    assert "::" not in code.replace("::main", "")
    assert "println" not in code
    assert "fs_fopen" in code


def test_plutonium_bo1_build_never_calls_spawn_directly():
    """An in-game test saw Plutonium T5 reject spawn() in scripts/sp/zom."""
    code = strip_comments_and_strings(bundle(all_sources("bo1", "plutonium")))
    assert not re.search(r"(?<![\w.])spawn\s*\(", code)
    assert "spawn_model(" in code


def test_no_stock_laststand_dependency():
    for game in GAMES:
        for route in ROUTES:
            raw = "".join(all_sources(game, route))
            code = strip_comments_and_strings(raw)
            assert "maps\\_laststand" not in code and "maps/_laststand" not in raw.replace("//", "")


@pytest.mark.parametrize("game", GAMES)
def test_modtools_build_has_no_plutonium_only_builtins(game):
    code = "".join(strip_comments_and_strings(s) for s in all_sources(game, "modtools"))
    for builtin in ("getFunction", "fs_fopen", "fs_writeline", "fs_fclose"):
        assert builtin.lower() not in code.lower()


def test_build_writes_both_layouts(tmp_path):
    written = {p.relative_to(tmp_path).as_posix() for p in build(load_config(), tmp_path)}
    for game in GAMES:
        assert f"{game}/mods/portal_bridge/maps/_portal_bridge.gsc" in written
        assert f"{game}/mods/portal_bridge/maps/_portal_bridge_platform.gsc" in written
    assert "bo1/plutonium/storage/t5/raw/scripts/sp/portal_bridge.gsc" in written
    assert "bo1/plutonium/storage/t5/raw/scriptdata/portal_bridge_readme.txt" in written
    csv = (tmp_path / "bo1/mods/portal_bridge/mod.csv").read_text()
    assert "rawfile,maps/_zombiemode.gsc" in csv and "rawfile,maps/_portal_bridge_platform.gsc" in csv


def test_patch_inserts_hook_first_in_main():
    src = "#include maps\\_utility;\r\n\r\nmain()\r\n{\r\n\tinit_dvars();\r\n\twait 1;\r\n}\r\n"
    out, changed = patch_text(src)
    assert changed
    assert out.index(HOOK) < out.index("init_dvars")
    assert "\r\n\t" + HOOK in out
    again, changed = patch_text(out)
    assert not changed and again == out


def test_maps_you_dont_own_are_left_out(tmp_path):
    from dataclasses import replace
    from portal_bridge.build import missing_maps
    config = load_config()
    (tmp_path / "zone/Common").mkdir(parents=True)
    for m in ("zombie_theater", "zombie_moon"):
        (tmp_path / f"zone/Common/{m}.ff").write_text("")
    config.games["bo1"] = replace(config.games["bo1"], game_dir=str(tmp_path))
    catalog = generate_catalog(config, "bo1")
    assert '"zombie_theater"' in catalog and '"zombie_moon"' in catalog
    assert '"zombie_pentagon"' not in catalog
    assert "Five" in missing_maps(config, "bo1")


def test_unreadable_game_folder_keeps_every_map():
    catalog = generate_catalog(load_config(), "bo1")  # default Windows path doesn't exist here
    assert '"zombie_pentagon"' in catalog
