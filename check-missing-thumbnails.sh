#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_file=${PHOTINA_CONFIG:-/etc/photina/photina.conf}
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
warn() { printf 'warning: %s\n' "$*" >&2; }

[[ -f "$config_file" ]] || die "configuration file does not exist: $config_file"
config_mode=$(stat -c '%a' -- "$config_file") || die "cannot read permissions for $config_file"
config_mode=$((0$config_mode))
(( (config_mode & 077) == 0 )) || warn "$config_file must be private; run chmod 600 '$config_file'"

# shellcheck source=/etc/photina/photina.conf
# shellcheck disable=SC1091
source "$config_file"

[[ $# -eq 0 ]] || die 'usage: check-missing-thumbnails.sh'
[[ -n "${ALBUMS_DIR:-}" ]] || die "ALBUMS_DIR must be set in $config_file"
[[ -n "${THUMBNAILS_DIR:-}" ]] || die "THUMBNAILS_DIR must be set in $config_file"
command -v find >/dev/null || die 'find is required'
command -v realpath >/dev/null || die 'realpath is required'

albums_dir=$(realpath -m -- "$ALBUMS_DIR")
thumbs_dir=$(realpath -m -- "$THUMBNAILS_DIR")
[[ -d "$albums_dir" ]] || die "albums directory does not exist: $albums_dir"

# shellcheck source=lib/thumbnails.sh
source "$script_dir/lib/thumbnails.sh"

missing=0
echo 'Checking for missing thumbnails ...'
shopt -s nullglob
for root_album_path in "$albums_dir"/*/; do
  [[ -d "$root_album_path" ]] || continue
  while IFS= read -r -d '' album_path; do
    album_name=${album_path#"$albums_dir"/}; album_name=${album_name%/}
    media_file=$(mktemp)
    if ! { thumbnail_find_media "$album_path" image direct; thumbnail_find_media "$album_path" video direct; } |
      sort -z >"$media_file"; then
      rm -f -- "$media_file"
      die "could not scan album: $album_name"
    fi

    while IFS= read -r -d '' source; do
      relative=${source#"$album_path"}; relative=${relative#/}
      thumbnail="$thumbs_dir/$album_name/$relative.webp"
      for missing_path in "$thumbnail" "${thumbnail%.webp}_medium.webp"; do
        [[ -f "$missing_path" ]] && continue
        printf 'Missing thumbnail: %s\n' "${missing_path#"$thumbs_dir"/}"
        missing=1
      done
      if thumbnail_needs_web_video "$source"; then
        missing_path="${thumbnail%.webp}.web.mp4"
        if [[ ! -f "$missing_path" ]]; then
          printf 'Missing thumbnail: %s\n' "${missing_path#"$thumbs_dir"/}"
          missing=1
        fi
      fi
    done <"$media_file"
    rm -f -- "$media_file"
  done < <(find -P "$root_album_path" -type d -print0 | sort -z)
done

if (( missing != 0 )); then
  exit 1
fi
echo 'No missing thumbnails found'
