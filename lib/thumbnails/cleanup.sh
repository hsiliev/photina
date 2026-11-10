#!/usr/bin/env bash

# Expected-output bookkeeping and stale-file cleanup.

# Stale cleanup must never trust the album scan alone: a flaky network mount
# can return a short or empty listing, which would make every cached file look
# stale. A file is therefore removed only when the original it belongs to is
# verified missing on disk, and nothing is removed when the albums directory
# looks empty (for example an unmounted share).
thumbnail_albums_dir_is_populated() {
  local albums_dir=$1
  [[ -n "$(find -P "$albums_dir" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]] && return 0
  printf 'error: albums directory %s is empty or unreadable (unmounted?); skipping cleanup.\n' "$albums_dir" >&2
  return 1
}

# Original media path (relative to the albums directory) of a generated
# thumbnail file: x.jpg.webp, x.jpg_me.webp (also _xs/_sm/_la/_xl), and
# x.avi.web.mp4 belong to x.jpg / x.jpg / x.avi.
# Originals are usually not .webp files.
thumbnail_original_relative() {
  local relative=$1 original suffix
  original=${relative%.web.mp4}
  if [[ "$original" == "$relative" ]]; then
    for suffix in _me _xs _sm _la _xl; do
      original=${relative%"$suffix.webp"}
      [[ "$original" == "$relative" ]] || break
    done
  fi
  [[ "$original" == "$relative" ]] && original=${original%.webp}
  printf '%s' "$original"
}

thumbnail_cleanup_stale() {
  local albums_dir=$1 thumbs_dir=$2 expected_name=$3
  local thumbnail stale_relative source_path reason kept=0
  local -n expected="$expected_name"

  [[ -d "$thumbs_dir" ]] || return 0
  thumbnail_albums_dir_is_populated "$albums_dir" || return 1

  printf 'Checking for stale thumbnail files in %s ...\n' "$thumbs_dir"
  while IFS= read -r -d '' thumbnail; do
    [[ -n ${expected["$thumbnail"]+present} ]] && continue
    stale_relative=${thumbnail#"$thumbs_dir"/}
    source_path=$(thumbnail_original_relative "$stale_relative")
    if [[ -e "$albums_dir/$source_path" || -L "$albums_dir/$source_path" ]]; then
      # The original exists, so the scan missed it: keep the thumbnail.
      kept=$((kept + 1))
      continue
    fi
    if [[ -d "$albums_dir/${source_path%/*}" ]]; then
      reason='no such original image'
    else
      reason='no such original album'
    fi
    printf 'Removing stale thumbnail: %s (%s)\n' "$stale_relative" "$reason"
    rm -f -- "$thumbnail"
  done < <(find -P "$thumbs_dir" -type f -print0)
  (( kept == 0 )) || printf 'Kept %d thumbnail(s) the album scan did not list because their originals exist\n' "$kept"

  printf 'Removing empty thumbnail directories in %s ...\n' "$thumbs_dir"
  find -P "$thumbs_dir" -mindepth 1 -depth -type d -empty -print -delete
}

# shellcheck disable=SC2034 # arrays are namerefs to the caller's variables
thumbnail_add_expected_outputs() {
  local album_path=$1 album_name=$2 thumbs_dir=$3 media_file=$4 expected_name=$5
  local source relative file
  local -a files=()
  local -n output="$expected_name"

  while IFS= read -r -d '' source; do
    relative=${source#"$album_path"}; relative=${relative#/}
    thumbnail_expected_files_to files "$source" "$thumbs_dir/$album_name/$relative.webp"
    for file in "${files[@]}"; do
      output["$file"]=1
    done
  done <"$media_file"
}

# shellcheck disable=SC2034 # arrays are namerefs to the caller's variables
thumbnail_add_expected_metadata() {
  local album_path=$1 album_name=$2 metadata_dir=$3 media_file=$4 metadata_name=$5 checksums_name=$6
  local source relative
  local -n metadata="$metadata_name" checksums="$checksums_name"

  while IFS= read -r -d '' source; do
    relative=${source#"$album_path"}; relative=${relative#/}
    metadata["$metadata_dir/$album_name/$relative.json"]=1
  done <"$media_file"
  checksums["$metadata_dir/$album_name/md5sums.txt"]=1
}

thumbnail_cleanup_stale_metadata() {
  local albums_dir=$1 metadata_dir=$2 metadata_name=$3 checksums_name=$4
  local metadata stale_relative original kept=0
  local -n metadata_expected="$metadata_name" checksums_expected="$checksums_name"

  [[ -d "$metadata_dir" ]] || return 0
  thumbnail_albums_dir_is_populated "$albums_dir" || return 1

  printf 'Checking for stale metadata files in %s ...\n' "$metadata_dir"
  while IFS= read -r -d '' metadata; do
    [[ -n ${metadata_expected["$metadata"]+present} || -n ${checksums_expected["$metadata"]+present} ]] && continue
    stale_relative=${metadata#"$metadata_dir"/}
    if [[ "$stale_relative" == *.json && "$stale_relative" != *.generating.json ]]; then
      original=${stale_relative%.json}
      if [[ -e "$albums_dir/$original" || -L "$albums_dir/$original" ]]; then
        kept=$((kept + 1))
        continue
      fi
    fi
    printf 'Removing stale metadata: %s\n' "$stale_relative"
    rm -f -- "$metadata"
  done < <(find -P "$metadata_dir" -type f -print0)
  (( kept == 0 )) || printf 'Kept %d metadata file(s) the album scan did not list because their originals exist\n' "$kept"

  printf 'Removing empty metadata directories in %s ...\n' "$metadata_dir"
  find -P "$metadata_dir" -mindepth 1 -depth -type d -empty -print -delete
}

# Scan every album and record the files it should have, in the associative
# arrays named by the arguments (see thumbnail_add_expected_outputs and
# thumbnail_add_expected_metadata). Dies when an album cannot be scanned, so
# callers never act on an incomplete listing. Metadata is collected only when
# METADATA_DIR is given; PROGRESS_FORMAT, if given, is printf'd with each
# album name.
# Usage: thumbnail_collect_expected albums_dir thumbs_dir thumbnails_name
#        [metadata_dir metadata_name checksums_name [progress_format]]
thumbnail_collect_expected() {
  local albums_dir=$1 thumbs_dir=$2 thumbnails_name=$3
  local metadata_dir=${4:-} metadata_name=${5:-} checksums_name=${6:-} progress_format=${7:-}
  local album_path album_name media_file

  while IFS= read -r -d '' album_path; do
    album_name=${album_path#"$albums_dir"/}; album_name=${album_name%/}
    # shellcheck disable=SC2059 # the caller supplies the format
    [[ -z "$progress_format" ]] || printf "$progress_format" "$album_name"
    media_file=$(mktemp)
    if ! thumbnail_list_media "$album_path" >"$media_file"; then
      rm -f -- "$media_file"
      die "could not scan album: $album_name"
    fi
    thumbnail_add_expected_outputs "$album_path" "$album_name" "$thumbs_dir" "$media_file" "$thumbnails_name"
    if [[ -n "$metadata_dir" ]]; then
      thumbnail_add_expected_metadata "$album_path" "$album_name" "$metadata_dir" "$media_file" "$metadata_name" "$checksums_name"
    fi
    rm -f -- "$media_file"
  done < <(thumbnail_list_albums "$albums_dir")
}
