#!/usr/bin/env bash
set -euo pipefail
ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="$ENGINE_ROOT/bin/aims"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REMOTE="$TMP/origin.git"; DATA="$TMP/data"
git init --bare -q --initial-branch=main "$REMOTE"; git clone -q "$REMOTE" "$DATA"
git -C "$DATA" config user.name 'AIMS Test'; git -C "$DATA" config user.email 'aims-test@example.invalid'
printf '# Test\n' > "$DATA/README.md"; git -C "$DATA" add README.md && git -C "$DATA" commit -q -m init && git -C "$DATA" push -q -u origin main
start="$(AIMS_HOME="$DATA" "$ENGINE" start meta source hermes --scope path:docs/source)"
sid="$(printf '%s\n' "$start" | sed -n 's/^SESSION_ID=//p')"; wt="$(printf '%s\n' "$start" | sed -n 's/^WORKTREE=//p')"
printf 'published source\n' > "$wt/source.txt"; (cd "$wt" && AIMS_HOME="$DATA" "$ENGINE" save >/dev/null)
AIMS_HOME="$DATA" "$ENGINE" publish "$sid" >/dev/null
[ ! -d "$DATA/.worktrees/$sid" ] || { echo 'published worktree remains' >&2; exit 1; }
if git -C "$DATA" show-ref --verify --quiet "refs/heads/ai/$sid"; then echo 'published local branch remains' >&2; exit 1; fi
git -C "$DATA" fetch -q origin main && git -C "$DATA" reset -q --hard origin/main
python3 - "$DATA/sessions/work/$sid/metadata.json" <<'PY'
import json,sys
path=sys.argv[1]
with open(path) as handle: metadata=json.load(handle)
metadata['status']='active'  # Simulate records published by pre-1.1 AIMS.
with open(path,'w') as handle: json.dump(metadata,handle); handle.write('\n')
PY
git -C "$DATA" add "sessions/work/$sid/metadata.json" && git -C "$DATA" commit -q -m legacy && git -C "$DATA" push -q origin main
status="$(AIMS_HOME="$DATA" "$ENGINE" status "$sid")"
printf '%s\n' "$status" | grep -F 'PUBLISHED'
printf '%s\n' "$status" | grep -F "sessions/work/$sid"
adopt="$(AIMS_HOME="$DATA" "$ENGINE" adopt "$sid")"
printf '%s\n' "$adopt" | grep -F 'CLOSED: session'
printf '%s\n' "$adopt" | grep -F 'aims continue'
continued="$(AIMS_HOME="$DATA" "$ENGINE" continue "$sid" outreach hermes --scope path:docs/outreach)"
next_sid="$(printf '%s\n' "$continued" | sed -n 's/^SESSION_ID=//p')"; next_wt="$(printf '%s\n' "$continued" | sed -n 's/^WORKTREE=//p')"
python3 - "$next_wt/sessions/work/$next_sid/metadata.json" "$sid" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))['continues_from'] == sys.argv[2]
PY
AIMS_HOME="$DATA" "$ENGINE" list --closed | grep -F "$sid"
conflict="$(AIMS_HOME="$DATA" "$ENGINE" conflicts --scope path:docs/other)"
printf '%s\n' "$conflict" | grep -F 'SAFE: no overlapping writable resource.'
printf 'PASS: published sessions report, continue safely, clean local branches, list closed, and diagnose scopes\n'
