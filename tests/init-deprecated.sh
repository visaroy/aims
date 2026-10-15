#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/helpers/install-env.sh"
fake_agent claude
err="$("$AIMS" init "$TMP/data" 2>&1 >/dev/null)" || fail "init failed"
printf '%s\n' "$err" | grep -qF "'aims init' is deprecated since 3.1.0" || fail "init does not print the deprecation notice"
[ -f "$TMP/data/SESSIONS.md" ] && [ -x "$TMP/data/.git/hooks/pre-push" ] || fail "init no longer scaffolds a data repo with its guard"
[ "$("$AIMS" init "$TMP/data" 2>/dev/null)" = "AIMS data repo already exists at $TMP/data" ] || fail "init on an existing repo changed its 3.x output"
"$AIMS" init >/dev/null 2>&1 && [ -d "$HOME/.aims/.git" ] || fail "init without arguments no longer creates ~/.aims"
[ ! -e "$HOME/.config/aims/home" ] && [ ! -e "$HOME/.claude/CLAUDE.md" ] && [ ! -e "$HOME/.local/bin/aims" ] || fail "deprecated init must keep its 3.x scope (data repo only)"
echo 'PASS: aims init keeps its 3.x contract and prints a deprecation notice'
