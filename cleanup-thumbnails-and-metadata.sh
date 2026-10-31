#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/common.sh
source "$script_dir/lib/common.sh"
# shellcheck source=lib/thumbnails.sh
source "$script_dir/lib/thumbnails.sh"

photina_load_config

[[ $# -eq 0 ]] || die 'usage: cleanup-thumbnails-and-metadata.sh'
[[ -n "${ALBUMS_DIR:-}" ]] || die "ALBUMS_DIR must be set in $config_file"
[[ -n "${THUMBNAILS_DIR:-}" ]] || die "THUMBNAILS_DIR must be set in $config_file"
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
while IFS= read -r -d '' album_path; do
  album_name=${album_path#"$albums_dir"/}; album_name=${album_name%/}
  printf 'Processing album for thumbnail and metadata cleanup: %s ...\n' "$album_name"
  media_file=$(mktemp)
  if ! thumbnail_list_media "$album_path" >"$media_file"; then
    rm -f -- "$media_file"
    die "could not scan album: $album_name"
  fi

  thumbnail_add_expected_outputs "$album_path" "$album_name" "$thumbs_dir" "$media_file" expected_thumbnails
  thumbnail_add_expected_metadata "$album_path" "$album_name" "$metadata_dir" "$media_file" expected_metadata expected_checksums
  rm -f -- "$media_file"
done < <(thumbnail_list_albums "$albums_dir")

echo "Cleaning redundant thumbnails and metadata in $thumbs_dir ..."
thumbnail_cleanup_stale "$albums_dir" "$thumbs_dir" expected_thumbnails
thumbnail_cleanup_stale_metadata "$albums_dir" "$metadata_dir" expected_metadata expected_checksums
