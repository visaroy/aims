#!/usr/bin/env bash
set -euo pipefail
BASH32="${BASH32:?set BASH32 to a Bash 3.2 executable}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git init -q -b main "$TMP/repo"
git -C "$TMP/repo" config user.name 'AIMS Test'
git -C "$TMP/repo" config user.email 'aims-test@example.invalid'
printf 'safe content\n' > "$TMP/repo/tracked.txt"
git -C "$TMP/repo" add tracked.txt && git -C "$TMP/repo" commit -q -m init
printf 'token=ghp_%s\n' 'abcdefghijklmnopqrstuvwxyz1234567890' > "$TMP/repo/untracked-secret.txt"
set +e
output="$(cd "$TMP/repo" && "$BASH32" "$ROOT/lib/validate-no-secrets.sh" 2>&1)"; status=$?
set -e
test "$status" -ne 0
printf '%s\n' "$output" | grep -F 'ERROR: potential secret pattern matched'
if printf '%s\n' "$output" | grep -qi 'syntax error'; then echo 'FAIL: Bash 3.2 parser error' >&2; exit 1; fi
printf 'PASS: Bash 3.2 scans untracked secret files without parser errors\n'
