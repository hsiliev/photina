#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/common.sh
source "$script_dir/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: trim-trailing-spaces.sh [-n|--dry-run] DIRECTORY

Rename files and directories below DIRECTORY whose names end with spaces,
removing the trailing spaces. DIRECTORY itself is never renamed. With
-n/--dry-run, only report what would be renamed.
USAGE
}

dry_run=0
case "${1:-}" in
  -n|--dry-run) dry_run=1; shift ;;
  -h|--help) usage; exit 0 ;;
esac
[[ $# -eq 1 ]] || { usage >&2; exit 2; }
directory=$(realpath -e -- "$1") || die "directory does not exist: $1"
[[ -d "$directory" ]] || die "not a directory: $1"
command -v find >/dev/null || die 'find is required'

# find -depth lists children before their parents, so renaming a directory
# never invalidates the paths of entries still to be processed.
mapfile -d '' -t paths < <(find -P "$directory" -mindepth 1 -depth -name '* ' -print0)

renamed=0
skipped=0
for path in "${paths[@]}"; do
  parent=${path%/*}
  name=${path##*/}
  trimmed=${name%"${name##*[! ]}"}
  if [[ -z "$trimmed" ]]; then
    warn "name consists only of spaces; skipping: $path"
    skipped=$((skipped + 1))
    continue
  fi
  target="$parent/$trimmed"
  if [[ -e "$target" || -L "$target" ]]; then
    warn "target already exists; skipping: $path -> $target"
    skipped=$((skipped + 1))
    continue
  fi
  if (( dry_run )); then
    printf 'Would rename: %s -> %s\n' "$path" "$target"
  else
    mv -n -- "$path" "$target"
    printf 'Renamed: %s -> %s\n' "$path" "$target"
  fi
  renamed=$((renamed + 1))
done

if (( dry_run )); then
  printf 'Would rename %d item(s); skipped %d.\n' "$renamed" "$skipped"
else
  printf 'Renamed %d item(s); skipped %d.\n' "$renamed" "$skipped"
fi
(( skipped == 0 )) || exit 1
