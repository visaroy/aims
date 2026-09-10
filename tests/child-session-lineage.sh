#!/usr/bin/env bash
set -euo pipefail
ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="$ENGINE_ROOT/bin/aims"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REMOTE="$TMP/origin.git"; DATA="$TMP/data"; ADOPTER="$TMP/adopter"; RACE_A="$TMP/race-a"; RACE_B="$TMP/race-b"
git init --bare -q --initial-branch=main "$REMOTE"; git clone -q "$REMOTE" "$DATA"
git -C "$DATA" config user.name 'AIMS Test'; git -C "$DATA" config user.email 'aims-test@example.invalid'
printf '# Test\n' > "$DATA/README.md"; git -C "$DATA" add README.md && git -C "$DATA" commit -q -m init && git -C "$DATA" push -q -u origin main
if AIMS_HOME="$DATA" "$ENGINE" start meta unscoped tester >/dev/null 2>&1; then echo 'unscoped session was created' >&2; exit 1; fi
if AIMS_HOME="$DATA" "$ENGINE" start meta malformed tester --scope 'path:valid,' >/dev/null 2>&1; then echo 'malformed scope was created' >&2; exit 1; fi
git clone -q "$REMOTE" "$RACE_A"; git clone -q "$REMOTE" "$RACE_B"
for clone in "$RACE_A" "$RACE_B"; do git -C "$clone" config user.name 'AIMS Test'; git -C "$clone" config user.email 'aims-test@example.invalid'; done
(AIMS_HOME="$RACE_A" "$ENGINE" start meta race-one tester --scope path:race >"$TMP/race-one.out" 2>&1) & race_one=$!
(AIMS_HOME="$RACE_B" "$ENGINE" start meta race-two tester --scope path:race/child >"$TMP/race-two.out" 2>&1) & race_two=$!
set +e; wait "$race_one"; race_one_status=$?; wait "$race_two"; race_two_status=$?; set -e
[ $((race_one_status + race_two_status)) = 1 ] || { echo 'scope race did not yield exactly one winner' >&2; exit 1; }
race_count="$(git --git-dir="$REMOTE" for-each-ref --format='%(refname)' 'refs/heads/ai/*race-*' | wc -l | tr -d ' ')"; [ "$race_count" = 1 ] || { echo 'scope race created multiple writers' >&2; exit 1; }
start_parent="$(AIMS_HOME="$DATA" "$ENGINE" start meta parent tester --scope path:shared)"; parent="$(printf '%s\n' "$start_parent" | sed -n 's/^SESSION_ID=//p')"
if git --git-dir="$REMOTE" show-ref --verify --quiet refs/heads/aims-start-lock; then echo 'admission lock survived start' >&2; exit 1; fi
git clone -q "$REMOTE" "$ADOPTER"; git -C "$ADOPTER" config user.name 'AIMS Test'; git -C "$ADOPTER" config user.email 'aims-test@example.invalid'
if active_adopt="$(AIMS_HOME="$ADOPTER" "$ENGINE" adopt "$parent" 2>&1)"; then echo 'active session was adopted locally' >&2; exit 1; fi
printf '%s\n' "$active_adopt" | grep -F 'not handed off' >/dev/null
if child="$(AIMS_HOME="$DATA" "$ENGINE" start meta child tester --scope path:shared --parent-session "$parent" 2>&1)"; then echo 'overlapping child was created' >&2; exit 1; fi
printf '%s\n' "$child" | grep -F "CONFLICT: $parent" >/dev/null
child_branch_count="$(git --git-dir="$REMOTE" for-each-ref --format='%(refname)' "refs/heads/ai/*child*" | wc -l | tr -d ' ')"; [ "$child_branch_count" = 0 ] || { echo 'rejected child branch exists' >&2; exit 1; }
start_external_path="$(AIMS_HOME="$DATA" "$ENGINE" start meta external-path tester --scope path:external)"; external_path="$(printf '%s\n' "$start_external_path" | sed -n 's/^SESSION_ID=//p')"
if blocked="$(AIMS_HOME="$DATA" "$ENGINE" start meta blocked tester --scope path:external --parent-session "$parent" 2>&1)"; then echo 'parented child ignored unrelated conflict' >&2; exit 1; fi
printf '%s\n' "$blocked" | grep -F "CONFLICT: $external_path" >/dev/null
blocked_branch_count="$(git --git-dir="$REMOTE" for-each-ref --format='%(refname)' "refs/heads/ai/*blocked*" | wc -l | tr -d ' ')"; [ "$blocked_branch_count" = 0 ] || { echo 'blocked child branch exists' >&2; exit 1; }
if ambient="$(AIMS_HOME="$DATA" AIMS_SESSION_ID="$parent" "$ENGINE" start meta ambient tester --scope path:other 2>&1)"; then echo 'ambient delegate start was allowed' >&2; exit 1; fi
printf '%s\n' "$ambient" | grep -Fx 'REASON=ALREADY_IN_SESSION' >/dev/null
if AIMS_HOME="$DATA" "$ENGINE" start meta invalid tester --scope path:invalid --parent-session 'bad/id' >/dev/null 2>&1; then echo 'unsafe parent accepted' >&2; exit 1; fi
if AIMS_HOME="$DATA" "$ENGINE" start meta missing tester --scope path:missing --parent-session missing-parent >/dev/null 2>&1; then echo 'missing parent accepted' >&2; exit 1; fi
start_empty="$(AIMS_HOME="$DATA" "$ENGINE" start meta empty tester --scope path:empty)"; empty="$(printf '%s\n' "$start_empty" | sed -n 's/^SESSION_ID=//p')"
printf 'main advanced\n' >> "$DATA/README.md"; git -C "$DATA" add README.md && git -C "$DATA" commit -q -m 'advance main' && git -C "$DATA" push -q origin main
AIMS_HOME="$DATA" "$ENGINE" abandon "$empty" --empty-only | grep -F "OK: abandoned empty session $empty" >/dev/null
if git --git-dir="$REMOTE" show-ref --verify --quiet "refs/heads/ai/$empty"; then echo 'empty session branch survived abandon' >&2; exit 1; fi
if git --git-dir="$REMOTE" show-ref --verify --quiet refs/heads/aims-start-lock; then echo 'admission lock survived abandon' >&2; exit 1; fi
start_ahead="$(AIMS_HOME="$DATA" "$ENGINE" start meta ahead tester --scope path:ahead)"; ahead="$(printf '%s\n' "$start_ahead" | sed -n 's/^SESSION_ID=//p')"; ahead_wt="$DATA/.worktrees/$ahead"
printf 'local commit\n' > "$ahead_wt/local-ahead.txt"; git -C "$ahead_wt" add local-ahead.txt && git -C "$ahead_wt" commit -q -m 'local ahead'
if AIMS_HOME="$DATA" "$ENGINE" abandon "$ahead" --empty-only >/dev/null 2>&1; then echo 'abandon removed clean local-ahead commit' >&2; exit 1; fi
printf 'PASS: active scopes and ambient delegates block nested writers before mutation\n'
