#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_file=${PHOTINA_CONFIG:-/etc/photina/photina.conf}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
warn() { printf 'warning: %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: update-caddy.sh

Regenerate Photina's managed Caddy configuration and reload Caddy.
EOF
}

[[ $# -eq 0 ]] || { usage >&2; exit 2; }
[[ -f "$config_file" ]] || die "configuration file does not exist: $config_file"
config_mode=$(stat -c '%a' -- "$config_file") || die "cannot read permissions for $config_file"
config_mode=$((0$config_mode))
(( (config_mode & 077) == 0 )) || warn "$config_file must be private; run chmod 600 '$config_file'"

GUEST_ALBUMS=()
# shellcheck source=/etc/photina/photina.conf
# shellcheck disable=SC1091
source "$config_file"

[[ -n "${ALBUMS_DIR:-}" ]] || die "ALBUMS_DIR must be set in $config_file"
[[ -n "${OUTPUT_DIR:-}" ]] || die "OUTPUT_DIR must be set in $config_file"
[[ -n "${THUMBNAILS_DIR:-}" ]] || die "THUMBNAILS_DIR must be set in $config_file"
[[ -n "${ADMIN_PASSWORD:-}" ]] || die "ADMIN_PASSWORD must be set in $config_file"
[[ -n "${GUEST_PASSWORD:-}" ]] || die "GUEST_PASSWORD must be set in $config_file"
command -v realpath >/dev/null || die 'realpath is required'

caddyfile=${CADDYFILE:-/etc/caddy/Caddyfile}
caddy_host=${HOST:-localhost}
caddy_port=${PORT:-443}
[[ "$caddy_host" =~ ^[A-Za-z0-9.-]+$ ]] || die "HOST must be a hostname"
[[ "$caddy_port" =~ ^[1-9][0-9]*$ && "$caddy_port" -le 65535 ]] ||
  die "PORT must be between 1 and 65535"

albums_dir=$(realpath -m -- "$ALBUMS_DIR")
output_dir=$(realpath -m -- "$OUTPUT_DIR")
thumbs_dir=$(realpath -m -- "$THUMBNAILS_DIR")
admin_output_dir="$output_dir/admin"
guest_output_dir="$output_dir/guest"

command -v caddy >/dev/null || die "caddy is required to hash passwords and update $caddyfile"
command -v sudo >/dev/null || die "sudo is required to set ownership and permissions on $caddyfile"
command -v systemctl >/dev/null || die 'systemctl is required to reload caddy'

# shellcheck source=lib/caddy.sh
source "$script_dir/lib/caddy.sh"
generate_caddyfile "$script_dir" "$caddyfile" "$albums_dir" "$admin_output_dir" "$guest_output_dir" "$thumbs_dir" \
  "$caddy_host" "$caddy_port" "$ADMIN_PASSWORD" "$GUEST_PASSWORD" "${GUEST_ALBUMS[@]}"
sudo chown caddy:caddy -- "$caddyfile"
sudo chmod 644 -- "$caddyfile"
echo 'Reloading Caddy'
sudo systemctl reload caddy
