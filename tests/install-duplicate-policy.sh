#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/helpers/install-env.sh"
fake_agent claude
mkdir -p "$HOME/.claude"; printf '# My rules\nUse AIMS only when I say so.\n' > "$HOME/.claude/CLAUDE.md"
out="$("$AIMS" install)" || fail "install failed: $out"
head -n 2 "$HOME/.claude/CLAUDE.md" | cmp -s - <(printf '# My rules\nUse AIMS only when I say so.\n') || fail "user text before the block changed"
grep -qF '<!-- >>> AIMS agent rules >>> -->' "$HOME/.claude/CLAUDE.md" || fail "file with user AIMS text was skipped instead of wired"
printf '%s\n' "$out" | grep -qF 'Possible duplicate AIMS text outside the block' || fail "duplicate not reported: $out"
printf '%s\n' "$out" | grep -qF '(lines 2)' || fail "duplicate line not named: $out"
grep -qF "Rules the user wrote outside this marked block take precedence" "$HOME/.claude/CLAUDE.md" || fail "block does not state that user rules take precedence"
echo 'PASS: user-written AIMS text is kept, the block is still added, and the possible duplicate is reported'
