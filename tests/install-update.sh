#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REMOTE="$TMP/origin.git"; ENGINE="$TMP/engine"; UPDATER="$TMP/updater"; HOME_DIR="$TMP/home"
git init --bare -q --initial-branch=main "$REMOTE"
git clone -q "$ROOT" "$ENGINE"
git -C "$ENGINE" branch -M main
git -C "$ENGINE" remote set-url origin "$REMOTE"
git -C "$ENGINE" config user.name 'AIMS Test'
git -C "$ENGINE" config user.email 'aims-test@example.invalid'
printf 'baseline\n' > "$ENGINE/baseline.txt"
git -C "$ENGINE" add baseline.txt && git -C "$ENGINE" commit -q -m 'test baseline'
git -C "$ENGINE" push -q -u origin main
git clone -q "$REMOTE" "$UPDATER"
git -C "$UPDATER" config user.name 'AIMS Test'
git -C "$UPDATER" config user.email 'aims-test@example.invalid'
printf 'updated\n' > "$UPDATER/update-marker.txt"
git -C "$UPDATER" add update-marker.txt && git -C "$UPDATER" commit -q -m update && git -C "$UPDATER" push -q origin main
output="$(HOME="$HOME_DIR" PATH="$PATH" bash "$ENGINE/install.sh")"
printf '%s\n' "$output" | grep -F '🔄 Pobieram aktualizację AIMS z oficjalnego repozytorium'
test "$(git -C "$ENGINE" show HEAD:update-marker.txt)" = updated
test "$(readlink "$HOME_DIR/.local/bin/aims")" = "$ENGINE/bin/aims"
printf 'PASS: install updates main from origin before linking aims\n'
