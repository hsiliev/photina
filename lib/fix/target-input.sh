#!/usr/bin/env bash

fix_emit_target_records() {
  local input="$1"
  local script_dir="$2"

  if [[ -f "$input" ]]; then
    python3 "$script_dir/lib/fix/parse-whereisit-xml.py" "$input"
  else
    find "$input" -maxdepth 1 -type f -printf '%f\t%s\t%T@\t%B@\t%TY:%Tm:%Td\t%BY:%Bm:%Bd\n'
  fi
}
