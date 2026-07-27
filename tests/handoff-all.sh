#!/usr/bin/env bash
set -euo pipefail
ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REMOTE="$TMP/origin.git"; DATA="$TMP/data"; WT="$DATA/.worktrees/20260727T000000Z-meta-recovery-test-hermes"; SID="20260727T000000Z-meta-recovery-test-hermes"; BRANCH="ai/$SID"
git init --bare -q --initial-branch=main "$REMOTE"
git clone -q "$REMOTE" "$DATA"
git -C "$DATA" config user.name 'AIMS Test'
git -C "$DATA" config user.email 'aims-test@example.invalid'
printf '# Test data repo\n' > "$DATA/README.md"
mkdir -p "$DATA/sessions/work" "$DATA/.worktrees"
git -C "$DATA" add README.md && git -C "$DATA" commit -q -m 'init'
git -C "$DATA" push -q -u origin main
git -C "$DATA" worktree add -q -b "$BRANCH" "$WT" origin/main
mkdir -p "$WT/sessions/work/$SID"
printf '{"session_id":"%s","status":"active"}\n' "$SID" > "$WT/sessions/work/$SID/metadata.json"
printf '# Worklog\n' > "$WT/sessions/work/$SID/worklog.md"
git -C "$WT" add sessions/work && git -C "$WT" commit -q -m 'start session' && git -C "$WT" push -q -u origin "$BRANCH"
printf 'unsaved Mac work\n' > "$WT/recovery-note.txt"
output="$(AIMS_HOME="$DATA" "$ENGINE_ROOT/bin/aims" handoff-all --yes)"
printf '%s\n' "$output" | grep -F "HANDOFF_OK $SID"
git -C "$DATA" fetch -q origin "$BRANCH"
test "$(git -C "$DATA" show "origin/$BRANCH:sessions/work/$SID/metadata.json" | python3 -c 'import json,sys;print(json.load(sys.stdin)["status"])')" = handoff
test "$(git -C "$DATA" show "origin/$BRANCH:recovery-note.txt")" = 'unsaved Mac work'
test "$(git -C "$DATA" rev-parse main)" = "$(git -C "$DATA" rev-parse origin/main)"
test -d "$WT"
printf 'PASS: handoff-all preserves and releases a dirty session\n'
