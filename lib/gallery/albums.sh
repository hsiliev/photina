#!/usr/bin/env bash

gallery_album_preview_url() {
  local source=$1 album_dir=$2 album_rel=$3 thumbs_dir=$4 output_dir=$5
  local relative preview_url
  relative=${source#"$album_dir"}; relative=${relative#/}
  preview_url=$(gallery_thumbnail_url "$thumbs_dir/$album_rel/$relative.webp" "$album_rel/$relative.webp")
  gallery_html_escape "$preview_url"
}

gallery_render_album() {
  local album_dir=$1 album_rel=$2 thumbs_dir=$3 metadata_dir=$4 output_dir=$5 thumbnail_size=$6 thumbnail_display_mode=$7
  local album_name source child child_name preview_source preview_url gallery_id item_index child_count thumbnail_width thumbnail_height
  local -a sources=() preview_sources=()

  album_name=${album_dir%/}; album_name=${album_name##*/}
  thumbnail_width=$thumbnail_size
  thumbnail_height=$thumbnail_size
  case "$thumbnail_display_mode" in
    cascading) thumbnail_height=auto ;;
    justified) thumbnail_width=auto ;;
  esac
  gallery_image_count=0
  if gallery_album_content_is_allowed "$album_rel"; then
    while IFS= read -r -d '' source; do sources+=("$source"); done < <(gallery_find_media_by_date "$album_dir" "$album_rel" "$metadata_dir")
    while IFS= read -r -d '' source; do preview_sources+=("$source"); done < <(gallery_find_album_cover "$album_dir")
    if ((${#preview_sources[@]} == 0)); then
      while IFS= read -r -d '' source; do preview_sources+=("$source"); done < <(gallery_find_first_media "$album_dir")
    fi
  fi

  child_count=0
  while IFS= read -r -d '' child; do
    child_name=${child%/}; child_name=${child_name##*/}
    gallery_album_is_visible "$album_rel/$child_name" || continue
    child_count=$((child_count + 1))
  done < <(gallery_find_child_albums "$album_dir")
  preview_source=${preview_sources[0]:-}
  if [[ -n "$preview_source" ]]; then
    preview_url=$(gallery_album_preview_url "$preview_source" "$album_dir" "$album_rel" "$thumbs_dir" "$output_dir")
    if (( child_count > 0 )); then
      gallery_print_template album-parent-preview.html "$preview_url" "$(gallery_html_escape "$album_name")"
    else
      gallery_print_template album-leaf-preview.html "$preview_url" "$(gallery_html_escape "$album_name")"
    fi
  elif (( child_count > 0 )); then
    gallery_print_template album-parent.html "$(gallery_html_escape "$album_name")"
  else
    gallery_print_template album-leaf.html "$(gallery_html_escape "$album_name")"
  fi

  while IFS= read -r -d '' child; do
    child_name=${child%/}; child_name=${child_name##*/}
    gallery_album_is_visible "$album_rel/$child_name" || continue
    gallery_render_album "$child" "$album_rel/$child_name" "$thumbs_dir" "$metadata_dir" \
      "$output_dir" "$thumbnail_size" "$thumbnail_display_mode"
  done < <(gallery_find_child_albums "$album_dir")

  if ((${#sources[@]})); then
    gallery_next_id=$((gallery_next_id + 1))
    gallery_id="gallery-$gallery_next_id"
    gallery_print_template items-start.html "$gallery_id" "$gallery_id" \
      "$thumbnail_width" "$thumbnail_height"
    item_index=0
    for source in "${sources[@]}"; do
      gallery_render_media_item "$source" "$album_dir" "$album_rel" "$thumbs_dir" \
        "$metadata_dir" "$output_dir" "$item_index"
      item_index=$((item_index + 1))
    done
    gallery_print_template items-end.html
  fi

  gallery_print_template album-end.html
}

gallery_write_nested_fragments() {
  local album_dir=$1 album_rel=$2 thumbs_dir=$3 metadata_dir=$4 output_dir=$5 fragment_dir=$6
  local child child_name child_rel fragment_tmp fragment_path

  while IFS= read -r -d '' child; do
    child_name=${child%/}; child_name=${child_name##*/}
    child_rel="$album_rel/$child_name"
    gallery_album_is_visible "$child_rel" || continue
    fragment_path="$fragment_dir/$child_rel.html"
    printf 'Generating album fragment: %s ...' "$child_rel"
    gallery_image_count=0
    if [[ -f "$fragment_path" ]]; then
      echo ' skipped'
      gallery_write_nested_fragments "$child" "$child_rel" "$thumbs_dir" "$metadata_dir" "$output_dir" "$fragment_dir"
      continue
    fi
    mkdir -p -- "$(dirname -- "$fragment_path")"
    fragment_tmp=$(mktemp "$(dirname -- "$fragment_path")/.fragment-XXXXXX")
    gallery_render_album "$child" "$child_rel" "$thumbs_dir" "$metadata_dir" "$output_dir" \
      "$thumbnail_size" "$thumbnail_display_mode" 3>&1 >"$fragment_tmp"
    printf '\n'
    mv -f -- "$fragment_tmp" "$fragment_path"
    gallery_write_nested_fragments "$child" "$child_rel" "$thumbs_dir" "$metadata_dir" "$output_dir" "$fragment_dir"
  done < <(gallery_find_child_albums "$album_dir")
}
