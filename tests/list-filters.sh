#!/usr/bin/env bash
set -euo pipefail
ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REMOTE="$TMP/origin.git"; DATA="$TMP/data"
git init --bare -q --initial-branch=main "$REMOTE"; git clone -q "$REMOTE" "$DATA"
git -C "$DATA" config user.name 'AIMS Test'; git -C "$DATA" config user.email 'aims-test@example.invalid'
printf '# Test\n' > "$DATA/README.md"; git -C "$DATA" add README.md && git -C "$DATA" commit -q -m init && git -C "$DATA" push -q -u origin main
recent_one="$(python3 -c 'from datetime import datetime,timezone; print(datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"))')"
recent_two="$recent_one"
for spec in "$recent_one-project-one-hermes:project-one:handoff" "$recent_two-project-two-hermes:project-two:active" '20200101T000001Z-project-three-old-hermes:project-three:handoff'; do
  sid="${spec%%:*}"; rest="${spec#*:}"; project="${rest%%:*}"; status="${rest##*:}"; wt="$TMP/$sid"
  git -C "$DATA" worktree add -q -b "ai/$sid" "$wt" origin/main; mkdir -p "$wt/sessions/work/$sid"
  printf '{"session_id":"%s","project":"%s","status":"%s","scope":[]}\n' "$sid" "$project" "$status" > "$wt/sessions/work/$sid/metadata.json"
  git -C "$wt" add sessions && git -C "$wt" commit -q -m start && git -C "$wt" push -q -u origin "ai/$sid"
done
AIMS_HOME="$DATA" "$ENGINE_ROOT/bin/aims" list --handoff | grep -F "ai/$recent_one-project-one-hermes"
AIMS_HOME="$DATA" "$ENGINE_ROOT/bin/aims" list --project project-two | grep -F "ai/$recent_two-project-two-hermes"
if AIMS_HOME="$DATA" "$ENGINE_ROOT/bin/aims" list --project project-one | grep -Fq 'project-two'; then echo 'project filter leaked project-two session' >&2; exit 1; fi
stale_output="$(AIMS_HOME="$DATA" "$ENGINE_ROOT/bin/aims" list --stale)"
printf '%s\n' "$stale_output" | grep -F 'ai/20200101T000001Z-project-three-old-hermes'
if printf '%s\n' "$stale_output" | grep -Fq "$recent_one"; then echo 'stale filter included a recent session' >&2; exit 1; fi
combined="$(AIMS_HOME="$DATA" "$ENGINE_ROOT/bin/aims" list --project project-three --handoff --stale)"
printf '%s\n' "$combined" | grep -F 'ai/20200101T000001Z-project-three-old-hermes'
reordered="$(AIMS_HOME="$DATA" "$ENGINE_ROOT/bin/aims" list --stale --project project-three --handoff)"
[ "$combined" = "$reordered" ] || { echo 'combined list filters depend on option order' >&2; exit 1; }
printf 'PASS: list filters handoff, project, stale, combined, and reordered sessions\n'
