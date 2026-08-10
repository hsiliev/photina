#!/usr/bin/env bash

thumbnail_is_video() {
  case "${1##*.}" in
    mp4|m4v|mov|mkv|webm|avi|mpeg|mpg|ts|mts) return 0 ;;
    *) return 1 ;;
  esac
}

thumbnail_make() {
  local source=$1 thumbnail=$2 thumbnail_size=$3 image_tool=$4 display_name=${5:-${source##*/}}
  local thumbnail_tmp=${thumbnail%.jpg}.generating.jpg
  local processed_tmp=${thumbnail%.jpg}.generated.jpg
  local ready_tmp

  printf '\t%s\n' "$display_name"
  mkdir -p -- "$(dirname -- "$thumbnail")"
  if thumbnail_is_video "$source"; then
    ffmpegthumbnailer -i "$source" -o "$thumbnail_tmp" -s "$thumbnail_size" -q 8 -f >/dev/null 2>&1
    "$image_tool" "$thumbnail_tmp" -thumbnail "${thumbnail_size}x${thumbnail_size}^" \
      -gravity center -extent "$thumbnail_size"x"$thumbnail_size" -background white -alpha remove \
      -alpha off -strip -quality 86 "$processed_tmp"
    ready_tmp=$processed_tmp
  else
    "$image_tool" "$source" -auto-orient -thumbnail "${thumbnail_size}x${thumbnail_size}^" \
      -gravity center -extent "$thumbnail_size"x"$thumbnail_size" -background white -alpha remove \
      -alpha off -strip -quality 86 "$thumbnail_tmp"
    ready_tmp=$thumbnail_tmp
  fi

  mv -f -- "$ready_tmp" "$thumbnail"
  rm -f -- "$thumbnail_tmp" "$processed_tmp"
}

update_thumbnails() {
  local albums_dir=$1 thumbs_dir=$2 thumbnail_size=$3 force=${4:-0}
  local image_tool parallel_jobs thumbnail_failed=0
  local album_path album_name source relative thumb_path
  local -a thumbnail_pids=()

  if command -v magick >/dev/null; then
    image_tool=magick
  elif command -v convert >/dev/null; then
    image_tool=convert
  else
    die 'ImageMagick (magick or convert) is required'
  fi
  if command -v nproc >/dev/null; then
    parallel_jobs=$(nproc)
  else
    parallel_jobs=1
  fi
  (( parallel_jobs > 0 )) || parallel_jobs=1

  echo "Updating thumbnails in $thumbs_dir"
  echo "Image tool: $image_tool"
  echo "Thumbnail workers: $parallel_jobs"
  mkdir -p -- "$thumbs_dir"

  shopt -s nullglob
  for album_path in "$albums_dir"/*/; do
    [[ -d "$album_path" ]] || continue
    album_name=${album_path%/}; album_name=${album_name##*/}
    echo "Scanning album: $album_name"
    while IFS= read -r -d '' source; do
      relative=${source#"$album_path"}; relative=${relative#/}
      thumb_path="$thumbs_dir/$album_name/$relative.jpg"
      [[ "$force" == 1 || ! -f "$thumb_path" ]] || continue
      thumbnail_make "$source" "$thumb_path" "$thumbnail_size" "$image_tool" "$relative" &
      thumbnail_pids+=("$!")
      while (( ${#thumbnail_pids[@]} >= parallel_jobs )); do
        if ! wait "${thumbnail_pids[0]}"; then thumbnail_failed=1; fi
        thumbnail_pids=("${thumbnail_pids[@]:1}")
      done
    done < <(find -P "$album_path" -type f \( \
      -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.webp' \
      -o -iname '*.bmp' -o -iname '*.tif' -o -iname '*.tiff' -o -iname '*.avif' -o -iname '*.heic' -o -iname '*.heif' \
      -o -iname '*.mp4' -o -iname '*.m4v' -o -iname '*.mov' -o -iname '*.mkv' -o -iname '*.webm' \
      -o -iname '*.avi' -o -iname '*.mpeg' -o -iname '*.mpg' -o -iname '*.ts' -o -iname '*.mts' \) -print0 | sort -z)
  done

  while (( ${#thumbnail_pids[@]} > 0 )); do
    if ! wait "${thumbnail_pids[0]}"; then thumbnail_failed=1; fi
    thumbnail_pids=("${thumbnail_pids[@]:1}")
  done
  if (( thumbnail_failed != 0 )); then die 'one or more thumbnails could not be generated'; fi
  echo 'Thumbnail update complete'
}
