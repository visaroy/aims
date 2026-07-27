#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git init -q -b main "$TMP/repo"
git -C "$TMP/repo" config user.name 'AIMS Test'
git -C "$TMP/repo" config user.email 'aims-test@example.invalid'
printf 'tracked safe content\n' > "$TMP/repo/tracked.txt"
git -C "$TMP/repo" add tracked.txt && git -C "$TMP/repo" commit -q -m init
printf 'token=ghp_abcdefghijklmnopqrstuvwxyz1234567890\n' > "$TMP/repo/untracked-secret.txt"
if (cd "$TMP/repo" && "$ROOT/lib/validate-no-secrets.sh") >/dev/null 2>&1; then
  echo 'FAIL: untracked secret was not rejected' >&2; exit 1
fi
printf 'PASS: secret scanner rejects untracked secret files\n'
