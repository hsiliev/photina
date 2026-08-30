#!/usr/bin/env bash

thumbnail_is_video() {
  local extension=${1##*.}
  extension=${extension,,}
  case "$extension" in
    mp4|m4v|mov|mkv|webm|avi|mpeg|mpg|ts|mts) return 0 ;;
    *) return 1 ;;
  esac
}

thumbnail_needs_web_video() {
  local extension=${1##*.}
  extension=${extension,,}
  case "$extension" in
    mp4) return 1 ;;
    *) thumbnail_is_video "$1" ;;
  esac
}

thumbnail_core_count() {
  local cores=1
  if command -v nproc >/dev/null; then
    cores=$(nproc)
  fi
  (( cores > 0 )) || cores=1
  printf '%s\n' "$cores"
}

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

thumbnail_make() {
  local source=$1 thumbnail=$2 thumbnail_size=$3 image_tool=$4
  local display_name=${5:-${source##*/}} medium_size=$6 display_mode=$7
  local thumbnail_tmp=${thumbnail%.webp}.generating.webp
  local medium=${thumbnail%.webp}_medium.webp
  local medium_tmp=${medium%.webp}.generating.webp
  local video_frame_tmp=${thumbnail%.webp}.video.jpg
  local web_video=${thumbnail%.webp}.web.mp4
  local web_video_tmp=${web_video%.mp4}.generating.mp4
  local progress=$display_name

  mkdir -p -- "$(dirname -- "$thumbnail")"
  if thumbnail_is_video "$source"; then
    ffmpegthumbnailer -i "$source" -o "$video_frame_tmp" -s "$thumbnail_size" -q 8 -f >/dev/null 2>&1
    if [[ "$display_mode" == cascading || "$display_mode" == justified ]]; then
      "$image_tool" "$video_frame_tmp" \
        \( +clone -thumbnail "${thumbnail_size}x" -strip -quality 86 -write "$thumbnail_tmp" +delete \) \
        \( +clone -thumbnail "${medium_size}x" -strip -quality 86 -write "$medium_tmp" +delete \) \
        null:
    else
      "$image_tool" "$video_frame_tmp" \
        \( +clone -thumbnail "${thumbnail_size}x${thumbnail_size}^" \
          -gravity center -extent "$thumbnail_size"x"$thumbnail_size" -background white -alpha remove \
          -alpha off -strip -quality 86 -write "$thumbnail_tmp" +delete \) \
        \( +clone -thumbnail "${medium_size}x${medium_size}>" \
          -background white -alpha remove -alpha off -strip -quality 86 -write "$medium_tmp" +delete \) \
        null:
    fi
    if thumbnail_needs_web_video "$source"; then
      ffmpeg -i "$source" -c:v libx264 -pix_fmt yuv420p -c:a aac -movflags +faststart -y "$web_video_tmp" \
        >/dev/null 2>&1
    fi
  else
    if [[ "$display_mode" == cascading || "$display_mode" == justified ]]; then
      "$image_tool" "$source" -auto-orient \
        \( +clone -thumbnail "${thumbnail_size}x" -strip -quality 86 -write "$thumbnail_tmp" +delete \) \
        \( +clone -thumbnail "${medium_size}x" -strip -quality 90 -write "$medium_tmp" +delete \) \
        null:
    else
      "$image_tool" "$source" -auto-orient \
        \( +clone -thumbnail "${thumbnail_size}x${thumbnail_size}^" \
          -gravity center -extent "$thumbnail_size"x"$thumbnail_size" -background white -alpha remove \
          -alpha off -strip -quality 86 -write "$thumbnail_tmp" +delete \) \
        \( +clone -thumbnail "${medium_size}x${medium_size}>" \
          -strip -quality 90 -write "$medium_tmp" +delete \) \
        null:
    fi
  fi

  mv -f -- "$thumbnail_tmp" "$thumbnail"
  mv -f -- "$medium_tmp" "$medium"
  if thumbnail_needs_web_video "$source"; then
    mv -f -- "$web_video_tmp" "$web_video"
  fi
  rm -f -- "$video_frame_tmp"
  printf '\t%s\n' "$progress"
}

thumbnail_process_item() {
  local source=$1 album_path=$2 album_name=$3 thumbs_dir=$4 thumbnail_size=$5 image_tool=$6 relative medium_size display_mode thumbnail
  [[ -n "$source" && -f "$source" ]] || return 0
  relative=${source#"$album_path"}; relative=${relative#/}
  [[ -n "$relative" ]] || return 0
  thumbnail="$thumbs_dir/$album_name/$relative.webp"
  medium_size=$7
  display_mode=$8
  if thumbnail_needs_web_video "$source"; then
    [[ ! -f "$thumbnail" || ! -f "${thumbnail%.webp}_medium.webp" || ! -f "${thumbnail%.webp}.web.mp4" ]] || return 0
  else
    [[ ! -f "$thumbnail" || ! -f "${thumbnail%.webp}_medium.webp" ]] || return 0
  fi
  thumbnail_make "$source" "$thumbnail" "$thumbnail_size" "$image_tool" "$relative" "$medium_size" "$display_mode"
}

# shellcheck disable=SC2016
thumbnail_batch_album() {
  local album_path=$1 album_name=$2 thumbs_dir=$3 thumbnail_size=$4 medium_size=$5 image_tool=$6 parallel_jobs=$7 kind=$8 display_mode=$9 media_file=${10:-}
  export -f thumbnail_is_video thumbnail_needs_web_video thumbnail_make thumbnail_process_item

  if [[ -n "$media_file" ]]; then
    cat -- "$media_file"
  elif [[ "$kind" == image ]]; then
    thumbnail_find_media "$album_path" image direct
  elif [[ "$kind" == all ]]; then
    { thumbnail_find_media "$album_path" image direct; thumbnail_find_media "$album_path" video direct; } | sort -z
  else
    thumbnail_find_media "$album_path" video direct
  fi |
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
    if [[ -n "$media_file" ]]; then cat -- "$media_file"; else
      { thumbnail_find_media "$album_path" image direct; thumbnail_find_media "$album_path" video direct; } | sort -z
    fi
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
    if [[ -n "$media_file" ]]; then cat -- "$media_file"; else
      { thumbnail_find_media "$album_path" image direct; thumbnail_find_media "$album_path" video direct; } | sort -z
    fi
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
    if [[ -n "$media_file" ]]; then cat -- "$media_file"; else
      { thumbnail_find_media "$album_path" image direct; thumbnail_find_media "$album_path" video direct; } | sort -z
    fi
  )

  ((current_count == manifest_count)) || return 0

  while IFS= read -r -d '' source; do
    [[ "$source" -nt "$checksum_file" ]] && return 0
  done < <(
    if [[ -n "$media_file" ]]; then cat -- "$media_file"; else
      { thumbnail_find_media "$album_path" image direct; thumbnail_find_media "$album_path" video direct; } | sort -z
    fi
  )

  return 1
}

update_thumbnails() {
  local albums_dir=$1 thumbs_dir=$2 metadata_dir=$3 thumbnail_size=$4 medium_size=$5 display_mode=$6
  local image_tool parallel_jobs thumbnail_failed=0
  local root_album_path album_path album_name source relative thumb_path medium_path web_video_path media_file
  local thumbnail stale_relative
  local metadata stale_metadata_relative
  local found_media cleanup_removed
  declare -A expected_thumbnails=() expected_metadata=() expected_checksums=()

  if command -v magick >/dev/null; then
    image_tool=magick
  elif command -v convert >/dev/null; then
    image_tool=convert
  else
    die 'ImageMagick (magick or convert) is required'
  fi
  parallel_jobs=$(thumbnail_core_count)

  echo "Updating thumbnails in $thumbs_dir"
  echo "Updating metadata in $metadata_dir"
  echo "Image tool: $image_tool"
  echo "Thumbnail workers: $parallel_jobs"
  mkdir -p -- "$thumbs_dir"
  mkdir -p -- "$metadata_dir"

  shopt -s nullglob
  for root_album_path in "$albums_dir"/*/; do
    [[ -d "$root_album_path" ]] || continue
    while IFS= read -r -d '' album_path; do
      album_name=${album_path#"$albums_dir"/}; album_name=${album_name%/}
      found_media=0
      media_file=$(mktemp)
      if ! { thumbnail_find_media "$album_path" image direct; thumbnail_find_media "$album_path" video direct; } | sort -z >"$media_file"; then
        rm -f -- "$media_file"
        thumbnail_failed=1
        continue
      fi
      while IFS= read -r -d '' source; do
        found_media=1
        relative=${source#"$album_path"}; relative=${relative#/}
        thumb_path="$thumbs_dir/$album_name/$relative.webp"
        medium_path="${thumb_path%.webp}_medium.webp"
        expected_thumbnails["$thumb_path"]=1
        expected_thumbnails["$medium_path"]=1
        expected_metadata["$metadata_dir/$album_name/$relative.json"]=1
        if thumbnail_needs_web_video "$source"; then
          web_video_path="${thumb_path%.webp}.web.mp4"
          expected_thumbnails["$web_video_path"]=1
        fi
      done <"$media_file"
      if (( ! found_media )); then
        rm -f -- "$media_file"
        continue
      fi
      expected_checksums["$metadata_dir/$album_name/md5sums.txt"]=1
      echo "Scanning album: $album_name"
      if thumbnail_batch_album "$album_path" "$album_name" "$thumbs_dir" "$thumbnail_size" "$medium_size" "$image_tool" "$parallel_jobs" all "$display_mode" "$media_file"; then
        if thumbnail_batch_metadata "$album_path" "$album_name" "$metadata_dir" "$media_file"; then
          if thumbnail_checksums_need_update "$album_path" "$album_name" "$metadata_dir" "$media_file"; then
            thumbnail_generate_checksums "$album_path" "$album_name" "$metadata_dir" "$media_file" || thumbnail_failed=1
          else
            printf '\tChecksums: unchanged for %s (skipped)\n' "$album_name"
          fi
        else
          thumbnail_failed=1
        fi
      else
        thumbnail_failed=1
      fi
      rm -f -- "$media_file"
    done < <(find -P "$root_album_path" -type d -print0 | sort -z)
  done
  while IFS= read -r -d '' thumbnail; do
    [[ -n ${expected_thumbnails["$thumbnail"]+present} ]] && continue
    stale_relative=${thumbnail#"$thumbs_dir"/}
    printf '\tRemoving stale thumbnail: %s\n' "$stale_relative"
    rm -f -- "$thumbnail"
  done < <(find -P "$thumbs_dir" -type f \( -name '*.webp' -o -name '*.avif' -o -name '*.jpg' -o -name '*.mp4' \) -print0)

  while :; do
    cleanup_removed=0
    while IFS= read -r -d '' stale_thumbnail_dir; do
      printf '\tRemoving stale thumbnail directory: %s\n' "${stale_thumbnail_dir#"$thumbs_dir"/}"
      if rmdir -- "$stale_thumbnail_dir"; then cleanup_removed=1; fi
    done < <(find -P "$thumbs_dir" -mindepth 1 -depth -type d -empty -print0)
    ((cleanup_removed)) || break
  done

  while IFS= read -r -d '' metadata; do
    [[ -n ${expected_metadata["$metadata"]+present} ]] && continue
    stale_metadata_relative=${metadata#"$metadata_dir"/}
    printf '\tRemoving stale metadata: %s\n' "$stale_metadata_relative"
    rm -f -- "$metadata"
  done < <(find -P "$metadata_dir" -type f -name '*.json' -print0)

  while IFS= read -r -d '' checksum_file; do
    [[ -n ${expected_checksums["$checksum_file"]+present} ]] && continue
    stale_relative=${checksum_file#"$metadata_dir"/}
    printf '\tRemoving stale checksum manifest: %s\n' "$stale_relative"
    rm -f -- "$checksum_file"
  done < <(find -P "$metadata_dir" -type f -name 'md5sums.txt' -print0)

  while :; do
    cleanup_removed=0
    while IFS= read -r -d '' stale_metadata_dir; do
      printf '\tRemoving stale metadata directory: %s\n' "${stale_metadata_dir#"$metadata_dir"/}"
      if rmdir -- "$stale_metadata_dir"; then cleanup_removed=1; fi
    done < <(find -P "$metadata_dir" -mindepth 1 -depth -type d -empty -print0)
    ((cleanup_removed)) || break
  done

  if (( thumbnail_failed != 0 )); then die 'one or more thumbnails could not be generated'; fi

  echo 'Thumbnail update complete'
}
