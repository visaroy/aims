#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/helpers/install-env.sh"
fake_agent claude codex
mkdir -p "$HOME/.claude"; printf '# Mine, no final newline' > "$HOME/.claude/CLAUDE.md"
make_repo "$TMP/rules" '# tracked rules'; ln -s "$TMP/rules/README.md" "$HOME/AGENTS.md"
before="$(snapshot "$HOME")"; rules_before="$(cksum < "$TMP/rules/README.md")"
"$AIMS" install >/dev/null || fail "install failed"
printf 'session note\n' > "$HOME/.aims/note.md"
out="$("$AIMS" uninstall)" || fail "uninstall failed: $out"
[ "$(cksum < "$TMP/rules/README.md")" = "$rules_before" ] || fail "tracked file not restored byte for byte"
[ -z "$(git -C "$TMP/rules" status --porcelain)" ] || fail "tracked repo not clean after uninstall"
[ ! -e "$HOME/.codex/AGENTS.md" ] || fail "file created by AIMS was not removed"
[ ! -e "$HOME/.local/bin/aims" ] && [ ! -e "$HOME/.config/aims/home" ] || fail "command link or recorded path left behind"
[ ! -e "$HOME/.aims/.git/hooks/pre-push" ] || fail "guard left behind"
[ -f "$HOME/.aims/note.md" ] && [ -d "$HOME/.aims/.git" ] || fail "uninstall touched the data repo"
after="$(snapshot "$HOME" | grep -v -e '^F ./.aims/' -e '^F ./.local/state/aims/')"
[ "$after" = "$before" ] || fail "files not restored byte for byte: $(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true)"
out2="$("$AIMS" uninstall)" || fail "second uninstall failed: $out2"
printf '%s\n' "$out2" | grep -qF 'no AIMS blocks found' || fail "second uninstall should find nothing to remove"
echo 'PASS: uninstall restores agent files byte for byte, removes what AIMS owns, keeps the data repo, and is idempotent'
