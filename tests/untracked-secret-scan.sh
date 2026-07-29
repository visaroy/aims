#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git init -q -b main "$TMP/repo"
git -C "$TMP/repo" config user.name 'AIMS Test'
git -C "$TMP/repo" config user.email 'aims-test@example.invalid'
printf 'tracked safe content\n' > "$TMP/repo/tracked.txt"
git -C "$TMP/repo" add tracked.txt && git -C "$TMP/repo" commit -q -m init
printf 'token=ghp_%s\n' 'abcdefghijklmnopqrstuvwxyz1234567890' > "$TMP/repo/untracked-secret.txt"
if (cd "$TMP/repo" && "$ROOT/lib/validate-no-secrets.sh") >/dev/null 2>&1; then
  echo 'FAIL: untracked secret was not rejected' >&2; exit 1
fi
rm "$TMP/repo/untracked-secret.txt"
printf 'placeholder token=ghp_%s\n' 'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890' > "$TMP/repo/mixed-placeholder-secret.txt"
if (cd "$TMP/repo" && "$ROOT/lib/validate-no-secrets.sh") >/dev/null 2>&1; then
  echo 'FAIL: real secret beside a placeholder was not rejected' >&2; exit 1
fi
rm "$TMP/repo/mixed-placeholder-secret.txt"
printf 'token=ghp_%s\n' 'AAAAAplaceholderBBBBB' > "$TMP/repo/embedded-placeholder-secret.txt"
if (cd "$TMP/repo" && "$ROOT/lib/validate-no-secrets.sh") >/dev/null 2>&1; then
  echo 'FAIL: placeholder substring inside a real token suppressed the token' >&2; exit 1
fi
rm "$TMP/repo/embedded-placeholder-secret.txt"
printf 'token=%s\n' '${EXAMPLE_API_TOKEN}' > "$TMP/repo/allowed-placeholder.txt"
if ! (cd "$TMP/repo" && "$ROOT/lib/validate-no-secrets.sh") >/dev/null 2>&1; then
  echo 'FAIL: complete variable placeholder was rejected' >&2; exit 1
fi
printf 'PASS: secret scanner rejects adjacent/embedded placeholder text and accepts a complete placeholder value\n'
