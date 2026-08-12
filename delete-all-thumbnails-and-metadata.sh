#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_file=${PHOTINA_CONFIG:-/etc/photina/photina.conf}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
[[ $# -eq 0 ]] || die 'usage: delete-all-thumbnails-and-metadata.sh'
[[ -f "$config_file" ]] || die "configuration file does not exist: $config_file"

# shellcheck source=/etc/photina/photina.conf
# shellcheck disable=SC1091
source "$config_file"
thumbnails_dir=$(realpath -m -- "${THUMBNAILS_DIR:-/mnt/gallery/thumbnails}")
metadata_dir=$(realpath -m -- "${METADATA_DIR:-/mnt/gallery/metadata}")
[[ "$thumbnails_dir" != / && "$metadata_dir" != / ]] || die 'refusing to delete the filesystem root'

rm -rf -- "$thumbnails_dir" "$metadata_dir"
printf 'Deleted thumbnails: %s\n' "$thumbnails_dir"
printf 'Deleted metadata: %s\n' "$metadata_dir"
