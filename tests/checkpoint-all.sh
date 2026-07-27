#!/usr/bin/env bash
set -euo pipefail
ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REMOTE="$TMP/origin.git"; DATA="$TMP/data"
git init --bare -q --initial-branch=main "$REMOTE"
git clone -q "$REMOTE" "$DATA"
git -C "$DATA" config user.name 'AIMS Test'
git -C "$DATA" config user.email 'aims-test@example.invalid'
printf '# Test data repo\n' > "$DATA/README.md"
mkdir -p "$DATA/sessions/work" "$DATA/.worktrees"
git -C "$DATA" add README.md && git -C "$DATA" commit -q -m 'init'
git -C "$DATA" push -q -u origin main
for n in 3 4; do
  SID="20260727T00000${n}Z-meta-checkpoint-all-test-hermes"; BRANCH="ai/$SID"; WT="$DATA/.worktrees/$SID"
  git -C "$DATA" worktree add -q -b "$BRANCH" "$WT" origin/main
  mkdir -p "$WT/sessions/work/$SID"
  printf '{"session_id":"%s","status":"active"}\n' "$SID" > "$WT/sessions/work/$SID/metadata.json"
  git -C "$WT" add sessions/work && git -C "$WT" commit -q -m 'start session' && git -C "$WT" push -q -u origin "$BRANCH"
  printf 'checkpoint %s\n' "$n" > "$WT/checkpoint-${n}.txt"
done
output="$(cd "$DATA" && AIMS_HOME="$DATA" "$ENGINE_ROOT/bin/aims" checkpoint --all)"
printf '%s\n' "$output" | grep -F 'CHECKPOINT_OK 20260727T000003Z-meta-checkpoint-all-test-hermes'
printf '%s\n' "$output" | grep -F 'CHECKPOINT_OK 20260727T000004Z-meta-checkpoint-all-test-hermes'
for n in 3 4; do
  SID="20260727T00000${n}Z-meta-checkpoint-all-test-hermes"; BRANCH="ai/$SID"
  git -C "$DATA" fetch -q origin "$BRANCH"
  test "$(git -C "$DATA" show "origin/$BRANCH:checkpoint-${n}.txt")" = "checkpoint $n"
done
printf 'PASS: checkpoint --all pushes every valid local session\n'
