#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/common.sh
source "$script_dir/lib/common.sh"
# shellcheck source=lib/thumbnails.sh
source "$script_dir/lib/thumbnails.sh"

photina_load_config

[[ $# -eq 0 ]] || die 'usage: check-missing-thumbnails.sh'
[[ -n "${ALBUMS_DIR:-}" ]] || die "ALBUMS_DIR must be set in $config_file"
[[ -n "${THUMBNAILS_DIR:-}" ]] || die "THUMBNAILS_DIR must be set in $config_file"
command -v find >/dev/null || die 'find is required'
command -v realpath >/dev/null || die 'realpath is required'

albums_dir=$(realpath -m -- "$ALBUMS_DIR")
thumbs_dir=$(realpath -m -- "$THUMBNAILS_DIR")
[[ -d "$albums_dir" ]] || die "albums directory does not exist: $albums_dir"

missing=0
declare -A expected_thumbnails=()
while IFS= read -r -d '' album_path; do
  album_name=${album_path#"$albums_dir"/}; album_name=${album_name%/}
  media_file=$(mktemp)
  if ! thumbnail_list_media "$album_path" >"$media_file"; then
    rm -f -- "$media_file"
    die "could not scan album: $album_name"
  fi

  thumbnail_add_expected_outputs "$album_path" "$album_name" "$thumbs_dir" "$media_file" expected_thumbnails
  rm -f -- "$media_file"
done < <(thumbnail_list_albums "$albums_dir")

echo 'Checking for missing thumbnails ...'
for thumbnail in "${!expected_thumbnails[@]}"; do
  [[ -f "$thumbnail" ]] && continue
  printf 'Missing thumbnail: %s\n' "${thumbnail#"$thumbs_dir"/}"
  missing=1
done

if (( missing != 0 )); then
  exit 1
fi
echo 'No missing thumbnails found'
