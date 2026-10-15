#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/helpers/install-env.sh"
ENGINE="$TMP/engine"; REMOTE="$TMP/engine.git"; UPDATER="$TMP/updater"
make_engine "$ENGINE" "$REMOTE"
git clone -q "$REMOTE" "$UPDATER"
printf 'updated\n' > "$UPDATER/update-marker.txt"
git -C "$UPDATER" add update-marker.txt && git -C "$UPDATER" commit -q -m update && git -C "$UPDATER" push -q origin main
printf 'local change\n' > "$ENGINE/local-change.txt"
mkdir -p "$ENGINE/.slim/worktrees/saved-worktree"
printf 'local Slim state\n' > "$ENGINE/.slim/worktrees/saved-worktree/state.txt"
git -C "$ENGINE/.slim/worktrees/saved-worktree" init -q
output="$(bash "$ENGINE/install.sh")" || fail "install.sh from a checkout failed: $output"
printf '%s\n' "$output" | grep -F '🔄 Restoring a fresh, official AIMS version from the official GitHub repository…' >/dev/null || fail "restore not announced"
test "$(git -C "$ENGINE" show HEAD:update-marker.txt)" = updated
test ! -e "$ENGINE/local-change.txt"
test ! -e "$ENGINE/.slim"
test -z "$(git -C "$ENGINE" status --porcelain)"
test "$(readlink "$HOME/.local/bin/aims")" = "$ENGINE/bin/aims"
printf '%s\n' "$output" | grep -F 'aims doctor passed' >/dev/null || fail "install.sh did not finish with aims install"
git -C "$ENGINE" checkout -q -b topic
if bash "$ENGINE/install.sh" >/dev/null 2>&1; then fail "install.sh must refuse a non-main engine branch"; fi
git -C "$ENGINE" checkout -q main
rm -rf "$HOME"; mkdir -p "$HOME"
AIMS_ACCEPT=1 AIMS_DIR="$TMP/piped" AIMS_REPO="$REMOTE" bash < "$ROOT/install.sh" >/dev/null || fail "piped install.sh failed"
test "$(readlink "$HOME/.local/bin/aims")" = "$TMP/piped/bin/aims"
AIMS_DIR="$TMP/piped" bash < "$ROOT/install.sh" >/dev/null || fail "piped install.sh over an existing checkout failed"
printf 'PASS: install.sh restores the engine to origin/main, then runs aims install (checkout and pipe)\n'
