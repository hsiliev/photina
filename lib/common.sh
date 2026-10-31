#!/usr/bin/env bash

# Helpers shared by the command scripts, thumbnail library, and gallery
# generator.

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
warn() { printf 'warning: %s\n' "$*" >&2; }

# Source the Photina configuration file, warning when it is not private.
# Callers may predefine defaults (such as GUEST_ALBUMS=()) before calling.
photina_load_config() {
  local mode
  config_file=${PHOTINA_CONFIG:-/etc/photina/photina.conf}
  [[ -f "$config_file" ]] || die "configuration file does not exist: $config_file"
  mode=$(stat -c '%a' -- "$config_file") || die "cannot read permissions for $config_file"
  mode=$((0$mode))
  (( (mode & 077) == 0 )) || warn "$config_file must be private; run chmod 600 '$config_file'"
  # shellcheck source=/etc/photina/photina.conf
  # shellcheck disable=SC1091
  source "$config_file"
}

photina_core_count() {
  local cores=1
  if command -v nproc >/dev/null; then
    cores=$(nproc)
  fi
  (( cores > 0 )) || cores=1
  printf '%s\n' "$cores"
}

photina_is_video() {
  local extension=${1##*.}
  extension=${extension,,}
  case "$extension" in
    mp4|m4v|mov|mkv|webm|avi|mpeg|mpg|ts|mts) return 0 ;;
    *) return 1 ;;
  esac
}

# Videos other than MP4 get a browser-compatible .web.mp4 companion.
photina_needs_web_video() {
  local extension=${1##*.}
  extension=${extension,,}
  [[ "$extension" != mp4 ]] && photina_is_video "$1"
}

