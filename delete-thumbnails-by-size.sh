#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/common.sh
source "$script_dir/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: delete-thumbnails-by-size.sh [-n|--dry-run] SIZE...

Delete the generated viewer images of the given sizes from THUMBNAILS_DIR.
SIZE is one or more of: xs sm me la xl (the <name>_<size>.webp files; see
du-thumbnails.sh for how much space each uses). The grid thumbnails
(<name>.webp), web videos, and metadata are never touched. With -n/--dry-run,
only report what would be deleted.

Run ./update-thumbnails.sh afterwards to regenerate them: a photo with any
missing output is regenerated in full, not only the deleted size.
USAGE
}

dry_run=0
sizes=()
for argument in "$@"; do
  case "$argument" in
    -n|--dry-run) dry_run=1 ;;
    -h|--help) usage; exit 0 ;;
    xs|sm|me|la|xl)
      case " ${sizes[*]:-} " in *" $argument "*) ;; *) sizes+=("$argument") ;; esac ;;
    *) usage >&2; exit 2 ;;
  esac
done
(( ${#sizes[@]} > 0 )) || { usage >&2; exit 2; }

photina_load_config
photina_require_config THUMBNAILS_DIR
command -v find >/dev/null || die 'find is required'
command -v realpath >/dev/null || die 'realpath is required'
command -v awk >/dev/null || die 'awk is required'

thumbs_dir=$(realpath -m -- "$THUMBNAILS_DIR")
[[ -d "$thumbs_dir" ]] || die "thumbnails directory does not exist: $thumbs_dir"
[[ "$thumbs_dir" != / ]] || die 'refusing to delete in the filesystem root'
photina_acquire_cache_lock "$thumbs_dir"

if (( dry_run )); then
  action=(); verb='Would delete'
else
  action=(-delete); verb=Deleted
fi

# Only regular files named like a viewer image are matched. A grid thumbnail
# of an original named "a_la.webp" is "a_la.webp.webp", so it never ends in
# "_la.webp" (the same rule thumbnail_original_relative uses). find prints
# "links TAB device:inode TAB 512-byte-blocks" for each match, then deletes
# it; awk totals the files and the disk usage, counting a hard-linked file
# (see eliminate-duplicates.sh) once. Dry runs and real runs report the same.
for size in "${sizes[@]}"; do
  printf 'Looking for %s thumbnails in %s ...\n' "$size" "$thumbs_dir"
  if ! find -P "$thumbs_dir" -type f -name "*_${size}.webp" -printf '%n\t%D:%i\t%b\n' "${action[@]}" |
    awk -F'\t' -v verb="$verb" -v size="$size" "$photina_awk_human"'
      NF >= 3 {
        files++
        # Deleting one link lowers the others link counts, so a later link of a
        # remembered inode must be skipped whatever its count reads now.
        if ($2 in seen) next
        if ($1 > 1) seen[$2] = 1
        bytes += $3 * 512
      }
      END { printf "%s %.0f %s file(s) (%s)\n", verb, files, size, human(bytes) }
    '; then
    warn "some $size thumbnails could not be read or deleted"
    exit 1
  fi
done
