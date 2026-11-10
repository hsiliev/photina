#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/common.sh
source "$script_dir/lib/common.sh"
# shellcheck source=lib/thumbnails.sh
source "$script_dir/lib/thumbnails.sh"

photina_load_config

[[ $# -eq 0 ]] || die 'usage: check-missing-thumbnails.sh'
photina_require_config ALBUMS_DIR THUMBNAILS_DIR
command -v find >/dev/null || die 'find is required'
command -v realpath >/dev/null || die 'realpath is required'

albums_dir=$(realpath -m -- "$ALBUMS_DIR")
thumbs_dir=$(realpath -m -- "$THUMBNAILS_DIR")
[[ -d "$albums_dir" ]] || die "albums directory does not exist: $albums_dir"

missing=0
# shellcheck disable=SC2034 # passed by name to functions that use namerefs
declare -A expected_thumbnails=()
thumbnail_collect_expected "$albums_dir" "$thumbs_dir" expected_thumbnails

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
