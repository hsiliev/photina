#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_file=${PHOTINA_CONFIG:-$script_dir/photina.conf}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ -f "$config_file" ]] || die "configuration file does not exist: $config_file"
config_mode=$(stat -c '%a' -- "$config_file") || die "cannot read permissions for $config_file"
config_mode=$((0$config_mode))
(( (config_mode & 077) == 0 )) || die "$config_file must be private; run chmod 600 '$config_file'"

GUEST_ALBUMS=()
# shellcheck source=/dev/null
source "$config_file"

usage() {
  cat <<'EOF'
Usage: generate-gallery.sh [ALBUMS_DIR] [OUTPUT_DIR] [THUMBNAILS_DIR]

Arguments override the matching values from photina.conf.

Configuration:
  ALBUMS_DIR, OUTPUT_DIR, THUMBNAILS_DIR
  CADDYFILE, ADMIN_PASSWORD, GUEST_PASSWORD, GUEST_ALBUMS, THUMBNAIL_SIZE
EOF
}

thumbnail_size=${THUMBNAIL_SIZE:-250}
[[ "$thumbnail_size" =~ ^[1-9][0-9]*$ ]] || die "THUMBNAIL_SIZE must be a positive integer"

caddyfile=${CADDYFILE:-$script_dir/Caddyfile}
[[ -n "${ADMIN_PASSWORD:-}" ]] || die "ADMIN_PASSWORD must be set in $config_file"
[[ -n "${GUEST_PASSWORD:-}" ]] || die "GUEST_PASSWORD must be set in $config_file"

[[ $# -le 3 ]] || { usage >&2; exit 2; }
albums_dir=$(realpath -m -- "${1:-${ALBUMS_DIR:-/mnt/gallery/photos}}")
output_dir=$(realpath -m -- "${2:-${OUTPUT_DIR:-/mnt/gallery/dist}}")
thumbs_dir=$(realpath -m -- "${3:-${THUMBNAILS_DIR:-/mnt/gallery/thumbnails}}")

[[ -d "$albums_dir" ]] || die "albums directory does not exist: $albums_dir"
[[ "$output_dir/" != "$albums_dir/"* ]] || die "output directory must be outside albums directory"
[[ "$thumbs_dir/" != "$albums_dir/"* ]] || die "thumbnail directory must be outside albums directory"

command -v find >/dev/null || die "find is required"
command -v realpath >/dev/null || die "realpath is required"
command -v ffmpegthumbnailer >/dev/null || die "ffmpegthumbnailer is required"
command -v caddy >/dev/null || die "caddy is required to hash passwords and update $caddyfile"

# shellcheck source=/dev/null
source "$script_dir/lib/gallery.sh"
# shellcheck source=/dev/null
source "$script_dir/lib/caddy.sh"

generate_gallery "$script_dir" "$albums_dir" "$output_dir" "$thumbs_dir" "$thumbnail_size"
generate_caddyfile "$script_dir" "$caddyfile" "$albums_dir" "$output_dir" "$thumbs_dir" \
  "$ADMIN_PASSWORD" "$GUEST_PASSWORD" "${GUEST_ALBUMS[@]}"
