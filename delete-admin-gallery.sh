#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_file=${PHOTINA_CONFIG:-/etc/photina/photina.conf}
[[ $# -eq 0 ]] || { printf 'usage: delete-admin-gallery.sh\n' >&2; exit 2; }
# shellcheck source=lib/gallery/delete.sh
source "$script_dir/lib/gallery/delete.sh"
gallery_delete_output "$config_file" admin
