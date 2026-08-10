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

gallery_js_escape() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  printf '%s' "$value"
}

gallery_metadata_values() {
  jq -r '
    .[0] as $m |
    def value($tag): ([ $m | to_entries[] |
      select(.key == $tag or (.key | endswith(":" + $tag))) | .value ][0] // "") | tostring;
    value("Description"),
    value("DateTimeOriginal"),
    value("Make"),
    value("Model"),
    value("LensModel"),
    value("ExposureTime"),
    value("FNumber"),
    value("ISO"),
    value("FocalLength"),
    value("Flash"),
    value("GPSLatitude"),
    value("GPSLongitude")
    ' -- "$1" 2>/dev/null
}

gallery_metadata_location() {
  local latitude=$1 longitude=$2
  [[ -n "$latitude" && -n "$longitude" ]] || return 0
  printf '%s, %s' "$latitude" "$longitude"
}

gallery_is_video() {
  local extension=${1##*.}
  extension=${extension,,}
  case "$extension" in
    mp4|m4v|mov|mkv|webm|avi|mpeg|mpg|ts|mts) return 0 ;;
    *) return 1 ;;
  esac
}

gallery_needs_web_video() {
  local extension=${1##*.}
  extension=${extension,,}
  case "$extension" in
    mp4) return 1 ;;
    *) gallery_is_video "$1" ;;
  esac
}

gallery_print_template() {
  local template_name=$1
  shift
  local template_content
  template_content=$(<"$gallery_template_dir/$template_name")
  # shellcheck disable=SC2059
  printf "$template_content" "$@"
}

gallery_find_media() {
  local directory=$1 scope=${2:-direct} extension first=1
  local -a find_args=(-P "$directory")
  [[ "$scope" == direct ]] && find_args+=(-mindepth 1 -maxdepth 1)
  find_args+=(-type f '(')
  for extension in "${IMAGE_EXTENSIONS[@]}" "${VIDEO_EXTENSIONS[@]}"; do
    (( first )) || find_args+=(-o)
    find_args+=(-iname "*.$extension")
    first=0
  done
  find_args+=(')' -print0)
  find "${find_args[@]}" | sort -z
}

gallery_find_first_media() {
  gallery_find_media "$1" all | head -z -n 1
}

gallery_find_album_cover() {
  find -P "$1" -mindepth 1 -maxdepth 1 -type f -iname 'album.jpg' -print0 | sort -z | head -z -n 1
}

gallery_find_child_albums() {
  find -P "$1" -mindepth 1 -maxdepth 1 -type d -print0 | LC_ALL=C sort -z
}

gallery_render_media_item() {
  local source=$1 album_dir=$2 album_rel=$3 thumbs_dir=$4 metadata_dir=$5 output_dir=$6 item_index=$7
  local relative metadata_path thumb_path medium_path web_video_path media_url medium_url thumb_url
  local title description exif_location exif_model exif_time exif_lens exif_focal_length exif_fstop exif_iso exif_exposure exif_flash viewer_url
  local -a metadata_values=()

  relative=${source#"$album_dir"}; relative=${relative#/}
  thumb_path="$thumbs_dir/$album_rel/$relative.webp"
  medium_path="${thumb_path%.webp}_medium.webp"
  media_url="media/$(gallery_url_escape_path "$album_rel/$relative")"
  medium_url=$(realpath --relative-to="$output_dir" "$medium_path")
  medium_url=$(gallery_url_escape_path "$medium_url")
  thumb_url=$(realpath --relative-to="$output_dir" "$thumb_path")
  thumb_url=$(gallery_url_escape_path "$thumb_url")
  title=${relative##*/}; title=${title%.*}

  metadata_path="$metadata_dir/$album_rel/$relative.json"
  description=''
  exif_location=''
  exif_model=''
  exif_time=''
  exif_lens=''
  exif_focal_length=''
  exif_fstop=''
  exif_iso=''
  exif_exposure=''
  exif_flash=''
  if [[ -f "$metadata_path" ]]; then
    mapfile -t metadata_values < <(gallery_metadata_values "$metadata_path")
    description=${metadata_values[0]:-}
    exif_model=${metadata_values[3]:-}
    if [[ -n "${metadata_values[2]:-}" && "${metadata_values[2]}" != "$exif_model" ]]; then
      exif_model="${metadata_values[2]} $exif_model"
    fi
    exif_time=${metadata_values[1]:-}
    exif_lens=${metadata_values[4]:-}
    exif_exposure=${metadata_values[5]:-}
    exif_fstop=${metadata_values[6]:-}
    exif_iso=${metadata_values[7]:-}
    exif_focal_length=${metadata_values[8]:-}
    exif_flash=${metadata_values[9]:-}
    exif_location=$(gallery_metadata_location "${metadata_values[10]:-}" "${metadata_values[11]:-}")
    if [[ -n "$description" && -n "$exif_lens" ]]; then
      description="Description: $description | Lens: $exif_lens"
    elif [[ -n "$exif_lens" ]]; then
      description="Lens: $exif_lens"
    elif [[ -n "$description" ]]; then
      description="Description: $description"
    fi
  fi

  viewer_url=$medium_url
  if gallery_needs_web_video "$source"; then
    web_video_path="${thumb_path%.webp}.web.mp4"
    viewer_url=$(realpath --relative-to="$output_dir" "$web_video_path")
    viewer_url=$(gallery_url_escape_path "$viewer_url")
  fi

  (( item_index > 0 )) && printf ','
  if [[ -n "$description" || -n "$exif_location" || -n "$exif_model" || -n "$exif_time" || \
          -n "$exif_focal_length" || -n "$exif_fstop" || -n "$exif_iso" || \
          -n "$exif_exposure" || -n "$exif_flash" ]]; then
    gallery_print_template item-with-metadata.html \
      "$(gallery_js_escape "$thumb_url")" "$(gallery_js_escape "$viewer_url")" \
      "$(gallery_js_escape "$media_url")" "$(gallery_js_escape "$media_url")" \
      "$(gallery_js_escape "$title")" "$(gallery_js_escape "$description")" \
      "$(gallery_js_escape "$exif_model")" \
      "$(gallery_js_escape "$exif_time")" "$(gallery_js_escape "$exif_focal_length")" \
      "$(gallery_js_escape "$exif_fstop")" "$(gallery_js_escape "$exif_iso")" \
      "$(gallery_js_escape "$exif_exposure")" "$(gallery_js_escape "$exif_flash")" \
      "$(gallery_js_escape "$exif_location")"
  else
    gallery_print_template item.html \
      "$(gallery_js_escape "$thumb_url")" "$(gallery_js_escape "$viewer_url")" \
      "$(gallery_js_escape "$media_url")" "$(gallery_js_escape "$media_url")" \
      "$(gallery_js_escape "$title")" "$(gallery_js_escape "$exif_model")" \
      "$(gallery_js_escape "$exif_time")" "$(gallery_js_escape "$exif_focal_length")" \
      "$(gallery_js_escape "$exif_fstop")" "$(gallery_js_escape "$exif_iso")" \
      "$(gallery_js_escape "$exif_exposure")" "$(gallery_js_escape "$exif_location")"
  fi

  gallery_image_count=$((gallery_image_count + 1))
  if (( gallery_image_count % 10 == 0 )); then
    printf '.' >&3
  fi
}

gallery_render_album() {
  local album_dir=$1 album_rel=$2 thumbs_dir=$3 metadata_dir=$4 output_dir=$5 thumbnail_size=$6 thumbnail_display_mode=$7
  local album_name source child child_name
  local preview_source preview_relative preview_thumb_path preview_url gallery_id item_index child_count
  local -a sources=() preview_sources=()

  album_name=${album_dir%/}; album_name=${album_name##*/}
  while IFS= read -r -d '' source; do sources+=("$source"); done < <(gallery_find_media "$album_dir")

  while IFS= read -r -d '' source; do preview_sources+=("$source"); done < <(gallery_find_album_cover "$album_dir")
  if ((${#preview_sources[@]} == 0)); then
    while IFS= read -r -d '' source; do preview_sources+=("$source"); done < <(gallery_find_first_media "$album_dir")
  fi
  preview_source=${preview_sources[0]:-}
  child_count=0
  while IFS= read -r -d '' child; do
    child_count=$((child_count + 1))
  done < <(gallery_find_child_albums "$album_dir")
  if [[ -n "$preview_source" ]]; then
    preview_relative=${preview_source#"$album_dir"}; preview_relative=${preview_relative#/}
    preview_thumb_path="$thumbs_dir/$album_rel/$preview_relative.webp"
    preview_url=$(realpath --relative-to="$output_dir" "$preview_thumb_path")
    preview_url=$(gallery_html_escape "$(gallery_url_escape_path "$preview_url")")
    if (( child_count > 0 )); then
      gallery_print_template album-parent-preview.html "$preview_url" "$(gallery_html_escape "$album_name")"
    else
      gallery_print_template album-leaf-preview.html "$preview_url" "$(gallery_html_escape "$album_name")"
    fi
  else
    if (( child_count > 0 )); then
      gallery_print_template album-parent.html "$(gallery_html_escape "$album_name")"
    else
      gallery_print_template album-leaf.html "$(gallery_html_escape "$album_name")"
    fi
  fi
  if ((${#sources[@]})); then
    gallery_next_id=$((gallery_next_id + 1))
    gallery_id="gallery-$gallery_next_id"
    gallery_print_template items-start.html \
      "$gallery_id" "$gallery_id" "$(gallery_js_escape "$thumbnail_display_mode")" "$thumbnail_size" "$thumbnail_size"
    item_index=0
    for source in "${sources[@]}"; do
      gallery_render_media_item "$source" "$album_dir" "$album_rel" "$thumbs_dir" \
        "$metadata_dir" "$output_dir" "$item_index"
      item_index=$((item_index + 1))
    done
    gallery_print_template items-end.html
  fi

  while IFS= read -r -d '' child; do
    child_name=${child%/}; child_name=${child_name##*/}
    gallery_render_album "$child" "$album_rel/$child_name" "$thumbs_dir" "$metadata_dir" "$output_dir" \
      "$thumbnail_size" "$thumbnail_display_mode"
  done < <(gallery_find_child_albums "$album_dir")
  gallery_print_template album-end.html
}

gallery_write_nested_fragments() {
  local album_dir=$1 album_rel=$2 thumbs_dir=$3 metadata_dir=$4 output_dir=$5 fragment_dir=$6
  local child child_name child_rel fragment_tmp fragment_path

  while IFS= read -r -d '' child; do
    child_name=${child%/}; child_name=${child_name##*/}
    child_rel="$album_rel/$child_name"
    fragment_path="$fragment_dir/$child_rel.html"
    printf 'Generating album fragment: %s ...' "$child_rel"
    gallery_image_count=0
    if [[ -f "$fragment_path" ]]; then
      echo ' skipped'
      gallery_write_nested_fragments "$child" "$child_rel" "$thumbs_dir" "$metadata_dir" \
        "$output_dir" "$fragment_dir"
      continue
    fi
    mkdir -p -- "$(dirname -- "$fragment_path")"
    fragment_tmp=$(mktemp "$(dirname -- "$fragment_path")/.fragment-XXXXXX")
    gallery_render_album "$child" "$child_rel" "$thumbs_dir" "$metadata_dir" "$output_dir" \
      "$thumbnail_size" "$thumbnail_display_mode" 3>&1 >"$fragment_tmp"
    printf '\n'
    mv -f -- "$fragment_tmp" "$fragment_path"
    gallery_write_nested_fragments "$child" "$child_rel" "$thumbs_dir" "$metadata_dir" \
      "$output_dir" "$fragment_dir"
  done < <(gallery_find_child_albums "$album_dir")
}

generate_gallery() {
  local script_dir=$1 albums_dir=$2 output_dir=$3 thumbs_dir=$4 metadata_dir=$5 thumbnail_size=$6 thumbnail_display_mode=$7
  local index_tmp index_template fragment_dir fragment_tmp fragment_path fragment_rel album_path album_name album_list child child_name source
  local -a direct_media=()
  gallery_next_id=0
  gallery_template_dir="$script_dir/templates/gallery"

  echo "Generating gallery in $output_dir"
  mkdir -p -- "$output_dir"
  mkdir -p -- "$output_dir/assets"
  fragment_dir="$output_dir/albums"
  mkdir -p -- "$fragment_dir"
  album_list=
  while IFS= read -r -d '' album_path; do
    album_name=${album_path%/}; album_name=${album_name##*/}
    gallery_image_count=0
    direct_media=()
    while IFS= read -r -d '' source; do direct_media+=("$source"); done < <(gallery_find_media "$album_path")
    if ((${#direct_media[@]} == 0)); then
      printf 'Generating album fragment: %s ...\n' "$album_name"
      gallery_write_nested_fragments "$album_path" "$album_name" "$thumbs_dir" "$metadata_dir" \
        "$output_dir" "$fragment_dir"
      local preview_source preview_relative preview_url= child_urls=
      while IFS= read -r -d '' preview_source; do
        preview_relative=${preview_source#"$album_path"}; preview_relative=${preview_relative#/}
        preview_url="thumbnails/$(gallery_url_escape_path "$album_name/$preview_relative.webp")"
        break
      done < <(gallery_find_album_cover "$album_path")
      if [[ -z "$preview_url" ]]; then
        while IFS= read -r -d '' preview_source; do
          preview_relative=${preview_source#"$album_path"}; preview_relative=${preview_relative#/}
          preview_url="thumbnails/$(gallery_url_escape_path "$album_name/$preview_relative.webp")"
          break
        done < <(gallery_find_first_media "$album_path")
      fi
      child_urls=
      while IFS= read -r -d '' child; do
        child_name=${child%/}; child_name=${child_name##*/}
        [[ -n "$child_urls" ]] && child_urls+=,
        child_urls+=$(printf '{"url":"albums/%s/%s.html"}' \
          "$(gallery_js_escape "$(gallery_url_escape_path "$album_name")")" \
          "$(gallery_js_escape "$(gallery_url_escape_path "$child_name")")")
      done < <(gallery_find_child_albums "$album_path")
      [[ -n "$album_list" ]] && album_list+=,
      album_list+=$(printf '{"title":"%s","thumbnail":"%s","children":[%s]}' \
        "$(gallery_js_escape "$album_name")" "$(gallery_js_escape "$preview_url")" "$child_urls")
      continue
    fi
    printf 'Generating album fragment: %s ...' "$album_name"
    fragment_rel="$album_name.html"
    fragment_path="$fragment_dir/$fragment_rel"
    if [[ -f "$fragment_path" ]]; then
      echo ' skipped'
      gallery_write_nested_fragments "$album_path" "$album_name" "$thumbs_dir" "$metadata_dir" \
        "$output_dir" "$fragment_dir"
      [[ -n "$album_list" ]] && album_list+=,
      album_list+=$(printf '{"url":"albums/%s"}' "$(gallery_url_escape_path "$fragment_rel")")
      continue
    fi
    fragment_tmp=$(mktemp "$fragment_dir/.fragment-XXXXXX")
    gallery_render_album "$album_path" "$album_name" "$thumbs_dir" "$metadata_dir" "$output_dir" \
      "$thumbnail_size" "$thumbnail_display_mode" 3>&1 >"$fragment_tmp"
    printf '\n'
    mv -f -- "$fragment_tmp" "$fragment_path"
    gallery_write_nested_fragments "$album_path" "$album_name" "$thumbs_dir" "$metadata_dir" \
      "$output_dir" "$fragment_dir"
    [[ -n "$album_list" ]] && album_list+=,
    album_list+=$(printf '{"url":"albums/%s"}' "$(gallery_url_escape_path "$fragment_rel")")
  done < <(gallery_find_child_albums "$albums_dir")

  index_tmp=$(mktemp)
  trap 'rm -f -- "$index_tmp"' EXIT
  index_template=$(<"$script_dir/templates/index.html.template")
  index_template=${index_template//__THUMBNAIL_SIZE__/$thumbnail_size}
  index_template=${index_template//__ALBUM_LIST__/$album_list}
  [[ "$index_template" != *'__ALBUM_LIST__'* ]] || die 'gallery template is missing __ALBUM_LIST__'

  echo 'Writing gallery index'
  printf '%s' "$index_template" >"$index_tmp"

  mv -f -- "$index_tmp" "$output_dir/index.html"
  trap - EXIT
  echo 'Gallery generation complete'
  printf 'Gallery written to %s\n' "$output_dir/index.html"
}
