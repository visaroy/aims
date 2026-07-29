#!/usr/bin/env python3
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LINK = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)(?:\s+['\"].*?['\"])?\)")
SCHEME = re.compile(r"^[a-zA-Z][a-zA-Z0-9+.-]*:")
errors = []
for doc in [ROOT / "README.md", *sorted((ROOT / "docs").rglob("*.md"))]:
    text = doc.read_text(encoding="utf-8")
    for target in LINK.findall(text):
        target = target.strip("<>")
        if not target or target.startswith("#") or target.startswith("//") or SCHEME.match(target):
            continue
        path_text = target.split("#", 1)[0].split("?", 1)[0]
        if not path_text:
            continue
        resolved = (doc.parent / path_text).resolve()
        try:
            resolved.relative_to(ROOT)
        except ValueError:
            errors.append(f"{doc.relative_to(ROOT)}: link escapes repository: {target}")
            continue
        if not resolved.exists():
            errors.append(f"{doc.relative_to(ROOT)}: missing local target: {target}")
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
print("OK: local Markdown links resolve")
