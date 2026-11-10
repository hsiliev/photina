#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/common.sh
source "$script_dir/lib/common.sh"
# shellcheck source=lib/thumbnails.sh
source "$script_dir/lib/thumbnails.sh"

photina_load_config

[[ $# -eq 0 ]] || die 'usage: cleanup-thumbnails-and-metadata.sh'
photina_require_config ALBUMS_DIR THUMBNAILS_DIR
command -v find >/dev/null || die 'find is required'
command -v realpath >/dev/null || die 'realpath is required'

albums_dir=$(realpath -m -- "$ALBUMS_DIR")
thumbs_dir=$(realpath -m -- "$THUMBNAILS_DIR")
metadata_dir=$(realpath -m -- "${METADATA_DIR:-/mnt/gallery/metadata}")
[[ -d "$albums_dir" ]] || die "albums directory does not exist: $albums_dir"

photina_acquire_cache_lock "$thumbs_dir"

# shellcheck disable=SC2034 # passed by name to functions that use namerefs
declare -A expected_thumbnails=()
# shellcheck disable=SC2034 # passed by name to functions that use namerefs
declare -A expected_metadata=() expected_checksums=()
thumbnail_collect_expected "$albums_dir" "$thumbs_dir" expected_thumbnails \
  "$metadata_dir" expected_metadata expected_checksums \
  'Processing album for thumbnail and metadata cleanup: %s ...\n'

echo "Cleaning redundant thumbnails and metadata in $thumbs_dir ..."
thumbnail_cleanup_stale "$albums_dir" "$thumbs_dir" expected_thumbnails
thumbnail_cleanup_stale_metadata "$albums_dir" "$metadata_dir" expected_metadata expected_checksums
