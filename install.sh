#!/usr/bin/env bash
set -euo pipefail
# Installs the `aims` command onto PATH after a safe fast-forward from official origin/main.
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 && git -C "$root" remote get-url origin >/dev/null 2>&1; then
  [ "$(git -C "$root" branch --show-current)" = main ] || { echo "❌ install.sh must run from the main branch; switch to main first" >&2; exit 1; }
  [ -z "$(git -C "$root" status --porcelain)" ] || { echo "❌ AIMS engine has local changes; commit or discard them before updating" >&2; exit 1; }
  echo "🔄 Pobieram aktualizację AIMS z oficjalnego repozytorium GitHub…"
  git -C "$root" fetch origin main
  git -C "$root" merge --ff-only origin/main
else
  echo "ℹ️  AIMS engine has no Git origin; skipping update"
fi
mkdir -p "$HOME/.local/bin"
ln -sf "$root/bin/aims" "$HOME/.local/bin/aims"
echo "✅ linked $HOME/.local/bin/aims -> $root/bin/aims"
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "⚠️  add ~/.local/bin to PATH";; esac
echo "Next: aims init && aims doctor"
