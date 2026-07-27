#!/usr/bin/env bash
set -euo pipefail
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$root"
# NOTE: .md files are scanned too. Do not exclude them — most leaks land in session/state markdown
# (agents pasting values "for context"). Scanning .md is the durable protection against that.
patterns=(
  '-----BEGIN (RSA |OPENSSH |DSA |EC |)PRIVATE KEY-----'
  'AKIA[0-9A-Z]{16}'
  'ghp_[A-Za-z0-9_]{20,}'
  'github_pat_[A-Za-z0-9_]{20,}'
  'glpat-[A-Za-z0-9_-]{20,}'
  # Other GitLab token prefixes (easy to miss): glptt- = pipeline trigger, glrt- = runner,
  # gldt- = deploy, glsoat- = scim/oauth.
  'gl(ptt|rt|dt|soat|cbt|ft|imt|agent)-[A-Za-z0-9_-]{15,}'
  'xox[baprs]-[A-Za-z0-9-]{20,}'
  "(api[_-]?key|token|secret|password)[\"' ]*[:=][\"' ]*[A-Za-z0-9_./+=-]{16,}"
)
# Literal placeholder values only — deliberately NOT generic words like "example" or
# "dummy", which legitimately co-occur with real secrets (e.g. host example.com on the
# same line) and would mask them. Extend only with strings that are never a real value.
placeholder='tutaj-twoj-klucz|twoj-klucz|your[_-]api[_-]key|YOUR_API_KEY|<your|changeme|CHANGEME|CHANGE_ME|placeholder|PLACEHOLDER|ZREDAGOWANE|\$\{|xxxxxxxx|XXXXXXXX'
fail=0
for pat in "${patterns[@]}"; do
  hits="$({
    git grep -InE "$pat" -- ':!secrets/*.example' ':!secrets/README.md' 2>/dev/null || true
    while IFS= read -r -d '' file; do
      case "$file" in secrets/*.example|secrets/README.md) continue;; esac
      [ -f "$file" ] || continue
      while IFS= read -r match; do printf '%s:%s\n' "$file" "$match"; done < <(grep -InE "$pat" -- "$file" 2>/dev/null || true)
    done < <(git ls-files --others --exclude-standard -z)
  } | grep -Ev "$placeholder" || true)"  # scan tracked and unstaged files, then drop placeholders
  [ -z "$hits" ] && continue
  printf 'ERROR: potential secret pattern matched: %s\n' "$pat" >&2
  printf '%s\n' "$hits" | cut -d: -f1-2 | sort -u >&2
  fail=1
done
[ "$fail" -eq 0 ] && echo "OK: no obvious secrets detected"
exit "$fail"
