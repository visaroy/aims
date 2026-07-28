#!/usr/bin/env bash
set -euo pipefail
ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REMOTE="$TMP/origin.git"; DATA="$TMP/data"
git init --bare -q --initial-branch=main "$REMOTE"; git clone -q "$REMOTE" "$DATA"
git -C "$DATA" config user.name 'AIMS Test'; git -C "$DATA" config user.email 'aims-test@example.invalid'
printf '# Test\n' > "$DATA/README.md"; git -C "$DATA" add README.md && git -C "$DATA" commit -q -m init && git -C "$DATA" push -q -u origin main
out="$(AIMS_HOME="$DATA" "$ENGINE_ROOT/bin/aims" start meta continuation hermes --continues-from 20260728T000001Z-meta-source-hermes)"
wt="$(printf '%s\n' "$out" | sed -n 's/^WORKTREE=//p')"; meta="$(find "$wt/sessions/work" -name metadata.json)"
python3 - "$meta" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))['continues_from']=='20260728T000001Z-meta-source-hermes'
PY
if AIMS_HOME="$DATA" "$ENGINE_ROOT/bin/aims" start meta bad hermes --continues-from '../unsafe' >/dev/null 2>&1; then echo 'expected unsafe predecessor rejection' >&2; exit 1; fi
printf 'PASS: start records validated continuation metadata\n'
