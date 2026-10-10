"""Static checks on the GSC. There's no WaW/BO1 compiler available outside the
games, so this catches the mistakes a compiler would: unbalanced brackets,
calls to functions that don't exist in one of the games, and syntax the T4/T5
compilers don't support."""
import re

import pytest

from portal_bridge.build import GSC_DIR, build, bundle, generate_catalog
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


def all_sources(game):
    return [CORE, ADAPTERS[game], generate_catalog(load_config(), game)]


@pytest.mark.parametrize("game", GAMES)
def test_brackets_balance(game):
    for src in all_sources(game):
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


@pytest.mark.parametrize("game", GAMES)
def test_every_pb_call_is_defined(game):
    defined = set()
    for src in all_sources(game):
        defined |= defined_functions(src)
    called = set()
    for src in all_sources(game):
        called |= set(PB_CALL_RE.findall(strip_comments_and_strings(src)))
    assert called - defined == set()


def test_adapters_define_the_same_functions():
    assert defined_functions(ADAPTERS["waw"]) == defined_functions(ADAPTERS["bo1"])


@pytest.mark.parametrize("game", GAMES)
def test_no_unsupported_syntax(game):
    for src in all_sources(game):
        code = strip_comments_and_strings(src)
        assert not re.search(r"\bforeach\b", code), "T4 has no foreach"
        assert "?" not in code, "GSC has no ternary operator"
        # `game` is the engine's global array; shadowing it breaks scripts.
        assert not re.search(r"(?<![.\w])game\s*=", code)


@pytest.mark.parametrize("game", GAMES)
def test_statements_end_with_semicolons(game):
    for src in all_sources(game):
        for raw in strip_comments_and_strings(src).splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or line in ("{", "}"):
                continue
            if re.match(r"^(if|else|for|while)\b", line) or FUNC_DEF_RE.match(line):
                continue
            assert line.endswith((";", "{", "}")), f"missing semicolon: {line!r}"


def test_bundle_is_self_contained():
    out = bundle(all_sources("waw"))
    assert not re.search(r"#include\s+maps\\_portal_bridge", out)
    assert out.count("#include maps\\_utility;") == 1
    assert "pb_give_perk" in out and "pb_catalog_maps" in out


def test_build_writes_both_layouts(tmp_path):
    written = {p.relative_to(tmp_path).as_posix() for p in build(load_config(), tmp_path)}
    for game in GAMES:
        assert f"{game}/mods/portal_bridge/maps/_portal_bridge.gsc" in written
        assert f"{game}/plutonium/scripts/sp/portal_bridge.gsc" in written
    assert "rawfile,maps/_zombiemode.gsc" in (tmp_path / "waw/mods/portal_bridge/mod.csv").read_text()


def test_patch_inserts_hook_first_in_main():
    src = "#include maps\\_utility;\r\n\r\nmain()\r\n{\r\n\tinit_dvars();\r\n\twait 1;\r\n}\r\n"
    out, changed = patch_text(src)
    assert changed
    assert out.index(HOOK) < out.index("init_dvars")
    assert "\r\n\t" + HOOK in out
    again, changed = patch_text(out)
    assert not changed and again == out
