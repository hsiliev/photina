#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/common.sh
source "$script_dir/lib/common.sh"

usage() {
  cat <<'USAGE'
Usage: fix-names.sh [-n|--dry-run] [-l|--max-length N] DIRECTORY

Make names below DIRECTORY safe for SMB/CIFS shares:

  * rename files and directories whose names end with spaces or dots,
    removing the trailing spaces and dots (DIRECTORY itself is never renamed);
  * report entries that an SMB/CIFS server exposed under a mangled 8.3 alias
    such as 2KT24Y~W and that cannot be opened. The real name (usually a
    trailing space or dot) is never delivered to the client, so it cannot
    be shown or fixed through that mount; run this script against an FTP or
    SFTP view of the same directory, or on the server's own filesystem;
  * report (without renaming) names containing characters SMB cannot store:
    \ : * ? " < > |, control characters, and the private-use characters
    U+F020-U+F029 that a mapposix CIFS mount shows in place of those.

  * shorten names longer than N characters (default 100) by replacing the
    middle with the ellipsis character "…"; a file extension is kept, and the
    result never exceeds 255 bytes. Names are never overwritten: a shortened
    name that already exists is skipped with a warning.

  * delete empty (0 byte) regular files before renaming, since they are
    never real media (symlinks are left alone).

With -n/--dry-run, only report what would be renamed or deleted.
Exit status: 0 when everything was fixed, 1 when entries were skipped,
mangled aliases were found, or names with forbidden characters were found.
USAGE
}

# Character counts and slicing below need a UTF-8 locale.
export LC_ALL=C.UTF-8

dry_run=0
max_length=100
while [[ "${1:-}" == -* ]]; do
  case "$1" in
    -n|--dry-run) dry_run=1; shift ;;
    -l|--max-length)
      [[ "${2:-}" =~ ^[0-9]+$ ]] && (( $2 >= 8 )) || die '--max-length needs a number >= 8'
      max_length=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ $# -eq 1 ]] || { usage >&2; exit 2; }
directory=$(realpath -e -- "$1") || die "directory does not exist: $1"
[[ -d "$directory" ]] || die "not a directory: $1"
command -v find >/dev/null || die 'find is required'

# Private-use characters (UTF-8 bytes EF 80 A0-A9) that Linux CIFS with
# mapposix uses for the forbidden characters and trailing space/dot.
sfm_chars=()
for byte in a0 a1 a2 a3 a4 a5 a6 a7 a8 a9; do
  sfm_chars+=("$(printf '\xef\x80%b' "\\x$byte")")
done

has_forbidden_character() {
  local name=$1 char
  [[ "$name" == *[\\:\*\?\"\<\>\|]* || "$name" == *[[:cntrl:]]* ]] && return 0
  for char in "${sfm_chars[@]}"; do
    [[ "$name" == *"$char"* ]] && return 0
  done
  return 1
}

# Samba's default name mangling turns names it cannot represent into
# "XXXXXX~Y" (optionally with a short extension). Only an alias that cannot
# be opened is reported, so a legitimate name of that shape is never flagged.
is_unopenable_mangled_name() {
  local path=$1 name=${1##*/}
  [[ "$name" =~ ^[A-Z0-9]{6}~[A-Z0-9](\.[A-Za-z0-9]{1,3})?$ ]] || return 1
  [[ ! -e "$path" && ! -L "$path" ]]
}

# Byte length of $1 (the script runs in a UTF-8 locale, so ${#1} counts
# characters). Stored in byte_len; forkless.
byte_length() {
  local LC_ALL=C
  byte_len=${#1}
}

# shorten_name NAME IS_DIR VARNAME: store NAME in VARNAME, with the middle of
# the stem replaced by "…" when it exceeds max_length characters or 255 bytes.
# A short extension of a file is preserved.
shorten_name() {
  local name=$1 is_dir=$2 ext='' stem allowed keep byte_len
  local -n out=$3
  out=$name
  stem=$name
  if [[ "$is_dir" != 1 && "$name" =~ ^(.+)(\.[A-Za-z0-9]{1,8})$ ]]; then
    stem=${BASH_REMATCH[1]}; ext=${BASH_REMATCH[2]}
  fi
  byte_length "$name"
  (( ${#name} > max_length || byte_len > 255 )) || return 0
  allowed=$((max_length - ${#ext}))
  while (( allowed > 2 )); do
    keep=$((allowed - 1))
    out=${stem:0:keep - keep / 2}…
    (( keep / 2 > 0 )) && out+=${stem: -keep / 2}
    out+=$ext
    byte_length "$out"
    (( byte_len <= 255 )) && return 0
    allowed=$((allowed - 1))
  done
}

# find -depth lists children before their parents, so renaming a directory
# never invalidates the paths of entries still to be processed. Names are
# prefiltered by find; bash classifies the few candidates.
find_args=(-P "$directory" -mindepth 1 -depth -regextype posix-extended '(' -regex ".*/[^/]{$((max_length + 1)),}" -o -name '* ' -o -name '*.' -o -name '*[\\:*?"<>|]*' -o -name '*[[:cntrl:]]*'
  -o -name '??????~?' -o -name '??????~?.*')
for char in "${sfm_chars[@]}"; do
  find_args+=(-o -name "*$char*")
done
find_args+=(')' -print0)

echo "Scanning $directory ..."
deleted=0
while IFS= read -r -d '' path; do
  if (( dry_run )); then
    printf 'Would delete empty file: %s\n' "$path"
  else
    rm -f -- "$path"
    printf 'Deleted empty file: %s\n' "$path"
  fi
  deleted=$((deleted + 1))
done < <(find -P "$directory" -mindepth 1 -type f -empty -print0)

mapfile -d '' -t paths < <(find "${find_args[@]}")

renamed=0
skipped=0
forbidden=()
mangled=()
for path in "${paths[@]}"; do
  parent=${path%/*}
  name=${path##*/}
  # Strip all trailing spaces and dots, then shorten overlong names.
  trimmed=${name%"${name##*[! .]}"}
  if [[ -z "$trimmed" && -n "$name" ]]; then
    warn "name consists only of spaces or dots; skipping: $path"
    skipped=$((skipped + 1))
    continue
  fi
  [[ -d "$path" && ! -L "$path" ]] && is_dir=1 || is_dir=0
  shorten_name "$trimmed" "$is_dir" trimmed
  if [[ "$trimmed" == "$name" ]]; then
    if is_unopenable_mangled_name "$path"; then
      mangled+=("$path")
    elif has_forbidden_character "$name"; then
      forbidden+=("$path")
    fi
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
  has_forbidden_character "$trimmed" && forbidden+=("$target")
done

if ((${#mangled[@]})); then
  warn "${#mangled[@]} SMB-mangled alias(es) cannot be opened; the real name probably ends with a space or dot. Rename them via FTP/SFTP or on the server:"
  printf '  mangled: %s\n' "${mangled[@]}" >&2
fi

if ((${#forbidden[@]})); then
  warn "${#forbidden[@]} name(s) contain characters SMB cannot store; rename them manually:"
  printf '  forbidden: %s\n' "${forbidden[@]}" >&2
fi

if (( dry_run )); then
  printf 'Would rename %d item(s); skipped %d; forbidden %d; mangled %d.\n' "$renamed" "$skipped" "${#forbidden[@]}" "${#mangled[@]}"
else
  printf 'Renamed %d item(s); skipped %d; forbidden %d; mangled %d.\n' "$renamed" "$skipped" "${#forbidden[@]}" "${#mangled[@]}"
fi
if (( dry_run )); then
  printf 'Would delete %d empty file(s).\n' "$deleted"
else
  printf 'Deleted %d empty file(s).\n' "$deleted"
fi
(( skipped == 0 && ${#forbidden[@]} == 0 && ${#mangled[@]} == 0 )) || exit 1
