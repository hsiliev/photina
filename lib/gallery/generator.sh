#!/usr/bin/env bash

gallery_fragment_version=9

gallery_album_is_visible() {
  local album_rel=$1 allowed
  ((${#gallery_allowed_albums[@]} == 0)) && return 0
  for allowed in "${gallery_allowed_albums[@]}"; do
    [[ "$allowed" == "$album_rel" || "$allowed" == "$album_rel/"* || "$album_rel" == "$allowed/"* ]] && return 0
  done
  return 1
}

gallery_album_content_is_allowed() {
  local album_rel=$1 allowed
  ((${#gallery_allowed_albums[@]} == 0)) && return 0
  for allowed in "${gallery_allowed_albums[@]}"; do
    [[ "$allowed" == "$album_rel" || "$album_rel" == "$allowed/"* ]] && return 0
  done
  return 1
}

gallery_nested_album_preview_url() {
  local album_path=$1 album_name=$2 thumbs_dir=$3
  local preview_child preview_child_name preview_source preview_relative

  if gallery_album_content_is_allowed "$album_name"; then
    while IFS= read -r -d '' preview_source; do
      preview_relative=${preview_source#"$album_path"}; preview_relative=${preview_relative#/}
      gallery_thumbnail_url "$thumbs_dir/$album_name/$preview_relative.webp" \
        "$album_name/$preview_relative.webp"
      return
    done < <(gallery_find_album_cover "$album_path")
    while IFS= read -r -d '' preview_source; do
      preview_relative=${preview_source#"$album_path"}; preview_relative=${preview_relative#/}
      gallery_thumbnail_url "$thumbs_dir/$album_name/$preview_relative.webp" \
        "$album_name/$preview_relative.webp"
      return
    done < <(gallery_find_first_media "$album_path")
  fi

  while IFS= read -r -d '' preview_child; do
    preview_child_name=${preview_child%/}; preview_child_name=${preview_child_name##*/}
    gallery_album_is_visible "$album_name/$preview_child_name" || continue
    while IFS= read -r -d '' preview_source; do
      preview_relative=${preview_source#"$preview_child"}; preview_relative=${preview_relative#/}
      gallery_thumbnail_url "$thumbs_dir/$album_name/$preview_child_name/$preview_relative.webp" \
        "$album_name/$preview_child_name/$preview_relative.webp"
      return
    done < <(gallery_find_album_cover "$preview_child")
    while IFS= read -r -d '' preview_source; do
      preview_relative=${preview_source#"$preview_child"}; preview_relative=${preview_relative#/}
      gallery_thumbnail_url "$thumbs_dir/$album_name/$preview_child_name/$preview_relative.webp" \
        "$album_name/$preview_child_name/$preview_relative.webp"
      return
    done < <(gallery_find_first_media "$preview_child")
  done < <(gallery_find_child_albums "$album_path")
}

gallery_append_album_list_item() {
  local item=$1
  [[ -n "$album_list" ]] && album_list+=,
  album_list+="$item"
}

gallery_write_index() {
  local output_dir=$1 index_template=$2
  local index_path index_tmp rendered_index

  index_path="$output_dir/index.html"
  index_tmp=$(mktemp "$output_dir/.index-XXXXXX")
  rendered_index=${index_template//__ALBUM_LIST__/$album_list}
  printf '%s' "$rendered_index" >"$index_tmp"
  mv -f -- "$index_tmp" "$index_path"
}

gallery_album_manifest_checksum() {
  local album_name=$1 metadata_dir=$2 manifest

  manifest="$metadata_dir/$album_name/md5sums.txt"

  [[ -f "$manifest" ]] || return 1
  cksum -- "$manifest" | awk '{print $1 ":" $2}'
}

gallery_album_needs_regeneration() {
  local album_path=$1 album_name=$2 thumbs_dir=$3 metadata_dir=$4 fragment_path=${5:-}

  if [[ -n "$fragment_path" ]]; then
    [[ -f "$fragment_path" ]] || return 0
    local manifest_checksum
    manifest_checksum=$(gallery_album_manifest_checksum "$album_name" "$metadata_dir") || return 0
    grep -qF -- "<!-- photina-media-manifest: $manifest_checksum -->" "$fragment_path" || return 0
  fi

  return 1
}

gallery_cleanup_stale_fragments() {
  local albums_dir=$1 fragment_dir=$2 fragment fragment_rel album_rel

  [[ -d "$fragment_dir" ]] || return 0
  printf 'Checking for stale gallery fragments in %s ...\n' "$fragment_dir"
  while IFS= read -r -d '' fragment; do
    fragment_rel=${fragment#"$fragment_dir"/}
    album_rel=${fragment_rel%.html}
    [[ -d "$albums_dir/$album_rel" ]] && continue
    printf '\tRemoving stale gallery fragment: %s (no such original album)\n' "$fragment_rel"
    rm -f -- "$fragment"
  done < <(find -P "$fragment_dir" -type f -name '*.html' -print0)
  find -P "$fragment_dir" -mindepth 1 -depth -type d -empty -print -delete
}

gallery_generate_parent_album() {
  local album_path=$1 album_name=$2 thumbs_dir=$3 metadata_dir=$4 output_dir=$5 fragment_dir=$6 index_template=$7
  local child child_name child_urls= preview_url child_preview_url

  printf 'Generating album fragment: %s ...\n' "$album_name"
  preview_url=$(gallery_nested_album_preview_url "$album_path" "$album_name" "$thumbs_dir")
  child_urls=
  while IFS= read -r -d '' child; do
    child_name=${child%/}; child_name=${child_name##*/}
    gallery_album_is_visible "$album_name/$child_name" || continue
    child_preview_url=$(gallery_nested_album_preview_url "$child" "$album_name/$child_name" "$thumbs_dir")
    [[ -n "$child_urls" ]] && child_urls+=,
    child_urls+=$(printf '{"title":"%s","thumbnail":"%s","url":"%s/albums/%s/%s.html"}' \
      "$(gallery_js_escape "$child_name")" "$(gallery_js_escape "$child_preview_url")" \
      "$gallery_output_url_prefix" \
      "$(gallery_js_escape "$(gallery_url_escape_path "$album_name")")" \
      "$(gallery_js_escape "$(gallery_url_escape_path "$child_name")")")
  done < <(gallery_find_child_albums "$album_path")
  gallery_append_album_list_item "$(printf '{"title":"%s","thumbnail":"%s","children":[%s]}' \
    "$(gallery_js_escape "$album_name")" "$(gallery_js_escape "$preview_url")" "$child_urls")"
  gallery_write_index "$output_dir" "$index_template"
  gallery_write_nested_fragments "$album_path" "$album_name" "$thumbs_dir" "$metadata_dir" "$output_dir" "$fragment_dir"
}

gallery_generate_leaf_album() {
  local album_path=$1 album_name=$2 thumbs_dir=$3 metadata_dir=$4 output_dir=$5 fragment_dir=$6 index_template=$7
  local fragment_rel fragment_path fragment_tmp preview_source preview_relative preview_url

  printf 'Generating album fragment: %s ...\n' "$album_name"
  fragment_rel="$album_name.html"
  fragment_path="$fragment_dir/$fragment_rel"
  if [[ -f "$fragment_path" ]] &&
    grep -qF -- "<!-- photina-fragment-version: $gallery_fragment_version -->" "$fragment_path" &&
    ! gallery_album_needs_regeneration "$album_path" "$album_name" "$thumbs_dir" "$metadata_dir" "$fragment_path"; then
    :
  else
    fragment_tmp=$(mktemp "$fragment_dir/.fragment-XXXXXX")
    gallery_render_album "$album_path" "$album_name" "$thumbs_dir" "$metadata_dir" "$output_dir" \
      "$thumbnail_size" "$thumbnail_display_mode" 3>&1 >"$fragment_tmp"
    mv -f -- "$fragment_tmp" "$fragment_path"
  fi
  preview_source=
  while IFS= read -r -d '' preview_source; do break; done < <(gallery_find_album_cover "$album_path")
  if [[ -z "$preview_source" ]]; then
    while IFS= read -r -d '' preview_source; do break; done < <(gallery_find_first_media "$album_path")
  fi
  preview_url=
  if [[ -n "$preview_source" ]]; then
    preview_relative=${preview_source#"$album_path"}; preview_relative=${preview_relative#/}
    preview_url=$(gallery_thumbnail_url "$thumbs_dir/$album_name/$preview_relative.webp" \
      "$album_name/$preview_relative.webp")
  fi
  gallery_append_album_list_item "$(printf '{"title":"%s","thumbnail":"%s","url":"%s/albums/%s"}' \
    "$(gallery_js_escape "$album_name")" "$(gallery_js_escape "$preview_url")" \
    "$gallery_output_url_prefix" "$(gallery_url_escape_path "$fragment_rel")")"
  gallery_write_index "$output_dir" "$index_template"
  gallery_write_nested_fragments "$album_path" "$album_name" "$thumbs_dir" "$metadata_dir" "$output_dir" "$fragment_dir"
}

generate_gallery() {
  local script_dir=$1 albums_dir=$2 output_dir=$3 thumbs_dir=$4 metadata_dir=$5 thumbnail_size=$6 thumbnail_display_mode=$7
  shift 7
  local -a allowed_albums=("$@")
  local index_template fragment_dir album_path album_name
  local -a direct_media=()
  gallery_next_id=0
  gallery_allowed_albums=("${allowed_albums[@]}")
  gallery_output_url_prefix="/${output_dir##*/}"
  gallery_template_dir="$script_dir/templates/gallery"

  echo "Generating gallery in $output_dir"
  mkdir -p -- "$output_dir/assets"
  cp -- "$script_dir/assets/favicon.png" "$output_dir/assets/favicon.png"
  fragment_dir="$output_dir/albums"
  mkdir -p -- "$fragment_dir"
  gallery_cleanup_stale_fragments "$albums_dir" "$fragment_dir"
  album_list=
  index_template=$(<"$script_dir/templates/index.html.template")
  index_template=${index_template//__THUMBNAIL_SIZE__/$thumbnail_size}
  [[ "$index_template" == *'__ALBUM_LIST__'* ]] || die 'gallery template is missing __ALBUM_LIST__'
  printf '%s\n' 'Writing gallery index skeleton'
  gallery_write_index "$output_dir" "$index_template"
  while IFS= read -r -d '' album_path; do
    album_name=${album_path%/}; album_name=${album_name##*/}
    gallery_album_is_visible "$album_name" || continue
    direct_media=()
    while IFS= read -r -d '' source; do direct_media+=("$source"); done < <(gallery_find_media "$album_path")
    if ((${#direct_media[@]} == 0)); then
      gallery_generate_parent_album "$album_path" "$album_name" "$thumbs_dir" "$metadata_dir" "$output_dir" "$fragment_dir" "$index_template"
    else
      gallery_generate_leaf_album "$album_path" "$album_name" "$thumbs_dir" "$metadata_dir" "$output_dir" "$fragment_dir" "$index_template"
    fi
    gallery_write_index "$output_dir" "$index_template"
  done < <(gallery_find_child_albums "$albums_dir")
  echo 'Gallery generation complete'
  printf 'Gallery written to %s\n' "$output_dir/index.html"
}
