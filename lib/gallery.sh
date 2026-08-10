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

gallery_is_video() {
  case "${1##*.}" in
    mp4|m4v|mov|mkv|webm|avi|mpeg|mpg|ts|mts) return 0 ;;
    *) return 1 ;;
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

gallery_render_album() {
  local album_dir=$1 album_rel=$2 thumbs_dir=$3 output_dir=$4 thumbnail_size=$5 thumbnail_display_mode=$6
  local album_name source relative thumb_path medium_path web_video_path media_url medium_url thumb_url title child child_name
  local preview_source preview_relative preview_thumb_path preview_url gallery_id item_index viewer_url child_count
  local -a sources=() preview_sources=()

  album_name=${album_dir%/}; album_name=${album_name##*/}
  while IFS= read -r -d '' source; do sources+=("$source"); done < <(gallery_find_media "$album_dir")

  while IFS= read -r -d '' source; do preview_sources+=("$source"); done < <(gallery_find_album_cover "$album_dir")
  if ((${#preview_sources[@]} == 0)); then
    while IFS= read -r -d '' source; do preview_sources+=("$source"); done < <(gallery_find_first_media "$album_dir")
  fi
  preview_source=${preview_sources[0]:-}
  child_count=0
  for child in "$album_dir"/*/; do
    [[ -d "$child" ]] || continue
    child_count=$((child_count + 1))
  done
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
      viewer_url=$medium_url
      if gallery_is_video "$source"; then
        web_video_path="${thumb_path%.webp}.web.mp4"
        viewer_url=$(realpath --relative-to="$output_dir" "$web_video_path")
        viewer_url=$(gallery_url_escape_path "$viewer_url")
      fi
      (( item_index > 0 )) && printf ','
      gallery_print_template item.html \
        "$(gallery_js_escape "$thumb_url")" "$(gallery_js_escape "$viewer_url")" \
        "$(gallery_js_escape "$media_url")" "$(gallery_js_escape "$title")"
      item_index=$((item_index + 1))
    done
    gallery_print_template items-end.html
  fi

  for child in "$album_dir"/*/; do
    [[ -d "$child" ]] || continue
    child_name=${child%/}; child_name=${child_name##*/}
    gallery_render_album "$child" "$album_rel/$child_name" "$thumbs_dir" "$output_dir" \
      "$thumbnail_size" "$thumbnail_display_mode"
  done
  gallery_print_template album-end.html
}

generate_gallery() {
  local script_dir=$1 albums_dir=$2 output_dir=$3 thumbs_dir=$4 thumbnail_size=$5 thumbnail_display_mode=$6
  local index_tmp index_template fragment_dir fragment_tmp album_path album_name album_index album_list
  gallery_next_id=0
  gallery_template_dir="$script_dir/templates/gallery"

  echo "Generating gallery in $output_dir"
  mkdir -p -- "$output_dir/assets"
  fragment_dir="$output_dir/albums"
  mkdir -p -- "$fragment_dir"
  find -P "$fragment_dir" -type f -name 'album-*.html' -delete
  album_list=
  album_index=0
  shopt -s nullglob
  for album_path in "$albums_dir"/*/; do
    [[ -d "$album_path" ]] || continue
    album_index=$((album_index + 1))
    album_name=${album_path%/}; album_name=${album_name##*/}
    fragment_tmp=$(mktemp "$fragment_dir/.album-XXXXXX")
    gallery_render_album "$album_path" "$album_name" "$thumbs_dir" "$output_dir" \
      "$thumbnail_size" "$thumbnail_display_mode" >"$fragment_tmp"
    mv -f -- "$fragment_tmp" "$fragment_dir/album-$album_index.html"
    [[ -n "$album_list" ]] && album_list+=,
    album_list+=$(printf '{"url":"albums/album-%s.html"}' "$album_index")
  done

  index_tmp=$(mktemp)
  trap 'rm -f -- "$index_tmp"' EXIT
  index_template=$(<"$script_dir/templates/index.html.template")
  index_template=${index_template//__THUMBNAIL_SIZE__/$thumbnail_size}
  index_template=${index_template//__ALBUM_LIST__/$album_list}
  [[ "$index_template" != *'__ALBUM_LIST__'* ]] || die 'gallery template is missing __ALBUM_LIST__'

  printf '%s' "$index_template" >"$index_tmp"

  mv -f -- "$index_tmp" "$output_dir/index.html"
  trap - EXIT
  echo 'Gallery generation complete'
  printf 'Gallery written to %s\n' "$output_dir/index.html"
}
