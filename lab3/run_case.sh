#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <executable> <input_bin> <output_bin> <samples_file>" >&2
  exit 1
fi

exe="$1"
in_bin="$2"
out_bin="$3"
samples="$4"

if [[ ! -x "$exe" ]]; then
  echo "Error: executable not found: $exe" >&2
  exit 1
fi
if [[ ! -f "$in_bin" ]]; then
  echo "Error: input image not found: $in_bin" >&2
  exit 1
fi
if [[ ! -f "$samples" ]]; then
  echo "Error: samples file not found: $samples" >&2
  exit 1
fi

{
  echo "$in_bin"
  echo "$out_bin"
  cat "$samples"
} | "$exe" > /dev/null
