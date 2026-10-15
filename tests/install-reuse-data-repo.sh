#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/helpers/install-env.sh"
reset_home() { chmod -R u+w "$HOME" 2>/dev/null || true; rm -rf "$HOME"; mkdir -p "$HOME"; }
expect_reuse() {  # expect_reuse <repo> <source> [env...]
  local repo="$1" src="$2" out had=0; shift 2
  [ ! -e "$HOME/.aims" ] || had=1
  out="$(env "$@" "$AIMS" install)" || fail "install failed for source $src: $out"
  printf '%s\n' "$out" | grep -qF "Data repo:     $repo (reused, from $src)" || fail "did not reuse $repo from $src: $out"
  [ "$(cat "$HOME/.config/aims/home")" = "$repo" ] || fail "recorded path is not $repo"
  [ "$(git -C "$repo" rev-list --count HEAD)" = 1 ] || fail "installer modified the data repo content"
  [ "$had" -eq 1 ] || [ ! -e "$HOME/.aims" ] || fail "a second data repo appeared at ~/.aims"
}
make_repo "$TMP/data-env"; expect_reuse "$TMP/data-env" env AIMS_HOME="$TMP/data-env"
[ "$("$AIMS" home)" = "$TMP/data-env" ] || fail "lifecycle commands do not resolve the recorded repo without AIMS_HOME"
reset_home; make_repo "$TMP/data-cfg"; mkdir -p "$HOME/.config/aims"; printf '%s\n' "$TMP/data-cfg" > "$HOME/.config/aims/home"
expect_reuse "$TMP/data-cfg" config
reset_home; make_repo "$HOME/data-prof"; printf 'export AIMS_HOME="$HOME/data-prof"  # data repo\n' > "$HOME/.zshenv"
[ "$("$AIMS" home)" = "$HOME/data-prof" ] || fail "profile export not parsed"
expect_reuse "$HOME/data-prof" found
reset_home; make_repo "$HOME/.aims"; expect_reuse "$HOME/.aims" found
reset_home; make_repo "$HOME/.aims"; make_repo "$HOME/other"; printf "AIMS_HOME='~/other'\n" > "$HOME/.bashrc"
before="$(snapshot "$HOME")"
if out="$("$AIMS" install 2>&1)"; then fail "two data repo candidates must block the install"; fi
printf '%s\n' "$out" | grep -qF 'more than one AIMS data repo candidate' || fail "ambiguity blocker not explained: $out"
printf '%s\n' "$out" | grep -qF 'nothing was changed' || fail "blocker output does not state that nothing changed"
[ "$(snapshot "$HOME")" = "$before" ] || fail "a blocked install changed files"
explain="$("$AIMS" home --explain)"; printf '%s\n' "$explain" | grep -qF 'WARN: more than one data repo candidate' || fail "aims home --explain does not warn about ambiguity"
expect_reuse "$HOME/other" env AIMS_HOME="$HOME/other"
expect_reuse "$HOME/other" config
echo 'PASS: install reuses the data repo from env, config, profile export, or ~/.aims, and blocks on ambiguity without changes'
