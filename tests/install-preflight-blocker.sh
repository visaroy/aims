#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/helpers/install-env.sh"
fake_agent claude
expect_block() {  # expect_block <label> <expected text>
  local before out; before="$(snapshot "$HOME")"
  if out="$("$AIMS" install 2>&1)"; then fail "$1: install should have been blocked"; fi
  printf '%s\n' "$out" | grep -qF "$2" || fail "$1: blocker not named ($2): $out"
  printf '%s\n' "$out" | grep -qF 'nothing was changed' || fail "$1: output does not state that nothing changed"
  [ "$(snapshot "$HOME")" = "$before" ] || fail "$1: a blocked install changed files"
}
mkdir -p "$HOME/.claude"; printf '# mine\n<<<<<<< HEAD\na\n=======\nb\n>>>>>>> other\n' > "$HOME/.claude/CLAUDE.md"
expect_block 'conflict markers' 'unresolved Git conflict markers'
printf '# mine\n<!-- >>> AIMS agent rules >>> -->\nhalf a block\n' > "$HOME/.claude/CLAUDE.md"
expect_block 'malformed block' 'malformed AIMS block'
printf '# mine\n' > "$HOME/.claude/CLAUDE.md"
mkdir -p "$HOME/.aims"; printf 'not a repo\n' > "$HOME/.aims/notes.txt"
expect_block 'non-repo data path' 'exists but is not a Git repository'
rm -rf "$HOME/.aims"; make_repo "$HOME/.aims"; printf '#!/bin/sh\nexit 0\n' > "$HOME/.aims/.git/hooks/pre-push"
expect_block 'foreign hook' 'pre-push hook not managed by AIMS'
rm -f "$HOME/.aims/.git/hooks/pre-push"; mkdir -p "$HOME/.local/bin"; printf 'other\n' > "$HOME/.local/bin/aims"
expect_block 'foreign command' 'exists and is not a symlink'
rm -f "$HOME/.local/bin/aims"
if [ "$(id -u)" -ne 0 ]; then
  chmod 444 "$HOME/.claude/CLAUDE.md"; expect_block 'read-only target' 'cannot write'; chmod 644 "$HOME/.claude/CLAUDE.md"
fi
"$AIMS" install >/dev/null || fail "install should pass once every blocker is resolved"
echo 'PASS: preflight blockers stop the installer before any change and name the fix'
