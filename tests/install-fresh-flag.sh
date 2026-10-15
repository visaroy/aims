#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/helpers/install-env.sh"
"$AIMS" install >/dev/null || fail "initial install failed"
expect_refusal() {  # expect_refusal <label> <expected text>
  local before out; before="$(snapshot "$HOME")"
  if out="$("$AIMS" install --fresh 2>&1)"; then fail "$1: --fresh should refuse"; fi
  printf '%s\n' "$out" | grep -qF "$2" || fail "$1: reason not named ($2): $out"
  [ "$(snapshot "$HOME")" = "$before" ] || fail "$1: a refused --fresh changed files"
}
git -C "$HOME/.aims" commit -q --allow-empty -m 'local work'
expect_refusal 'no origin' 'no origin remote'
git init --bare -q "$TMP/data-origin.git"; git -C "$HOME/.aims" remote add origin "$TMP/data-origin.git"; git -C "$HOME/.aims" push -q -u origin main
printf 'draft\n' > "$HOME/.aims/draft.md"; expect_refusal 'dirty' 'uncommitted changes'
git -C "$HOME/.aims" add draft.md; git -C "$HOME/.aims" commit -qm draft; expect_refusal 'unpushed' 'commits that are not on origin'
AIMS_PUBLISH=1 git -C "$HOME/.aims" push -q
out="$("$AIMS" install --fresh)" || fail "--fresh failed on a clean, pushed repo: $out"
aside="$(ls -d "$HOME"/.aims.aims-replaced-* 2>/dev/null)"; [ -n "$aside" ] || fail "old data repo not moved aside"
[ -f "$aside/draft.md" ] && [ "$(git -C "$aside" rev-list --count HEAD)" -ge 3 ] || fail "old data repo content not preserved"
[ "$(git -C "$HOME/.aims" log -1 --format=%s)" = '🌱 init: AIMS data repo' ] || fail "new data repo not created"
cmp -s "$ROOT/hooks/pre-push" "$HOME/.aims/.git/hooks/pre-push" || fail "guard missing in the new data repo"
printf '%s\n' "$out" | grep -qF "Old data repo: $aside" || fail "report does not name the moved-aside repo"
echo 'PASS: --fresh refuses unsaved work and otherwise moves the old data repo aside without deleting it'
