#!/usr/bin/env bash
set -euo pipefail
# Deprecated since 3.1.0 — kept so existing links keep working. It runs install.sh, the single installer:
#   curl -fsSL https://raw.githubusercontent.com/visaroy/aims/main/install.sh | AIMS_ACCEPT=1 bash
echo "NOTE: bootstrap.sh is deprecated since 3.1.0; it now runs install.sh (same result)." >&2
self="${BASH_SOURCE[0]:-}"
if [ -n "$self" ] && [ -f "$self" ] && [ -f "$(dirname "$self")/install.sh" ]; then exec bash "$(dirname "$self")/install.sh" "$@"; fi
repo="${AIMS_REPO:-https://github.com/visaroy/aims}"; dir="${AIMS_DIR:-$HOME/aims}"
if [ ! -d "$dir/.git" ]; then
  echo "AIMS is MIT-licensed, provided \"AS IS\", WITHOUT WARRANTY OF ANY KIND (see LICENSE in $repo)."
  [ "${AIMS_ACCEPT:-0}" = 1 ] || [ "${AIMS_ACCEPT:-}" = yes ] || { echo "Re-run with AIMS_ACCEPT=1 to accept the terms, or use install.sh." >&2; exit 1; }
  git clone -q "$repo" "$dir"
fi
exec bash "$dir/install.sh" "$@"
