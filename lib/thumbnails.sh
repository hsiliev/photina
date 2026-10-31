#!/usr/bin/env bash

# shellcheck source=lib/common.sh
source "${BASH_SOURCE[0]%/*}/common.sh"

thumbnail_find_media() {
  local directory=$1 kind=$2 scope=${3:-direct}
  local -a extensions find_args
  if [[ "$kind" == image ]]; then
    extensions=("${IMAGE_EXTENSIONS[@]}")
  else
    extensions=("${VIDEO_EXTENSIONS[@]}")
  fi
  find_args=(-P "$directory")
  [[ "$scope" == direct ]] && find_args+=(-mindepth 1 -maxdepth 1)
  find_args+=(-type f '(')
  local extension first=1
  for extension in "${extensions[@]}"; do
    (( first )) || find_args+=(-o)
    find_args+=(-iname "*.$extension")
    first=0
  done
  find_args+=(')' -print0)
  find "${find_args[@]}"
}

# Sorted NUL-delimited list of all media files directly inside an album.
thumbnail_list_media() {
  { thumbnail_find_media "$1" image direct; thumbnail_find_media "$1" video direct; } | sort -z
}

# NUL-delimited media list: the precomputed file when given, else a fresh scan.
thumbnail_media_source() {
  local album_path=$1 media_file=${2:-}
  if [[ -n "$media_file" ]]; then cat -- "$media_file"; else thumbnail_list_media "$album_path"; fi
}

# NUL-delimited album directories (every directory below each top-level album).
thumbnail_list_albums() {
  local albums_dir=$1 root
  for root in "$albums_dir"/*/; do
    [[ -d "$root" ]] || continue
    find -P "$root" -type d -print0 | sort -z
  done
}

thumbnail_make() {
  local source=$1 thumbnail=$2 thumbnail_size=$3 image_tool=$4
  local display_name=${5:-${source##*/}} medium_size=$6 display_mode=$7
  local thumbnail_tmp=${thumbnail%.webp}.generating.webp
  local medium=${thumbnail%.webp}_medium.webp
  local medium_tmp=${medium%.webp}.generating.webp
  local video_frame_tmp=${thumbnail%.webp}.video.jpg
  local web_video=${thumbnail%.webp}.web.mp4
  local web_video_tmp=${web_video%.mp4}.generating.mp4

  local input medium_quality=90
  local -a input_args=()

  mkdir -p -- "$(dirname -- "$thumbnail")"
  if photina_is_video "$source"; then
    # Unreadable videos (empty, truncated) must not reach ImageMagick or mv.
    if ! ffmpegthumbnailer -i "$source" -o "$video_frame_tmp" -s "$thumbnail_size" -q 8 -f >/dev/null 2>&1 \
      || [[ ! -s "$video_frame_tmp" ]]; then
      rm -f -- "$video_frame_tmp"
      ffmpeg -v error -i "$source" -frames:v 1 -y "$video_frame_tmp" >/dev/null 2>&1 || true
    fi
    if [[ ! -s "$video_frame_tmp" ]]; then
      rm -f -- "$video_frame_tmp"
      warn "skipping unreadable video: $display_name"
      return 0
    fi
    input=$video_frame_tmp
    medium_quality=86
  else
    input=$source
    input_args=(-auto-orient)
  fi

  if [[ "$display_mode" == cascading || "$display_mode" == justified ]]; then
    "$image_tool" "$input" "${input_args[@]}" \
      \( +clone -thumbnail "${thumbnail_size}x" -strip -quality 86 -write "$thumbnail_tmp" +delete \) \
      \( +clone -thumbnail "${medium_size}x" -strip -quality "$medium_quality" -write "$medium_tmp" +delete \) \
      null: || true
  else
    "$image_tool" "$input" "${input_args[@]}" \
      \( +clone -thumbnail "${thumbnail_size}x${thumbnail_size}^" \
        -gravity center -extent "$thumbnail_size"x"$thumbnail_size" -background white -alpha remove \
        -alpha off -strip -quality 86 -write "$thumbnail_tmp" +delete \) \
      \( +clone -thumbnail "${medium_size}x${medium_size}>" \
        -strip -quality "$medium_quality" -write "$medium_tmp" +delete \) \
      null: || true
  fi
  rm -f -- "$video_frame_tmp"
  if [[ ! -s "$thumbnail_tmp" || ! -s "$medium_tmp" ]]; then
    rm -f -- "$thumbnail_tmp" "$medium_tmp"
    warn "skipping unreadable media: $display_name"
    return 0
  fi

  if photina_needs_web_video "$source"; then
    if ffmpeg -i "$source" -c:v libx264 -pix_fmt yuv420p -c:a aac -movflags +faststart -y "$web_video_tmp" \
      >/dev/null 2>&1 && [[ -s "$web_video_tmp" ]]; then
      mv -f -- "$web_video_tmp" "$web_video"
    else
      rm -f -- "$web_video_tmp"
      warn "web video conversion failed: $display_name"
    fi
  fi
  mv -f -- "$thumbnail_tmp" "$thumbnail"
  mv -f -- "$medium_tmp" "$medium"
  printf '\t%s\n' "$display_name"
}

thumbnail_process_item() {
  local source=$1 album_path=$2 album_name=$3 thumbs_dir=$4 thumbnail_size=$5 image_tool=$6 relative medium_size display_mode thumbnail
  [[ -n "$source" && -f "$source" ]] || return 0
  relative=${source#"$album_path"}; relative=${relative#/}
  [[ -n "$relative" ]] || return 0
  thumbnail="$thumbs_dir/$album_name/$relative.webp"
  medium_size=$7
  display_mode=$8
  if photina_needs_web_video "$source"; then
    [[ ! -f "$thumbnail" || ! -f "${thumbnail%.webp}_medium.webp" || ! -f "${thumbnail%.webp}.web.mp4" ]] || return 0
  else
    [[ ! -f "$thumbnail" || ! -f "${thumbnail%.webp}_medium.webp" ]] || return 0
  fi
  thumbnail_make "$source" "$thumbnail" "$thumbnail_size" "$image_tool" "$relative" "$medium_size" "$display_mode"
}

# Filter a NUL-delimited media list on stdin down to files whose thumbnail,
# medium image, or web video is missing. Done in-process so complete files do
# not cost a bash start each.
thumbnail_filter_pending() {
  local album_path=$1 album_name=$2 thumbs_dir=$3 source relative thumbnail
  while IFS= read -r -d '' source; do
    relative=${source#"$album_path"}; relative=${relative#/}
    thumbnail="$thumbs_dir/$album_name/$relative.webp"
    [[ -f "$thumbnail" && -f "${thumbnail%.webp}_medium.webp" ]] || { printf '%s\0' "$source"; continue; }
    if photina_needs_web_video "$source" && [[ ! -f "${thumbnail%.webp}.web.mp4" ]]; then
      printf '%s\0' "$source"
    fi
  done
}

# shellcheck disable=SC2016
thumbnail_batch_album() {
  local album_path=$1 album_name=$2 thumbs_dir=$3 thumbnail_size=$4 medium_size=$5 image_tool=$6 parallel_jobs=$7 kind=$8 display_mode=$9 media_file=${10:-}
  export -f warn photina_is_video photina_needs_web_video thumbnail_make thumbnail_process_item

  if [[ -n "$media_file" ]]; then
    cat -- "$media_file"
  elif [[ "$kind" == image ]]; then
    thumbnail_find_media "$album_path" image direct
  elif [[ "$kind" == all ]]; then
    thumbnail_list_media "$album_path"
  else
    thumbnail_find_media "$album_path" video direct
  fi | thumbnail_filter_pending "$album_path" "$album_name" "$thumbs_dir" |
    if ! xargs -0 -r -n 1 -P "$parallel_jobs" bash -c '
      thumbnail_process_item "$8" "$1" "$2" "$3" "$4" "$5" "$6" "$7"
    ' _ "$album_path" "$album_name" "$thumbs_dir" "$thumbnail_size" "$image_tool" "$medium_size" "$display_mode"; then
    return 1
  fi
}

thumbnail_batch_metadata() {
  local album_path=$1 album_name=$2 metadata_dir=$3 media_file=${4:-}
  local source relative metadata metadata_tmp batch_tmp records_tmp record
  local -a sources=()

  while IFS= read -r -d '' source; do
    relative=${source#"$album_path"}; relative=${relative#/}
    metadata="$metadata_dir/$album_name/$relative.json"
    if [[ ! -f "$metadata" ]]; then
      sources+=("$source")
    fi
  done < <(
    thumbnail_media_source "$album_path" "$media_file"
  )

  if ((${#sources[@]} == 0)); then
    printf '\tMetadata: no new files for %s\n' "$album_name"
    return 0
  fi
  printf '\tMetadata: extracting EXIF from %d files in %s\n' "${#sources[@]}" "$album_name"
  mkdir -p -- "$metadata_dir/$album_name"
  batch_tmp=$(mktemp)
  if ! exiftool -j -G1 -n -- "${sources[@]}" >"$batch_tmp"; then
    printf '\tMetadata: EXIF extraction failed for %s\n' "$album_name" >&2
    rm -f -- "$batch_tmp"
    return 1
  fi
  printf '\tMetadata: EXIF extraction complete for %s\n' "$album_name"
  records_tmp=$(mktemp)
  if ! jq -jr '.[] | .SourceFile, "\u0000", (tojson), "\u0000"' -- "$batch_tmp" >"$records_tmp"; then
    printf '\tMetadata: JSON conversion failed for %s\n' "$album_name" >&2
    rm -f -- "$batch_tmp" "$records_tmp"
    return 1
  fi

  while IFS= read -r -d '' source && IFS= read -r -d '' record; do
    relative=${source#"$album_path"}; relative=${relative#/}
    metadata="$metadata_dir/$album_name/$relative.json"
    metadata_tmp=${metadata%.json}.generating.json
    mkdir -p -- "$(dirname -- "$metadata")"
    printf '[%s]\n' "$record" >"$metadata_tmp"
    mv -f -- "$metadata_tmp" "$metadata"
  done <"$records_tmp"
  rm -f -- "$batch_tmp" "$records_tmp"
}

thumbnail_generate_checksums() {
  local album_path=$1 album_name=$2 metadata_dir=$3 media_file=${4:-}
  local source relative checksum_file checksum_tmp checksum_count=0
  local -a relative_sources=()

  checksum_file="$metadata_dir/$album_name/md5sums.txt"
  checksum_tmp="$checksum_file.generating"
  printf '\tChecksums: starting for %s\n' "$album_name"
  mkdir -p -- "$(dirname -- "$checksum_file")"
  while IFS= read -r -d '' source; do
    relative=${source#"$album_path"}; relative=${relative#/}
    relative_sources+=("$relative")
    checksum_count=$((checksum_count + 1))
  done < <(
    thumbnail_media_source "$album_path" "$media_file"
  )

  if ((${#relative_sources[@]})); then
    if ! printf '%s\0' "${relative_sources[@]}" |
      (cd -- "$album_path" && xargs -0 -r md5sum --) >"$checksum_tmp"; then
      rm -f -- "$checksum_tmp"
      return 1
    fi
  else
    : >"$checksum_tmp"
  fi
  mv -f -- "$checksum_tmp" "$checksum_file"
  printf '\tChecksums: completed for %s (%d records)\n' "$album_name" "$checksum_count"
}

thumbnail_checksums_need_update() {
  local album_path=$1 album_name=$2 metadata_dir=$3 media_file=${4:-}
  local checksum_file=$metadata_dir/$album_name/md5sums.txt
  local line relative source current_count=0 manifest_count=0
  local -A manifest_sources=()

  [[ -f "$checksum_file" ]] || return 0

  while IFS= read -r line; do
    [[ ${#line} -ge 34 ]] || return 0
    relative=${line:34}
    [[ -n "$relative" ]] || return 0
    manifest_sources["$relative"]=1
    manifest_count=$((manifest_count + 1))
  done <"$checksum_file"

  while IFS= read -r -d '' source; do
    relative=${source#"$album_path"}; relative=${relative#/}
    [[ -n ${manifest_sources["$relative"]+present} ]] || return 0
    current_count=$((current_count + 1))
  done < <(
    thumbnail_media_source "$album_path" "$media_file"
  )

  ((current_count == manifest_count)) || return 0

  while IFS= read -r -d '' source; do
    [[ "$source" -nt "$checksum_file" ]] && return 0
  done < <(
    thumbnail_media_source "$album_path" "$media_file"
  )

  return 1
}

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
# thumbnail file: x.jpg.webp, x.jpg_medium.webp, and x.avi.web.mp4 all belong
# to x.jpg / x.jpg / x.avi. Originals are usually not .webp files.
thumbnail_original_relative() {
  local relative=$1 original
  original=${relative%.web.mp4}
  [[ "$original" == "$relative" ]] && original=${original%_medium.webp}
  [[ "$original" == "$relative" ]] && original=${original%.webp}
  printf '%s' "$original"
}

thumbnail_cleanup_stale() {
  local albums_dir=$1 thumbs_dir=$2 expected_name=$3
  local thumbnail stale_relative source_path reason kept=0
  local -n expected="$expected_name"

  [[ -d "$thumbs_dir" ]] || return 0
  thumbnail_albums_dir_is_populated "$albums_dir" || return 1

  printf '\tChecking for stale thumbnail files in %s ...\n' "$thumbs_dir"
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
    printf '\tRemoving stale thumbnail: %s (%s)\n' "$stale_relative" "$reason"
    rm -f -- "$thumbnail"
  done < <(find -P "$thumbs_dir" -type f -print0)
  (( kept == 0 )) || printf '\tKept %d thumbnail(s) the album scan did not list because their originals exist\n' "$kept"

  printf '\tRemoving empty thumbnail directories in %s ...\n' "$thumbs_dir"
  find -P "$thumbs_dir" -mindepth 1 -depth -type d -empty -print -delete
}

# shellcheck disable=SC2034 # arrays are namerefs to the caller's variables
thumbnail_add_expected_outputs() {
  local album_path=$1 album_name=$2 thumbs_dir=$3 media_file=$4 expected_name=$5
  local source relative thumbnail
  local -n output="$expected_name"

  while IFS= read -r -d '' source; do
    relative=${source#"$album_path"}; relative=${relative#/}
    thumbnail="$thumbs_dir/$album_name/$relative.webp"
    output["$thumbnail"]=1
    output["${thumbnail%.webp}_medium.webp"]=1
    if photina_needs_web_video "$source"; then
      output["${thumbnail%.webp}.web.mp4"]=1
    fi
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

  printf '\tChecking for stale metadata files in %s ...\n' "$metadata_dir"
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
    printf '\tRemoving stale metadata: %s\n' "$stale_relative"
    rm -f -- "$metadata"
  done < <(find -P "$metadata_dir" -type f -print0)
  (( kept == 0 )) || printf '\tKept %d metadata file(s) the album scan did not list because their originals exist\n' "$kept"

  printf '\tRemoving empty metadata directories in %s ...\n' "$metadata_dir"
  find -P "$metadata_dir" -mindepth 1 -depth -type d -empty -print -delete
}

# Generate thumbnails, metadata, and checksums for one album. Returns 1 on any failure.
thumbnail_update_album() {
  local album_path=$1 album_name=$2 thumbs_dir=$3 metadata_dir=$4 thumbnail_size=$5 medium_size=$6
  local image_tool=$7 parallel_jobs=$8 display_mode=$9 media_file=${10}

  thumbnail_batch_album "$album_path" "$album_name" "$thumbs_dir" "$thumbnail_size" "$medium_size" \
    "$image_tool" "$parallel_jobs" all "$display_mode" "$media_file" || return 1
  thumbnail_batch_metadata "$album_path" "$album_name" "$metadata_dir" "$media_file" || return 1
  if thumbnail_checksums_need_update "$album_path" "$album_name" "$metadata_dir" "$media_file"; then
    thumbnail_generate_checksums "$album_path" "$album_name" "$metadata_dir" "$media_file" || return 1
  else
    printf '\tChecksums: unchanged for %s (skipped)\n' "$album_name"
  fi
}

update_thumbnails() {
  local albums_dir=$1 thumbs_dir=$2 metadata_dir=$3 thumbnail_size=$4 medium_size=$5 display_mode=$6
  local image_tool parallel_jobs thumbnail_failed=0 cleanup_failed=0
  local album_path album_name media_file
  # shellcheck disable=SC2034 # passed by name to functions that use namerefs
  declare -A expected_thumbnails=() expected_metadata=() expected_checksums=()

  if command -v magick >/dev/null; then
    image_tool=magick
  elif command -v convert >/dev/null; then
    image_tool=convert
  else
    die 'ImageMagick (magick or convert) is required'
  fi
  parallel_jobs=$(photina_core_count)

  echo "Updating thumbnails in $thumbs_dir"
  echo "Updating metadata in $metadata_dir"
  echo "Image tool: $image_tool"
  echo "Thumbnail workers: $parallel_jobs"
  mkdir -p -- "$thumbs_dir" "$metadata_dir"

  while IFS= read -r -d '' album_path; do
    album_name=${album_path#"$albums_dir"/}; album_name=${album_name%/}
    media_file=$(mktemp)
    if ! thumbnail_list_media "$album_path" >"$media_file"; then
      thumbnail_failed=1
    elif [[ -s "$media_file" ]]; then
      thumbnail_add_expected_outputs "$album_path" "$album_name" "$thumbs_dir" "$media_file" expected_thumbnails
      thumbnail_add_expected_metadata "$album_path" "$album_name" "$metadata_dir" "$media_file" expected_metadata expected_checksums
      echo "Scanning album: $album_name"
      thumbnail_update_album "$album_path" "$album_name" "$thumbs_dir" "$metadata_dir" "$thumbnail_size" \
        "$medium_size" "$image_tool" "$parallel_jobs" "$display_mode" "$media_file" || thumbnail_failed=1
    fi
    rm -f -- "$media_file"
  done < <(thumbnail_list_albums "$albums_dir")
  # Never delete based on an incomplete scan: expected_* only list albums
  # whose media list was read successfully.
  if (( thumbnail_failed != 0 )); then
    echo 'Skipping stale thumbnail and metadata cleanup because some albums failed'
  else
    thumbnail_cleanup_stale "$albums_dir" "$thumbs_dir" expected_thumbnails || cleanup_failed=1
    thumbnail_cleanup_stale_metadata "$albums_dir" "$metadata_dir" expected_metadata expected_checksums || cleanup_failed=1
  fi

  if (( thumbnail_failed != 0 )); then die 'one or more thumbnails could not be generated'; fi
  if (( cleanup_failed != 0 )); then die 'stale file cleanup was skipped because the albums directory looks empty'; fi

  echo 'Thumbnail update complete'
}
