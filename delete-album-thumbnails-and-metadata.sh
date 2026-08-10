#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_file=${PHOTINA_CONFIG:-$script_dir/photina.conf}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
[[ $# -eq 1 ]] || die 'usage: delete-album-thumbnails-and-metadata.sh ALBUM_NAME'
album_name=$1
[[ -f "$config_file" ]] || die "configuration file does not exist: $config_file"
[[ "$album_name" != /* && "$album_name" != . && "$album_name" != .. && "$album_name" != */../* && "$album_name" != ../* && "$album_name" != */.. ]] || die 'album name must stay inside the configured directories'

# shellcheck source=photina.conf
# shellcheck disable=SC1091
source "$config_file"
thumbnails_dir=$(realpath -m -- "${THUMBNAILS_DIR:-/mnt/gallery/thumbnails}")
metadata_dir=$(realpath -m -- "${METADATA_DIR:-/mnt/gallery/metadata}")
thumbnail_target=$(realpath -m -- "$thumbnails_dir/$album_name")
metadata_target=$(realpath -m -- "$metadata_dir/$album_name")
[[ "$thumbnail_target" == "$thumbnails_dir"/* && "$metadata_target" == "$metadata_dir"/* ]] || die 'album target must stay inside the configured directories'

rm -rf -- "$thumbnail_target" "$metadata_target"
printf 'Deleted album thumbnails: %s\n' "$thumbnail_target"
printf 'Deleted album metadata: %s\n' "$metadata_target"
