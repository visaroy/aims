#!/usr/bin/env bash
set -euo pipefail
ENGINE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REMOTE="$TMP/origin.git"; DATA="$TMP/data"
git init --bare -q --initial-branch=main "$REMOTE"; git clone -q "$REMOTE" "$DATA"
git -C "$DATA" config user.name 'AIMS Test'; git -C "$DATA" config user.email 'aims-test@example.invalid'
printf '# Test\n' > "$DATA/README.md"; git -C "$DATA" add README.md && git -C "$DATA" commit -q -m init && git -C "$DATA" push -q -u origin main
for spec in '20260728T000001Z-alpha-one-hermes:alpha:handoff' '20260728T000002Z-beta-two-hermes:beta:active' '20200101T000001Z-gamma-old-hermes:gamma:handoff'; do
  sid="${spec%%:*}"; rest="${spec#*:}"; project="${rest%%:*}"; status="${rest##*:}"; wt="$TMP/$sid"
  git -C "$DATA" worktree add -q -b "ai/$sid" "$wt" origin/main; mkdir -p "$wt/sessions/work/$sid"
  printf '{"session_id":"%s","project":"%s","status":"%s","scope":[]}\n' "$sid" "$project" "$status" > "$wt/sessions/work/$sid/metadata.json"
  git -C "$wt" add sessions && git -C "$wt" commit -q -m start && git -C "$wt" push -q -u origin "ai/$sid"
done
AIMS_HOME="$DATA" "$ENGINE_ROOT/bin/aims" list --handoff | grep -F 'ai/20260728T000001Z-alpha-one-hermes'
AIMS_HOME="$DATA" "$ENGINE_ROOT/bin/aims" list --project beta | grep -F 'ai/20260728T000002Z-beta-two-hermes'
if AIMS_HOME="$DATA" "$ENGINE_ROOT/bin/aims" list --project alpha | grep -Fq 'beta-two'; then echo 'project filter leaked beta session' >&2; exit 1; fi
stale_output="$(AIMS_HOME="$DATA" "$ENGINE_ROOT/bin/aims" list --stale)"
printf '%s\n' "$stale_output" | grep -F 'ai/20200101T000001Z-gamma-old-hermes'
if printf '%s\n' "$stale_output" | grep -Fq '20260728T000001Z'; then echo 'stale filter included a recent session' >&2; exit 1; fi
combined="$(AIMS_HOME="$DATA" "$ENGINE_ROOT/bin/aims" list --project gamma --handoff --stale)"
printf '%s\n' "$combined" | grep -F 'ai/20200101T000001Z-gamma-old-hermes'
reordered="$(AIMS_HOME="$DATA" "$ENGINE_ROOT/bin/aims" list --stale --project gamma --handoff)"
[ "$combined" = "$reordered" ] || { echo 'combined list filters depend on option order' >&2; exit 1; }
printf 'PASS: list filters handoff, project, stale, combined, and reordered sessions\n'
