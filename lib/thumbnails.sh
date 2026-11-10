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

# Every generated file expected for SOURCE whose thumbnail is THUMBNAIL: the
# thumbnail, its viewer variants (_xs/_sm/_me/_la, plus _xl for formats
# browsers cannot show), and the web video when one is needed. The array named
# by $1 receives the paths. Do not name the caller's array "files_out".
thumbnail_expected_files_to() {
  local -n files_out=$1
  local source=$2 thumbnail=$3 variant
  local -a variants=()
  files_out=("$thumbnail")
  photina_viewer_variants_to variants "$source"
  for variant in "${variants[@]}"; do
    files_out+=("${thumbnail%.webp}_$variant.webp")
  done
  if photina_needs_web_video "$source"; then
    files_out+=("${thumbnail%.webp}.web.mp4")
  fi
}

# Older versions named the viewer image <name>_medium.webp; it is now
# <name>_me.webp. Rename instead of regenerating. A leftover _medium file whose
# _me twin already exists is redundant and removed.
thumbnail_migrate_legacy_medium() {
  local thumbs_dir=$1 legacy target renamed=0
  [[ -d "$thumbs_dir" ]] || return 0
  while IFS= read -r -d '' legacy; do
    target=${legacy%_medium.webp}_me.webp
    if [[ -e "$target" ]]; then
      rm -f -- "$legacy"
    elif mv -- "$legacy" "$target"; then
      renamed=$((renamed + 1))
    else
      warn "could not rename $legacy"
    fi
  done < <(find -P "$thumbs_dir" -type f -name '*_medium.webp' -print0)
  (( renamed == 0 )) || printf 'Renamed %d _medium.webp file(s) to _me.webp\n' "$renamed"
}

thumbnail_make() {
  local source=$1 thumbnail=$2 thumbnail_size=$3 image_tool=$4
  local display_name=${5:-${source##*/}} medium_size=$6 display_mode=$7
  local base=${thumbnail%.webp}
  local thumbnail_tmp=$base.generating.webp
  local video_frame_tmp=$base.video.jpg
  local web_video=$base.web.mp4
  local web_video_tmp=${web_video%.mp4}.generating.mp4

  local input variant quality=90 tmp
  local -a input_args=() variants=() resize=() magick_args=() temps=("$thumbnail_tmp")

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
    quality=86
  else
    input=$source
    input_args=(-auto-orient)
  fi

  # One ImageMagick run decodes the source once and writes every output.
  if [[ "$display_mode" == cascading || "$display_mode" == justified ]]; then
    magick_args=('(' +clone -thumbnail "${thumbnail_size}x" -strip -quality 86 -write "$thumbnail_tmp" +delete ')')
  else
    magick_args=('(' +clone -thumbnail "${thumbnail_size}x${thumbnail_size}^"
      -gravity center -extent "$thumbnail_size"x"$thumbnail_size" -background white -alpha remove
      -alpha off -strip -quality 86 -write "$thumbnail_tmp" +delete ')')
  fi
  photina_viewer_variants_to variants "$source"
  for variant in "${variants[@]}"; do
    case "$variant" in
      xs) resize=(-thumbnail '800x>') ;;
      sm) resize=(-thumbnail '1280x>') ;;
      me)
        if [[ "$display_mode" == cascading || "$display_mode" == justified ]]; then
          resize=(-thumbnail "${medium_size}x")
        else
          resize=(-thumbnail "${medium_size}x${medium_size}>")
        fi ;;
      la) resize=(-thumbnail '2400x>') ;;
      *) resize=() ;; # xl: full resolution, converted to WebP only
    esac
    tmp=${base}_$variant.generating.webp
    temps+=("$tmp")
    magick_args+=('(' +clone "${resize[@]}" -strip -quality "$quality" -write "$tmp" +delete ')')
  done
  "$image_tool" "$input" "${input_args[@]}" "${magick_args[@]}" null: || true
  rm -f -- "$video_frame_tmp"
  for tmp in "${temps[@]}"; do
    if [[ ! -s "$tmp" ]]; then
      rm -f -- "${temps[@]}"
      warn "skipping unreadable media: $display_name"
      return 0
    fi
  done

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
  for variant in "${variants[@]}"; do
    mv -f -- "${base}_$variant.generating.webp" "${base}_$variant.webp"
  done
  printf '\t%s\n' "$display_name"
}

thumbnail_process_item() {
  local source=$1 album_path=$2 album_name=$3 thumbs_dir=$4 thumbnail_size=$5 image_tool=$6 relative medium_size display_mode thumbnail
  local file complete=1
  local -a expected=()
  [[ -n "$source" && -f "$source" ]] || return 0
  relative=${source#"$album_path"}; relative=${relative#/}
  [[ -n "$relative" ]] || return 0
  thumbnail="$thumbs_dir/$album_name/$relative.webp"
  medium_size=$7
  display_mode=$8
  thumbnail_expected_files_to expected "$source" "$thumbnail"
  for file in "${expected[@]}"; do
    [[ -f "$file" ]] || { complete=0; break; }
  done
  (( complete == 0 )) || return 0
  thumbnail_make "$source" "$thumbnail" "$thumbnail_size" "$image_tool" "$relative" "$medium_size" "$display_mode"
}

# Filter a NUL-delimited media list on stdin down to files with any generated
# output missing (thumbnail, viewer variants, web video). Done in-process so
# complete files do not cost a bash start each.
thumbnail_filter_pending() {
  local album_path=$1 album_name=$2 thumbs_dir=$3 source relative thumbnail file
  local -a expected=()
  while IFS= read -r -d '' source; do
    relative=${source#"$album_path"}; relative=${relative#/}
    thumbnail="$thumbs_dir/$album_name/$relative.webp"
    thumbnail_expected_files_to expected "$source" "$thumbnail"
    for file in "${expected[@]}"; do
      if [[ ! -f "$file" ]]; then
        printf '%s\0' "$source"
        break
      fi
    done
  done
}

# shellcheck disable=SC2016
thumbnail_batch_album() {
  local album_path=$1 album_name=$2 thumbs_dir=$3 thumbnail_size=$4 medium_size=$5 image_tool=$6 parallel_jobs=$7 kind=$8 display_mode=$9 media_file=${10:-}
  export -f warn photina_is_video photina_needs_web_video photina_browser_image photina_viewer_variants_to \
    thumbnail_expected_files_to thumbnail_make thumbnail_process_item

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
# thumbnail file: x.jpg.webp, x.jpg_me.webp (also _xs/_sm/_la/_xl, and the
# legacy _medium), and x.avi.web.mp4 belong to x.jpg / x.jpg / x.avi.
# Originals are usually not .webp files.
thumbnail_original_relative() {
  local relative=$1 original suffix
  original=${relative%.web.mp4}
  if [[ "$original" == "$relative" ]]; then
    for suffix in _me _xs _sm _la _xl _medium; do
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

# Generate thumbnails, metadata, and checksums for one album. Sets the global
# THUMBNAIL_FAILURE_REASON and returns 1 on failure, naming the failed stage.
thumbnail_update_album() {
  local album_path=$1 album_name=$2 thumbs_dir=$3 metadata_dir=$4 thumbnail_size=$5 medium_size=$6
  local image_tool=$7 parallel_jobs=$8 display_mode=$9 media_file=${10}

  thumbnail_batch_album "$album_path" "$album_name" "$thumbs_dir" "$thumbnail_size" "$medium_size" \
    "$image_tool" "$parallel_jobs" all "$display_mode" "$media_file" || {
      THUMBNAIL_FAILURE_REASON='thumbnail generation failed for one or more files (see warnings above)'
      return 1
    }
  thumbnail_batch_metadata "$album_path" "$album_name" "$metadata_dir" "$media_file" || {
    THUMBNAIL_FAILURE_REASON='EXIF metadata extraction failed (exiftool/jq error above)'
    return 1
  }
  if thumbnail_checksums_need_update "$album_path" "$album_name" "$metadata_dir" "$media_file"; then
    thumbnail_generate_checksums "$album_path" "$album_name" "$metadata_dir" "$media_file" || {
      THUMBNAIL_FAILURE_REASON='md5 checksum generation failed (unreadable file?)'
      return 1
    }
  else
    printf '\tChecksums: unchanged for %s (skipped)\n' "$album_name"
  fi
}

update_thumbnails() {
  local albums_dir=$1 thumbs_dir=$2 metadata_dir=$3 thumbnail_size=$4 medium_size=$5 display_mode=$6
  local image_tool parallel_jobs thumbnail_failed=0 cleanup_failed=0
  local -a failed_albums=()
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
  thumbnail_migrate_legacy_medium "$thumbs_dir"

  while IFS= read -r -d '' album_path; do
    album_name=${album_path#"$albums_dir"/}; album_name=${album_name%/}
    media_file=$(mktemp)
    if ! thumbnail_list_media "$album_path" >"$media_file"; then
      thumbnail_failed=1
      failed_albums+=("$album_name (could not list media)")
    elif [[ -s "$media_file" ]]; then
      thumbnail_add_expected_outputs "$album_path" "$album_name" "$thumbs_dir" "$media_file" expected_thumbnails
      thumbnail_add_expected_metadata "$album_path" "$album_name" "$metadata_dir" "$media_file" expected_metadata expected_checksums
      echo "Scanning album: $album_name"
      THUMBNAIL_FAILURE_REASON='thumbnail/metadata update failed'
      thumbnail_update_album "$album_path" "$album_name" "$thumbs_dir" "$metadata_dir" "$thumbnail_size" \
        "$medium_size" "$image_tool" "$parallel_jobs" "$display_mode" "$media_file" || {
          thumbnail_failed=1
          failed_albums+=("$album_name ($THUMBNAIL_FAILURE_REASON)")
        }
    fi
    rm -f -- "$media_file"
  done < <(thumbnail_list_albums "$albums_dir")
  # Never delete based on an incomplete scan: expected_* only list albums
  # whose media list was read successfully.
  if (( thumbnail_failed != 0 )); then
    echo 'Skipping stale thumbnail and metadata cleanup because some albums failed:'
    printf '\t%s\n' "${failed_albums[@]}"
  else
    thumbnail_cleanup_stale "$albums_dir" "$thumbs_dir" expected_thumbnails || cleanup_failed=1
    thumbnail_cleanup_stale_metadata "$albums_dir" "$metadata_dir" expected_metadata expected_checksums || cleanup_failed=1
  fi

  if (( thumbnail_failed != 0 )); then die 'one or more thumbnails could not be generated'; fi
  if (( cleanup_failed != 0 )); then die 'stale file cleanup was skipped because the albums directory looks empty'; fi

  echo 'Thumbnail update complete'
}
