#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCANNER="$ROOT/lib/validate-no-secrets.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/aims-secret-scan-batching.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; FAKEBIN="$TMP/fakebin"; mkdir -p "$REPO" "$FAKEBIN"
REAL_GIT="$(command -v git)"; REAL_GREP="$(command -v grep)"; ORIG_PATH="$PATH"
assert_contains() { case "$1" in *"$2"*) ;; *) echo "FAIL: expected output to contain $2" >&2; exit 1;; esac; }
assert_not_contains() { case "$1" in *"$2"*) echo "FAIL: output leaked $2" >&2; exit 1;; esac; }
run_scan() { set +e; output="$(cd "$1" && "$SCANNER" 2>&1)"; status=$?; set -e; }
run_scan_with_path() { set +e; output="$(cd "$1" && PATH="$2" "$SCANNER" 2>&1)"; status=$?; set -e; }
GH_PREFIX="$(printf '%s%s' gh p_)"; GH_PAT_PREFIX="$(printf '%s%s' github_ pat_)"; AWS_PREFIX="$(printf '%s%s' AK IA)"; GLPAT_PREFIX="$(printf '%s%s' gl pat-)"
PRIVATE_RSA="$(printf '%s%s%s' '-----BEGIN ' 'RSA ' 'PRIVATE KEY-----')"; PRIVATE_PLAIN="$(printf '%s%s' '-----BEGIN ' 'PRIVATE KEY-----')"
git init -q -b main "$REPO"; git -C "$REPO" config user.name 'AIMS Test'; git -C "$REPO" config user.email 'aims-test@example.invalid'
printf 'safe content\n' > "$REPO/tracked.txt"
printf 'token=%s%s\n' "$AWS_PREFIX" 'ABCDEF1234567890' > "$REPO/tracked-positive.txt"
printf 'api_key=${TEST_API_TOKEN}\n' > "$REPO/generic-placeholder.txt"
printf 'ignored=%s%s\n' "$GH_PREFIX" 'IGNORED_BODY_1234567890' > "$REPO/ignored-secret.txt"
printf 'ignored-secret.txt\n' > "$REPO/.gitignore"
git -C "$REPO" add .; git -C "$REPO" commit -qm init
run_scan "$REPO"
[ "$status" -ne 0 ] || { echo 'FAIL: unchanged tracked positive was accepted' >&2; exit 1; }
assert_contains "$output" 'tracked-positive.txt:1'; assert_not_contains "$output" 'ABCDEF1234567890'; assert_not_contains "$output" 'ignored-secret.txt'
rm "$REPO/tracked-positive.txt"
run_scan "$REPO"
[ "$status" -eq 0 ] || { echo 'FAIL: deleted tracked file was not skipped' >&2; exit 1; }
assert_not_contains "$output" 'tracked-positive.txt'
printf 'text %sshort\n' "$GH_PREFIX" > "$REPO/negative.txt"
AWS_FAMILY_BODY='ABCDEF1234567890'; FAMILY_BODY='G1h2J3k4L5m6N7o8P9q0R1s2'; PAT_BODY='T2u3V4w5X6y7Z8a9B0c1D2'; GL_BODY='E3f4G5h6I7j8K9l0M1n2O3'; SLACK_BODY='P4q5R6s7T8u9V0w1X2y3Z4'; GENERIC_BODY='GENERIC_VALUE_123456'
{
  printf '%s\n' "$PRIVATE_RSA" "$PRIVATE_PLAIN"
  printf 'aws=%s%s\n' "$AWS_PREFIX" "$AWS_FAMILY_BODY"
  printf 'github=%s%s\n' "$GH_PREFIX" "$FAMILY_BODY"
  printf 'github-pat=%s%s\n' "$GH_PAT_PREFIX" "$PAT_BODY"
  printf 'gitlab=%s%s\n' "$GLPAT_PREFIX" "$GL_BODY"
  for suffix in ptt rt dt soat cbt ft imt agent; do printf 'gitlab-variant=gl%s-%s\n' "$suffix" "$GL_BODY"; done
  for suffix in b a p r s; do printf 'slack=%s%s\n' "$(printf '%s%s' xo "x${suffix}-")" "$SLACK_BODY"; done
  printf 'api_key=%s\n' "$GENERIC_BODY"
  printf 'api_key=%s\n' '${TEST_API_TOKEN}'
  printf 'api_key=%s\n' 'xxxxxxxxxxxxxxxx'
} > "$REPO/detector-families.txt"
run_scan "$REPO"
[ "$status" -ne 0 ] || { echo 'FAIL: detector-family positives were accepted' >&2; exit 1; }
assert_contains "$output" 'detector-families.txt:'
assert_contains "$output" 'potential secret pattern matched: -----BEGIN'
assert_contains "$output" 'potential secret pattern matched: AKIA'
assert_contains "$output" 'potential secret pattern matched: ghp_'
assert_contains "$output" 'potential secret pattern matched: github_pat_'
assert_contains "$output" 'potential secret pattern matched: glpat-'
assert_contains "$output" 'potential secret pattern matched: gl(ptt|rt|dt|soat|cbt|ft|imt|agent)-'
assert_contains "$output" 'potential secret pattern matched: xox[baprs]-'
assert_contains "$output" 'potential secret pattern matched: (api[_-]?key'
assert_not_contains "$output" "$AWS_FAMILY_BODY"; assert_not_contains "$output" "$FAMILY_BODY"; assert_not_contains "$output" "$PAT_BODY"; assert_not_contains "$output" "$GL_BODY"; assert_not_contains "$output" "$SLACK_BODY"; assert_not_contains "$output" "$GENERIC_BODY"
{
  printf 'aws=%s%s\n' "$AWS_PREFIX" 'ABCDEF123456789'
  printf 'github=%s%s\n' "$GH_PREFIX" '1234567890123456789'
  printf 'github-pat=%s%s\n' "$GH_PAT_PREFIX" '1234567890123456789'
  printf 'gitlab=%s%s\n' "$GLPAT_PREFIX" '1234567890123456789'
  printf 'gitlab-variant=glptt-%s\n' '12345678901234'
  printf 'slack=%s%s\n' "$(printf '%s%s' xo 'xb-')" '1234567890123456789'
  printf 'api_key=%s\n' '123456789012345'
} > "$REPO/boundaries.txt"
rm "$REPO/detector-families.txt"
run_scan "$REPO"
[ "$status" -eq 0 ] || { echo 'FAIL: detector boundary negatives were rejected' >&2; exit 1; }
HIGH_PLACEHOLDER='PLACEHOLDER_PLACEHOLDER_123456'
printf 'token=%s%s\n' "$GH_PREFIX" "$HIGH_PLACEHOLDER" > "$REPO/high-confidence-placeholder.txt"
run_scan "$REPO"
[ "$status" -ne 0 ] || { echo 'FAIL: high-confidence placeholder was allowlisted' >&2; exit 1; }
assert_contains "$output" 'high-confidence-placeholder.txt:1'; assert_not_contains "$output" "$HIGH_PLACEHOLDER"; rm "$REPO/high-confidence-placeholder.txt"
PATH_BODY='Q5r6S7t8U9v0W1x2Y3z4A5'; printf 'token=%s%s\n' "$GH_PREFIX" "$PATH_BODY" > "$REPO/space name.txt"; printf 'token=%s%s\n' "$GH_PREFIX" "$PATH_BODY" > "$REPO/-leading-dash.txt"
run_scan "$REPO"
[ "$status" -ne 0 ] || { echo 'FAIL: space/leading-dash positives were accepted' >&2; exit 1; }
assert_contains "$output" 'space name.txt:1'; assert_contains "$output" '-leading-dash.txt:1'; assert_not_contains "$output" "$PATH_BODY"; rm "$REPO/space name.txt" "$REPO/-leading-dash.txt"
SPECIAL_DIR="$REPO/nested"; mkdir -p "$SPECIAL_DIR"
safe_colon="$SPECIAL_DIR/colon:safe.txt"; safe_newline="$SPECIAL_DIR/"$'newline\nsafe.txt'; safe_backslash="$SPECIAL_DIR/literal\\safe.txt"
printf 'safe content\n' > "$safe_colon"; printf 'safe content\n' > "$safe_newline"; printf 'safe content\n' > "$safe_backslash"
run_scan "$REPO"
[ "$status" -eq 0 ] || { echo 'FAIL: safe colon/newline files were rejected' >&2; exit 1; }
rm "$safe_colon" "$safe_newline" "$safe_backslash"
SPECIAL_BODY='B6c7D8e9F0g1H2i3J4k5L6'; colon_positive="$SPECIAL_DIR/colon:positive.txt"; newline_positive="$SPECIAL_DIR/"$'newline\npositive.txt'; backslash_positive="$SPECIAL_DIR/literal\\positive.txt"
printf 'token=%s%s\n' "$GH_PREFIX" "$SPECIAL_BODY" > "$colon_positive"; printf 'token=%s%s\n' "$GH_PREFIX" "$SPECIAL_BODY" > "$newline_positive"; printf 'token=%s%s\n' "$GH_PREFIX" "$SPECIAL_BODY" > "$backslash_positive"
run_scan "$REPO"
[ "$status" -ne 0 ] || { echo 'FAIL: colon/newline positives were accepted' >&2; exit 1; }
assert_contains "$output" '"nested/colon:positive.txt":1'; assert_contains "$output" '"nested/newline\npositive.txt":1'; assert_contains "$output" '"nested/literal\\positive.txt":1'; assert_not_contains "$output" "$SPECIAL_BODY"; rm "$colon_positive" "$newline_positive" "$backslash_positive"
cat > "$FAKEBIN/git" <<EOF
#!/bin/sh
for arg do
  [ "\$arg" = ls-files ] && exit 73
done
exec "$REAL_GIT" "\$@"
EOF
chmod 700 "$FAKEBIN/git"; run_scan_with_path "$REPO" "$FAKEBIN:$ORIG_PATH"
[ "$status" -ne 0 ] || { echo 'FAIL: injected git inventory failure was accepted' >&2; exit 1; }
assert_contains "$output" 'unable to enumerate files'; rm "$FAKEBIN/git"
cat > "$FAKEBIN/xargs" <<'EOF'
#!/bin/sh
exit 74
EOF
chmod 700 "$FAKEBIN/xargs"; run_scan_with_path "$REPO" "$FAKEBIN:$ORIG_PATH"
[ "$status" -ne 0 ] || { echo 'FAIL: injected xargs failure was accepted' >&2; exit 1; }
assert_contains "$output" 'unable to scan a secret batch'; rm "$FAKEBIN/xargs"
MASS="$TMP/mass"; mkdir -p "$MASS"; git init -q -b main "$MASS"; git -C "$MASS" config user.name 'AIMS Test'; git -C "$MASS" config user.email 'aims-test@example.invalid'
MASS_BODY='C7d8E9f0G1h2I3j4K5l6M7'; printf 'token=%s%s\n' "$GH_PREFIX" "$MASS_BODY" > "$MASS/aaa-earlier.txt"; printf 'token=%s%s\n' "$GH_PREFIX" "$MASS_BODY" > "$MASS/zzz-later.txt"
i=1; while [ "$i" -le 200 ]; do printf 'safe %s\n' "$i" > "$MASS/safe-$i.txt"; i=$((i + 1)); done
: > "$TMP/grep.log"
cat > "$FAKEBIN/grep" <<'EOF'
#!/bin/sh
printf 'call\n' >> "$AIMS_TEST_GREP_LOG"
exec "$AIMS_TEST_REAL_GREP" "$@"
EOF
chmod 700 "$FAKEBIN/grep"; set +e; output="$(cd "$MASS" && PATH="$FAKEBIN:$ORIG_PATH" AIMS_TEST_GREP_LOG="$TMP/grep.log" AIMS_TEST_REAL_GREP="$REAL_GREP" "$SCANNER" 2>&1)"; status=$?; set -e; calls="$(wc -l < "$TMP/grep.log")"
[ "$status" -ne 0 ] || { echo 'FAIL: instrumented grep run did not detect the positive' >&2; exit 1; }
[ "$calls" -lt 100 ] || { echo "FAIL: grep was invoked $calls times for 202 files" >&2; exit 1; }; [ "$calls" -gt 0 ] || { echo 'FAIL: grep instrumentation saw no calls' >&2; exit 1; }; assert_not_contains "$output" "$MASS_BODY"
: > "$TMP/grep.log"
cat > "$FAKEBIN/grep" <<'EOF'
#!/bin/sh
printf 'call\n' >> "$AIMS_TEST_GREP_LOG"
calls=$(wc -l < "$AIMS_TEST_GREP_LOG")
if [ "$calls" -eq "${AIMS_TEST_GREP_FAIL_ON:-0}" ]; then
  "$AIMS_TEST_REAL_GREP" "$@"
  exit 88
fi
exec "$AIMS_TEST_REAL_GREP" "$@"
EOF
chmod 700 "$FAKEBIN/grep"; set +e; output="$(cd "$MASS" && PATH="$FAKEBIN:$ORIG_PATH" AIMS_TEST_GREP_LOG="$TMP/grep.log" AIMS_TEST_REAL_GREP="$REAL_GREP" AIMS_TEST_GREP_FAIL_ON=6 "$SCANNER" 2>&1)"; status=$?; set -e
[ "$status" -ne 0 ] || { echo 'FAIL: later-batch grep failure was accepted' >&2; exit 1; }; assert_contains "$output" 'aaa-earlier.txt:1'; assert_contains "$output" 'zzz-later.txt:1'; assert_not_contains "$output" "$MASS_BODY"
if [ -n "${BASH32:-}" ]; then
  BASH32_BIN="$BASH32"; [ -x "$BASH32_BIN" ] || BASH32_BIN="$(command -v "$BASH32" 2>/dev/null || true)"
  if [ -x "$BASH32_BIN" ]; then
    BASH32_PATH="$TMP/bash32-path"; mkdir -p "$BASH32_PATH"; ln -s "$BASH32_BIN" "$BASH32_PATH/bash"
    set +e; output="$(cd "$MASS" && PATH="$BASH32_PATH:$ORIG_PATH" "$BASH32_BIN" "$SCANNER" 2>&1)"; status=$?; set -e
    [ "$status" -ne 0 ] || { echo 'FAIL: Bash 3.2 scanner run accepted the positive' >&2; exit 1; }
    assert_contains "$output" 'aaa-earlier.txt:1'; assert_not_contains "$output" "$MASS_BODY"
    assert_not_contains "$output" 'syntax error'; assert_not_contains "$output" 'bad substitution'; assert_not_contains "$output" 'command not found'; assert_not_contains "$output" 'unable to scan a secret batch'; assert_not_contains "$output" 'unable to parse secret scan batch output'
  else
    printf 'SKIP: BASH32 is set but not executable\n'
  fi
else
  printf 'SKIP: BASH32 is not set\n'
fi
printf 'PASS: secret scanner batches all detector families, handles special paths safely, fails closed, preserves findings, and avoids per-file grep launches\n'
