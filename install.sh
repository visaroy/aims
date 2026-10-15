#!/usr/bin/env bash
# AIMS installer — the single entry point. Zero configuration, idempotent, reversible (aims uninstall).
#   curl -fsSL https://raw.githubusercontent.com/visaroy/aims/main/install.sh | AIMS_ACCEPT=1 bash
#   bash ~/aims/install.sh [--fresh]
# From a pipe it clones the engine to ~/aims (asking to accept the MIT terms first, or AIMS_ACCEPT=1);
# from a checkout it restores that checkout to the official origin/main. Then it runs `aims install`:
# preflight, command link, data repo (reused, never deleted), guard, agent rules, report.
# Overridable via env: AIMS_REPO (engine URL for a first clone), AIMS_DIR (engine checkout).
set -euo pipefail
restore_engine() {  # the only place AIMS resets or cleans anything: the engine checkout itself
  local d="$1"
  if git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1 && git -C "$d" remote get-url origin >/dev/null 2>&1; then
    [ "$(git -C "$d" branch --show-current)" = main ] || { echo "❌ install.sh must run from the main branch; switch to main first" >&2; exit 1; }
    echo "🔄 Restoring a fresh, official AIMS version from the official GitHub repository…"
    git -C "$d" fetch origin main
    git -C "$d" reset --hard origin/main
    git -C "$d" clean -ffdx
  else
    echo "ℹ️  AIMS engine has no Git origin; skipping update"
  fi
}
accept_terms() {  # only before the first clone; a checkout was already obtained by the user
  cat <<TERMS
AIMS — AI Multi-agent Sessions.   License: MIT — provided "AS IS", WITHOUT WARRANTY OF ANY KIND.
On THIS machine this installer will clone the engine to $1, link the 'aims' command into
~/.local/bin, reuse your AIMS data repo (or create ~/.aims), install its pre-push guard, and add a
marked AIMS rules block to the config of each detected AI agent. Every modified file is backed up and
'aims uninstall' reverts it. No network calls except 'git' to repositories you configure.
See LICENSE and SECURITY.md in $2.
TERMS
  if [ "${AIMS_ACCEPT:-0}" = 1 ] || [ "${AIMS_ACCEPT:-}" = yes ]; then echo "  accepted via AIMS_ACCEPT"; return; fi
  if ( : </dev/tty ) 2>/dev/null; then
    printf 'Type "yes" to accept these terms and continue: ' > /dev/tty; read -r ans < /dev/tty || ans=
    [ "$ans" = yes ] || { echo "Aborted — nothing installed."; exit 1; }
  else
    echo "Non-interactive install: re-run with AIMS_ACCEPT=1 to accept the terms above." >&2; exit 1
  fi
}
main() {
  local repo="${AIMS_REPO:-https://github.com/visaroy/aims}" dir="${AIMS_DIR:-$HOME/aims}" self="${BASH_SOURCE[0]:-}" root=""
  if [ -n "$self" ] && [ -f "$self" ] && [ -f "$(dirname "$self")/lib/aims-install" ]; then root="$(cd "$(dirname "$self")" && pwd)"; fi
  if [ -z "$root" ]; then  # piped: work on the default engine checkout
    root="$dir"
    if [ -d "$root/.git" ]; then restore_engine "$root"
    else accept_terms "$root" "$repo"; git clone -q "$repo" "$root"; echo "✅ cloned $repo -> $root"; fi
  else
    restore_engine "$root"
  fi
  exec "$root/lib/aims-install" "$@"
}
main "$@"; exit $?
