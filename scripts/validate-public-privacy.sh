#!/usr/bin/env bash
set -euo pipefail
root="${1:-.}"; root="$(cd "$root" && pwd)"
exec python3 - "$root" <<'PY'
import os
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
result = subprocess.run(["git", "-C", str(root), "ls-files", "-z", "--", "*.md", "*.markdown"], check=True, stdout=subprocess.PIPE)
files = [os.fsdecode(item) for item in result.stdout.split(b"\0") if item]
if not files:
    print("OK: no public Markdown files to scan")
    raise SystemExit(0)
byline_re = re.compile(r"^\s*(?:\*\*)?(?:Author|Autor)(?:\*\*)?\s*:\s*(.*)$")
composite_byline_re = re.compile(r"^The AIMS authors\s+·\s+\*\*(?:Wersja|Version)\*\*:\s*(?:\d{4}-\d{2}-\d{2}|v?\d+(?:\.\d+)*)(?:\s+·\s+\*\*(?:Repo|Repository)\*\*:\s*`?<[^>\r\n]+>`?)?$")
domain_label = r"[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?"
email_re = re.compile(rf"(?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]+@{domain_label}(?:\.{domain_label})*(?![A-Za-z0-9-]|\.[A-Za-z0-9])")
unix_re = re.compile(r"/(?:home|Users)/([A-Za-z0-9._-]+)")
windows_re = re.compile(r"(?:[A-Za-z]:)?\\users\\([^\\\r\n]+)", re.IGNORECASE)
placeholder_users = {"you", "user", "runner", "test", "example"}
findings = []
for relative in files:
    path = root / relative
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError as error:
        print(f"ERROR: cannot read {relative}: {error}", file=sys.stderr)
        raise SystemExit(1)
    for number, line in enumerate(lines, 1):
        byline = byline_re.match(line)
        if byline:
            value = byline.group(1).strip()
            if value != "The AIMS authors" and not composite_byline_re.fullmatch(value):
                findings.append((relative, number, "personal author byline"))
        for email in email_re.findall(line):
            local, domain = email.rsplit("@", 1); domain = domain.lower()
            allowed_domain = domain in {"example.invalid", "example.internal"} or domain.endswith((".example.invalid", ".example.internal"))
            if email.lower() != "aims@localhost" and not allowed_domain:
                findings.append((relative, number, "non-placeholder email"))
        for username in unix_re.findall(line):
            if username.casefold() not in placeholder_users:
                findings.append((relative, number, "non-placeholder absolute home path"))
        for username in windows_re.findall(line):
            if username.strip().casefold() not in placeholder_users:
                findings.append((relative, number, "non-placeholder Windows home path"))
if findings:
    for relative, number, kind in sorted(set(findings)):
        print(f"{relative}:{number}: {kind}")
    print("ERROR: public documentation privacy guard failed.", file=sys.stderr)
    raise SystemExit(1)
print("OK: public Markdown contains no personal bylines, emails, or absolute home paths")
PY
