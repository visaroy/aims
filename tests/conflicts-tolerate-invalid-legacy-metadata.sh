#!/usr/bin/env bash
set -euo pipefail
ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="$ENGINE_ROOT/bin/aims"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REMOTE="$TMP/origin.git"; DATA="$TMP/data"
git init --bare -q --initial-branch=main "$REMOTE"; git clone -q "$REMOTE" "$DATA"
git -C "$DATA" config user.name 'AIMS Test'; git -C "$DATA" config user.email 'aims-test@example.invalid'
printf '# Test\n' > "$DATA/README.md"; git -C "$DATA" add README.md && git -C "$DATA" commit -q -m init && git -C "$DATA" push -q -u origin main

# Simulate a legacy session created before --scope was mandatory: push a
# branch directly with missing/invalid scope metadata, bypassing `aims
# start`'s own validation entirely (this is exactly how such branches exist
# in the wild today — created by an older AIMS version).
legacy_sid="20200101T000000Z-legacy-no-scope-agent"
legacy_wt="$TMP/legacy-wt"
git clone -q "$REMOTE" "$legacy_wt"
git -C "$legacy_wt" config user.name 'AIMS Test'; git -C "$legacy_wt" config user.email 'aims-test@example.invalid'
git -C "$legacy_wt" checkout -q -b "ai/$legacy_sid"
mkdir -p "$legacy_wt/sessions/work/$legacy_sid"
cat > "$legacy_wt/sessions/work/$legacy_sid/metadata.json" <<JSON
{
  "session_id": "$legacy_sid",
  "project": "legacy",
  "topic": "no scope",
  "agent": "legacy-agent",
  "status": "active",
  "scope": []
}
JSON
touch "$legacy_wt/sessions/work/$legacy_sid/worklog.md" "$legacy_wt/sessions/work/$legacy_sid/commands.md" "$legacy_wt/sessions/work/$legacy_sid/tests.md" "$legacy_wt/sessions/work/$legacy_sid/final-summary.md" "$legacy_wt/sessions/work/$legacy_sid/prompt-log.md"
git -C "$legacy_wt" add -A && git -C "$legacy_wt" commit -q -m "legacy session with empty scope"
git -C "$legacy_wt" push -q -u origin "ai/$legacy_sid"

# A completely unrelated valid session must still be checkable, and a fresh
# `aims start` on a genuinely free scope must still succeed — one legacy
# broken branch must not turn the whole fleet's conflict check into a hard
# failure.
diag="$(AIMS_HOME="$DATA" "$ENGINE" conflicts --scope path:brand-new-free-scope 2>&1)"
printf '%s\n' "$diag" | grep -q "WARN: $legacy_sid" || { echo "FAIL: conflicts did not warn about the legacy invalid-scope session" >&2; echo "$diag" >&2; exit 1; }
printf '%s\n' "$diag" | grep -q '^SAFE:' || { echo "FAIL: conflicts did not report SAFE despite the requested scope being genuinely free" >&2; echo "$diag" >&2; exit 1; }
echo 'PASS: conflicts warns about a legacy invalid-scope branch but still reports SAFE for an unrelated free scope'

start_out="$(AIMS_HOME="$DATA" "$ENGINE" start meta start-despite-legacy-junk tester --scope path:brand-new-free-scope 2>&1)"
printf '%s\n' "$start_out" | grep -q '^SESSION_ID=' || { echo "FAIL: aims start failed even though the requested scope did not overlap the legacy broken session" >&2; echo "$start_out" >&2; exit 1; }
echo 'PASS: aims start succeeds on a free scope despite an unrelated legacy invalid-scope session existing'

printf 'PASS: one legacy invalid-scope branch does not block conflict checking or admission for other scopes\n'
