#!/usr/bin/env bash
set -Eeuo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
warn() { printf 'warning: %s\n' "$*" >&2; }

[[ $# -eq 1 ]] || die 'usage: split-by-year.sh DIRECTORY'
directory=$(realpath -e -- "$1") || die "directory does not exist: $1"
[[ -d "$directory" ]] || die "not a directory: $1"

command -v exiftool >/dev/null || die 'exiftool is required'
command -v find >/dev/null || die 'find is required'
command -v mv >/dev/null || die 'mv is required'

is_image() {
  local filename=${1##*/}
  case ${filename##*.} in
    jpg|jpeg|png|gif|webp|bmp|tif|tiff|avif|heic|heif|JPG|JPEG|PNG|GIF|WEBP|BMP|TIF|TIFF|AVIF|HEIC|HEIF)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

photo_year() {
  local file=$1 date
  local -a dates=()

  # DateTimeOriginal is the date the picture was taken. The other tags cover
  # images written by applications that do not preserve DateTimeOriginal.
  mapfile -t dates < <(
    exiftool -q -q -s3 -d '%Y' \
      -DateTimeOriginal -CreateDate -CreationDate -- "$file"
  )
  for date in "${dates[@]}"; do
    if [[ $date =~ ^[0-9]{4}$ ]]; then
      printf '%s\n' "$date"
      return 0
    fi
  done
  return 1
}

moved=0
skipped=0
while IFS= read -r -d '' file; do
  is_image "$file" || continue

  if ! year=$(photo_year "$file"); then
    warn "no usable EXIF date; leaving in place: $file"
    skipped=$((skipped + 1))
    continue
  fi

  year_directory="$directory/$year"
  mkdir -p -- "$year_directory"
  destination="$year_directory/${file##*/}"
  [[ ! -d "$destination" ]] || die "destination is a directory: $destination"
  mv -f -- "$file" "$destination"
  printf 'Moved: %s -> %s\n' "$file" "$destination"
  moved=$((moved + 1))
done < <(find -P "$directory" -mindepth 1 -maxdepth 1 -type f -print0 | sort -z)

printf 'Moved %d image(s); skipped %d image(s) without a usable EXIF year.\n' \
  "$moved" "$skipped"
