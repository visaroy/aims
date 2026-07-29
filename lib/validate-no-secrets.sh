#!/usr/bin/env bash
set -euo pipefail
root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; cd "$root"
generic_prefix="(api[_-]?key|token|secret|password)[\"' ]*[:=][\"' ]*"
generic_pattern="${generic_prefix}[A-Za-z0-9_./+={}$<>-]{16,}"
patterns=(
  '-----BEGIN (RSA |OPENSSH |DSA |EC |)PRIVATE KEY-----'
  'AKIA[0-9A-Z]{16}'
  'ghp_[A-Za-z0-9_]{20,}'
  'github_pat_[A-Za-z0-9_]{20,}'
  'glpat-[A-Za-z0-9_-]{20,}'
  'gl(ptt|rt|dt|soat|cbt|ft|imt|agent)-[A-Za-z0-9_-]{15,}'
  'xox[baprs]-[A-Za-z0-9-]{20,}'
  "$generic_pattern"
)
# Only a complete generic key/value payload may be ignored. High-confidence token prefixes are never allowlisted.
placeholder_value='^(tutaj-twoj-klucz|twoj-klucz|your[_-]api[_-]key|YOUR_API_KEY|<your[^>]*>|changeme|CHANGEME|CHANGE_ME|placeholder|PLACEHOLDER|ZREDAGOWANE|\$\{[^}]+\}|x{8,}|X{8,})$'
fail=0
scan_file="$(mktemp "${TMPDIR:-/tmp}/aims-secret-scan.XXXXXX")"; trap 'rm -f "$scan_file"' EXIT
for pat in "${patterns[@]}"; do
  : > "$scan_file"
  while IFS= read -r -d '' file; do
    case "$file" in secrets/*.example|secrets/README.md) continue;; esac
    [ -f "$file" ] || continue
    { grep -InEo -- "$pat" "$file" 2>/dev/null || true; } | while IFS= read -r match; do
      if [ "$pat" = "$generic_pattern" ]; then
        payload="${match#*:}"
        value="$(printf '%s\n' "$payload" | sed -E "s/^$generic_prefix//")"
        if printf '%s\n' "$value" | grep -Eq "$placeholder_value"; then continue; fi
      fi
      printf '%s:%s\n' "$file" "$match" >> "$scan_file"
    done
  done < <(git ls-files --cached --others --exclude-standard -z)
  hits="$(<"$scan_file")"; [ -z "$hits" ] && continue
  printf 'ERROR: potential secret pattern matched: %s\n' "$pat" >&2
  printf '%s\n' "$hits" | cut -d: -f1-2 | sort -u >&2
  fail=1
done
[ "$fail" -eq 0 ] && echo "OK: no obvious secrets detected"
exit "$fail"
