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
Usage: generate-gallery.sh

Check the configuration in photina.conf
EOF
}

thumbnail_size=${THUMBNAIL_SIZE:-250}
[[ "$thumbnail_size" =~ ^[1-9][0-9]*$ ]] || die "THUMBNAIL_SIZE must be a positive integer"

caddyfile=${CADDYFILE:-/etc/caddy/Caddyfile}
[[ -n "${ADMIN_PASSWORD:-}" ]] || die "ADMIN_PASSWORD must be set in $config_file"
[[ -n "${GUEST_PASSWORD:-}" ]] || die "GUEST_PASSWORD must be set in $config_file"

[[ $# -eq 0 ]] || { usage >&2; exit 2; }
[[ -n "${ALBUMS_DIR:-}" ]] || die "ALBUMS_DIR must be set in $config_file"
[[ -n "${OUTPUT_DIR:-}" ]] || die "OUTPUT_DIR must be set in $config_file"
[[ -n "${THUMBNAILS_DIR:-}" ]] || die "THUMBNAILS_DIR must be set in $config_file"

albums_dir=$(realpath -m -- "$ALBUMS_DIR")
output_dir=$(realpath -m -- "$OUTPUT_DIR")
thumbs_dir=$(realpath -m -- "$THUMBNAILS_DIR")

printf 'Configured directories:\n'
printf '  ALBUMS_DIR: %s\n' "$albums_dir"
printf '  OUTPUT_DIR: %s\n' "$output_dir"
printf '  THUMBNAILS_DIR: %s\n' "$thumbs_dir"
printf '  CADDYFILE: %s\n' "$caddyfile"

[[ -d "$albums_dir" ]] || die "albums directory does not exist: $albums_dir"
[[ "$output_dir/" != "$albums_dir/"* ]] || die "output directory must be outside albums directory"
[[ "$thumbs_dir/" != "$albums_dir/"* ]] || die "thumbnail directory must be outside albums directory"

command -v find >/dev/null || die "find is required"
command -v realpath >/dev/null || die "realpath is required"
command -v ffmpegthumbnailer >/dev/null || die "ffmpegthumbnailer is required"
command -v caddy >/dev/null || die "caddy is required to hash passwords and update $caddyfile"

# shellcheck source=/dev/null
source "$script_dir/lib/thumbnails.sh"
# shellcheck source=/dev/null
source "$script_dir/lib/gallery.sh"
# shellcheck source=/dev/null
source "$script_dir/lib/caddy.sh"

update_thumbnails "$albums_dir" "$thumbs_dir" "$thumbnail_size"
generate_gallery "$script_dir" "$albums_dir" "$output_dir" "$thumbs_dir" "$thumbnail_size"
generate_caddyfile "$script_dir" "$caddyfile" "$albums_dir" "$output_dir" "$thumbs_dir" \
  "$ADMIN_PASSWORD" "$GUEST_PASSWORD" "${GUEST_ALBUMS[@]}"
