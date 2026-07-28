#!/usr/bin/env bash
set -euo pipefail
ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REMOTE="$TMP/origin.git"; DATA="$TMP/data"; SID="20260728T000003Z-meta-brief-test-hermes"; BRANCH="ai/$SID"; WT="$DATA/.worktrees/$SID"
git init --bare -q --initial-branch=main "$REMOTE"; git clone -q "$REMOTE" "$DATA"
git -C "$DATA" config user.name 'AIMS Test'; git -C "$DATA" config user.email 'aims-test@example.invalid'
printf '# Test\n' > "$DATA/README.md"; mkdir -p "$DATA/sessions/work" "$DATA/.worktrees"
git -C "$DATA" add README.md && git -C "$DATA" commit -q -m init && git -C "$DATA" push -q -u origin main
git -C "$DATA" worktree add -q -b "$BRANCH" "$WT" origin/main
mkdir -p "$WT/sessions/work/$SID"; printf '{"session_id":"%s","project":"meta","topic":"brief"}\n' "$SID" > "$WT/sessions/work/$SID/metadata.json"; printf '# Worklog\n' > "$WT/sessions/work/$SID/worklog.md"
git -C "$WT" add sessions/work && git -C "$WT" commit -q -m start && git -C "$WT" push -q -u origin "$BRANCH"
AIMS_HOME="$DATA" "$ENGINE_ROOT/bin/aims" brief "$SID" | grep -F "OK: created handoff brief"
brief="$WT/sessions/work/$SID/handoff.md"
test -s "$brief"; grep -F '## Immediate next action' "$brief"
if AIMS_HOME="$DATA" "$ENGINE_ROOT/bin/aims" brief "$SID" >/dev/null 2>&1; then echo 'expected existing brief refusal' >&2; exit 1; fi
printf 'PASS: brief creates optional handoff document without overwrite\n'
