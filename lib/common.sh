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

# Locks live outside the directories they protect so stale-file cleanup and
# gallery deletion never see them. KIND is "cache" (thumbnail/metadata
# caches, keyed by the thumbnail directory) or "gallery" (generated output,
# keyed by OUTPUT_DIR, which also covers the shared Caddyfile).
photina_lock_path() {
  local kind=$1 key
  key=$(printf '%s' "$2" | cksum | cut -d' ' -f1)
  printf '%s/photina-%s-%s.lock' "${TMPDIR:-/tmp}" "$kind" "$key"
}

# Hold a non-blocking lock for the lifetime of the calling script (fd 9). The
# holder's PID and script name are written to the lock file. Locks are
# released automatically when the holder exits, so a leftover file does not
# block anything; deleting the file while a job still runs would let a second
# job start, which is the manual override.
photina_acquire_lock() {
  local kind=$1 target=$2 lock holder
  command -v flock >/dev/null || die 'flock is required'
  lock=$(photina_lock_path "$kind" "$target")
  exec 9>>"$lock" || die "cannot create lock file: $lock"
  if ! flock -n 9; then
    holder=$(<"$lock") || holder=
    warn "lock file ${lock} is held by: ${holder:-an unknown process}"
    warn "if no other Photina job is really running, delete the lock file and rerun: rm -- '$lock'"
    die "another Photina job is already using the $kind for $target"
  fi
  printf '%s %s\n' "$$" "${0##*/}" >"$lock"
}

photina_acquire_cache_lock() { photina_acquire_lock cache "$1"; }
photina_acquire_gallery_lock() { photina_acquire_lock gallery "$1"; }
