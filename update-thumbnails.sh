#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_file=${PHOTINA_CONFIG:-$script_dir/photina.conf}
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ -f "$config_file" ]] || die "configuration file does not exist: $config_file"
config_mode=$(stat -c '%a' -- "$config_file") || die "cannot read permissions for $config_file"
config_mode=$((0$config_mode))
(( (config_mode & 077) == 0 )) || die "$config_file must be private; run chmod 600 '$config_file'"

# shellcheck source=/dev/null
source "$config_file"

force=0
if [[ $# -gt 0 ]]; then
  [[ $# -eq 1 && $1 == --force ]] || die 'usage: update-thumbnails.sh [--force]'
  force=1
fi

[[ -n "${ALBUMS_DIR:-}" ]] || die "ALBUMS_DIR must be set in $config_file"
[[ -n "${THUMBNAILS_DIR:-}" ]] || die "THUMBNAILS_DIR must be set in $config_file"
thumbnail_size=${THUMBNAIL_SIZE:-250}
[[ "$thumbnail_size" =~ ^[1-9][0-9]*$ ]] || die 'THUMBNAIL_SIZE must be a positive integer'

albums_dir=$(realpath -m -- "$ALBUMS_DIR")
thumbs_dir=$(realpath -m -- "$THUMBNAILS_DIR")
[[ -d "$albums_dir" ]] || die "albums directory does not exist: $albums_dir"
command -v find >/dev/null || die 'find is required'
command -v realpath >/dev/null || die 'realpath is required'
command -v ffmpegthumbnailer >/dev/null || die 'ffmpegthumbnailer is required'

# shellcheck source=/dev/null
source "$script_dir/lib/thumbnails.sh"
update_thumbnails "$albums_dir" "$thumbs_dir" "$thumbnail_size" "$force"
