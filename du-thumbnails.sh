#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/common.sh
source "$script_dir/lib/common.sh"

usage() { printf 'usage: du-thumbnails.sh [-l|--list]\n'; }

list_files=0
case "${1:-}" in
  '') ;;
  -l|--list) list_files=1 ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac
(( $# <= 1 )) || { usage >&2; exit 2; }

photina_load_config
photina_require_config THUMBNAILS_DIR
command -v find >/dev/null || die 'find is required'
command -v realpath >/dev/null || die 'realpath is required'
command -v awk >/dev/null || die 'awk is required'

thumbs_dir=$(realpath -m -- "$THUMBNAILS_DIR")
[[ -d "$thumbs_dir" ]] || die "thumbnails directory does not exist: $thumbs_dir"

# The scan can take long on a big or network-mounted cache and prints nothing
# until it ends (except --list lines), so say what is happening.
printf 'Calculating disk usage of thumbnails in %s ...\n' "$thumbs_dir"

# One find pass feeds one awk program (a bash loop per file was ~30x slower).
# find prints "links TAB device:inode TAB 512-byte-blocks TAB relative-path";
# tr turns newlines inside file names into spaces and the NUL terminators into
# newlines, so any awk (mawk included) can read the records.
#
# Groups: "thumbnail" is the plain <name>.webp grid thumbnail; xs/sm/me/la/xl
# are the viewer images; "video" is <name>.web.mp4; "other" is anything else
# (temporary files left by an interrupted update). The suffix tests match
# thumbnail_original_relative: a thumbnail of an original named "a_xs.webp" is
# "a_xs.webp.webp", which ends in ".webp.webp", not "_xs.webp".
#
# Disk usage is allocated blocks, like du. A hard-linked file (see
# eliminate-duplicates.sh) counts once in the usage; only inodes with more
# than one link are remembered, so memory stays small on a huge cache.
if ! find -P "$thumbs_dir" -type f -printf '%n\t%D:%i\t%b\t%P\0' | tr '\n\0' ' \n' |
  awk -F'\t' -v list="$list_files" "$photina_awk_human"'
    function group_of(name) {
      sub(/^.*\//, "", name)
      if (name ~ /\.generating\./ || name ~ /\.video\.jpg$/) return "other"
      if (name ~ /\.web\.mp4$/) return "video"
      if (name ~ /_xs\.webp$/) return "xs"
      if (name ~ /_sm\.webp$/) return "sm"
      if (name ~ /_me\.webp$/) return "me"
      if (name ~ /_la\.webp$/) return "la"
      if (name ~ /_xl\.webp$/) return "xl"
      if (name ~ /\.webp$/) return "thumbnail"
      return "other"
    }
    BEGIN {
      group_count = split("thumbnail xs sm me la xl video other", order, " ")
      if (list) printf "\n%-10s %10s  %s\n", "GROUP", "SIZE", "FILE"
    }
    NF >= 4 {
      path = $4
      for (i = 5; i <= NF; i++) path = path "\t" $i
      group = group_of(path)
      bytes = $3 * 512
      files[group]++; total_files++
      if ($1 > 1) {
        if ($2 in seen) { shared++; bytes = 0 }
        else seen[$2] = 1
      }
      usage[group] += bytes; total_bytes += bytes
      if (list) printf "%-10s %10s  %s\n", group, human($3 * 512), path
    }
    END {
      printf "\n%-10s %10s %12s\n", "GROUP", "FILES", "DISK USAGE"
      for (i = 1; i <= group_count; i++) {
        group = order[i]
        # "other" only appears when there are leftovers to report.
        if (group == "other" && files[group] == 0) continue
        printf "%-10s %10.0f %12s\n", group, files[group], human(usage[group])
      }
      printf "%-10s %10.0f %12s\n", "total", total_files, human(total_bytes)
      if (shared > 0)
        printf "(%d hard-linked file(s) counted once in the disk usage)\n", shared
    }
  '; then
  warn 'some files could not be read; the totals may be incomplete'
  exit 1
fi
