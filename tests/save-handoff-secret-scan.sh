#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AIMS="$ROOT/bin/aims"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/aims-secret-commands.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
REMOTE="$TMP/origin.git"; DATA="$TMP/data"
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME"
git init --bare -q --initial-branch=main "$REMOTE"
git clone -q "$REMOTE" "$DATA"
git -C "$DATA" config user.name 'AIMS Test'; git -C "$DATA" config user.email 'aims-test@example.invalid'
printf '# Secret command regression\n' > "$DATA/README.md"; printf '# Sessions\n' > "$DATA/SESSIONS.md"
git -C "$DATA" add .; git -C "$DATA" commit -qm init; git -C "$DATA" push -q -u origin main
start_output="$(cd "$DATA" && AIMS_HOME="$DATA" "$AIMS" start security secret-scan hermes --scope path:test)"
sid="$(printf '%s\n' "$start_output" | sed -n 's/^SESSION_ID=//p')"; wt="$DATA/.worktrees/$sid"; branch="ai/$sid"
make_secret() { printf 'ghp_%s\n' 'A1b2C3d4E5f6G7h8I9j0K1l2'; }
assert_unchanged() {
  label="$1"; head_before="$2"; remote_before="$3"; meta_before="$4"; worklog_before="$5"; index_before="$6"; refs_before="$7"
  [ "$(git -C "$wt" rev-parse HEAD)" = "$head_before" ] || { echo "FAIL: $label changed HEAD" >&2; exit 1; }
  [ "$(git --git-dir="$REMOTE" rev-parse "refs/heads/$branch")" = "$remote_before" ] || { echo "FAIL: $label changed remote" >&2; exit 1; }
  [ "$(git -C "$wt" hash-object "sessions/work/$sid/metadata.json")" = "$meta_before" ] || { echo "FAIL: $label changed metadata" >&2; exit 1; }
  [ "$(git -C "$wt" hash-object "sessions/work/$sid/worklog.md")" = "$worklog_before" ] || { echo "FAIL: $label changed worklog" >&2; exit 1; }
  [ "$(git -C "$wt" ls-files --stage | cksum)" = "$index_before" ] || { echo "FAIL: $label changed the index" >&2; exit 1; }
  [ "$(git -C "$wt" for-each-ref --format='%(refname) %(objectname)' | cksum)" = "$refs_before" ] || { echo "FAIL: $label changed local refs" >&2; exit 1; }
}
head_before="$(git -C "$wt" rev-parse HEAD)"; remote_before="$(git --git-dir="$REMOTE" rev-parse "refs/heads/$branch")"
meta_before="$(git -C "$wt" hash-object "sessions/work/$sid/metadata.json")"; worklog_before="$(git -C "$wt" hash-object "sessions/work/$sid/worklog.md")"
index_before="$(git -C "$wt" ls-files --stage | cksum)"; refs_before="$(git -C "$wt" for-each-ref --format='%(refname) %(objectname)' | cksum)"
make_secret > "$wt/untracked-secret.txt"
set +e; (cd "$wt" && AIMS_HOME="$DATA" "$AIMS" save >/dev/null 2>&1); save_status=$?; set -e
[ "$save_status" -ne 0 ] || { echo 'FAIL: save accepted an untracked secret' >&2; exit 1; }
assert_unchanged save "$head_before" "$remote_before" "$meta_before" "$worklog_before" "$index_before" "$refs_before"
git -C "$wt" ls-files --error-unmatch untracked-secret.txt >/dev/null 2>&1 && { echo 'FAIL: save staged the secret' >&2; exit 1; } || true
rm "$wt/untracked-secret.txt"; printf 'safe payload\n' > "$wt/payload.txt"
(cd "$wt" && AIMS_HOME="$DATA" "$AIMS" save >/dev/null)
head_before="$(git -C "$wt" rev-parse HEAD)"; remote_before="$(git --git-dir="$REMOTE" rev-parse "refs/heads/$branch")"
meta_before="$(git -C "$wt" hash-object "sessions/work/$sid/metadata.json")"; worklog_before="$(git -C "$wt" hash-object "sessions/work/$sid/worklog.md")"
index_before="$(git -C "$wt" ls-files --stage | cksum)"; refs_before="$(git -C "$wt" for-each-ref --format='%(refname) %(objectname)' | cksum)"
make_secret > "$wt/untracked-secret.txt"
set +e; (cd "$wt" && AIMS_HOME="$DATA" "$AIMS" handoff >/dev/null 2>&1); handoff_status=$?; set -e
[ "$handoff_status" -ne 0 ] || { echo 'FAIL: handoff accepted an untracked secret' >&2; exit 1; }
assert_unchanged handoff "$head_before" "$remote_before" "$meta_before" "$worklog_before" "$index_before" "$refs_before"
git -C "$wt" ls-files --error-unmatch untracked-secret.txt >/dev/null 2>&1 && { echo 'FAIL: handoff staged the secret' >&2; exit 1; } || true
echo 'PASS: save and handoff reject untracked secrets before mutation or push'
