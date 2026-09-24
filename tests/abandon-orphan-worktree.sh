#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AIMS="$ROOT/bin/aims"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/aims-abandon-orphan.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
REMOTE="$TMP/remote.git"
DATA="$TMP/data"
export HOME="$TMP/home"
export GIT_CONFIG_NOSYSTEM=1
export GIT_TERMINAL_PROMPT=0
export GIT_EDITOR=true
export GIT_SEQUENCE_EDITOR=true
export GIT_PAGER=cat
unset GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_SSH_COMMAND
mkdir -p "$HOME"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "$3 (missing: $2)";; esac; }
assert_ref_exists() { if [ "$1" = "$REMOTE" ]; then git --git-dir="$1" show-ref --verify --quiet "$2" || fail "missing ref $2"; else git -C "$1" show-ref --verify --quiet "$2" || fail "missing ref $2"; fi; }
assert_ref_absent() { if [ "$1" = "$REMOTE" ]; then git --git-dir="$1" show-ref --verify --quiet "$2" && fail "unexpected ref $2" || true; else git -C "$1" show-ref --verify --quiet "$2" && fail "unexpected ref $2" || true; fi; }
assert_worktree_registered() { sid="$1"; git -C "$DATA" worktree list --porcelain | grep -Fqx "branch refs/heads/ai/$sid" || fail "missing registered worktree $sid"; }
assert_worktree_absent() { sid="$1"; if [ -e "$DATA/.worktrees/$sid" ] || [ -L "$DATA/.worktrees/$sid" ] || git -C "$DATA" worktree list --porcelain | grep -Fqx "branch refs/heads/ai/$sid"; then fail "unexpected worktree $sid"; fi; }
expect_failure() {
  label="$1"; shift
  if output="$(AIMS_HOME="$DATA" "$AIMS" abandon "$@" 2>&1)"; then
    echo "$output" >&2
    fail "$label unexpectedly succeeded"
  fi
  LAST_OUTPUT="$output"
}
expect_success() {
  label="$1"; shift
  if ! output="$(AIMS_HOME="$DATA" "$AIMS" abandon "$@" 2>&1)"; then
    echo "$output" >&2
    fail "$label failed"
  fi
  LAST_OUTPUT="$output"
}
snapshot_refs() { git -C "$DATA" for-each-ref --format='%(refname) %(objectname)' refs/remotes/origin refs/heads/ai; }
remote_oid() { git --git-dir="$REMOTE" rev-parse "refs/heads/ai/$1" 2>/dev/null; }
clean_case() {
  sid="$1"
  rm -f "$REMOTE/hooks/pre-receive" "$REMOTE/hooks/update"
  git --git-dir="$REMOTE" update-ref -d "refs/heads/ai/$sid" 2>/dev/null || true
  git -C "$DATA" update-ref -d "refs/heads/ai/$sid" 2>/dev/null || true
  git -C "$DATA" update-ref -d "refs/remotes/origin/ai/$sid" 2>/dev/null || true
  if [ -e "$DATA/.worktrees/$sid" ] || [ -L "$DATA/.worktrees/$sid" ]; then git -C "$DATA" worktree remove --force "$DATA/.worktrees/$sid" 2>/dev/null || rm -rf "$DATA/.worktrees/$sid"; fi
}
json_key() {
  python3 - "$1" "$2" <<'PY'
import json,sys
print(json.dumps({sys.argv[1]: sys.argv[2]}, separators=(',', ':')))
PY
}
setup_repositories() {
  git init -q --bare "$REMOTE"
  seed="$TMP/seed"
  git init -q "$seed"
  git -C "$seed" config user.name 'AIMS Test'
  git -C "$seed" config user.email 'aims-test@example.invalid'
  printf 'base\n' > "$seed/base.txt"
  git -C "$seed" add base.txt
  git -C "$seed" commit -q -m base
  git -C "$seed" branch -M main
  git -C "$seed" remote add origin "$REMOTE"
  git -C "$seed" push -q -u origin main
  git --git-dir="$REMOTE" symbolic-ref HEAD refs/heads/main
  git clone -q "$REMOTE" "$DATA"
  git -C "$DATA" config user.name 'AIMS Test Data'
  git -C "$DATA" config user.email 'aims-data@example.invalid'
  mkdir -p "$DATA/.worktrees"
}
make_scaffold() {
  sid="$1"; overrides="${2:-}"; mode="${3:-}"
  wt="$DATA/.worktrees/$sid"
  git -C "$DATA" fetch -q origin main
  git -C "$DATA" worktree add -q "$wt" -b "ai/$sid" origin/main
  mkdir -p "$wt/sessions/work/$sid"
  host="$(aims_hostname)"
  marker="$(aims_process_started_marker "$$")"
  python3 - "$sid" "$wt" "$host" "$$" "$marker" "$overrides" > "$wt/sessions/work/$sid/metadata.json" <<'PY'
import json,sys
sid,wt,host,pid,marker,overrides=sys.argv[1:]
metadata={
    'session_id':sid,
    'project':'test',
    'topic':'orphan',
    'agent':'test',
    'branch':'ai/'+sid,
    'worktree':wt,
    'status':'active',
    'scope':['path:tests/'+sid],
    'observed':{
        'hostname':host,
        'ancestor_pid':pid,
        'ancestor_pid_started':marker,
        'last_heartbeat':'2026-09-24T07:30:00Z',
    },
}
if overrides:
    metadata.update(json.loads(overrides))
print(json.dumps(metadata, separators=(',', ':')))
PY
  for file in worklog.md commands.md tests.md final-summary.md prompt-log.md; do
    case ",$mode," in *,missing:$file,*) ;; *,nonempty:$file,*) printf 'not empty\n' > "$wt/sessions/work/$sid/$file" ;; *) : > "$wt/sessions/work/$sid/$file" ;; esac
  done
  case "$mode" in
    extra-path) printf 'extra\n' > "$wt/extra.txt" ;;
    missing-metadata) rm "$wt/sessions/work/$sid/metadata.json" ;;
    missing-worklog) rm "$wt/sessions/work/$sid/worklog.md" ;;
    malformed-metadata) printf '{' > "$wt/sessions/work/$sid/metadata.json" ;;
    nonobject-metadata) printf '[]\n' > "$wt/sessions/work/$sid/metadata.json" ;;
    status-absent) python3 - "$wt/sessions/work/$sid/metadata.json" <<'PY'
import json,sys
path=sys.argv[1]; metadata=json.load(open(path)); metadata.pop('status'); json.dump(metadata,open(path,'w'),separators=(',',':'))
PY
      ;;
    status-wrong-type) python3 - "$wt/sessions/work/$sid/metadata.json" <<'PY'
import json,sys
path=sys.argv[1]; metadata=json.load(open(path)); metadata['status']=[]; json.dump(metadata,open(path,'w'),separators=(',',':'))
PY
      ;;
  esac
  git -C "$wt" add -A
  git -C "$wt" commit -q -m "fixture $sid"
  git -C "$wt" push -q origin "ai/$sid:refs/heads/ai/$sid"
  git -C "$DATA" worktree remove --force "$wt"
  git -C "$DATA" fetch -q origin "refs/heads/ai/$sid:refs/remotes/origin/ai/$sid"
}
restore_default_worktree() { sid="$1"; git -C "$DATA" worktree add -q "$DATA/.worktrees/$sid" "ai/$sid"; }
make_second_remote_commit() {
  sid="$1"; writer="$TMP/writer-$sid"
  git -C "$DATA" worktree add -q "$writer" -b "writer-$sid" "origin/ai/$sid"
  printf 'second commit\n' > "$writer/second.txt"
  git -C "$writer" add second.txt
  git -C "$writer" commit -q -m 'second fixture commit'
  git -C "$writer" push -q origin "writer-$sid:refs/heads/ai/$sid"
  git -C "$DATA" worktree remove --force "$writer"
  git -C "$DATA" branch -D "writer-$sid" >/dev/null
  git -C "$DATA" fetch -q origin "refs/heads/ai/$sid:refs/remotes/origin/ai/$sid"
}
make_remote_advance_oid() {
  sid="$1"; writer="$TMP/advance-$sid"
  git -C "$DATA" worktree add -q "$writer" -b "advance-$sid" "origin/ai/$sid"
  printf 'remote advance\n' > "$writer/advance.txt"
  git -C "$writer" add advance.txt
  git -C "$writer" commit -q -m 'remote advance object'
  ADVANCE_OID="$(git -C "$writer" rev-parse HEAD)"
  git -C "$writer" push -q origin "advance-$sid:refs/heads/advance-$sid"
  git -C "$DATA" worktree remove --force "$writer"
  git -C "$DATA" branch -D "advance-$sid" >/dev/null
}
advance_main() {
  file="$1"
  printf 'main advancement\n' > "$DATA/$file"
  git -C "$DATA" add "$file"
  git -C "$DATA" commit -q -m 'advance main'
  git -C "$DATA" push -q origin main
}
install_failure_wrapper() {
  sid="$1"; failure_mode="$2"; wrapper_dir="$TMP/wrapper-$sid"; count_file="$TMP/count-$sid"
  mkdir -p "$wrapper_dir"
  real_git="$(command -v git)"
  wrapper="$TMP/wrapper-script-$sid"
  cat > "$wrapper" <<HOOK
#!/bin/sh
case "$failure_mode" in
  pre-show-ref)
    case "\$*" in *"show-ref --verify --quiet refs/heads/ai/$sid"*) exit 2;; esac ;;
  pre-grep)
    case "\$*" in *"-Fqx branch refs/heads/ai/$sid"*) exit 2;; esac ;;
  pre-worktree-list)
    case "\$*" in *"worktree list --porcelain"*) exit 2;; esac ;;
  post-show-ref)
    case "\$*" in
      *"show-ref --verify --quiet refs/heads/ai/$sid"*)
        count=0; [ -f "$count_file" ] && IFS= read -r count < "$count_file"
        count=\$((count + 1)); printf '%s\n' "\$count" > "$count_file"
        [ "\$count" -ge 3 ] && exit 2 ;;
    esac ;;
  post-cleanup-show-ref)
    case "\$*" in
      *"show-ref --verify --quiet refs/heads/ai/$sid"*)
        count=0; [ -f "$count_file" ] && IFS= read -r count < "$count_file"
        count=\$((count + 1)); printf '%s\n' "\$count" > "$count_file"
        [ "\$count" -ge 4 ] && exit 2 ;;
    esac ;;
  post-worktree-list)
    case "\$*" in
      *"worktree list --porcelain"*)
        count=0; [ -f "$count_file" ] && IFS= read -r count < "$count_file"
        count=\$((count + 1)); printf '%s\n' "\$count" > "$count_file"
        [ "\$count" -ge 3 ] && exit 2 ;;
    esac ;;
  post-ls-remote)
    case "\$*" in *"ls-remote origin refs/heads/ai/$sid"*) exit 2;; esac ;;
  default-status)
    case "\$*" in *"status --porcelain"*) exit 2;; esac ;;
  default-show-ref)
    case "\$*" in *"show-ref --verify --quiet refs/heads/ai/$sid"*) exit 2;; esac ;;
  default-worktree-remove)
    case "\$*" in
      *"worktree remove $DATA/.worktrees/$sid"*)
        printf 'race dirty\n' > "$DATA/.worktrees/$sid/race.txt"
        exec "$real_git" "\$@" ;;
    esac ;;
  default-update-ref)
    case "\$*" in *"update-ref -d refs/heads/ai/$sid"*) exit 2;; esac ;;
esac
exec "$real_git" "\$@"
HOOK
  chmod +x "$wrapper"
  cp "$wrapper" "$wrapper_dir/git"
  if [ "$failure_mode" = pre-grep ]; then
    real_grep="$(command -v grep)"
    cat > "$wrapper_dir/grep" <<HOOK
#!/bin/sh
case "\$*" in *"-Fqx branch refs/heads/ai/$sid"*) exit 2;; esac
exec "$real_grep" "\$@"
HOOK
    chmod +x "$wrapper_dir/grep"
  fi
  WRAPPER_PATH="$wrapper_dir"
}
run_wrapped_failure() {
  sid="$1"; failure_mode="$2"; expected_phase="$3"
  make_scaffold "$sid"
  install_failure_wrapper "$sid" "$failure_mode"
  old_path="$PATH"; PATH="$WRAPPER_PATH:$PATH"
  expect_failure "injected $failure_mode" "$sid" --empty-only --confirm-orphan "$sid"
  PATH="$old_path"
  assert_contains "$LAST_OUTPUT" "$expected_phase" "$failure_mode phase"
  if [ "$expected_phase" = REFUSE ]; then
    assert_ref_exists "$REMOTE" "refs/heads/ai/$sid"
  else
    assert_ref_absent "$REMOTE" "refs/heads/ai/$sid"
  fi
  assert_ref_exists "$DATA" "refs/heads/ai/$sid"
  clean_case "$sid"
}
run_default_wrapped_failure() {
  sid="$1"; failure_mode="$2"; expected_phase="$3"
  make_scaffold "$sid"
  restore_default_worktree "$sid"
  install_failure_wrapper "$sid" "$failure_mode"
  old_path="$PATH"; PATH="$WRAPPER_PATH:$PATH"
  expect_failure "injected default $failure_mode" "$sid" --empty-only
  PATH="$old_path"
  assert_contains "$LAST_OUTPUT" "$expected_phase" "default $failure_mode phase"
  if [ "$expected_phase" = REFUSE ]; then
    assert_ref_exists "$REMOTE" "refs/heads/ai/$sid"
    assert_worktree_registered "$sid"
  else
    assert_ref_absent "$REMOTE" "refs/heads/ai/$sid"
    assert_ref_exists "$DATA" "refs/heads/ai/$sid"
    if [ "$failure_mode" = default-worktree-remove ]; then
      assert_worktree_registered "$sid"
      [ -f "$DATA/.worktrees/$sid/race.txt" ] || fail 'dirty race worktree was not preserved'
    else
      assert_worktree_absent "$sid"
    fi
  fi
  clean_case "$sid"
}
setup_repositories
. "$ROOT/lib/aims-observed-facts"

sid=default-no-worktree
make_scaffold "$sid"
expect_failure 'default abandon requires local worktree' "$sid" --empty-only
assert_contains "$LAST_OUTPUT" 'local pristine session worktree' 'default local-worktree refusal'
assert_ref_exists "$DATA" "refs/heads/ai/$sid"
clean_case "$sid"
pass 'default --empty-only still refuses without its local worktree'

sid=default-success
make_scaffold "$sid"
restore_default_worktree "$sid"
expect_success 'default abandon succeeds with a clean local worktree' "$sid" --empty-only
assert_ref_absent "$REMOTE" "refs/heads/ai/$sid"
assert_ref_absent "$DATA" "refs/heads/ai/$sid"
assert_worktree_absent "$sid"
pass 'default --empty-only preserves successful clean-session behavior'

run_default_wrapped_failure default-status default-status REFUSE
run_default_wrapped_failure default-show-ref default-show-ref REFUSE
run_default_wrapped_failure default-worktree-remove default-worktree-remove PARTIAL
run_default_wrapped_failure default-update-ref default-update-ref PARTIAL
pass 'default status, show-ref, worktree removal, and update-ref failures fail closed'

sid=cli-contract
make_scaffold "$sid"
before_refs="$(snapshot_refs)"; before_remote="$(remote_oid "$sid")"
for args in \
  "$sid --empty-only --confirm-orphan" \
  "$sid --empty-only --confirm-orphan wrong-sid" \
  "ai/$sid --empty-only --confirm-orphan ai/$sid" \
  "$sid --confirm-orphan $sid --empty-only" \
  "$sid --empty-only --confirm-orphan $sid surplus"; do
  # shellcheck disable=SC2086
  expect_failure "reject CLI form: $args" $args
  [ "$before_refs" = "$(snapshot_refs)" ] || fail "invalid CLI form fetched or changed tracking refs: $args"
  [ "$before_remote" = "$(remote_oid "$sid")" ] || fail "invalid CLI form changed remote ref: $args"
done
clean_case "$sid"
pass 'wrong, missing, reordered, ai/ alias, and surplus confirmation are rejected before fetch'

sid=success-absent
make_scaffold "$sid"
git -C "$DATA" update-ref -d "refs/heads/ai/$sid"
expect_success 'confirmed orphan with absent local ref' "$sid" --empty-only --confirm-orphan "$sid"
assert_contains "$LAST_OUTPUT" 'cannot detect uncommitted work in another clone' 'orphan warning'
assert_ref_absent "$DATA" "refs/heads/ai/$sid"
[ -z "$(git --git-dir="$REMOTE" for-each-ref --format='%(refname)' "refs/heads/ai/$sid")" ] || fail 'remote branch survived absent-ref success'
pass 'confirmed orphan succeeds with absent local ref and emits the warning'

sid=success-equal
make_scaffold "$sid"
expect_success 'confirmed orphan with equal local ref' "$sid" --empty-only --confirm-orphan "$sid"
assert_ref_absent "$DATA" "refs/heads/ai/$sid"
pass 'confirmed orphan succeeds and exact-OID-cleans an equal local ref'

for status in handoff published; do
  sid="status-$status"
  make_scaffold "$sid" "$(json_key status "$status")"
  expect_failure "reject status $status" "$sid" --empty-only --confirm-orphan "$sid"
  clean_case "$sid"
done
for mode in malformed-metadata nonobject-metadata status-absent status-wrong-type; do
  sid="metadata-$mode"
  make_scaffold "$sid" '' "$mode"
  expect_failure "reject $mode" "$sid" --empty-only --confirm-orphan "$sid"
  clean_case "$sid"
done
sid=scope-empty
make_scaffold "$sid" '{"scope":[]}'
expect_failure 'reject empty scope' "$sid" --empty-only --confirm-orphan "$sid"; clean_case "$sid"
sid=scope-invalid
make_scaffold "$sid" '{"scope":["not-a-scope"]}'
expect_failure 'reject invalid scope' "$sid" --empty-only --confirm-orphan "$sid"; clean_case "$sid"
sid=scope-wrong-type
make_scaffold "$sid" '{"scope":"path:wrong-type"}'
expect_failure 'reject wrong-typed scope' "$sid" --empty-only --confirm-orphan "$sid"; clean_case "$sid"
sid=scope-noncanonical
make_scaffold "$sid" '{"scope":["path:z","path:a"]}'
expect_failure 'reject noncanonical scope' "$sid" --empty-only --confirm-orphan "$sid"; clean_case "$sid"
pass 'malformed/non-object metadata, inactive/typed status, and invalid/noncanonical scopes are refused'

valid_observed="$(python3 - "$(aims_hostname)" "$$" "$(aims_process_started_marker "$$")" <<'PY'
import json,sys
print(json.dumps({'hostname':sys.argv[1],'ancestor_pid':sys.argv[2],'ancestor_pid_started':sys.argv[3],'last_heartbeat':'2026-09-24T07:30:00Z'}, separators=(',', ':')))
PY
)"
for field in hostname ancestor_pid ancestor_pid_started last_heartbeat; do
  override="$(python3 - "$valid_observed" "$field" <<'PY'
import json,sys
observed=json.loads(sys.argv[1]); observed.pop(sys.argv[2]); print(json.dumps({'observed':observed}, separators=(',', ':')))
PY
)"
  sid="missing-$field"
  make_scaffold "$sid" "$override"
  expect_failure "reject missing observed $field" "$sid" --empty-only --confirm-orphan "$sid"; clean_case "$sid"
done
for field in hostname ancestor_pid ancestor_pid_started last_heartbeat; do
  override="$(python3 - "$valid_observed" "$field" <<'PY'
import json,sys
observed=json.loads(sys.argv[1]); observed[sys.argv[2]]='malformed'; print(json.dumps({'observed':observed}, separators=(',', ':')))
PY
)"
  sid="malformed-$field"
  make_scaffold "$sid" "$override"
  expect_failure "reject malformed observed $field" "$sid" --empty-only --confirm-orphan "$sid"; clean_case "$sid"
done
sid='other-host'
make_scaffold "$sid" "$(python3 - "$valid_observed" <<'PY'
import json,sys
observed=json.loads(sys.argv[1]); observed['hostname']='different-host'; print(json.dumps({'observed':observed}, separators=(',', ':')))
PY
)"
expect_failure 'reject other observed host' "$sid" --empty-only --confirm-orphan "$sid"; clean_case "$sid"
pass 'each observed field requires valid structure and the current aims_hostname host'

for key in session_id branch worktree; do
  case "$key" in
    session_id) value='other-session' ;;
    branch) value=ai/other-session ;;
    worktree) value="$TMP/not-canonical" ;;
  esac
  sid="identity-$key"
  make_scaffold "$sid" "$(json_key "$key" "$value")"
  expect_failure "reject metadata $key mismatch" "$sid" --empty-only --confirm-orphan "$sid"; clean_case "$sid"
done
sid=missing-metadata
make_scaffold "$sid" '' missing-metadata
expect_failure 'reject missing metadata blob' "$sid" --empty-only --confirm-orphan "$sid"; clean_case "$sid"
pass 'metadata session, branch, worktree identity, and blob presence are guarded'

sid=second-commit
make_scaffold "$sid"
make_second_remote_commit "$sid"
expect_failure 'reject second commit' "$sid" --empty-only --confirm-orphan "$sid"; clean_case "$sid"
sid=extra-path
make_scaffold "$sid" '' extra-path
expect_failure 'reject extra scaffold path' "$sid" --empty-only --confirm-orphan "$sid"; clean_case "$sid"
sid=missing-worklog
make_scaffold "$sid" '' missing-worklog
expect_failure 'reject missing artifact blob' "$sid" --empty-only --confirm-orphan "$sid"; clean_case "$sid"
sid=nonempty-tests
make_scaffold "$sid" '' nonempty:tests.md
expect_failure 'reject nonempty artifact blob' "$sid" --empty-only --confirm-orphan "$sid"; clean_case "$sid"
pass 'second commit, extra path, missing artifact, and nonempty artifact are refused'

sid=dangling-canonical
make_scaffold "$sid"
ln -s "$TMP/no-such-target" "$DATA/.worktrees/$sid"
expect_failure 'reject dangling canonical worktree path' "$sid" --empty-only --confirm-orphan "$sid"
rm "$DATA/.worktrees/$sid"; clean_case "$sid"
sid=existing-canonical
make_scaffold "$sid"
mkdir "$DATA/.worktrees/$sid"
expect_failure 'reject existing canonical worktree path' "$sid" --empty-only --confirm-orphan "$sid"
rmdir "$DATA/.worktrees/$sid"; clean_case "$sid"
sid=registered-noncanonical
make_scaffold "$sid"
other="$TMP/noncanonical-$sid"
git -C "$DATA" worktree add -q "$other" "ai/$sid"
printf 'dirty clone\n' > "$other/dirty.txt"
expect_failure 'reject registered noncanonical worktree' "$sid" --empty-only --confirm-orphan "$sid"
git -C "$DATA" worktree remove --force "$other"; clean_case "$sid"
pass 'canonical, dangling, and registered noncanonical worktrees are refused'

for kind in ahead diverged; do
  sid="local-$kind"
  make_scaffold "$sid"
  writer="$TMP/local-$kind-writer"
  if [ "$kind" = ahead ]; then base="origin/ai/$sid"; else base=origin/main; fi
  git -C "$DATA" worktree add -q "$writer" -b "local-$kind-$sid" "$base"
  printf '%s\n' "$kind" > "$writer/local.txt"
  git -C "$writer" add local.txt
  git -C "$writer" commit -q -m "local $kind"
  local_oid="$(git -C "$writer" rev-parse HEAD)"
  git -C "$DATA" worktree remove --force "$writer"
  git -C "$DATA" branch -D "local-$kind-$sid" >/dev/null
  git -C "$DATA" update-ref "refs/heads/ai/$sid" "$local_oid"
  expect_failure "reject local $kind ref" "$sid" --empty-only --confirm-orphan "$sid"; clean_case "$sid"
done
pass 'local ahead and diverged refs are preserved'

sid=main-advanced
make_scaffold "$sid"
advance_main main-advanced.txt
expect_success 'allow main advancement from true merge-base' "$sid" --empty-only --confirm-orphan "$sid"
pass 'main advancement does not invalidate a one-commit scaffold beyond the true merge-base'

run_wrapped_failure injected-pre-show-ref pre-show-ref REFUSE
run_wrapped_failure injected-pre-grep pre-grep REFUSE
run_wrapped_failure injected-pre-worktree-list pre-worktree-list REFUSE
run_wrapped_failure injected-post-show-ref post-show-ref PARTIAL
run_wrapped_failure injected-post-cleanup-show-ref post-cleanup-show-ref PARTIAL
run_wrapped_failure injected-post-worktree-list post-worktree-list PARTIAL
run_wrapped_failure injected-post-ls-remote post-ls-remote PARTIAL
pass 'show-ref, grep, worktree-list, and post-delete ls-remote failures fail closed at the correct phase'

sid=remote-advance
make_scaffold "$sid"
make_remote_advance_oid "$sid"
remote_old="$(remote_oid "$sid")"
remote_signal="$TMP/remote-advance-signal"
cat > "$REMOTE/hooks/pre-receive" <<HOOK
#!/bin/sh
read old new ref
if [ "\$ref" = "refs/heads/ai/$sid" ]; then
  touch "$remote_signal"
  sleep 1
  echo 'simulated remote advance' >&2
  exit 1
fi
exit 0
HOOK
chmod +x "$REMOTE/hooks/pre-receive"
(while [ ! -f "$remote_signal" ]; do sleep 0.01; done; while ! git --git-dir="$REMOTE" update-ref "refs/heads/ai/$sid" "$ADVANCE_OID" "$remote_old" 2>/dev/null; do sleep 0.01; done) &
racer_pid=$!
expect_failure 'preserve remote advance race' "$sid" --empty-only --confirm-orphan "$sid"
wait "$racer_pid"
assert_ref_exists "$DATA" "refs/heads/ai/$sid"
clean_case "$sid"
git --git-dir="$REMOTE" update-ref -d "refs/heads/advance-$sid" 2>/dev/null || true
pass 'remote advance race fails closed without recreating or deleting local state'

sid=remote-delete
make_scaffold "$sid"
remote_old="$(remote_oid "$sid")"
remote_signal="$TMP/remote-delete-signal"
cat > "$REMOTE/hooks/pre-receive" <<HOOK
#!/bin/sh
read old new ref
if [ "\$ref" = "refs/heads/ai/$sid" ]; then
  touch "$remote_signal"
  exit 1
fi
exit 0
HOOK
chmod +x "$REMOTE/hooks/pre-receive"
(while [ ! -f "$remote_signal" ]; do sleep 0.01; done; while ! git --git-dir="$REMOTE" update-ref -d "refs/heads/ai/$sid" "$remote_old" 2>/dev/null; do sleep 0.01; done) &
racer_pid=$!
expect_failure 'preserve remote deletion race' "$sid" --empty-only --confirm-orphan "$sid"
wait "$racer_pid"
assert_ref_absent "$REMOTE" "refs/heads/ai/$sid"
assert_ref_exists "$DATA" "refs/heads/ai/$sid"
clean_case "$sid"
pass 'remote deletion race reports partial and preserves local state without recreation'

sid=server-reject
make_scaffold "$sid"
cat > "$REMOTE/hooks/pre-receive" <<HOOK
#!/bin/sh
read old new ref
if [ "\$ref" = "refs/heads/ai/$sid" ]; then echo 'deterministic rejection' >&2; exit 1; fi
exit 0
HOOK
chmod +x "$REMOTE/hooks/pre-receive"
expect_failure 'preserve server rejection' "$sid" --empty-only --confirm-orphan "$sid"
assert_ref_exists "$REMOTE" "refs/heads/ai/$sid"
assert_ref_exists "$DATA" "refs/heads/ai/$sid"
clean_case "$sid"
pass 'server rejection preserves the remote branch and local state'

sid=worktree-race
make_scaffold "$sid"
race_wt="$TMP/race-worktree-$sid"
cat > "$REMOTE/hooks/pre-receive" <<HOOK
#!/bin/sh
read old new ref
if [ "\$ref" = "refs/heads/ai/$sid" ]; then
  unset GIT_DIR
  git -C "$DATA" worktree add -q "$race_wt" "ai/$sid" || exit 1
fi
exit 0
HOOK
chmod +x "$REMOTE/hooks/pre-receive"
expect_failure 'detect worktree appearance during delete' "$sid" --empty-only --confirm-orphan "$sid"
assert_contains "$LAST_OUTPUT" 'PARTIAL' 'worktree-race partial result'
assert_ref_absent "$REMOTE" "refs/heads/ai/$sid"
git -C "$DATA" worktree list --porcelain | grep -Fqx "branch refs/heads/ai/$sid" || fail 'worktree race was not registered'
git -C "$DATA" worktree remove --force "$race_wt"; clean_case "$sid"
pass 'worktree appearance after the pre-delete recheck produces PARTIAL'

sid=cas-race
make_scaffold "$sid"
cas_writer="$TMP/cas-writer-$sid"
git -C "$DATA" worktree add -q "$cas_writer" -b "cas-writer-$sid" origin/main
printf 'alternate local ref\n' > "$cas_writer/cas.txt"
git -C "$cas_writer" add cas.txt
git -C "$cas_writer" commit -q -m 'alternate local ref'
CAS_OID="$(git -C "$cas_writer" rev-parse HEAD)"
git -C "$DATA" worktree remove --force "$cas_writer"
git -C "$DATA" branch -D "cas-writer-$sid" >/dev/null
CAS_REMOTE_OID="$(remote_oid "$sid")"
REAL_GIT="$(command -v git)"
WRAPPER="$TMP/git-wrapper"
cat > "$WRAPPER" <<HOOK
#!/bin/sh
case "\$*" in
  *"update-ref -d refs/heads/ai/$sid $CAS_REMOTE_OID"*)
    "$REAL_GIT" -C "$DATA" update-ref refs/heads/ai/$sid "$CAS_OID" "$CAS_REMOTE_OID"
    ;;
esac
exec "$REAL_GIT" "\$@"
HOOK
chmod +x "$WRAPPER"
old_path="$PATH"; PATH="$TMP:$PATH"; cp "$WRAPPER" "$TMP/git"; expect_failure 'detect exact-OID cleanup CAS race' "$sid" --empty-only --confirm-orphan "$sid"; PATH="$old_path"
assert_contains "$LAST_OUTPUT" 'PARTIAL' 'CAS-race partial result'
assert_ref_absent "$REMOTE" "refs/heads/ai/$sid"
assert_ref_exists "$DATA" "refs/heads/ai/$sid"
clean_case "$sid"
pass 'local cleanup uses exact-OID CAS and reports PARTIAL on a cleanup race'

echo 'All abandon-orphan-worktree tests passed.'
