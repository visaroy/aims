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
inventory_file="$(mktemp "${TMPDIR:-/tmp}/aims-secret-scan-inventory.XXXXXX")" || { echo 'ERROR: unable to create secret scan inventory' >&2; exit 1; }
scan_inventory="$(mktemp "${TMPDIR:-/tmp}/aims-secret-scan-files.XXXXXX")" || { echo 'ERROR: unable to create secret scan file list' >&2; rm -f "$inventory_file"; exit 1; }
special_inventory="$(mktemp "${TMPDIR:-/tmp}/aims-secret-scan-special-files.XXXXXX")" || { echo 'ERROR: unable to create special secret scan file list' >&2; rm -f "$inventory_file" "$scan_inventory"; exit 1; }
scan_file="$(mktemp "${TMPDIR:-/tmp}/aims-secret-scan-findings.XXXXXX")" || { echo 'ERROR: unable to create secret scan findings file' >&2; rm -f "$inventory_file" "$scan_inventory" "$special_inventory"; exit 1; }
batch_output="$(mktemp "${TMPDIR:-/tmp}/aims-secret-scan-output.XXXXXX")" || { echo 'ERROR: unable to create secret scan batch output file' >&2; rm -f "$inventory_file" "$scan_inventory" "$special_inventory" "$scan_file"; exit 1; }
batch_runner="$(mktemp "${TMPDIR:-/tmp}/aims-secret-scan-runner.XXXXXX")" || { echo 'ERROR: unable to create secret scan batch runner' >&2; rm -f "$inventory_file" "$scan_inventory" "$special_inventory" "$scan_file" "$batch_output"; exit 1; }
trap 'rm -f "$inventory_file" "$scan_inventory" "$special_inventory" "$scan_file" "$batch_output" "$batch_runner"' EXIT
cat > "$batch_runner" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
pattern="$1"; mode="$2"; shift 2
[ "$#" -gt 0 ] || exit 0
grep_pattern="$pattern"
case "$pattern" in
  '-----BEGIN (RSA |OPENSSH |DSA |EC |)PRIVATE KEY-----') grep_pattern='-----BEGIN (RSA |OPENSSH |DSA |EC )?PRIVATE KEY-----' ;; # Equivalent BSD-compatible form; attribution remains exact.
esac
case "$mode" in
  normal)
    set +e
    matches="$(grep -HInEo -- "$grep_pattern" "$@" 2>/dev/null)"
    status=$?
    set -e
    [ -n "$matches" ] && printf '%s\n' "$matches"
    case "$status" in 0|1) exit 0;; *) exit "$status";; esac
    ;;
  special)
    overall_status=0
    for file in "$@"; do
      set +e
      matches="$(grep -hInEo -- "$grep_pattern" "$file" 2>/dev/null)"
      status=$?
      set -e
      if [ -n "$matches" ]; then
        while IFS= read -r match; do
          [ -n "$match" ] || continue
          case "$match" in *:*) ;; *) overall_status=2; continue;; esac
          line="${match%%:*}"; payload="${match#*:}"
          case "$line" in ''|*[!0-9]*) overall_status=2; continue;; esac
          printf '%s\0%s\0%s\0' "$file" "$line" "$payload"
        done <<< "$matches"
      fi
      case "$status" in
        0|1) ;;
        *) [ "$overall_status" -eq 0 ] && overall_status="$status" ;;
      esac
    done
    exit "$overall_status"
    ;;
  *) exit 64;;
esac
EOF
chmod 700 "$batch_runner" || { echo 'ERROR: unable to prepare secret scan batch runner' >&2; exit 1; }
if ! git ls-files --cached --others --exclude-standard -z > "$inventory_file"; then
  echo 'ERROR: unable to enumerate files for secret scan' >&2
  exit 1
fi
inventory_size="$(wc -c < "$inventory_file")" || { echo 'ERROR: unable to parse secret scan inventory' >&2; exit 1; }
if [ "$inventory_size" -gt 0 ]; then
  if ! final_byte="$(tail -c 1 "$inventory_file" | od -An -tx1 | tr -d '[:space:]')" || [ "$final_byte" != 00 ]; then
    echo 'ERROR: unable to parse secret scan inventory' >&2
    exit 1
  fi
fi
prepare_inventory() {
  local file
  while IFS= read -r -d '' file; do
    case "$file" in secrets/*.example|secrets/README.md) continue;; esac
    [ -f "$file" ] || continue
    case "$file" in
      *:*|*$'\n'*|*\\*) printf '%s\0' "$file" >> "$special_inventory" || return 1 ;;
      *) printf '%s\0' "$file" >> "$scan_inventory" || return 1 ;;
    esac
  done < "$inventory_file"
}
if ! prepare_inventory; then
  echo 'ERROR: unable to prepare secret scan file lists' >&2
  exit 1
fi
nul_terminated() {
  local path="$1" size final_byte
  size="$(wc -c < "$path")" || return 1
  [ "$size" -eq 0 ] && return 0
  final_byte="$(tail -c 1 "$path" | od -An -tx1 | tr -d '[:space:]')" || return 1
  [ "$final_byte" = 00 ]
}
record_finding() {
  local file="$1" line="$2" payload="$3" mode="$4" value placeholder_status escaped_file
  case "$file" in ''|*$'\n'*) [ "$mode" = special ] || return 1;; esac
  case "$line" in ''|*[!0-9]*) return 1;; esac
  [ -f "$file" ] || return 1
  if [ "$pat" = "$generic_pattern" ]; then
    if value="$(printf '%s\n' "$payload" | sed -E "s/^$generic_prefix//")"; then
      if printf '%s\n' "$value" | grep -Eq "$placeholder_value"; then
        return 2
      else
        placeholder_status=$?
        [ "$placeholder_status" -eq 1 ] || return 1
      fi
    else
      return 1
    fi
  fi
  if [ "$mode" = special ]; then
    if ! escaped_file="$(python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.argv[1], ensure_ascii=True))' "$file" 2>/dev/null)"; then
      return 1
    fi
    printf '%s:%s\n' "$escaped_file" "$line" >> "$scan_file"
  else
    printf '%s:%s\n' "$file" "$line" >> "$scan_file"
  fi
}
process_batch_output() {
  local mode="$1" match file rest line payload record_status
  local parse_failed=0
  if [ "$mode" = special ]; then
    if ! nul_terminated "$batch_output"; then
      return 1
    fi
    while IFS= read -r -d '' file; do
      if ! IFS= read -r -d '' line || ! IFS= read -r -d '' payload; then
        parse_failed=1
        break
      fi
      if record_finding "$file" "$line" "$payload" special; then
        :
      else
        record_status=$?
        [ "$record_status" -eq 2 ] || parse_failed=1
      fi
    done < "$batch_output"
  else
    while IFS= read -r match; do
      [ -n "$match" ] || { parse_failed=1; continue; }
      case "$match" in *:*) ;; *) parse_failed=1; continue;; esac
      file="${match%%:*}"; rest="${match#*:}"
      case "$file" in ''|*:*|*$'\n'*) parse_failed=1; continue;; esac
      case "$rest" in *:*) ;; *) parse_failed=1; continue;; esac
      line="${rest%%:*}"; payload="${rest#*:}"
      if record_finding "$file" "$line" "$payload" normal; then
        :
      else
        record_status=$?
        [ "$record_status" -eq 2 ] || parse_failed=1
      fi
    done < "$batch_output"
  fi
  [ "$parse_failed" -eq 0 ]
}
scan_inventory_batches() {
  local mode="$1" inventory="$2" batch_size xargs_status parse_status
  [ -s "$inventory" ] || return 0
  : > "$batch_output" || return 1
  [ "$mode" = normal ] && batch_size=128 || batch_size=16
  xargs_status=0
  if xargs -0 -n "$batch_size" "$batch_runner" "$pat" "$mode" < "$inventory" > "$batch_output" 2>/dev/null; then
    :
  else
    xargs_status=$?
  fi
  parse_status=0
  if ! process_batch_output "$mode"; then
    parse_status=1
  fi
  if [ "$xargs_status" -ne 0 ]; then
    printf 'ERROR: unable to scan a secret batch for pattern: %s\n' "$pat" >&2
  fi
  if [ "$parse_status" -ne 0 ]; then
    echo 'ERROR: unable to parse secret scan batch output' >&2
  fi
  [ "$xargs_status" -eq 0 ] && [ "$parse_status" -eq 0 ]
}
for pat in "${patterns[@]}"; do
  : > "$scan_file" || { echo 'ERROR: unable to write secret scan findings' >&2; exit 1; }
  pattern_failed=0
  if ! scan_inventory_batches normal "$scan_inventory"; then pattern_failed=1; fi
  if ! scan_inventory_batches special "$special_inventory"; then pattern_failed=1; fi
  if [ -s "$scan_file" ]; then
    printf 'ERROR: potential secret pattern matched: %s\n' "$pat" >&2
    fail=1
    if ! sort -u "$scan_file" >&2; then
      pattern_failed=1
    fi
  fi
  [ "$pattern_failed" -eq 0 ] || fail=1
done
[ "$fail" -eq 0 ] && echo "OK: no obvious secrets detected"
exit "$fail"
