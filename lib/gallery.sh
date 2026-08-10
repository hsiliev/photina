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
    value("Model"),
    value("LensModel"),
    value("ExposureTime"),
    value("FNumber"),
    value("ISO"),
    value("FocalLength"),
    value("GPSLatitude"),
    value("GPSLongitude")
  ' -- "$1" 2>/dev/null
}

gallery_metadata_description() {
  local description='' map_url latitude longitude
  local description_value=$1 date camera lens exposure aperture iso focal_length
  date=$2; camera=$3; lens=$4; exposure=$5; aperture=$6; iso=$7; focal_length=$8
  local -a values=(
    "Description:$description_value" "Date:$date" "Camera:$camera" "Lens:$lens"
    "Exposure:$exposure" "Aperture:$aperture" "ISO:$iso" "Focal length:$focal_length"
  )
  local field label value

  description=''
  for field in "${values[@]}"; do
    label=${field%%:*}
    value=${field#*:}
    [[ -n "$value" ]] || continue
    description+="<div><strong>$(gallery_html_escape "$label"):</strong> $(gallery_html_escape "$value")</div>"
  done

  latitude=$9; longitude=${10}
  if [[ -n "$latitude" && -n "$longitude" ]]; then
    map_url="https://www.openstreetmap.org/?mlat=$(gallery_url_escape_path "$latitude")&mlon=$(gallery_url_escape_path "$longitude")#map=15/$latitude/$longitude"
    description+="<div><a href=\"$(gallery_html_escape "$map_url")\" target=\"_blank\" rel=\"noopener\">View map</a></div>"
  fi

  printf '%s' "$description"
}

gallery_metadata_custom_data() {
  local camera=$1 date=$2 lens=$3 exposure=$4 aperture=$5 iso=$6 focal_length=$7
  jq -cn --arg camera "$camera" --arg date "$date" --arg lens "$lens" \
    --arg exposure "$exposure" --arg aperture "$aperture" --arg iso "$iso" \
    --arg focalLength "$focal_length" \
    '{camera:$camera,date:$date,lens:$lens,exposure:$exposure,aperture:$aperture,iso:$iso,focalLength:$focalLength}
     | with_entries(select(.value != ""))'
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

gallery_render_album() {
  local album_dir=$1 album_rel=$2 thumbs_dir=$3 metadata_dir=$4 output_dir=$5 thumbnail_size=$6 thumbnail_display_mode=$7
  local album_name source relative metadata_path thumb_path medium_path web_video_path media_url medium_url thumb_url title description exif_location custom_data child child_name
  local preview_source preview_relative preview_thumb_path preview_url gallery_id item_index viewer_url child_count
  local -a sources=() preview_sources=() metadata_values=()

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
      custom_data='{}'
      if [[ -f "$metadata_path" ]]; then
        mapfile -t metadata_values < <(gallery_metadata_values "$metadata_path")
        description=$(gallery_metadata_description \
          "${metadata_values[0]:-}" "${metadata_values[1]:-}" "${metadata_values[2]:-}" \
          "${metadata_values[3]:-}" "${metadata_values[4]:-}" "${metadata_values[5]:-}" \
          "${metadata_values[6]:-}" "${metadata_values[7]:-}" "${metadata_values[8]:-}" \
          "${metadata_values[9]:-}")
        exif_location=$(gallery_metadata_location "${metadata_values[8]:-}" "${metadata_values[9]:-}")
        custom_data=$(gallery_metadata_custom_data \
          "${metadata_values[2]:-}" "${metadata_values[1]:-}" "${metadata_values[3]:-}" \
          "${metadata_values[4]:-}" "${metadata_values[5]:-}" "${metadata_values[6]:-}" \
          "${metadata_values[7]:-}")
      fi
      viewer_url=$medium_url
      if gallery_needs_web_video "$source"; then
        web_video_path="${thumb_path%.webp}.web.mp4"
        viewer_url=$(realpath --relative-to="$output_dir" "$web_video_path")
        viewer_url=$(gallery_url_escape_path "$viewer_url")
      fi
      (( item_index > 0 )) && printf ','
      if [[ -n "$description" ]]; then
        gallery_print_template item-with-description.html \
          "$(gallery_js_escape "$thumb_url")" "$(gallery_js_escape "$viewer_url")" \
          "$(gallery_js_escape "$media_url")" "$(gallery_js_escape "$media_url")" \
          "$(gallery_js_escape "$title")" "$(gallery_js_escape "$description")" \
          "$(gallery_js_escape "$exif_location")" "$custom_data"
      elif [[ -n "$exif_location" || "$custom_data" != '{}' ]]; then
        gallery_print_template item-with-metadata.html \
          "$(gallery_js_escape "$thumb_url")" "$(gallery_js_escape "$viewer_url")" \
          "$(gallery_js_escape "$media_url")" "$(gallery_js_escape "$media_url")" \
          "$(gallery_js_escape "$title")" "$(gallery_js_escape "$exif_location")" "$custom_data"
      else
        gallery_print_template item.html \
          "$(gallery_js_escape "$thumb_url")" "$(gallery_js_escape "$viewer_url")" \
          "$(gallery_js_escape "$media_url")" "$(gallery_js_escape "$media_url")" \
          "$(gallery_js_escape "$title")"
      fi
      item_index=$((item_index + 1))
      gallery_image_count=$((gallery_image_count + 1))
      if (( gallery_image_count % 10 == 0 )); then
        printf '.' >&3
      fi
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
  local album_dir=$1 album_rel=$2 thumbs_dir=$3 metadata_dir=$4 output_dir=$5 fragment_dir=$6 force=$7
  local child child_name child_rel fragment_tmp fragment_path

  while IFS= read -r -d '' child; do
    child_name=${child%/}; child_name=${child_name##*/}
    child_rel="$album_rel/$child_name"
    fragment_path="$fragment_dir/$child_rel.html"
    if [[ "$force" != 1 && -f "$fragment_path" ]]; then
      gallery_write_nested_fragments "$child" "$child_rel" "$thumbs_dir" "$metadata_dir" \
        "$output_dir" "$fragment_dir" "$force"
      continue
    fi
    mkdir -p -- "$(dirname -- "$fragment_path")"
    fragment_tmp=$(mktemp "$(dirname -- "$fragment_path")/.fragment-XXXXXX")
    gallery_render_album "$child" "$child_rel" "$thumbs_dir" "$metadata_dir" "$output_dir" \
      "$thumbnail_size" "$thumbnail_display_mode" 3>&1 >"$fragment_tmp"
    mv -f -- "$fragment_tmp" "$fragment_path"
    gallery_write_nested_fragments "$child" "$child_rel" "$thumbs_dir" "$metadata_dir" \
      "$output_dir" "$fragment_dir" "$force"
  done < <(gallery_find_child_albums "$album_dir")
}

generate_gallery() {
  local script_dir=$1 albums_dir=$2 output_dir=$3 thumbs_dir=$4 metadata_dir=$5 thumbnail_size=$6 thumbnail_display_mode=$7 force=${8:-0}
  local index_tmp index_template fragment_dir fragment_tmp fragment_path fragment_rel album_path album_name album_list
  local backup_dir old_entry
  gallery_next_id=0
  gallery_template_dir="$script_dir/templates/gallery"

  echo "Generating gallery in $output_dir"
  mkdir -p -- "$output_dir"
  backup_dir="$output_dir/backup"
  [[ ! -e "$backup_dir" ]] || die "gallery backup directory already exists: $backup_dir"
  if (( force )); then
    mkdir -- "$backup_dir"
    echo "Backing up existing gallery files to $backup_dir"
    while IFS= read -r -d '' old_entry; do
      mv -- "$old_entry" "$backup_dir/"
    done < <(find -P "$output_dir" -mindepth 1 -maxdepth 1 ! -path "$backup_dir" -print0)
  fi
  mkdir -p -- "$output_dir/assets"
  fragment_dir="$output_dir/albums"
  mkdir -p -- "$fragment_dir"
  if (( force )); then
    echo "Cleaning old album fragments in $fragment_dir"
    find -P "$fragment_dir" -type f -name '*.html' -delete
  fi
  album_list=
  while IFS= read -r -d '' album_path; do
    album_name=${album_path%/}; album_name=${album_name##*/}
    printf 'Generating album fragment: %s ' "$album_name"
    gallery_image_count=0
    fragment_rel="$album_name.html"
    fragment_path="$fragment_dir/$fragment_rel"
    if [[ "$force" != 1 && -f "$fragment_path" ]]; then
      echo ' skipped'
      gallery_write_nested_fragments "$album_path" "$album_name" "$thumbs_dir" "$metadata_dir" \
        "$output_dir" "$fragment_dir" "$force"
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
      "$output_dir" "$fragment_dir" "$force"
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
  if (( force )); then
    rm -rf -- "$backup_dir"
    echo "Removed gallery backup $backup_dir"
  fi
  echo 'Gallery generation complete'
  printf 'Gallery written to %s\n' "$output_dir/index.html"
}
