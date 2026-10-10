"""Adds the Portal Bridge hook to a copy of the game's maps/_zombiemode.gsc."""
from __future__ import annotations

import re
import shutil
from pathlib import Path

HOOK = "maps\\_portal_bridge::main();"
HOOK_LINE = f"\t{HOOK} // Portal Bridge\n"
MAIN_RE = re.compile(r"^main\s*\(\s*\)\s*\{[^\n]*\n", re.MULTILINE)


class PatchError(ValueError):
    pass


def patch_text(text: str) -> tuple[str, bool]:
    """Insert the hook as the first statement of main() - before any wait, so
    its precache calls are still legal. Returns (text, changed)."""
    if HOOK in text:
        return text, False
    match = MAIN_RE.search(text)
    if not match:
        raise PatchError("couldn't find `main()` in this file - is it maps/_zombiemode.gsc?")
    newline = "\r\n" if "\r\n" in text else "\n"
    hook = HOOK_LINE.replace("\n", newline)
    return text[: match.end()] + hook + text[match.end():], True


def patch_file(path: Path | str) -> bool:
    path = Path(path)
    text = path.read_text(encoding="utf-8", errors="surrogateescape")
    patched, changed = patch_text(text)
    if changed:
        shutil.copy2(path, path.with_suffix(path.suffix + ".bak"))
        path.write_text(patched, encoding="utf-8", errors="surrogateescape", newline="")
    return changed
