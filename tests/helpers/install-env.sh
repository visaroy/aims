#!/usr/bin/env bash
# shellcheck disable=SC2034  # ROOT/AIMS/TMP are used by the tests that source this file
# Shared setup for installer tests: a disposable HOME, no network, fake agent CLIs, isolated Git config.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"; AIMS="$ROOT/bin/aims"
TMP="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/aims-install-test.XXXXXX")" && pwd -P)"; trap 'chmod -R u+w "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT
unset AIMS_HOME XDG_CONFIG_HOME XDG_STATE_HOME AIMS_ACCEPT AIMS_DIR AIMS_REPO
export PYTHONDONTWRITEBYTECODE=1 HOME="$TMP/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 PATH="$TMP/agents:/usr/bin:/bin"
export GIT_AUTHOR_NAME='AIMS Test' GIT_AUTHOR_EMAIL='aims-test@example.invalid' GIT_COMMITTER_NAME='AIMS Test' GIT_COMMITTER_EMAIL='aims-test@example.invalid'
mkdir -p "$HOME" "$TMP/agents"
fail() { echo "FAIL: $*" >&2; exit 1; }
fake_agent() { local a; for a in "$@"; do printf '#!/bin/sh\nexit 0\n' > "$TMP/agents/$a"; chmod +x "$TMP/agents/$a"; done; }
snapshot() {  # content fingerprint of every file and symlink under a directory
  (cd "$1" && find . -path ./Library -prune -o \( -type f -o -type l \) -print | LC_ALL=C sort | while IFS= read -r f; do
    if [ -L "$f" ]; then printf 'L %s -> %s\n' "$f" "$(readlink "$f")"; else printf 'F %s %s\n' "$f" "$(cksum < "$f")"; fi
  done)
}
make_repo() { git init -q -b main "$1" 2>/dev/null || { git init -q "$1" && git -C "$1" checkout -q -b main; }; printf '%s\n' "${2:-data}" > "$1/README.md"; git -C "$1" add README.md; git -C "$1" commit -qm init; }
make_engine() {  # make_engine <checkout> <bare origin>: the current working tree as an engine on main
  git init --bare -q "$2"; git -C "$2" symbolic-ref HEAD refs/heads/main
  mkdir -p "$1"; (cd "$ROOT" && git ls-files -co --exclude-standard | while IFS= read -r f; do [ -e "$f" ] && printf '%s\n' "$f"; done) > "$TMP/engine-files"
  tar -C "$ROOT" -cf - -T "$TMP/engine-files" | tar -C "$1" -xf -
  git init -q -b main "$1" 2>/dev/null || { git init -q "$1" && git -C "$1" checkout -q -b main; }; git -C "$1" add -A; git -C "$1" commit -qm engine
  git -C "$1" remote add origin "$2"; git -C "$1" push -q -u origin main
}
