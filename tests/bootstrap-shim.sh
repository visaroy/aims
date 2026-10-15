#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/helpers/install-env.sh"
make_engine "$TMP/engine" "$TMP/engine.git"
err="$(bash "$TMP/engine/bootstrap.sh" 2>&1 >/dev/null)" || fail "bootstrap.sh from a checkout failed: $err"
printf '%s\n' "$err" | grep -qF 'bootstrap.sh is deprecated since 3.1.0' || fail "no deprecation notice"
[ "$(readlink "$HOME/.local/bin/aims")" = "$TMP/engine/bin/aims" ] && [ -d "$HOME/.aims/.git" ] || fail "bootstrap.sh did not run the installer"
rm -rf "$HOME"; mkdir -p "$HOME"
if AIMS_DIR="$TMP/piped" AIMS_REPO="$TMP/engine.git" bash < "$ROOT/bootstrap.sh" >/dev/null 2>&1; then fail "piped bootstrap must require accepting the terms"; fi
[ ! -e "$TMP/piped" ] || fail "piped bootstrap cloned without consent"
AIMS_ACCEPT=1 AIMS_DIR="$TMP/piped" AIMS_REPO="$TMP/engine.git" bash < "$ROOT/bootstrap.sh" >/dev/null 2>&1 || fail "piped bootstrap failed"
[ "$(readlink "$HOME/.local/bin/aims")" = "$TMP/piped/bin/aims" ] && [ -d "$HOME/.aims/.git" ] || fail "piped bootstrap did not clone and install"
echo 'PASS: bootstrap.sh is a deprecated shim that runs install.sh, from a checkout and from a pipe'
