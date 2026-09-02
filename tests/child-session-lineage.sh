#!/usr/bin/env bash
set -euo pipefail
ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="$ENGINE_ROOT/bin/aims"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REMOTE="$TMP/origin.git"; DATA="$TMP/data"
git init --bare -q --initial-branch=main "$REMOTE"; git clone -q "$REMOTE" "$DATA"
git -C "$DATA" config user.name 'AIMS Test'; git -C "$DATA" config user.email 'aims-test@example.invalid'
printf '# Test\n' > "$DATA/README.md"; git -C "$DATA" add README.md && git -C "$DATA" commit -q -m init && git -C "$DATA" push -q -u origin main
start_parent="$(AIMS_HOME="$DATA" "$ENGINE" start meta parent tester --scope path:shared)"; parent="$(printf '%s\n' "$start_parent" | sed -n 's/^SESSION_ID=//p')"
start_child="$(AIMS_HOME="$DATA" "$ENGINE" start meta child tester --scope path:shared --parent-session "$parent")"; child="$(printf '%s\n' "$start_child" | sed -n 's/^SESSION_ID=//p')"
child_wt="$(printf '%s\n' "$start_child" | sed -n 's/^WORKTREE=//p')"
python3 - "$child_wt/sessions/work/$child/metadata.json" "$parent" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))['parent_session'] == sys.argv[2]
PY
listing="$(AIMS_HOME="$DATA" "$ENGINE" list)"; printf '%s\n' "$listing" | grep -F "parent=$parent" >/dev/null
plain="$(AIMS_HOME="$DATA" "$ENGINE" conflicts --scope path:shared || true)"; printf '%s\n' "$plain" | grep -F "CONFLICT: $child" >/dev/null
contextual="$(AIMS_HOME="$DATA" "$ENGINE" conflicts --scope path:shared --session "$parent" || true)"; printf '%s\n' "$contextual" | grep -F "RELATED_CHILD: $child parent=$parent" >/dev/null; printf '%s\n' "$contextual" | grep -Fx "REUSE_CHILD_SESSION=$child" >/dev/null
if sibling="$(AIMS_HOME="$DATA" "$ENGINE" start meta sibling tester --scope path:shared --parent-session "$parent" 2>&1)"; then echo 'overlapping sibling was created' >&2; exit 1; fi
printf '%s\n' "$sibling" | grep -Fx "REUSE_CHILD_SESSION=$child" >/dev/null
sibling_branch_count="$(git --git-dir="$REMOTE" for-each-ref --format='%(refname)' "refs/heads/ai/*sibling*" | wc -l | tr -d ' ')"; [ "$sibling_branch_count" = 0 ] || { echo 'rejected sibling branch exists' >&2; exit 1; }
start_external_path="$(AIMS_HOME="$DATA" "$ENGINE" start meta external-path tester --scope path:external)"; external_path="$(printf '%s\n' "$start_external_path" | sed -n 's/^SESSION_ID=//p')"
if blocked="$(AIMS_HOME="$DATA" "$ENGINE" start meta blocked tester --scope path:external --parent-session "$parent" 2>&1)"; then echo 'parented child ignored unrelated conflict' >&2; exit 1; fi
printf '%s\n' "$blocked" | grep -F "CONFLICT: $external_path" >/dev/null
blocked_branch_count="$(git --git-dir="$REMOTE" for-each-ref --format='%(refname)' "refs/heads/ai/*blocked*" | wc -l | tr -d ' ')"; [ "$blocked_branch_count" = 0 ] || { echo 'blocked child branch exists' >&2; exit 1; }
start_external="$(AIMS_HOME="$DATA" "$ENGINE" start meta external tester --scope path:shared)"; external="$(printf '%s\n' "$start_external" | sed -n 's/^SESSION_ID=//p')"
contextual_external="$(AIMS_HOME="$DATA" "$ENGINE" conflicts --scope path:shared --session "$parent" || true)"; printf '%s\n' "$contextual_external" | grep -F "CONFLICT: $external" >/dev/null
if AIMS_HOME="$DATA" "$ENGINE" start meta invalid tester --parent-session 'bad/id' >/dev/null 2>&1; then echo 'unsafe parent accepted' >&2; exit 1; fi
if AIMS_HOME="$DATA" "$ENGINE" start meta missing tester --parent-session missing-parent >/dev/null 2>&1; then echo 'missing parent accepted' >&2; exit 1; fi
printf 'PASS: parented child lineage prevents overlapping sibling writers without suppressing external conflicts\n'
