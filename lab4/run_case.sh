#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <executable> <input_file> <output_file>" >&2
  exit 1
fi

exe="$1"
in_file="$2"
out_file="$3"

if [[ ! -x "$exe" ]]; then
  echo "Error: executable not found: $exe" >&2
  exit 1
fi
if [[ ! -f "$in_file" ]]; then
  echo "Error: input file not found: $in_file" >&2
  exit 1
fi

"$exe" < "$in_file" > "$out_file"
