#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
config_file=${PHOTINA_CONFIG:-$script_dir/photina.conf}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
warn() { printf 'warning: %s\n' "$*" >&2; }

[[ -f "$config_file" ]] || die "configuration file does not exist: $config_file"
config_mode=$(stat -c '%a' -- "$config_file") || die "cannot read permissions for $config_file"
config_mode=$((0$config_mode))
(( (config_mode & 077) == 0 )) || warn "$config_file must be private; run chmod 600 '$config_file'"

GUEST_ALBUMS=()
# shellcheck source=photina.conf
# shellcheck disable=SC1091
source "$config_file"

usage() {
  cat <<'EOF'
Usage: generate.sh admin|guest

Generate the selected gallery output.
EOF
}

[[ $# -eq 1 ]] || { usage >&2; exit 2; }
gallery_target=$1
[[ "$gallery_target" == admin || "$gallery_target" == guest ]] || { usage >&2; exit 2; }

thumbnail_size=${THUMBNAIL_SIZE:-250}
[[ "$thumbnail_size" =~ ^[1-9][0-9]*$ ]] || die "THUMBNAIL_SIZE must be a positive integer"
thumbnail_display_mode=${THUMBNAIL_DISPLAY_MODE:-cascading}
[[ "$thumbnail_display_mode" =~ ^[A-Za-z]+$ ]] || die "THUMBNAIL_DISPLAY_MODE must be a mode name"

caddyfile=${CADDYFILE:-/etc/caddy/Caddyfile}
caddy_host=${HOST:-localhost}
caddy_port=${PORT:-80}
[[ "$caddy_host" =~ ^[A-Za-z0-9.-]+$ ]] || die "HOST must be a hostname"
[[ "$caddy_port" =~ ^[1-9][0-9]*$ && "$caddy_port" -le 65535 ]] || die "PORT must be between 1 and 65535"
[[ -n "${ADMIN_PASSWORD:-}" ]] || die "ADMIN_PASSWORD must be set in $config_file"
[[ -n "${GUEST_PASSWORD:-}" ]] || die "GUEST_PASSWORD must be set in $config_file"

[[ -n "${ALBUMS_DIR:-}" ]] || die "ALBUMS_DIR must be set in $config_file"
[[ -n "${OUTPUT_DIR:-}" ]] || die "OUTPUT_DIR must be set in $config_file"
[[ -n "${THUMBNAILS_DIR:-}" ]] || die "THUMBNAILS_DIR must be set in $config_file"
metadata_dir=$(realpath -m -- "${METADATA_DIR:-/mnt/gallery/metadata}")

albums_dir=$(realpath -m -- "$ALBUMS_DIR")
output_dir=$(realpath -m -- "$OUTPUT_DIR")
thumbs_dir=$(realpath -m -- "$THUMBNAILS_DIR")
admin_output_dir="$output_dir/admin"
guest_output_dir="$output_dir/guest"

printf 'Configured directories:\n'
printf '  ALBUMS_DIR: %s\n' "$albums_dir"
printf '  OUTPUT_DIR: %s\n' "$output_dir"
printf '  ADMIN_OUTPUT_DIR: %s\n' "$admin_output_dir"
printf '  GUEST_OUTPUT_DIR: %s\n' "$guest_output_dir"
printf '  THUMBNAILS_DIR: %s\n' "$thumbs_dir"
printf '  METADATA_DIR: %s\n' "$metadata_dir"
printf '  CADDYFILE: %s\n' "$caddyfile"

[[ -d "$albums_dir" ]] || die "albums directory does not exist: $albums_dir"
[[ "$output_dir/" != "$albums_dir/"* ]] || die "output directory must be outside albums directory"
[[ "$thumbs_dir/" != "$albums_dir/"* ]] || die "thumbnail directory must be outside albums directory"

command -v find >/dev/null || die "find is required"
command -v realpath >/dev/null || die "realpath is required"
command -v jq >/dev/null || die "jq is required to read image metadata"
command -v caddy >/dev/null || die "caddy is required to hash passwords and update $caddyfile"
command -v sudo >/dev/null || die "sudo is required to set ownership and permissions on $caddyfile"
command -v systemctl >/dev/null || die 'systemctl is required to reload caddy'

# shellcheck source=lib/gallery/main.sh
source "$script_dir/lib/gallery/main.sh"
# shellcheck source=lib/caddy.sh
source "$script_dir/lib/caddy.sh"

if [[ "$gallery_target" == admin ]]; then
  generate_gallery "$script_dir" "$albums_dir" "$admin_output_dir" \
    "$thumbs_dir" "$metadata_dir" "$thumbnail_size" "$thumbnail_display_mode"
fi
if [[ "$gallery_target" == guest ]]; then
  generate_gallery "$script_dir" "$albums_dir" "$guest_output_dir" \
    "$thumbs_dir" "$metadata_dir" "$thumbnail_size" "$thumbnail_display_mode" \
    "${GUEST_ALBUMS[@]}"
fi
generate_caddyfile "$script_dir" "$caddyfile" "$albums_dir" "$admin_output_dir" "$guest_output_dir" "$thumbs_dir" \
  "$caddy_host" "$caddy_port" "$ADMIN_PASSWORD" "$GUEST_PASSWORD" "${GUEST_ALBUMS[@]}"
sudo chown caddy:caddy -- "$caddyfile"
sudo chmod 644 -- "$caddyfile"
echo 'Reloading Caddy'
sudo systemctl reload caddy
