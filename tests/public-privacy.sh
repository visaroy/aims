#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/aims-privacy.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
new_repo() {
  name="$1"; repo="$TMP/$name"; git init -q -b main "$repo"
  git -C "$repo" config user.name 'AIMS Test'; git -C "$repo" config user.email 'aims-test@example.invalid'
  printf '# Safe docs\n\n**Author**: The AIMS authors\n' > "$repo/README.md"
  git -C "$repo" add README.md; git -C "$repo" commit -qm init
  printf '%s\n' "$repo"
}
expect_pass() { label="$1"; repo="$2"; bash "$ROOT/scripts/validate-public-privacy.sh" "$repo" >/dev/null || { echo "FAIL: $label was rejected" >&2; exit 1; }; }
expect_fail() { label="$1"; repo="$2"; if bash "$ROOT/scripts/validate-public-privacy.sh" "$repo" >/dev/null 2>&1; then echo "FAIL: $label bypassed the guard" >&2; exit 1; fi; }
repo="$(new_repo punctuation)"; printf 'Contact aims@localhost.\n' >> "$repo/README.md"; expect_pass 'allowed email before sentence punctuation' "$repo"
repo="$(new_repo collision)"; printf 'Collision email: notaims@localhost.com\n' >> "$repo/README.md"; expect_fail 'email substring collision' "$repo"
repo="$(new_repo windows)"; printf 'Private path: C:\\users\\personal name\\project\n' > "$repo/notes.markdown"; git -C "$repo" add notes.markdown; expect_fail 'case-variant Windows home path' "$repo"
repo="$(new_repo option-name)"; printf 'Private email: person@private.test\n' > "$repo/-privacy.markdown"; git -C "$repo" add -- -privacy.markdown; expect_fail 'option-like Markdown filename' "$repo"
repo="$(new_repo byline)"; printf '**Author**: The AIMS authors · **Version**: 1 · Personal Name\n' > "$repo/README.md"; expect_fail 'personal suffix in composite byline' "$repo"
echo 'PASS: public privacy guard handles punctuation and independently rejects collision, path, filename, and byline regressions'
