#!/usr/bin/env bash

# shellcheck source=lib/common.sh
source "${BASH_SOURCE[0]%/*}/../common.sh"

gallery_delete_output() {
  local config_file=$1 gallery_target=$2
  local output_dir delete_dir

  [[ -f "$config_file" ]] || {
    printf 'error: configuration file does not exist: %s\n' "$config_file" >&2
    return 1
  }
  # shellcheck disable=SC1090
  source "$config_file"
  output_dir=$(realpath -m -- "${OUTPUT_DIR:-/mnt/gallery/dist}")
  [[ "$output_dir" != / ]] || {
    printf 'error: refusing to delete the filesystem root\n' >&2
    return 1
  }
  delete_dir="$output_dir/$gallery_target"
  photina_acquire_gallery_lock "$output_dir"

  if [[ -e "$delete_dir" ]]; then
    rm -rf -- "$delete_dir"
    printf 'Deleted %s gallery: %s\n' "$gallery_target" "$delete_dir"
  else
    printf '%s gallery does not exist: %s\n' "$gallery_target" "$delete_dir"
  fi
}
