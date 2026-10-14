#!/usr/bin/env bash
# pre-push guard: blocks existing main, allows branches/seed/AIMS_PUBLISH, message names PR + aims publish
set -euo pipefail
HOOK="$(cd "$(dirname "$0")/.." && pwd)/hooks/pre-push"
Z=0000000000000000000000000000000000000000; S=1111111111111111111111111111111111111111
run() { printf 'refs/heads/x %s %s %s\n' "$S" "$1" "$2" | env AIMS_PUBLISH="${3:-0}" bash "$HOOK" origin url; }  # $1=remote ref $2=remote sha
err="$(run refs/heads/main "$S" 2>&1)" && { echo "FAIL: push to existing main allowed"; exit 1; }
grep -q 'pull request' <<<"$err" || { echo "FAIL: message lacks PR path: $err"; exit 1; }
grep -q 'aims publish <session-id>' <<<"$err" || { echo "FAIL: message lacks aims publish: $err"; exit 1; }
run refs/heads/main "$S" 1 || { echo "FAIL: AIMS_PUBLISH=1 blocked"; exit 1; }
run refs/heads/main "$Z" || { echo "FAIL: seeding new main blocked"; exit 1; }
run refs/heads/docs/x "$S" || { echo "FAIL: branch push blocked"; exit 1; }
echo "OK: pre-push guard"
