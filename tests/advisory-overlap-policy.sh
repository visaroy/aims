#!/usr/bin/env bash
set -euo pipefail
ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="$ENGINE_ROOT/bin/aims"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REMOTE="$TMP/origin.git"; DATA="$TMP/data"; ADOPTER="$TMP/adopter"; ACTIVE_ADOPTER="$TMP/active-adopter"
git init --bare -q --initial-branch=main "$REMOTE"; git clone -q "$REMOTE" "$DATA"
git -C "$DATA" config user.name 'AIMS Test'; git -C "$DATA" config user.email 'aims-test@example.invalid'
printf '# Test\n' > "$DATA/README.md"; git -C "$DATA" add README.md && git -C "$DATA" commit -q -m init && git -C "$DATA" push -q -u origin main
start() { AIMS_HOME="$DATA" "$ENGINE" start "$@"; }

dashboard_first="$(start meta dashboard-first tester --scope dashboard:team)"
printf '%s\n' "$dashboard_first" | grep -q '^SESSION_ID='
dashboard_overlap="$(start meta dashboard-overlap tester --scope dashboard:team 2>&1)"
printf '%s\n' "$dashboard_overlap" | grep -q '^SESSION_ID='
printf '%s\n' "$dashboard_overlap" | grep -q '^CONFLICT:'
printf '%s\n' "$dashboard_overlap" | grep -q 'WARN: advisory scope overlap'
echo 'PASS: dashboard is accepted and an exact dashboard overlap warns while both starts succeed'

path_parent="$(start meta path-parent tester --scope path:shared)"
printf '%s\n' "$path_parent" | grep -q '^SESSION_ID='
path_child="$(start meta path-child tester --scope path:shared/child 2>&1)"
printf '%s\n' "$path_child" | grep -q '^SESSION_ID='
printf '%s\n' "$path_child" | grep -q 'WARN: advisory scope overlap'
echo 'PASS: path overlap warns while the second start succeeds'

unrelated="$(AIMS_HOME="$DATA" "$ENGINE" conflicts --scope dashboard:unrelated 2>&1)"
printf '%s\n' "$unrelated" | grep -q '^SAFE:'
if printf '%s\n' "$unrelated" | grep -q '^CONFLICT:'; then echo 'FAIL: unrelated dashboard scope was reported as overlapping' >&2; exit 1; fi
echo 'PASS: unrelated scope remains SAFE'

if start meta invalid-kind tester --scope unsupported:value >/dev/null 2>&1; then echo 'FAIL: unsupported scope kind was accepted' >&2; exit 1; fi
if start meta invalid-dashboard tester --scope dashboard: >/dev/null 2>&1; then echo 'FAIL: malformed dashboard scope was accepted' >&2; exit 1; fi
echo 'PASS: malformed scopes remain blocking'

handoff_out="$(start meta handoff-target tester --scope dashboard:handoff)"
handoff_sid="$(printf '%s\n' "$handoff_out" | sed -n 's/^SESSION_ID=//p')"
handoff_wt="$DATA/.worktrees/$handoff_sid"
(cd "$handoff_wt" && AIMS_HOME="$DATA" "$ENGINE" handoff ready-for-adoption >/dev/null)
handoff_overlap="$(start meta handoff-overlap tester --scope dashboard:handoff 2>&1)"
printf '%s\n' "$handoff_overlap" | grep -q '^SESSION_ID='
git clone -q "$REMOTE" "$ADOPTER"; git -C "$ADOPTER" config user.name 'AIMS Test'; git -C "$ADOPTER" config user.email 'aims-test@example.invalid'
adopt_out="$(AIMS_HOME="$ADOPTER" "$ENGINE" adopt "$handoff_sid" 2>&1)"
printf '%s\n' "$adopt_out" | grep -q 'ADVISORY SCOPE DIAGNOSTICS'
printf '%s\n' "$adopt_out" | grep -q 'WARN: advisory scope overlap detected for handed-off session'
echo 'PASS: handed-off adoption reports advisory overlap without blocking'

active_out="$(start meta active-target tester --scope dashboard:active)"
active_sid="$(printf '%s\n' "$active_out" | sed -n 's/^SESSION_ID=//p')"
git clone -q "$REMOTE" "$ACTIVE_ADOPTER"; git -C "$ACTIVE_ADOPTER" config user.name 'AIMS Test'; git -C "$ACTIVE_ADOPTER" config user.email 'aims-test@example.invalid'
set +e
non_handoff_out="$(AIMS_HOME="$ACTIVE_ADOPTER" "$ENGINE" adopt "$active_sid" 2>&1)"
non_handoff_status=$?
set -e
[ "$non_handoff_status" -ne 0 ] || { echo 'FAIL: non-handoff adoption succeeded' >&2; exit 1; }
printf '%s\n' "$non_handoff_out" | grep -q 'not handed off'
echo 'PASS: non-handoff adoption remains blocking'

printf 'PASS: advisory overlap policy regression suite\n'
