#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <n> <executable>" >&2
  exit 1
fi

n="$1"
exe="$2"

if ! [[ "$n" =~ ^[0-9]+$ ]] || [[ "$n" -le 0 ]]; then
  echo "Error: n must be a positive integer" >&2
  exit 1
fi

if [[ ! -x "$exe" ]]; then
  echo "Error: executable is not found or not executable: $exe" >&2
  exit 1
fi

tmp_input="$(mktemp)"
cleanup() {
  rm -f "$tmp_input"
}
trap cleanup EXIT

{
  echo "$n"
  edge=33554432
  awk -v min="$edge" -v max="-$edge" -v n="$n" 'BEGIN{ for (i = 1; i <= n; ++i) { srand(); print int(min+rand()*(max-min+1)) } }'
  awk -v min="$edge" -v max="-$edge" -v n="$n" 'BEGIN{ for (i = 1; i <= n; ++i) { srand(); print int(min+rand()*(max-min+1)) } }'
} > "$tmp_input"

"$exe" < "$tmp_input"