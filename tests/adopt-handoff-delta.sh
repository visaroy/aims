#!/usr/bin/env bash
set -euo pipefail
ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REMOTE="$TMP/origin.git"; DATA="$TMP/data"; SID="20260728T000002Z-meta-delta-test-hermes"; BRANCH="ai/$SID"; WT="$DATA/.worktrees/$SID"
git init --bare -q --initial-branch=main "$REMOTE"
git clone -q "$REMOTE" "$DATA"
git -C "$DATA" config user.name 'AIMS Test'; git -C "$DATA" config user.email 'aims-test@example.invalid'
printf '# Test data repo\n' > "$DATA/README.md"; mkdir -p "$DATA/sessions/work" "$DATA/.worktrees"
git -C "$DATA" add README.md && git -C "$DATA" commit -q -m init && git -C "$DATA" push -q -u origin main
git -C "$DATA" worktree add -q -b "$BRANCH" "$WT" origin/main
mkdir -p "$WT/sessions/work/$SID"
printf '{"session_id":"%s","project":"meta","topic":"delta","agent":"test","branch":"%s","status":"active","environment":{}}\n' "$SID" "$BRANCH" > "$WT/sessions/work/$SID/metadata.json"
printf '# Worklog\n' > "$WT/sessions/work/$SID/worklog.md"
git -C "$WT" add sessions/work && git -C "$WT" commit -q -m start && git -C "$WT" push -q -u origin "$BRANCH"
base="$(git -C "$WT" rev-parse HEAD)"
python3 - "$WT/sessions/work/$SID/metadata.json" "$base" <<'PY'
import json,sys
p=sys.argv[1]; m=json.load(open(p)); m['status']='handoff'; m['handoff_base_commit']=sys.argv[2]; json.dump(m,open(p,'w')); open(p,'a').write('\n')
PY
git -C "$WT" add sessions/work && git -C "$WT" commit -q -m handoff && git -C "$WT" push -q origin "$BRANCH"
printf 'later work\n' > "$WT/later.txt"; git -C "$WT" add later.txt && git -C "$WT" commit -q -m later && git -C "$WT" push -q origin "$BRANCH"
output="$(AIMS_HOME="$DATA" "$ENGINE_ROOT/bin/aims" adopt "$SID" --remote)"
printf '%s\n' "$output" | grep -F 'HANDOFF DELTA'
printf '%s\n' "$output" | grep -F "comparison boundary: $base"
printf '%s\n' "$output" | grep -F 'commits since boundary: 2'
printf '%s\n' "$output" | grep -F 'later.txt'
printf 'PASS: adopt reports Git-native handoff delta\n'
