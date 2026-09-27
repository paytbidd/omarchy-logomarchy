#!/usr/bin/env python3
"""Add or remove the Logomarchy row in the Omarchy menu extension file.

The row sits between marker comments so teardown can drop it with sed even
after the plugin folder is gone. The menu's JSONC parser skips comment lines
and tolerates trailing commas, so the block is valid wherever it lands.
Nothing is written unless the result still parses.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import sys
import tempfile
from pathlib import Path

KEY = "style.logomarchy"
BEGIN = "// >>> payton.logomarchy (added by the plugin, removed when it is disabled)"
END = "// <<< payton.logomarchy"
BLOCK_RE = re.compile(r"^[ \t]*// >>> payton\.logomarchy.*?^[ \t]*// <<< payton\.logomarchy[^\n]*\n?", re.M | re.S)


# Same rules as stripJsonc in the shell's MenuModel.js.
def strip_jsonc(raw: str) -> str:
    raw = re.sub(r"^\s*//[^\n]*(\n|$)", "", raw, flags=re.M)
    return re.sub(r",(\s*[}\]])", r"\1", raw)


def parses(text: str) -> bool:
    stripped = strip_jsonc(text).strip()
    if not stripped:
        return True
    try:
        return isinstance(json.loads(stripped), dict)
    except ValueError:
        return False


def skip_ws_and_comments(text: str, i: int) -> int:
    n = len(text)
    while i < n:
        if text[i] in " \t\r\n":
            i += 1
        elif text.startswith("//", i):
            nl = text.find("\n", i)
            i = n if nl < 0 else nl + 1
        else:
            break
    return i


def match_string(text: str, i: int) -> int:
    quote = text[i]
    i += 1
    while i < len(text):
        if text[i] == "\\":
            i += 2
            continue
        if text[i] == quote:
            return i + 1
        i += 1
    return len(text)


# Span of `"key": { ... }` plus its trailing comma. Used only to notice a
# row the user wrote with the same key.
def find_key(text: str, key: str) -> tuple[int, int] | None:
    needle = f'"{key}"'
    start = 0
    n = len(text)
    while True:
        idx = text.find(needle, start)
        if idx < 0:
            return None
        i = skip_ws_and_comments(text, idx + len(needle))
        if i >= n or text[i] != ":":
            start = idx + 1
            continue
        i = skip_ws_and_comments(text, i + 1)
        if i >= n or text[i] != "{":
            start = idx + 1
            continue
        depth = 0
        j = i
        while j < n:
            ch = text[j]
            if ch == '"':
                j = match_string(text, j)
                continue
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    end = j + 1
                    k = skip_ws_and_comments(text, end)
                    if k < n and text[k] == ",":
                        end = k + 1
                    return idx, end
            j += 1
        return None


# Only the marked block is ours; anything else is the user's.
def without_row(text: str) -> str:
    return BLOCK_RE.sub("", text)


def row_block(action_bin: str) -> str:
    quoted = shlex.quote(action_bin)
    entry = {
        "icon": "󰸉",
        "label": "Logomarchy",
        "description": "Omarchy logo wallpaper in this theme's colors",
        "aliases": ["logomarchy", "logo wallpaper", "omarchy wallpaper"],
        "when": f"[[ -x {quoted} ]]",
        "action": f"{quoted} panel",
    }
    body = json.dumps(entry, indent=2, ensure_ascii=False).replace("\n", "\n  ")
    return f"  {BEGIN}\n  \"{KEY}\": {body},\n  {END}\n"


def with_row(text: str, action_bin: str) -> str:
    text = without_row(text)
    if find_key(text, KEY):
        raise ValueError(f"{KEY} is already defined outside the managed block")
    block = row_block(action_bin)
    if not strip_jsonc(text).strip():
        return "{\n" + block + "}\n"
    i = skip_ws_and_comments(text, 0)
    if i >= len(text) or text[i] != "{":
        raise ValueError("menu file does not start with an object")
    rest = text[i + 1:]
    if rest.startswith("\n"):
        rest = rest[1:]
    return text[:i + 1] + "\n" + block + rest


def write_if_changed(path: Path, original: str, text: str) -> None:
    if text == original:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, path)


def main(argv: list[str]) -> int:
    if len(argv) < 3 or argv[1] not in ("upsert", "remove") or (argv[1] == "upsert" and len(argv) < 4):
        print("usage: menu.py upsert <menu-file> <omarchy-logomarchy path>\n       menu.py remove <menu-file>", file=sys.stderr)
        return 2

    path = Path(argv[2])
    original = path.read_text(encoding="utf-8") if path.exists() else ""
    if not parses(original):
        print(f"menu.py: {path} does not parse; leaving it alone", file=sys.stderr)
        return 1

    try:
        text = with_row(original, argv[3]) if argv[1] == "upsert" else without_row(original)
    except ValueError as err:
        print(f"menu.py: {err}; leaving {path} alone", file=sys.stderr)
        return 1

    if not parses(text):
        print(f"menu.py: edit would break {path}; leaving it alone", file=sys.stderr)
        return 1

    write_if_changed(path, original, text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
