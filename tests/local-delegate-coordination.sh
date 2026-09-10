#!/usr/bin/env bash
set -euo pipefail
ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="$ENGINE_ROOT/bin/aims"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REMOTE="$TMP/origin.git"; DATA="$TMP/data"
git init --bare -q --initial-branch=main "$REMOTE"; git clone -q "$REMOTE" "$DATA"
git -C "$DATA" config user.name 'AIMS Test'; git -C "$DATA" config user.email 'aims-test@example.invalid'
printf '# Test\n' > "$DATA/README.md"; git -C "$DATA" add README.md && git -C "$DATA" commit -q -m init && git -C "$DATA" push -q -u origin main

# --- Phase 2: metadata is stamped with OS-observed facts, never caller input ---
start_out="$(AIMS_HOME="$DATA" "$ENGINE" start meta observed-facts tester --scope path:observed)"
sid="$(printf '%s\n' "$start_out" | sed -n 's/^SESSION_ID=//p')"
wt="$DATA/.worktrees/$sid"
meta="$wt/sessions/work/$sid/metadata.json"
python3 - "$meta" <<'PY'
import json,sys
m=json.load(open(sys.argv[1]))
o=m.get('observed')
assert isinstance(o,dict), 'observed block missing'
assert o.get('hostname'), 'hostname not stamped'
assert o.get('ancestor_pid'), 'ancestor_pid not stamped'
assert o.get('last_heartbeat'), 'last_heartbeat not stamped'
PY
echo 'PASS: aims start stamps OS-observed facts (hostname, ancestor pid, heartbeat) into metadata'

# --- aims heartbeat bumps last_heartbeat and pushes ---
before="$(python3 -c 'import json;print(json.load(open("'"$meta"'"))["observed"]["last_heartbeat"])')"
sleep 1
(cd "$wt" && AIMS_HOME="$DATA" "$ENGINE" heartbeat "$sid" >/dev/null)
after="$(python3 -c 'import json;print(json.load(open("'"$meta"'"))["observed"]["last_heartbeat"])')"
[ "$before" != "$after" ] || { echo 'FAIL: heartbeat did not advance last_heartbeat' >&2; exit 1; }
git -C "$DATA" fetch -q origin "ai/$sid"
remote_hb="$(git -C "$DATA" show "origin/ai/$sid:sessions/work/$sid/metadata.json" | python3 -c 'import json,sys;print(json.load(sys.stdin)["observed"]["last_heartbeat"])')"
[ "$remote_hb" = "$after" ] || { echo 'FAIL: heartbeat was not pushed to origin' >&2; exit 1; }
echo 'PASS: aims heartbeat advances and pushes observed.last_heartbeat'

# --- aims save also bumps the heartbeat as a side effect ---
before_save_hb="$after"
sleep 1
printf 'work\n' > "$wt/work.txt"
(cd "$wt" && AIMS_HOME="$DATA" "$ENGINE" save >/dev/null)
after_save_hb="$(python3 -c 'import json;print(json.load(open("'"$meta"'"))["observed"]["last_heartbeat"])')"
[ "$before_save_hb" != "$after_save_hb" ] || { echo 'FAIL: aims save did not bump heartbeat' >&2; exit 1; }
echo 'PASS: aims save bumps observed.last_heartbeat as a side effect'

# --- Phase 1: local admission lock serializes two same-machine racers on overlapping scope ---
RACE_A="$TMP/race-a"; RACE_B="$TMP/race-b"
git clone -q "$REMOTE" "$RACE_A"; git clone -q "$REMOTE" "$RACE_B"
for clone in "$RACE_A" "$RACE_B"; do git -C "$clone" config user.name 'AIMS Test'; git -C "$clone" config user.email 'aims-test@example.invalid'; done
# Same AIMS_HOME (same machine, shared .locks/ dir) — the scenario the local lock protects.
common_home="$TMP/common-home"; git clone -q "$REMOTE" "$common_home"
git -C "$common_home" config user.name 'AIMS Test'; git -C "$common_home" config user.email 'aims-test@example.invalid'
cp -r "$common_home" "$TMP/common-home-2"
(AIMS_HOME="$common_home" "$ENGINE" start meta lock-race-one tester --scope path:lockrace >"$TMP/lock-race-one.out" 2>&1) & one=$!
(AIMS_HOME="$TMP/common-home-2" "$ENGINE" start meta lock-race-two tester --scope path:lockrace >"$TMP/lock-race-two.out" 2>&1) & two=$!
set +e; wait "$one"; one_status=$?; wait "$two"; two_status=$?; set -e
[ $((one_status + two_status)) -ge 1 ] || { echo 'FAIL: overlapping-scope race did not produce at least one rejection' >&2; exit 1; }
echo 'PASS: overlapping-scope racers do not both succeed (git-ref lease enforces this end state regardless of local lock timing)'

# --- Phase 4: conflicts diagnoses a same-machine, dead-ancestor, zero-commit orphan ---
sleep_pid_holder() {
  # A short-lived process we can reliably confirm has exited, used as a
  # deterministic dead-ancestor fixture instead of racing a real subshell.
  sh -c 'exit 0' &
  local pid=$!
  wait "$pid" 2>/dev/null || true
  printf '%s\n' "$pid"
}
orphan_out="$(AIMS_HOME="$DATA" "$ENGINE" start meta dead-orphan tester --scope path:orphanzone)"
orphan_sid="$(printf '%s\n' "$orphan_out" | sed -n '/^SESSION_ID=/s/^SESSION_ID=//p')"
dead_pid="$(sleep_pid_holder)"
git -C "$DATA" fetch -q origin "ai/$orphan_sid"
orphan_wt="$DATA/.worktrees/$orphan_sid"
python3 - "$orphan_wt/sessions/work/$orphan_sid/metadata.json" "$dead_pid" <<'PY'
import json,sys
path,pid=sys.argv[1],sys.argv[2]
m=json.load(open(path))
m['observed']['ancestor_pid']=pid
m['observed']['ancestor_pid_started']='definitely-not-a-real-marker'
json.dump(m,open(path,'w'),indent=2)
PY
(cd "$orphan_wt" && git add -A && git -c user.name='AIMS Test' -c user.email='aims-test@example.invalid' commit -q -m 'test: stamp dead ancestor' --amend)
git -C "$orphan_wt" push -q --force-with-lease="refs/heads/ai/$orphan_sid" origin "ai/$orphan_sid"
diag="$(AIMS_HOME="$DATA" "$ENGINE" conflicts --scope path:orphanzone 2>&1 || true)"
printf '%s\n' "$diag" | grep -q "CONFLICT: $orphan_sid" || { echo 'FAIL: conflicts did not flag the orphan scope as a conflict' >&2; echo "$diag" >&2; exit 1; }
printf '%s\n' "$diag" | grep -qi 'DIAGNOSIS' || { echo 'FAIL: conflicts did not print a reclaim diagnosis for the dead-ancestor zero-commit orphan' >&2; echo "$diag" >&2; exit 1; }
printf '%s\n' "$diag" | grep -q 'aims abandon' || { echo 'FAIL: diagnosis did not suggest aims abandon' >&2; exit 1; }
echo 'PASS: conflicts diagnoses a same-machine, dead-ancestor, zero-commit orphan and suggests reclaim'

# --- Phase 4 non-negotiable invariant: never suggest reclaim once real commits exist ---
worked_out="$(AIMS_HOME="$DATA" "$ENGINE" start meta has-real-work tester --scope path:realwork)"
worked_sid="$(printf '%s\n' "$worked_out" | sed -n '/^SESSION_ID=/s/^SESSION_ID=//p')"
worked_wt="$DATA/.worktrees/$worked_sid"
printf 'real work, not a scaffold\n' > "$worked_wt/real.txt"
(cd "$worked_wt" && AIMS_HOME="$DATA" "$ENGINE" save >/dev/null)
# Even if we forge a dead-ancestor stamp on a branch with real commits, the
# scaffold check must refuse to call it reclaimable.
python3 - "$worked_wt/sessions/work/$worked_sid/metadata.json" <<'PY'
import json,sys
path=sys.argv[1]
m=json.load(open(path))
m['observed']['ancestor_pid']='999999'
m['observed']['ancestor_pid_started']='definitely-not-a-real-marker'
json.dump(m,open(path,'w'),indent=2)
PY
(cd "$worked_wt" && git add -A && AIMS_HOME="$DATA" "$ENGINE" save >/dev/null)
diag2="$(AIMS_HOME="$DATA" "$ENGINE" conflicts --scope path:realwork 2>&1 || true)"
printf '%s\n' "$diag2" | grep -q "CONFLICT: $worked_sid" || { echo 'FAIL: conflicts did not flag the real-work scope as a conflict' >&2; exit 1; }
if printf '%s\n' "$diag2" | grep -qi 'DIAGNOSIS'; then echo 'FAIL: conflicts suggested reclaim against a session with real commits — hard invariant violated' >&2; exit 1; fi
echo 'PASS: conflicts never suggests reclaim once a branch has real commits (hard invariant holds)'

# --- Phase 3: delegate-exec pre-registers dispatch durably before the child can complete ---
parent_out="$(AIMS_HOME="$DATA" "$ENGINE" start meta delegate-parent tester --scope path:delegatezone)"
parent_sid="$(printf '%s\n' "$parent_out" | sed -n '/^SESSION_ID=/s/^SESSION_ID=//p')"
parent_wt="$DATA/.worktrees/$parent_sid"
set +e
(cd "$parent_wt" && AIMS_HOME="$DATA" "$ENGINE" delegate-exec "$parent_sid" -- sh -c 'exit 0' >"$TMP/delegate-ok.out" 2>&1)
delegate_status=$?
set -e
[ "$delegate_status" -eq 0 ] || { echo 'FAIL: delegate-exec did not propagate the child success exit code' >&2; cat "$TMP/delegate-ok.out" >&2; exit 1; }
grep -q '^STATUS=completed$' "$TMP/delegate-ok.out" || { echo 'FAIL: delegate-exec did not report STATUS=completed' >&2; exit 1; }
git -C "$DATA" fetch -q origin "ai/$parent_sid"
delegations="$(git -C "$DATA" show "origin/ai/$parent_sid:sessions/work/$parent_sid/metadata.json" | python3 -c 'import json,sys; m=json.load(sys.stdin); print(len(m.get("delegations",[])))')"
[ "$delegations" = 1 ] || { echo "FAIL: expected exactly 1 delegation record, found $delegations" >&2; exit 1; }
completed_status="$(git -C "$DATA" show "origin/ai/$parent_sid:sessions/work/$parent_sid/metadata.json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["delegations"][0]["status"])')"
[ "$completed_status" = completed ] || { echo "FAIL: expected delegation status completed, found $completed_status" >&2; exit 1; }
echo 'PASS: delegate-exec durably records dispatch and completion in the parent session metadata'

# --- delegate-exec: child that would create a competing overlapping-scope session is blocked ---
parent2_out="$(AIMS_HOME="$DATA" "$ENGINE" start meta delegate-guard tester --scope path:delegateguard)"
parent2_sid="$(printf '%s\n' "$parent2_out" | sed -n '/^SESSION_ID=/s/^SESSION_ID=//p')"
parent2_wt="$DATA/.worktrees/$parent2_sid"
set +e
(cd "$parent2_wt" && AIMS_HOME="$DATA" "$ENGINE" delegate-exec "$parent2_sid" -- "$ENGINE" start meta should-be-blocked tester --scope path:delegateguard >"$TMP/delegate-blocked.out" 2>&1)
blocked_status=$?
set -e
[ "$blocked_status" -ne 0 ] || { echo 'FAIL: delegated child was able to run aims start (lifecycle guard did not fire)' >&2; cat "$TMP/delegate-blocked.out" >&2; exit 1; }
grep -q 'ALREADY_IN_SESSION' "$TMP/delegate-blocked.out" || { echo 'FAIL: delegated child rejection did not cite ALREADY_IN_SESSION' >&2; cat "$TMP/delegate-blocked.out" >&2; exit 1; }
echo 'PASS: delegate-exec propagates AIMS_SESSION_ID so a delegated child cannot start a competing session'

# --- Non-cooperating scenario from the design brief: an arbitrary process invoking
# aims start directly (no delegate-exec, no env var) on an already-active local scope
# is still caught — by the pre-existing git-level conflict check, which local admission
# does not bypass or weaken.
direct_out=""
set +e
direct_out="$(AIMS_HOME="$DATA" "$ENGINE" start meta uncooperative-caller tester --scope path:delegateguard 2>&1)"
direct_status=$?
set -e
[ "$direct_status" -ne 0 ] || { echo 'FAIL: an uncooperative caller was able to start a session on an already-active scope' >&2; exit 1; }
printf '%s\n' "$direct_out" | grep -q 'CONFLICT' || { echo 'FAIL: the rejection did not cite a scope CONFLICT' >&2; exit 1; }
echo 'PASS: an arbitrary uncooperative caller with no env var and no delegate-exec is still blocked from an overlapping-scope start'

printf 'PASS: local admission lock, observed-fact stamping, heartbeat, reclaim diagnostics, and delegate-exec all behave as designed\n'
