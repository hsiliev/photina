#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_file=${PHOTINA_CONFIG:-$script_dir/photina.conf}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
[[ $# -eq 0 ]] || die 'usage: delete-gallery.sh'
[[ -f "$config_file" ]] || die "configuration file does not exist: $config_file"

# shellcheck source=photina.conf
# shellcheck disable=SC1091
source "$config_file"
output_dir=$(realpath -m -- "${OUTPUT_DIR:-/mnt/gallery/dist}")
[[ "$output_dir" != / ]] || die 'refusing to delete the filesystem root'

if [[ -e "$output_dir" ]]; then
  rm -rf -- "$output_dir"
  printf 'Deleted gallery: %s\n' "$output_dir"
else
  printf 'Gallery does not exist: %s\n' "$output_dir"
fi
