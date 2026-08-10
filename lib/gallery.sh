#!/usr/bin/env bash

gallery_html_escape() {
  local value=$1
  value=${value//&/&amp;}; value=${value//</&lt;}; value=${value//>/&gt;}
  value=${value//\"/&quot;}; value=${value//\'/&#39;}
  printf '%s' "$value"
}

gallery_url_escape_path() {
  local value=$1
  value=${value//%/%25}; value=${value//\ /%20}; value=${value//\#/%23}
  value=${value//\?/%3F}; value=${value//\"/%22}; value=${value//\'/%27}
  printf '%s' "$value"
}

gallery_is_video() {
  case "${1##*.}" in
    mp4|m4v|mov|mkv|webm|avi|mpeg|mpg|ts|mts) return 0 ;;
    *) return 1 ;;
  esac
}

gallery_make_thumbnail() {
  local source=$1 thumbnail=$2 thumbnail_size=$3 image_tool=$4
  local thumbnail_tmp=${thumbnail%.jpg}.generating.jpg
  local processed_tmp=${thumbnail%.jpg}.generated.jpg
  local ready_tmp

  printf '\t%s\n' "$source"
  mkdir -p -- "$(dirname -- "$thumbnail")"
  if gallery_is_video "$source"; then
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

generate_gallery() {
  local script_dir=$1 albums_dir=$2 output_dir=$3 thumbs_dir=$4 thumbnail_size=$5
  local image_tool index_tmp index_template index_head index_tail
  local parallel_jobs thumbnail_failed=0
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

  mkdir -p -- "$output_dir/assets" "$thumbs_dir"
  index_tmp=$(mktemp)
  trap 'rm -f -- "$index_tmp"' EXIT
  index_template=$(<"$script_dir/resources/index.html.template")
  index_template=${index_template//__THUMBNAIL_SIZE__/$thumbnail_size}
  index_head=${index_template%%__GALLERY_ITEMS__*}
  index_tail=${index_template#*__GALLERY_ITEMS__}
  [[ "$index_head" != "$index_template" ]] || die 'gallery template is missing __GALLERY_ITEMS__'

  {
    printf '%s' "$index_head"
    shopt -s nullglob
    local album_found=0 album_path album_name relative source thumb_path
    local media_url thumb_url title

    for album_path in "$albums_dir"/*/; do
      [[ -d "$album_path" ]] || continue
      album_found=1
      album_name=${album_path%/}; album_name=${album_name##*/}
      printf '  <section class="album"><h2>%s</h2>\n' "$(gallery_html_escape "$album_name")"
      printf "    <div data-nanogallery2='{\"thumbnailHeight\":%s,\"thumbnailWidth\":%s,\"thumbnailLabel\":{\"display\":true},\"viewerTools\":{\"topLeft\":\"label\"}}'>\n" \
        "$thumbnail_size" "$thumbnail_size"

      while IFS= read -r -d '' source; do
        relative=${source#"$album_path"}; relative=${relative#/}
        thumb_path="$thumbs_dir/$album_name/$relative.jpg"
        if [[ ! -f "$thumb_path" ]]; then
          gallery_make_thumbnail "$source" "$thumb_path" "$thumbnail_size" "$image_tool" &
          thumbnail_pids+=("$!")
          while (( ${#thumbnail_pids[@]} >= parallel_jobs )); do
            if ! wait "${thumbnail_pids[0]}"; then thumbnail_failed=1; fi
            thumbnail_pids=("${thumbnail_pids[@]:1}")
          done
        fi

        media_url="media/$(gallery_url_escape_path "$album_name/$relative")"
        thumb_url=$(realpath --relative-to="$output_dir" "$thumb_path")
        thumb_url=$(gallery_url_escape_path "$thumb_url")
        title=${relative##*/}; title=${title%.*}
        printf '      <a href="%s" data-ngthumb="%s" data-ngdesc="%s">%s</a>\n' \
          "$(gallery_html_escape "$media_url")" "$(gallery_html_escape "$thumb_url")" \
          "$(gallery_html_escape "$title")" "$(gallery_html_escape "$title")"
      done < <(find -P "$album_path" -type f \( \
        -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.webp' \
        -o -iname '*.bmp' -o -iname '*.tif' -o -iname '*.tiff' -o -iname '*.avif' -o -iname '*.heic' -o -iname '*.heif' \
        -o -iname '*.mp4' -o -iname '*.m4v' -o -iname '*.mov' -o -iname '*.mkv' -o -iname '*.webm' \
        -o -iname '*.avi' -o -iname '*.mpeg' -o -iname '*.mpg' -o -iname '*.ts' -o -iname '*.mts' \) -print0 | sort -z)
      printf '    </div></section>\n'
    done
    (( album_found )) || printf '  <p>No albums found.</p>\n'

    while (( ${#thumbnail_pids[@]} > 0 )); do
      if ! wait "${thumbnail_pids[0]}"; then thumbnail_failed=1; fi
      thumbnail_pids=("${thumbnail_pids[@]:1}")
    done
    if (( thumbnail_failed != 0 )); then die 'one or more thumbnails could not be generated'; fi
    printf '%s' "$index_tail"
  } >"$index_tmp"

  mv -f -- "$index_tmp" "$output_dir/index.html"
  trap - EXIT
  printf 'Gallery written to %s\nThumbnails written to %s\n' "$output_dir/index.html" "$thumbs_dir"
}
