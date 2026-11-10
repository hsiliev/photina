#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/common.sh
source "$script_dir/lib/common.sh"

photina_load_config

[[ $# -eq 0 ]] || die 'usage: update-thumbnails.sh'

photina_require_config ALBUMS_DIR THUMBNAILS_DIR
metadata_dir=$(realpath -m -- "${METADATA_DIR:-/mnt/gallery/metadata}")
thumbnail_size=${THUMBNAIL_SIZE:-250}
[[ "$thumbnail_size" =~ ^[1-9][0-9]*$ ]] || die 'THUMBNAIL_SIZE must be a positive integer'
me_size=${MEDIUM_SIZE:-1600}
[[ "$me_size" =~ ^[1-9][0-9]*$ ]] || die 'MEDIUM_SIZE must be a positive integer'
display_mode=${THUMBNAIL_DISPLAY_MODE:-cascading}
[[ "$display_mode" =~ ^[A-Za-z]+$ ]] || die 'THUMBNAIL_DISPLAY_MODE must be a mode name'

albums_dir=$(realpath -m -- "$ALBUMS_DIR")
thumbs_dir=$(realpath -m -- "$THUMBNAILS_DIR")
printf 'Configured metadata directory: %s\n' "$metadata_dir"
[[ -d "$albums_dir" ]] || die "albums directory does not exist: $albums_dir"
command -v find >/dev/null || die 'find is required'
command -v md5sum >/dev/null || die 'md5sum is required to generate checksums'
command -v realpath >/dev/null || die 'realpath is required'
command -v ffmpegthumbnailer >/dev/null || die 'ffmpegthumbnailer is required'
command -v exiftool >/dev/null || die 'exiftool is required to write metadata'
command -v jq >/dev/null || die 'jq is required to minify metadata'
command -v ffmpeg >/dev/null || die 'ffmpeg is required to create browser-compatible videos'
command -v sudo >/dev/null || die 'sudo is required to check Caddy access'

output_dir=$(realpath -m -- "${OUTPUT_DIR:-/mnt/gallery/dist}")

# UTF-8 album names on mounted volumes (vfat/exfat/ntfs/iso9660) need the
# nls_utf8 kernel module. It may also be built into the kernel, so modprobe
# failing alone is not an error. Warn only: ext4/xfs volumes do not need it.
check_utf8_support() {
  local kernel
  kernel=$(uname -r)
  echo 'Checking UTF-8 filename support (nls_utf8)'
  if [[ -d /sys/module/nls_utf8 ]] ||
    grep -qs '/nls_utf8\.ko' "/lib/modules/$kernel/modules.builtin" ||
    modprobe -n nls_utf8 >/dev/null 2>&1; then
    echo '  available: nls_utf8'
  else
    warn "kernel module nls_utf8 is not available for $kernel; UTF-8 album and file names may fail on non-ext4 volumes (install the kernel's extra modules package, then run: modprobe nls_utf8)"
  fi
}

check_caddy_access() {
  local path current
  local -a access_paths=("$albums_dir" "$thumbs_dir" "$output_dir")

  echo 'Checking Caddy access to gallery directories'
  for path in "${access_paths[@]}"; do
    [[ -d "$path" ]] || continue
    if sudo -u caddy test -r "$path" -a -x "$path"; then
      echo "  accessible: $path"
    else
      warn "Caddy cannot read/traverse $path"
    fi

    current=$(dirname -- "$path")
    while [[ "$current" != / ]]; do
      sudo -u caddy test -x "$current" || warn "Caddy cannot traverse $current"
      current=$(dirname -- "$current")
    done
  done
}

# shellcheck source=lib/thumbnails.sh
source "$script_dir/lib/thumbnails.sh"
photina_acquire_cache_lock "$thumbs_dir"
check_utf8_support
check_caddy_access
update_thumbnails "$albums_dir" "$thumbs_dir" "$metadata_dir" "$thumbnail_size" "$me_size" "$display_mode"
