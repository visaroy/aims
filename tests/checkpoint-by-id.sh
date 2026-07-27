#!/usr/bin/env bash
set -euo pipefail
ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REMOTE="$TMP/origin.git"; DATA="$TMP/data"; SID="20260727T000002Z-meta-checkpoint-test-hermes"; BRANCH="ai/$SID"; WT="$DATA/.worktrees/$SID"
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
git -C "$WT" add sessions/work && git -C "$WT" commit -q -m 'start session' && git -C "$WT" push -q -u origin "$BRANCH"
printf 'checkpointed work\n' > "$WT/checkpoint-note.txt"
output="$(cd "$DATA" && AIMS_HOME="$DATA" "$ENGINE_ROOT/bin/aims" checkpoint "$SID")"
printf '%s\n' "$output" | grep -F "CHECKPOINT_OK $SID"
git -C "$DATA" fetch -q origin "$BRANCH"
test "$(git -C "$DATA" show "origin/$BRANCH:checkpoint-note.txt")" = 'checkpointed work'
test "$(git -C "$DATA" show "origin/$BRANCH:sessions/work/$SID/metadata.json" | python3 -c 'import json,sys;print(json.load(sys.stdin)["status"])')" = active
printf 'PASS: checkpoint pushes a selected session without handing it off\n'
