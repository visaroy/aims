#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/helpers/install-env.sh"
fake_agent claude codex
out="$("$AIMS" install)" || fail "install on an empty HOME failed: $out"
[ -d "$HOME/.aims/.git" ] || fail "data repo not created at ~/.aims"
printf '%s\n' "$out" | grep -qF "Data repo:     $HOME/.aims (created)" || fail "report does not say the data repo was created"
[ "$(cat "$HOME/.config/aims/home")" = "$HOME/.aims" ] || fail "data repo path not recorded"
[ "$(readlink "$HOME/.local/bin/aims")" = "$ROOT/bin/aims" ] || fail "command link missing"
cmp -s "$ROOT/hooks/pre-push" "$HOME/.aims/.git/hooks/pre-push" || fail "guard not installed"
for f in "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md" "$HOME/AGENTS.md"; do
  grep -qF '<!-- >>> AIMS agent rules >>> -->' "$f" || fail "no AIMS block in $f"
  [ "$(grep -cF '<!-- >>> AIMS agent rules >>> -->' "$f")" -eq 1 ] || fail "more than one block in $f"
done
[ ! -e "$HOME/.gemini/GEMINI.md" ] || fail "wired an agent that is not installed"
[ "$(cut -f 3 "$HOME"/.local/state/aims/backups/*/manifest.tsv | sort -u)" = "-" ] || fail "manifest should record new files as absent"
[ "$("$AIMS" home)" = "$HOME/.aims" ] || fail "aims home does not resolve the recorded repo"
before="$(snapshot "$HOME")"
out2="$("$AIMS" install)" || fail "second install failed: $out2"
[ "$(snapshot "$HOME")" = "$before" ] || fail "second install changed files (not idempotent)"
printf '%s\n' "$out2" | grep -qF 'Agent files changed: none' || fail "second install should report no agent changes"
printf '%s\n' "$out2" | grep -qF "(reused, from config)" || fail "second install should reuse the recorded repo"
doctor="$("$AIMS" doctor)"; printf '%s\n' "$doctor" | grep -qF 'agent rules current' || fail "doctor does not confirm current agent rules"
echo 'PASS: install on an empty HOME creates and records one data repo, guard, and agent blocks; rerun is a no-op'
