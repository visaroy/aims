#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AIMS="$ROOT/bin/aims"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/aims-cli-contract.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
REMOTE="$TMP/origin.git"; DATA_A="$TMP/data-a"; DATA_B="$TMP/data-b"
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$XDG_CONFIG_HOME"
expect_status() {
  expected="$1"; label="$2"; shift 2
  set +e; "$@" >/dev/null 2>&1; actual=$?; set -e
  [ "$actual" -eq "$expected" ] || { echo "FAIL: $label returned $actual instead of $expected" >&2; exit 1; }
}
version="$(tr -d '\r\n' < "$ROOT/VERSION")"
for form in help -h --help; do "$AIMS" "$form" | grep -q 'AIMS — AI Multi-agent Sessions'; done
for form in version -v --version; do [ "$("$AIMS" "$form")" = "$version" ] || { echo "FAIL: $form output does not match VERSION" >&2; exit 1; }; done
for command in init start save handoff handoff-all checkpoint brief rebase adopt publish list artifacts doctor wire-agents install-hooks preflight version; do
  "$AIMS" help | grep -q "  $command" || { echo "FAIL: help omits public command $command" >&2; exit 1; }
done
expect_status 2 'unknown command' "$AIMS" unknown-command
expect_status 2 'help extra argument' "$AIMS" help extra
expect_status 2 'version extra argument' "$AIMS" version extra
expect_status 2 'init extra argument' "$AIMS" init "$TMP/must-not-exist" extra
[ ! -e "$TMP/must-not-exist" ] || { echo 'FAIL: invalid init mutated the filesystem' >&2; exit 1; }
expect_status 2 'start missing project/topic' "$AIMS" start only-project
expect_status 2 'start missing scope value' "$AIMS" start project topic --scope
expect_status 2 'start missing continuation value' "$AIMS" start project topic --continues-from
expect_status 2 'save extra argument' "$AIMS" save extra
expect_status 2 'handoff-all invalid flag' "$AIMS" handoff-all --typo
expect_status 2 'checkpoint --all extra argument' "$AIMS" checkpoint --all extra
expect_status 2 'brief extra argument' "$AIMS" brief safe-id extra
expect_status 2 'rebase extra argument' "$AIMS" rebase safe-id extra
expect_status 2 'adopt invalid flag' "$AIMS" adopt safe-id --typo
expect_status 2 'publish extra argument' "$AIMS" publish safe-id extra
expect_status 2 'list unknown flag' "$AIMS" list --typo
expect_status 2 'list missing project value' "$AIMS" list --project
expect_status 2 'artifacts extra argument' env AIMS_ARTIFACTS="$TMP/artifacts" "$AIMS" artifacts safe-id extra
expect_status 2 'doctor extra argument' "$AIMS" doctor extra
expect_status 2 'wire-agents extra argument' "$AIMS" wire-agents extra
expect_status 2 'install-hooks extra argument' "$AIMS" install-hooks extra
expect_status 2 'preflight extra argument' "$AIMS" preflight write extra
"$AIMS" init "$TMP/init-data" >/dev/null
"$AIMS" init "$TMP/init-data" | grep -q 'already exists'
(cd "$TMP/init-data" && "$AIMS" preflight read | grep -q 'mode=read')
HOME="$TMP/wire-home" AIMS_YES=1 "$AIMS" wire-agents >/dev/null
git init --bare -q --initial-branch=main "$REMOTE"
git clone -q "$REMOTE" "$DATA_A"
git -C "$DATA_A" config user.name 'AIMS Test'; git -C "$DATA_A" config user.email 'aims-test@example.invalid'
printf '# Contract test\n' > "$DATA_A/README.md"; printf '# Sessions\n' > "$DATA_A/SESSIONS.md"
git -C "$DATA_A" add .; git -C "$DATA_A" commit -qm init; git -C "$DATA_A" push -q -u origin main
git clone -q "$REMOTE" "$DATA_B"
git -C "$DATA_B" config user.name 'AIMS Test'; git -C "$DATA_B" config user.email 'aims-test@example.invalid'
AIMS_HOME="$DATA_B" "$AIMS" doctor | grep -q 'aims doctor passed'
AIMS_HOME="$DATA_B" "$AIMS" install-hooks | grep -q 'pre-push hook installed'
mkdir -p "$TMP/artifacts" "$TMP/non-git"
artifact_path="$(AIMS_ARTIFACTS="$TMP/artifacts" "$AIMS" artifacts ai/contract-artifact)"
[ "$artifact_path" = "$TMP/artifacts/contract-artifact" ] && [ -d "$artifact_path" ] || { echo 'FAIL: artifacts success path' >&2; exit 1; }
(cd "$TMP/non-git" && expect_status 2 'handoff by-id extra argument outside Git' env AIMS_HOME="$DATA_B" "$AIMS" handoff safe-id note extra)
start_output="$(cd "$DATA_A" && AIMS_HOME="$DATA_A" "$AIMS" start contract typo hermes --scope path:test)"
sid="$(printf '%s\n' "$start_output" | sed -n 's/^SESSION_ID=//p')"
wt_a="$DATA_A/.worktrees/$sid"
printf 'handoff payload\n' > "$wt_a/payload.txt"
(cd "$wt_a" && AIMS_HOME="$DATA_A" "$AIMS" handoff 'ready for contract test' >/dev/null)
set +e
(cd "$DATA_B" && AIMS_HOME="$DATA_B" "$AIMS" adopt "$sid" --typo >/dev/null 2>&1)
status=$?
set -e
[ "$status" -eq 2 ] || { echo "FAIL: adopt unknown flag returned $status instead of usage status 2" >&2; exit 1; }
[ ! -e "$DATA_B/.worktrees/$sid" ] || { echo 'FAIL: adopt unknown flag mutated local worktrees' >&2; exit 1; }
echo 'PASS: public command contract accepts documented forms and rejects unknown arguments without mutation'
