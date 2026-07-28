#!/usr/bin/env bash
set -euo pipefail
ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REMOTE="$TMP/origin.git"; DATA="$TMP/data"; SID="20260728T000001Z-meta-check-test-hermes"; BRANCH="ai/$SID"; WT="$DATA/.worktrees/$SID"
git init --bare -q --initial-branch=main "$REMOTE"
git clone -q "$REMOTE" "$DATA"
git -C "$DATA" config user.name 'AIMS Test'
git -C "$DATA" config user.email 'aims-test@example.invalid'
printf '# Test data repo\n' > "$DATA/README.md"
mkdir -p "$DATA/sessions/work" "$DATA/.worktrees"
git -C "$DATA" add README.md && git -C "$DATA" commit -q -m 'init' && git -C "$DATA" push -q -u origin main
git -C "$DATA" worktree add -q -b "$BRANCH" "$WT" origin/main
mkdir -p "$WT/sessions/work/$SID"
printf '{"session_id":"%s","project":"meta","branch":"%s","status":"active","environment":{"code_repos":[],"toolchain":[],"exec_host":"","setup":"","test":""}}\n' "$SID" "$BRANCH" > "$WT/sessions/work/$SID/metadata.json"
printf '# Worklog\n\n- Next action: run the handoff check test.\n' > "$WT/sessions/work/$SID/worklog.md"
git -C "$WT" add sessions/work && git -C "$WT" commit -q -m 'start session' && git -C "$WT" push -q -u origin "$BRANCH"
before="$(git -C "$WT" status --porcelain)"
output="$(cd "$DATA" && AIMS_HOME="$DATA" "$ENGINE_ROOT/bin/aims" handoff check "$SID")"
printf '%s\n' "$output" | grep -F 'READY'
test "$before" = "$(git -C "$WT" status --porcelain)"
if cd "$DATA" && AIMS_HOME="$DATA" "$ENGINE_ROOT/bin/aims" handoff check missing-session >/dev/null 2>&1; then echo 'expected missing session to be blocked' >&2; exit 1; fi
printf 'PASS: handoff check is advisory and non-mutating\n'
