#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/aims-rebase-safe-save.XXXXXX")"
REMOTE="$TMP/remote.git"
SEED="$TMP/seed"
CLONE_A="$TMP/clone-a"
CLONE_B="$TMP/clone-b"
HOOKS_A="$TMP/hooks-a"
HOOKS_B="$TMP/hooks-b"
export HOME="$TMP/home"
export GNUPGHOME="$TMP/gnupg"
export GIT_CONFIG_NOSYSTEM=1
export GIT_TERMINAL_PROMPT=0
export GIT_EDITOR=true
export GIT_SEQUENCE_EDITOR=true
export GIT_PAGER=cat
unset GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_SSH_COMMAND
mkdir -p "$HOME" "$GNUPGHOME" "$HOOKS_A" "$HOOKS_B"
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
AIMS="$ROOT/bin/aims"
[ -x "$AIMS" ] || fail "checkout dispatcher missing: $AIMS"

pass() { echo "PASS: $*"; }
assert_contains() { case "$1" in *"$2"*) ;; *) fail "$3 (missing: $2)";; esac; }
assert_ref_exists() { git -C "$1" show-ref --verify --quiet "$2" || fail "missing ref $2"; }
assert_ref_absent() { git -C "$1" show-ref --verify --quiet "$2" && fail "unexpected ref $2" || true; }
configure_repo() {
  repo="$1"; hooks="$2"
  git -C "$repo" config core.hooksPath "$hooks"
  git -C "$repo" config commit.gpgSign false
  git -C "$repo" config tag.gpgSign false
  git -C "$repo" config push.gpgSign false
}
expect_success() {
  label="$1"; shift
  if ! output="$("$@" 2>&1)"; then
    echo "$output" >&2
    fail "$label"
  fi
  LAST_OUTPUT="$output"
}
expect_failure() {
  label="$1"; shift
  if output="$("$@" 2>&1)"; then
    echo "$output" >&2
    fail "$label unexpectedly succeeded"
  fi
  LAST_OUTPUT="$output"
}

setup_repositories() {
  git init -q --bare "$REMOTE"
  mkdir -p "$SEED"
  git -C "$SEED" init -q
  git -C "$SEED" config user.name "AIMS Test"
  git -C "$SEED" config user.email "aims-test@example.invalid"
  configure_repo "$SEED" "$HOOKS_A"
  printf 'base\n' > "$SEED/base.txt"
  git -C "$SEED" add base.txt
  git -C "$SEED" commit -q -m 'base'
  git -C "$SEED" branch -M main
  git -C "$SEED" remote add origin "$REMOTE"
  git -C "$SEED" push -q -u origin main
  git -C "$REMOTE" symbolic-ref HEAD refs/heads/main
  git clone -q "$REMOTE" "$CLONE_A"
  git clone -q "$REMOTE" "$CLONE_B"
  git -C "$CLONE_A" config user.name "AIMS Test A"
  git -C "$CLONE_A" config user.email "aims-test-a@example.invalid"
  configure_repo "$CLONE_A" "$HOOKS_A"
  git -C "$CLONE_B" config user.name "AIMS Test B"
  git -C "$CLONE_B" config user.email "aims-test-b@example.invalid"
  configure_repo "$CLONE_B" "$HOOKS_B"
}

test_sha256_initial_lease() {
  sha_remote="$TMP/sha256-remote.git"; sha_data="$TMP/sha256-data"
  if ! git init -q --bare --object-format=sha256 "$sha_remote" 2>/dev/null; then
    echo "SKIP: installed Git does not support SHA-256 repositories"
    return
  fi
  git clone -q "$sha_remote" "$sha_data"
  git -C "$sha_data" config user.name "AIMS SHA-256 Test"
  git -C "$sha_data" config user.email "aims-sha256@example.invalid"
  printf '# SHA-256 test\n' > "$sha_data/README.md"
  git -C "$sha_data" add README.md
  git -C "$sha_data" commit -q -m 'initialize SHA-256 main'
  git -C "$sha_data" branch -M main
  git -C "$sha_data" push -q -u origin main
  git -C "$sha_remote" symbolic-ref HEAD refs/heads/main
  expect_success "SHA-256 initial session lease" env AIMS_HOME="$sha_data" "$AIMS" start sha256 initial-lease test-agent
  git -C "$sha_remote" for-each-ref --format='%(refname)' refs/heads/ai/ | grep -q '^refs/heads/ai/' || fail "SHA-256 start did not create a remote session branch"
  pass "initial creation uses the repository object format for the zero-OID lease"
}

make_session() {
  sid="$1"
  git -C "$CLONE_A" fetch -q origin
  git -C "$CLONE_A" worktree add -q "$CLONE_A/.worktrees/$sid" -b "ai/$sid" origin/main
}

session_worktree() { printf '%s\n' "$CLONE_A/.worktrees/$1"; }
session_branch() { printf 'ai/%s\n' "$1"; }
save_session() {
  sid="$1"; wt="$(session_worktree "$sid")"
  (cd "$wt" && AIMS_HOME="$CLONE_A" "$AIMS" save)
}
rebase_session() {
  sid="$1"
  (cd "$CLONE_A" && AIMS_HOME="$CLONE_A" "$AIMS" rebase "$sid")
}
start_session() {
  project="$1"; topic="$2"
  (cd "$CLONE_A" && AIMS_HOME="$CLONE_A" "$AIMS" start "$project" "$topic" test-agent)
}
handoff_session() {
  sid="$1"; wt="$(session_worktree "$sid")"
  (cd "$wt" && AIMS_HOME="$CLONE_A" "$AIMS" handoff lifecycle-test)
}
adopt_session() {
  sid="$1"
  (cd "$CLONE_B" && AIMS_HOME="$CLONE_B" "$AIMS" adopt "$sid")
}
adopt_remote_session() {
  sid="$1"
  (cd "$CLONE_B" && AIMS_HOME="$CLONE_B" "$AIMS" adopt "$sid" --remote)
}
session_id_from_output() {
  printf '%s\n' "$1" | while IFS='=' read -r key value; do
    if [ "$key" = SESSION_ID ]; then printf '%s\n' "$value"; break; fi
  done
}
install_delete_push_hook() {
  hook_dir="$1"; sid="$2"
  cat > "$hook_dir/pre-push" <<HOOK
#!/bin/sh
while read local_ref local_oid remote_ref remote_oid; do
  if [ "\$remote_ref" = "refs/heads/ai/$sid" ]; then
    git --git-dir="$REMOTE" update-ref -d "\$remote_ref"
  fi
done
exit 0
HOOK
  chmod +x "$hook_dir/pre-push"
}
advance_main() {
  sid="$1"; file="$2"; text="$3"
  git -C "$CLONE_B" fetch -q origin main
  printf '%s\n' "$text" > "$CLONE_B/$file"
  git -C "$CLONE_B" add "$file"
  git -C "$CLONE_B" commit -q -m "main $sid"
  git -C "$CLONE_B" push -q origin main
}
advance_session_from_writer() {
  sid="$1"; file="$2"; text="$3"
  branch="$(session_branch "$sid")"
  writer="$CLONE_B/.worktrees/writer-$sid"
  git -C "$CLONE_B" fetch -q origin "$branch"
  git -C "$CLONE_B" worktree add -q "$writer" -b "writer-$sid" "origin/$branch"
  printf '%s\n' "$text" > "$writer/$file"
  git -C "$writer" add "$file"
  git -C "$writer" commit -q -m "competing writer $sid"
  git -C "$writer" push -q origin "writer-$sid:refs/heads/$branch"
}

setup_repositories
test_sha256_initial_lease

main_oid="$(git -C "$REMOTE" rev-parse refs/heads/main)"
cat > "$HOOKS_A/pre-push" <<HOOK
#!/bin/sh
while read local_ref local_oid remote_ref remote_oid; do
  case "\$remote_ref" in
    refs/heads/ai/*) git --git-dir="$REMOTE" update-ref "\$remote_ref" "$main_oid" ;;
  esac
done
exit 0
HOOK
chmod +x "$HOOKS_A/pre-push"
expect_failure "start initial creation race" start_session lifecycle-project initial-race
start_race_ref="$(git --git-dir="$REMOTE" for-each-ref --format='%(refname)' refs/heads/ai/ | tr -d '\n')"
[ -n "$start_race_ref" ] || fail "start initial race did not create the competing remote ref"
rm -f "$HOOKS_A/pre-push"
pass "start initial creation is protected by the zero-OID lease"

sid="save-initial-race"
make_session "$sid"
printf 'initial race\n' > "$(session_worktree "$sid")/initial-race.txt"
cat > "$HOOKS_A/pre-push" <<HOOK
#!/bin/sh
while read local_ref local_oid remote_ref remote_oid; do
  case "\$remote_ref" in
    refs/heads/ai/*) git --git-dir="$REMOTE" update-ref "\$remote_ref" "$main_oid" ;;
  esac
done
exit 0
HOOK
chmod +x "$HOOKS_A/pre-push"
expect_failure "save initial creation race" save_session "$sid"
rm -f "$HOOKS_A/pre-push"
race_remote_oid="$(git -C "$REMOTE" rev-parse "refs/heads/ai/$sid")"
[ "$race_remote_oid" = "$main_oid" ] || fail "save initial race overwrote competitor"
pass "save initial creation is protected by the zero-OID lease"

expect_success "aims start sentinel" start_session lifecycle-project lifecycle-start
sid="$(session_id_from_output "$LAST_OUTPUT")"
[ -n "$sid" ] || fail "could not parse session id from installed aims start"
assert_ref_exists "$CLONE_A" "refs/aims/published/$sid"
assert_ref_exists "$CLONE_A" "refs/remotes/origin/ai/$sid"
expect_success "aims handoff sentinel" handoff_session "$sid"
assert_ref_exists "$CLONE_A" "refs/aims/published/$sid"
expect_success "aims adopt sentinel" adopt_session "$sid"
assert_ref_exists "$CLONE_B" "refs/aims/published/$sid"
pass "start, handoff, and adopt seed the publication sentinel"

expect_success "aims start remote-report-only" start_session lifecycle-project remote-report-only
sid="$(session_id_from_output "$LAST_OUTPUT")"
expect_success "aims handoff remote-report-only" handoff_session "$sid"
git -C "$CLONE_B" update-ref -d "refs/aims/published/$sid"
expect_success "aims adopt remote report only" adopt_remote_session "$sid"
assert_ref_absent "$CLONE_B" "refs/aims/published/$sid"
[ ! -d "$CLONE_B/.worktrees/$sid" ] || fail "adopt --remote created a local worktree"
pass "adopt --remote leaves local worktrees and publication sentinels unchanged"

expect_success "aims start adopt-stale-local" start_session lifecycle-project adopt-stale-local
sid="$(session_id_from_output "$LAST_OUTPUT")"
expect_success "aims handoff adopt-stale-local" handoff_session "$sid"
git -C "$CLONE_B" fetch -q origin "ai/$sid"
git -C "$CLONE_B" branch "ai/$sid" origin/main
stale_head="$(git -C "$CLONE_B" rev-parse "refs/heads/ai/$sid")"
expect_failure "adopt stale local ai branch" adopt_session "$sid"
assert_contains "$LAST_OUTPUT" "is not an ancestor" "stale local branch guidance"
[ ! -d "$CLONE_B/.worktrees/$sid" ] || fail "adopt created a worktree before stale branch refusal"
[ "$stale_head" = "$(git -C "$CLONE_B" rev-parse "refs/heads/ai/$sid")" ] || fail "adopt changed stale local branch"
pass "adopt rejects a stale local ai branch before creating a worktree"

expect_success "aims start adopt-wrong-worktree" start_session lifecycle-project adopt-wrong-worktree
sid="$(session_id_from_output "$LAST_OUTPUT")"
expect_success "aims handoff adopt-wrong-worktree" handoff_session "$sid"
wrong_wt="$CLONE_B/.worktrees/$sid"
git -C "$CLONE_B" fetch -q origin "ai/$sid"
git -C "$CLONE_B" worktree add -q "$wrong_wt" -b "wrong-$sid" "origin/ai/$sid"
expect_failure "adopt wrong worktree branch" adopt_session "$sid"
assert_contains "$LAST_OUTPUT" "expected ai/$sid" "wrong worktree branch guidance"
[ "$(git -C "$wrong_wt" branch --show-current)" = "wrong-$sid" ] || fail "adopt changed wrong worktree branch"
pass "adopt rejects an existing worktree on the wrong branch"

expect_success "aims start handoff pre-fetch race" start_session lifecycle-project handoff-prefetch-race
sid="$(session_id_from_output "$LAST_OUTPUT")"
expect_success "aims handoff pre-fetch setup" handoff_session "$sid"
handoff_pre_head="$(git -C "$(session_worktree "$sid")" rev-parse HEAD)"
advance_session_from_writer "$sid" handoff-prefetch-race.txt "competing writer"
expect_failure "handoff pre-fetch divergence" handoff_session "$sid"
assert_contains "$LAST_OUTPUT" "is not an ancestor" "handoff pre-fetch divergence guidance"
[ "$handoff_pre_head" = "$(git -C "$(session_worktree "$sid")" rev-parse HEAD)" ] || fail "handoff committed before divergence refusal"
pass "handoff refuses pre-existing remote divergence before checkpointing"

expect_success "aims start adopt pre-fetch race" start_session lifecycle-project adopt-prefetch-race
sid="$(session_id_from_output "$LAST_OUTPUT")"
expect_success "aims handoff adopt pre-fetch setup" handoff_session "$sid"
pre_wt="$CLONE_B/.worktrees/$sid"
git -C "$CLONE_B" fetch -q origin "ai/$sid"
git -C "$CLONE_B" worktree add -q "$pre_wt" -b "ai/$sid" "origin/ai/$sid"
printf 'local adopt work\n' > "$pre_wt/adopt-prefetch-local.txt"
git -C "$pre_wt" add adopt-prefetch-local.txt
git -C "$pre_wt" commit -q -m "local adopt work"
pre_head="$(git -C "$pre_wt" rev-parse HEAD)"
advance_session_from_writer "$sid" adopt-prefetch-race.txt "competing writer"
expect_failure "adopt pre-fetch divergence" adopt_session "$sid"
assert_contains "$LAST_OUTPUT" "is not an ancestor" "adopt pre-fetch divergence guidance"
[ "$pre_head" = "$(git -C "$pre_wt" rev-parse HEAD)" ] || fail "adopt changed divergent worktree before refusal"
pass "adopt refuses pre-existing remote divergence before checkpointing"

sid="save-delete-during-push"
make_session "$sid"
printf 'published\n' > "$(session_worktree "$sid")/save-delete.txt"
expect_success "save deletion setup" save_session "$sid"
printf 'local update\n' > "$(session_worktree "$sid")/save-delete.txt"
install_delete_push_hook "$HOOKS_A" "$sid"
expect_failure "save deletion during push" save_session "$sid"
rm -f "$HOOKS_A/pre-push"
git --git-dir="$REMOTE" show-ref --verify --quiet "refs/heads/ai/$sid" && fail "save recreated branch after deletion race" || true
assert_ref_exists "$CLONE_A" "refs/aims/published/$sid"
pass "save uses an exact observed-OID lease during updates"

expect_success "aims start handoff-delete" start_session lifecycle-project handoff-delete
sid="$(session_id_from_output "$LAST_OUTPUT")"
install_delete_push_hook "$HOOKS_A" "$sid"
expect_failure "handoff deletion during push" handoff_session "$sid"
rm -f "$HOOKS_A/pre-push"
git --git-dir="$REMOTE" show-ref --verify --quiet "refs/heads/ai/$sid" && fail "handoff recreated branch after deletion race" || true
assert_ref_exists "$CLONE_A" "refs/aims/published/$sid"
pass "handoff uses an exact observed-OID lease during updates"

expect_success "aims start legacy handoff deletion" start_session lifecycle-project legacy-handoff-deletion
sid="$(session_id_from_output "$LAST_OUTPUT")"
assert_ref_exists "$CLONE_A" "refs/remotes/origin/ai/$sid"
git -C "$CLONE_A" update-ref -d "refs/aims/published/$sid"
git --git-dir="$REMOTE" update-ref -d "refs/heads/ai/$sid"
expect_failure "legacy handoff deleted before fetch" handoff_session "$sid"
assert_contains "$LAST_OUTPUT" "disappeared after prior publication" "legacy handoff deletion guidance"
git --git-dir="$REMOTE" show-ref --verify --quiet "refs/heads/ai/$sid" && fail "legacy handoff recreated a deleted branch" || true
pass "handoff does not recreate a deleted legacy branch after tracking-ref prune"

expect_success "aims start adopt-delete" start_session lifecycle-project adopt-delete
sid="$(session_id_from_output "$LAST_OUTPUT")"
expect_success "aims handoff adopt-delete" handoff_session "$sid"
install_delete_push_hook "$HOOKS_B" "$sid"
expect_failure "adopt deletion during push" adopt_session "$sid"
rm -f "$HOOKS_B/pre-push"
git --git-dir="$REMOTE" show-ref --verify --quiet "refs/heads/ai/$sid" && fail "adopt recreated branch after deletion race" || true
assert_ref_exists "$CLONE_B" "refs/aims/published/$sid"
[ -d "$CLONE_B/.worktrees/$sid" ] || fail "adopt removed worktree after deletion race"
pass "adopt uses an exact observed-OID lease during updates"

expect_success "aims start adopt-race sentinel" start_session lifecycle-project adopt-race
sid="$(session_id_from_output "$LAST_OUTPUT")"
expect_success "aims handoff adopt-race" handoff_session "$sid"
race_wt="$CLONE_A/.worktrees/race-$sid"
git -C "$CLONE_A" fetch -q origin "ai/$sid"
git -C "$CLONE_A" worktree add -q "$race_wt" -b "race-$sid" "origin/ai/$sid"
printf 'competing writer\n' > "$race_wt/adopt-race.txt"
git -C "$race_wt" add adopt-race.txt
git -C "$race_wt" commit -q -m "adoption competing writer"
race_oid="$(git -C "$race_wt" rev-parse HEAD)"
race_signal="$TMP/adopt-race-signal"
race_done="$TMP/adopt-race-done"
cat > "$REMOTE/hooks/pre-receive" <<HOOK
#!/bin/sh
read old new ref
if [ "\$ref" = "refs/heads/ai/$sid" ]; then
  if [ ! -f "$race_done" ]; then
    touch "$race_done"
    touch "$race_signal"
    sleep 1
    echo "simulated adoption race" >&2
    exit 1
  fi
fi
exit 0
HOOK
chmod +x "$REMOTE/hooks/pre-receive"
remote_tip_before="$(git -C "$REMOTE" rev-parse "refs/heads/ai/$sid")"
(
  while [ ! -f "$race_signal" ]; do sleep 0.05; done
  git -C "$race_wt" push -q origin "race-$sid:refs/heads/ai/$sid"
) > "$TMP/adopt-race-push.log" 2>&1 &
racer_pid=$!
expect_failure "adopt competing-writer push" adopt_session "$sid"
if ! wait "$racer_pid"; then
  read -r race_error < "$TMP/adopt-race-push.log" || race_error="unknown race push failure"
  fail "competing writer push failed: $race_error"
fi
assert_contains "$LAST_OUTPUT" "checkpoint push failed" "adopt push failure guidance"
[ -d "$CLONE_B/.worktrees/$sid" ] || fail "adopt removed worktree after push failure"
remote_tip_after="$(git -C "$REMOTE" rev-parse "refs/heads/ai/$sid")"
[ "$remote_tip_before" != "$remote_tip_after" ] || fail "adopt race did not advance remote branch"
[ "$remote_tip_after" = "$race_oid" ] || fail "adopt race wrote unexpected remote tip"
assert_ref_exists "$CLONE_B" "refs/aims/published/$sid"
rm -f "$REMOTE/hooks/pre-receive"
git -C "$CLONE_A" worktree remove --force "$race_wt"
pass "adopt push race is fatal and retains the worktree"

sid="normal-save"
make_session "$sid"
printf 'normal\n' > "$(session_worktree "$sid")/normal.txt"
expect_success "normal save" save_session "$sid"
assert_ref_exists "$CLONE_A" "refs/remotes/origin/ai/$sid"
expect_success "normal save no-op" save_session "$sid"
expect_success "rebase session-id form no-op" rebase_session "$sid"
assert_ref_absent "$CLONE_A" "refs/aims/rewrite/$sid"
expect_success "rebase ai/session-id form no-op" rebase_session "ai/$sid"
pass "normal save and both rebase argument forms"

sid="managed-rewrite"
make_session "$sid"
printf 'session\n' > "$(session_worktree "$sid")/session.txt"
expect_success "save before managed rewrite" save_session "$sid"
git -C "$CLONE_A" update-ref -d "refs/aims/published/$sid"
advance_main "$sid" main-managed.txt "main change"
expect_success "managed rebase" rebase_session "$sid"
assert_ref_exists "$CLONE_A" "refs/aims/published/$sid"
assert_ref_exists "$CLONE_A" "refs/aims/rewrite/$sid"
expect_success "save managed rewrite" save_session "$sid"
assert_ref_absent "$CLONE_A" "refs/aims/rewrite/$sid"
pass "managed rewrite succeeds with an exact lease"

sid="rebase-conflict"
make_session "$sid"
printf 'session version\n' > "$(session_worktree "$sid")/conflict.txt"
expect_success "save conflict setup" save_session "$sid"
advance_main "$sid" conflict.txt "main version"
expect_failure "rebase conflict" rebase_session "$sid"
assert_contains "$LAST_OUTPUT" "rewrite marker retained" "rebase conflict guidance"
assert_ref_exists "$CLONE_A" "refs/aims/rewrite/$sid"
expect_failure "save during active rebase" save_session "$sid"
assert_contains "$LAST_OUTPUT" "active rebase/merge operation" "save during rebase guidance"
printf 'resolved version\n' > "$(session_worktree "$sid")/conflict.txt"
git -C "$(session_worktree "$sid")" add conflict.txt
GIT_EDITOR=true git -C "$(session_worktree "$sid")" rebase --continue >/dev/null 2>&1
expect_success "save after rebase continue" save_session "$sid"
assert_ref_absent "$CLONE_A" "refs/aims/rewrite/$sid"
pass "rebase conflict, continue, and checkpoint"

sid="rebase-abort"
make_session "$sid"
printf 'session version\n' > "$(session_worktree "$sid")/abort.txt"
expect_success "save abort setup" save_session "$sid"
advance_main "$sid" abort.txt "main version"
expect_failure "abort conflict" rebase_session "$sid"
git -C "$(session_worktree "$sid")" rebase --abort
expect_success "save after rebase abort" save_session "$sid"
assert_ref_absent "$CLONE_A" "refs/aims/rewrite/$sid"
pass "rebase abort clears an unchanged rewrite marker"

sid="competing-writer"
make_session "$sid"
printf 'session\n' > "$(session_worktree "$sid")/competing.txt"
expect_success "save competing setup" save_session "$sid"
advance_main "$sid" main-competing.txt "main change"
expect_success "rebase competing setup" rebase_session "$sid"
advance_session_from_writer "$sid" competing-writer.txt "writer change"
git -C "$(session_worktree "$sid")" fetch -q origin
expect_failure "competing writer refusal after background fetch" save_session "$sid"
assert_contains "$LAST_OUTPUT" "advanced after the rewrite marker" "competing writer guidance"
assert_ref_exists "$CLONE_A" "refs/aims/rewrite/$sid"
pass "competing writer is preserved after a background fetch"

sid="unmarked-divergence"
make_session "$sid"
printf 'session\n' > "$(session_worktree "$sid")/unmarked.txt"
expect_success "save unmarked setup" save_session "$sid"
git -C "$CLONE_A" update-ref -d "refs/aims/published/$sid"
advance_session_from_writer "$sid" unmarked-writer.txt "writer change"
printf 'local\n' > "$(session_worktree "$sid")/unmarked-local.txt"
expect_failure "unmarked divergence refusal" save_session "$sid"
assert_contains "$LAST_OUTPUT" "without an AIMS rewrite marker" "unmarked divergence guidance"
assert_ref_exists "$CLONE_A" "refs/aims/published/$sid"
pass "legacy unmarked divergence is refused and observed publication is marked"

sid="local-behind"
make_session "$sid"
printf 'session\n' > "$(session_worktree "$sid")/behind.txt"
expect_success "save local-behind setup" save_session "$sid"
git -C "$CLONE_A" update-ref -d "refs/aims/published/$sid"
advance_session_from_writer "$sid" behind-writer.txt "writer change"
expect_failure "local behind refusal" save_session "$sid"
branch="$(session_branch "$sid")"
assert_contains "$LAST_OUTPUT" "behind origin/$branch" "local-behind guidance"
assert_ref_exists "$CLONE_A" "refs/aims/published/$sid"
pass "legacy local-behind branch is refused and observed publication is marked"

sid="remote-deletion"
make_session "$sid"
printf 'session\n' > "$(session_worktree "$sid")/deleted.txt"
expect_success "save deletion setup" save_session "$sid"
assert_ref_exists "$CLONE_A" "refs/aims/published/$sid"
advance_main "$sid" main-deleted.txt "main change"
expect_success "rebase deletion setup" rebase_session "$sid"
git -C "$CLONE_B" push -q origin --delete "ai/$sid"
git -C "$CLONE_A" fetch -q --prune origin
expect_failure "deleted remote refusal" save_session "$sid"
assert_contains "$LAST_OUTPUT" "disappeared" "deleted remote guidance"
assert_ref_exists "$CLONE_A" "refs/aims/rewrite/$sid"
assert_ref_exists "$CLONE_A" "refs/aims/published/$sid"
pass "deleted remote branch is not recreated after tracking-ref prune"

sid="pre-rebase-hook"
make_session "$sid"
printf 'session\n' > "$(session_worktree "$sid")/hook.txt"
expect_success "save pre-rebase-hook setup" save_session "$sid"
advance_main "$sid" main-hook.txt "main change"
cat > "$HOOKS_A/pre-rebase" <<'HOOK'
#!/bin/sh
echo "simulated pre-rebase startup failure" >&2
exit 1
HOOK
chmod +x "$HOOKS_A/pre-rebase"
expect_failure "pre-rebase hook failure" rebase_session "$sid"
assert_contains "$LAST_OUTPUT" "HEAD is unchanged" "pre-rebase hook guidance"
assert_ref_absent "$CLONE_A" "refs/aims/rewrite/$sid"
test_head="$(git -C "$(session_worktree "$sid")" rev-parse HEAD)"
remote_head="$(git -C "$(session_worktree "$sid")" rev-parse "refs/remotes/origin/ai/$sid")"
[ "$test_head" = "$remote_head" ] || fail "pre-rebase hook changed HEAD"
rm -f "$HOOKS_A/pre-rebase"
expect_success "save after pre-rebase hook failure" save_session "$sid"
pass "non-resumable startup failure clears the marker with CAS"

sid="fetch-failure"
make_session "$sid"
printf 'session\n' > "$(session_worktree "$sid")/fetch.txt"
expect_success "save fetch setup" save_session "$sid"
UPLOAD_COUNT="$TMP/upload-pack-count"
UPLOAD_PACK="$TMP/fail-second-upload-pack"
cat > "$UPLOAD_PACK" <<HOOK
#!/bin/sh
count=0
if [ -f "$UPLOAD_COUNT" ]; then IFS= read -r count < "$UPLOAD_COUNT"; fi
count=\$((count + 1))
printf '%s\n' "\$count" > "$UPLOAD_COUNT"
if [ "\$count" -ne 1 ]; then echo "simulated origin/main fetch failure" >&2; exit 1; fi
exec git-upload-pack "\$1"
HOOK
chmod +x "$UPLOAD_PACK"
git -C "$CLONE_A" config remote.origin.uploadpack "$UPLOAD_PACK"
expect_failure "main fetch failure" rebase_session "$sid"
assert_contains "$LAST_OUTPUT" "origin/main fetch failed" "main fetch failure guidance"
assert_ref_exists "$CLONE_A" "refs/aims/rewrite/$sid"
git -C "$CLONE_A" config --unset remote.origin.uploadpack
expect_success "save after main fetch failure" save_session "$sid"
assert_ref_absent "$CLONE_A" "refs/aims/rewrite/$sid"
git -C "$CLONE_A" remote set-url origin "$TMP/missing-remote.git"
expect_failure "rebase fetch failure" rebase_session "$sid"
assert_ref_absent "$CLONE_A" "refs/aims/rewrite/$sid"
git -C "$CLONE_A" remote set-url origin "$REMOTE"
printf 'local after fetch failure\n' > "$(session_worktree "$sid")/fetch-local.txt"
git -C "$CLONE_A" remote set-url origin "$TMP/missing-remote.git"
expect_failure "save fetch failure" save_session "$sid"
git -C "$CLONE_A" remote set-url origin "$REMOTE"
pass "fetch failures do not create or consume rewrite markers"

sid="existing-marker"
make_session "$sid"
printf 'session\n' > "$(session_worktree "$sid")/marker.txt"
expect_success "save marker setup" save_session "$sid"
marker_oid="$(git -C "$(session_worktree "$sid")" rev-parse HEAD)"
git -C "$CLONE_A" update-ref "refs/aims/rewrite/$sid" "$marker_oid"
expect_failure "existing marker refusal" rebase_session "$sid"
assert_contains "$LAST_OUTPUT" "rewrite marker already exists" "existing marker guidance"
git -C "$CLONE_A" update-ref -d "refs/aims/rewrite/$sid" "$marker_oid"
expect_failure "absent worktree refusal" rebase_session absent-worktree
assert_contains "$LAST_OUTPUT" "worktree not found" "absent worktree guidance"
pass "existing marker and absent worktree guardrails"

sid="force-reject"
make_session "$sid"
printf 'session version\n' > "$(session_worktree "$sid")/force-conflict.txt"
expect_success "save force rejection setup" save_session "$sid"
advance_main "$sid" force-conflict.txt "main version"
cat > "$REMOTE/hooks/update" <<'HOOK'
#!/bin/sh
case "$1" in
  refs/heads/ai/force-reject)
    case "$2" in
      0000000000000000000000000000000000000000) exit 0 ;;
    esac
    if git merge-base --is-ancestor "$2" "$3"; then exit 0; fi
    echo "force pushes are disabled for this branch" >&2
    exit 1
    ;;
esac
exit 0
HOOK
chmod +x "$REMOTE/hooks/update"
expect_failure "force rejection actual conflict" rebase_session "$sid"
assert_ref_exists "$CLONE_A" "refs/aims/rewrite/$sid"
printf 'unique actual conflict resolution\n' > "$(session_worktree "$sid")/force-conflict.txt"
git -C "$(session_worktree "$sid")" add force-conflict.txt
GIT_EDITOR=true git -C "$(session_worktree "$sid")" rebase --continue >/dev/null 2>&1
expect_failure "force rejection guidance" save_session "$sid"
assert_contains "$LAST_OUTPUT" "safe rewritten-session push was rejected" "force rejection guidance"
assert_contains "$LAST_OUTPUT" "refs/aims/recovery/$sid" "force rejection safe alternative"
recovery_ref="refs/aims/recovery/$sid"
git -C "$(session_worktree "$sid")" update-ref "$recovery_ref" HEAD
git -C "$(session_worktree "$sid")" fetch -q origin main
git -C "$(session_worktree "$sid")" reset --hard "refs/aims/rewrite/$sid" >/dev/null
if git -C "$(session_worktree "$sid")" merge --no-commit --no-ff origin/main >/dev/null 2>&1; then :; else :; fi
git -C "$(session_worktree "$sid")" checkout "$recovery_ref" -- .
git -C "$(session_worktree "$sid")" add -A
GIT_EDITOR=true git -C "$(session_worktree "$sid")" commit --no-edit -q
assert_ref_exists "$CLONE_A" "$recovery_ref"
expect_success "force rejection no-force recovery" save_session "$sid"
assert_ref_absent "$CLONE_A" "refs/aims/rewrite/$sid"
assert_ref_exists "$CLONE_A" "$recovery_ref"
git -C "$CLONE_A" update-ref -d "$recovery_ref"
assert_ref_absent "$CLONE_A" "$recovery_ref"
git -C "$CLONE_B" fetch -q origin "ai/$sid"
resolved_remote="$(git -C "$CLONE_B" show "origin/ai/$sid:force-conflict.txt")"
[ "$resolved_remote" = "unique actual conflict resolution" ] || fail "no-force recovery lost actual conflict resolution"
pass "force-push policy rejection preserves actual conflict work through recovery"

echo "All rebase-safe-save integration tests passed."
