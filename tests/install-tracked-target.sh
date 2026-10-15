#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/helpers/install-env.sh"
fake_agent opencode
make_repo "$TMP/rules" '# my rules'; ln -s "$TMP/rules/README.md" "$HOME/AGENTS.md"
out="$("$AIMS" install)" || fail "install failed: $out"
[ -L "$HOME/AGENTS.md" ] || fail "the symlink was replaced instead of followed"
grep -qF '<!-- >>> AIMS agent rules >>> -->' "$TMP/rules/README.md" || fail "block not written to the real (tracked) file"
printf '%s\n' "$out" | grep -qF 'Tracked by Git — commit these through a branch and pull request' || fail "tracked file not reported: $out"
printf '%s\n' "$out" | grep -qF "(repo $TMP/rules)" || printf '%s\n' "$out" | grep -qF "/rules)" || fail "tracked repo not named: $out"
[ "$(git -C "$TMP/rules" status --porcelain)" = ' M README.md' ] || fail "stray files in the tracked repo: $(git -C "$TMP/rules" status --porcelain)"
ls "$HOME"/.local/state/aims/backups/*/files/*README.md >/dev/null 2>&1 || fail "backup of the tracked file not kept outside the repo"
[ "$(cut -f 1 "$HOME"/.local/state/aims/backups/*/manifest.tsv)" = "$HOME/AGENTS.md" ] || fail "manifest does not record the original (symlink) path"
echo 'PASS: a Git-tracked symlink target is wired, reported for a pull request, and backed up outside the repo'
