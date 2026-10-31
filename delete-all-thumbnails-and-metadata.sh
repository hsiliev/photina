#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/common.sh
source "$script_dir/lib/common.sh"

[[ $# -eq 0 ]] || die 'usage: delete-all-thumbnails-and-metadata.sh'

photina_load_config
thumbnails_dir=$(realpath -m -- "${THUMBNAILS_DIR:-/mnt/gallery/thumbnails}")
metadata_dir=$(realpath -m -- "${METADATA_DIR:-/mnt/gallery/metadata}")
photina_acquire_cache_lock "$thumbnails_dir"
[[ "$thumbnails_dir" != / && "$metadata_dir" != / ]] || die 'refusing to delete the filesystem root'

rm -rf -- "$thumbnails_dir" "$metadata_dir"
printf 'Deleted thumbnails: %s\n' "$thumbnails_dir"
printf 'Deleted metadata: %s\n' "$metadata_dir"
