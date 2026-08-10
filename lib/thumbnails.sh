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

thumbnail_write_metadata() {
  local source=$1 metadata=$2
  local metadata_tmp=${metadata%.json}.generating.json
  mkdir -p -- "$(dirname -- "$metadata")"
  exiftool -j -G1 -n -- "$source" | jq -c '.' >"$metadata_tmp"
  mv -f -- "$metadata_tmp" "$metadata"
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
  local directory=$1 kind=$2
  local -a extensions find_args
  if [[ "$kind" == image ]]; then
    extensions=("${IMAGE_EXTENSIONS[@]}")
  else
    extensions=("${VIDEO_EXTENSIONS[@]}")
  fi
  find_args=(-P "$directory" -type f '(')
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
  local display_name=${5:-${source##*/}} medium_size=$6 metadata=$7
  local thumbnail_tmp=${thumbnail%.webp}.generating.webp
  local medium=${thumbnail%.webp}_medium.webp
  local medium_tmp=${medium%.webp}.generating.webp
  local video_frame_tmp=${thumbnail%.webp}.video.jpg
  local web_video=${thumbnail%.webp}.web.mp4
  local web_video_tmp=${web_video%.mp4}.generating.mp4
  local progress=$display_name

  mkdir -p -- "$(dirname -- "$thumbnail")"
  if thumbnail_is_video "$source"; then
    progress+=' ➤ 🎞️ video frame'
    ffmpegthumbnailer -i "$source" -o "$video_frame_tmp" -s "$thumbnail_size" -q 8 -f >/dev/null 2>&1
    "$image_tool" "$video_frame_tmp" \
      \( +clone -thumbnail "${thumbnail_size}x${thumbnail_size}^" \
        -gravity center -extent "$thumbnail_size"x"$thumbnail_size" -background white -alpha remove \
        -alpha off -strip -quality 86 -write "$thumbnail_tmp" +delete \) \
      \( +clone -thumbnail "${medium_size}x${medium_size}>" \
        -background white -alpha remove -alpha off -strip -quality 86 -write "$medium_tmp" +delete \) \
      null:
    thumbnail_write_metadata "$source" "$metadata"
    if thumbnail_needs_web_video "$source"; then
      progress+=' ➤ 🎬 web video'
      ffmpeg -i "$source" -c:v libx264 -pix_fmt yuv420p -c:a aac -movflags +faststart -y "$web_video_tmp" \
        >/dev/null 2>&1
    fi
  else
    "$image_tool" "$source" -auto-orient \
      \( +clone -thumbnail "${thumbnail_size}x${thumbnail_size}^" \
        -gravity center -extent "$thumbnail_size"x"$thumbnail_size" -background white -alpha remove \
        -alpha off -strip -quality 86 -write "$thumbnail_tmp" +delete \) \
      \( +clone -thumbnail "${medium_size}x${medium_size}>" \
        -strip -quality 90 -write "$medium_tmp" +delete \) \
      null:
    thumbnail_write_metadata "$source" "$metadata"
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
  local source=$1 album_path=$2 album_name=$3 thumbs_dir=$4 metadata_dir=$5 thumbnail_size=$6 image_tool=$7 relative medium_size thumbnail metadata force
  relative=${source#"$album_path"}; relative=${relative#/}
  thumbnail="$thumbs_dir/$album_name/$relative.webp"
  metadata="$metadata_dir/$album_name/$relative.json"
  medium_size=$8
  force=$9
  if [[ "$force" != 1 && -f "$metadata" ]]; then
    :
  elif [[ "$force" == 1 || ! -f "$thumbnail" || ! -f "${thumbnail%.webp}_medium.webp" ]]; then
    :
  else
    thumbnail_write_metadata "$source" "$metadata"
    printf '\t%s\n' "$relative"
    return 0
  fi
  if thumbnail_needs_web_video "$source"; then
    [[ "$force" == 1 || ! -f "$thumbnail" || ! -f "${thumbnail%.webp}_medium.webp" || ! -f "${thumbnail%.webp}.web.mp4" ]] || return 0
  else
    [[ "$force" == 1 || ! -f "$thumbnail" || ! -f "${thumbnail%.webp}_medium.webp" ]] || return 0
  fi
  thumbnail_make "$source" "$thumbnail" "$thumbnail_size" "$image_tool" "$relative" "$medium_size" "$metadata"
}

# shellcheck disable=SC2016
thumbnail_batch_album() {
  local album_path=$1 album_name=$2 thumbs_dir=$3 metadata_dir=$4 thumbnail_size=$5 medium_size=$6 image_tool=$7 parallel_jobs=$8 kind=$9 force=${10}
  export -f thumbnail_is_video thumbnail_needs_web_video thumbnail_write_metadata thumbnail_make thumbnail_process_item

  if [[ "$kind" == image ]]; then
    thumbnail_find_media "$album_path" image
  else
    thumbnail_find_media "$album_path" video
  fi |
    if ! xargs -0 -r -n 1 -P "$parallel_jobs" bash -c '
      thumbnail_process_item "$9" "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8"
    ' _ "$album_path" "$album_name" "$thumbs_dir" "$metadata_dir" "$thumbnail_size" "$image_tool" "$medium_size" "$force"; then
    return 1
  fi
}

update_thumbnails() {
  local albums_dir=$1 thumbs_dir=$2 metadata_dir=$3 thumbnail_size=$4 medium_size=$5 force=${6:-0}
  local image_tool parallel_jobs thumbnail_failed=0
  local album_path album_name source relative thumb_path medium_path web_video_path
  local thumbnail stale_relative
  local metadata stale_metadata_relative
  declare -A expected_thumbnails=() expected_metadata=()

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
  for album_path in "$albums_dir"/*/; do
    [[ -d "$album_path" ]] || continue
    album_name=${album_path%/}; album_name=${album_name##*/}
    echo "Scanning album: $album_name"
    while IFS= read -r -d '' source; do
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
    done < <(thumbnail_find_media "$album_path" image; thumbnail_find_media "$album_path" video | sort -z)
    thumbnail_batch_album "$album_path" "$album_name" "$thumbs_dir" "$metadata_dir" "$thumbnail_size" "$medium_size" "$image_tool" "$parallel_jobs" image "$force" || thumbnail_failed=1
    thumbnail_batch_album "$album_path" "$album_name" "$thumbs_dir" "$metadata_dir" "$thumbnail_size" "$medium_size" "$image_tool" "$parallel_jobs" video "$force" || thumbnail_failed=1
  done
  if (( thumbnail_failed != 0 )); then die 'one or more thumbnails could not be generated'; fi

  while IFS= read -r -d '' thumbnail; do
    [[ -n ${expected_thumbnails["$thumbnail"]+present} ]] && continue
    stale_relative=${thumbnail#"$thumbs_dir"/}
    printf '\tRemoving stale thumbnail: %s\n' "$stale_relative"
    rm -f -- "$thumbnail"
  done < <(find -P "$thumbs_dir" -type f \( -name '*.webp' -o -name '*.avif' -o -name '*.jpg' -o -name '*.mp4' \) -print0)

  while IFS= read -r -d '' metadata; do
    [[ -n ${expected_metadata["$metadata"]+present} ]] && continue
    stale_metadata_relative=${metadata#"$metadata_dir"/}
    printf '\tRemoving stale metadata: %s\n' "$stale_metadata_relative"
    rm -f -- "$metadata"
  done < <(find -P "$metadata_dir" -type f -name '*.json' -print0)

  echo 'Thumbnail update complete'
}
