#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <input_bin> <output_bin> <executable>" >&2
  exit 1
fi

in_bin="$1"
out_bin="$2"
exe="$3"

if [[ ! -x "$exe" ]]; then
  echo "Error: executable is not found or not executable: $exe" >&2
  exit 1
fi

if [[ ! -f "$in_bin" ]]; then
  echo "Error: input file not found: $in_bin" >&2
  exit 1
fi

printf "%s\n%s\n" "$in_bin" "$out_bin" | "$exe" > /dev/null
