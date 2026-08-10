#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_file=${PHOTINA_CONFIG:-$script_dir/photina.conf}
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
warn() { printf 'warning: %s\n' "$*" >&2; }

[[ -f "$config_file" ]] || die "configuration file does not exist: $config_file"
config_mode=$(stat -c '%a' -- "$config_file") || die "cannot read permissions for $config_file"
config_mode=$((0$config_mode))
(( (config_mode & 077) == 0 )) || warn "$config_file must be private; run chmod 600 '$config_file'"

# shellcheck source=photina.conf
# shellcheck disable=SC1091
source "$config_file"

[[ $# -eq 0 ]] || die 'usage: update-thumbnails.sh'

[[ -n "${ALBUMS_DIR:-}" ]] || die "ALBUMS_DIR must be set in $config_file"
[[ -n "${THUMBNAILS_DIR:-}" ]] || die "THUMBNAILS_DIR must be set in $config_file"
metadata_dir=$(realpath -m -- "${METADATA_DIR:-/mnt/gallery/metadata}")
thumbnail_size=${THUMBNAIL_SIZE:-250}
[[ "$thumbnail_size" =~ ^[1-9][0-9]*$ ]] || die 'THUMBNAIL_SIZE must be a positive integer'
medium_size=${MEDIUM_SIZE:-1600}
[[ "$medium_size" =~ ^[1-9][0-9]*$ ]] || die 'MEDIUM_SIZE must be a positive integer'

albums_dir=$(realpath -m -- "$ALBUMS_DIR")
thumbs_dir=$(realpath -m -- "$THUMBNAILS_DIR")
printf 'Configured metadata directory: %s\n' "$metadata_dir"
[[ -d "$albums_dir" ]] || die "albums directory does not exist: $albums_dir"
command -v find >/dev/null || die 'find is required'
command -v realpath >/dev/null || die 'realpath is required'
command -v ffmpegthumbnailer >/dev/null || die 'ffmpegthumbnailer is required'
command -v exiftool >/dev/null || die 'exiftool is required to write metadata'
command -v jq >/dev/null || die 'jq is required to minify metadata'
command -v ffmpeg >/dev/null || die 'ffmpeg is required to create browser-compatible videos'
command -v sudo >/dev/null || die 'sudo is required to check Caddy access'

output_dir=$(realpath -m -- "${OUTPUT_DIR:-/mnt/gallery/dist}")

check_caddy_access() {
  local path current
  local -a access_paths=("$albums_dir" "$thumbs_dir" "$output_dir")

  echo 'Checking Caddy access to gallery directories'
  for path in "${access_paths[@]}"; do
    [[ -d "$path" ]] || continue
    if sudo -u caddy test -r "$path" -a -x "$path"; then
      echo "  accessible: $path"
    else
      warn "Caddy cannot read/traverse $path"
    fi

    current=$(dirname -- "$path")
    while [[ "$current" != / ]]; do
      sudo -u caddy test -x "$current" || warn "Caddy cannot traverse $current"
      current=$(dirname -- "$current")
    done
  done
}

# shellcheck source=lib/thumbnails.sh
source "$script_dir/lib/thumbnails.sh"
check_caddy_access
update_thumbnails "$albums_dir" "$thumbs_dir" "$metadata_dir" "$thumbnail_size" "$medium_size"
