#!/usr/bin/env bash

declare -gA gallery_metadata_cache_ready=()
declare -gA gallery_metadata_cache_description=()
declare -gA gallery_metadata_cache_time=()
declare -gA gallery_metadata_cache_make=()
declare -gA gallery_metadata_cache_model=()
declare -gA gallery_metadata_cache_lens=()
declare -gA gallery_metadata_cache_exposure=()
declare -gA gallery_metadata_cache_fnumber=()
declare -gA gallery_metadata_cache_iso=()
declare -gA gallery_metadata_cache_focal_length=()
declare -gA gallery_metadata_cache_flash=()
declare -gA gallery_metadata_cache_latitude=()
declare -gA gallery_metadata_cache_longitude=()

gallery_metadata_cache_clear_album() {
  local album_prefix=$1 metadata_path
  album_prefix="${album_prefix%/}/"
  for metadata_path in "${!gallery_metadata_cache_ready[@]}"; do
    [[ "$metadata_path" == "$album_prefix"* ]] || continue
    unset 'gallery_metadata_cache_ready[$metadata_path]'
    unset 'gallery_metadata_cache_description[$metadata_path]'
    unset 'gallery_metadata_cache_time[$metadata_path]'
    unset 'gallery_metadata_cache_make[$metadata_path]'
    unset 'gallery_metadata_cache_model[$metadata_path]'
    unset 'gallery_metadata_cache_lens[$metadata_path]'
    unset 'gallery_metadata_cache_exposure[$metadata_path]'
    unset 'gallery_metadata_cache_fnumber[$metadata_path]'
    unset 'gallery_metadata_cache_iso[$metadata_path]'
    unset 'gallery_metadata_cache_focal_length[$metadata_path]'
    unset 'gallery_metadata_cache_flash[$metadata_path]'
    unset 'gallery_metadata_cache_latitude[$metadata_path]'
    unset 'gallery_metadata_cache_longitude[$metadata_path]'
  done
}

gallery_metadata_cache_store() {
  local metadata_path=$1
  shift
  gallery_metadata_cache_ready["$metadata_path"]=1
  gallery_metadata_cache_description["$metadata_path"]=${1:-}
  gallery_metadata_cache_time["$metadata_path"]=${2:-}
  gallery_metadata_cache_make["$metadata_path"]=${3:-}
  gallery_metadata_cache_model["$metadata_path"]=${4:-}
  gallery_metadata_cache_lens["$metadata_path"]=${5:-}
  gallery_metadata_cache_exposure["$metadata_path"]=${6:-}
  gallery_metadata_cache_fnumber["$metadata_path"]=${7:-}
  gallery_metadata_cache_iso["$metadata_path"]=${8:-}
  gallery_metadata_cache_focal_length["$metadata_path"]=${9:-}
  gallery_metadata_cache_flash["$metadata_path"]=${10:-}
  gallery_metadata_cache_latitude["$metadata_path"]=${11:-}
  gallery_metadata_cache_longitude["$metadata_path"]=${12:-}
}

# Fill the metadata cache for every media file in an album with a single jq
# run, so later gallery_read_metadata calls never spawn a process.
gallery_preload_metadata() {
  local album_dir=$1 album_rel=$2 metadata_dir=$3
  local source relative metadata_path chunk field
  local -a files=() record=()

  while IFS= read -r -d '' source; do
    relative=${source#"$album_dir"}; relative=${relative#/}
    metadata_path="$metadata_dir/$album_rel/$relative.json"
    [[ -f "$metadata_path" && -z "${gallery_metadata_cache_ready["$metadata_path"]+present}" ]] &&
      files+=("$metadata_path")
  done < <(gallery_find_media "$album_dir")
  ((${#files[@]})) || return 0

  # Chunk the file list to stay well below the argument-length limit.
  for ((chunk = 0; chunk < ${#files[@]}; chunk += 500)); do
    while IFS= read -r -d '' metadata_path; do
      record=()
      for ((field = 0; field < 12; field++)); do
        IFS= read -r -d '' relative || relative=
        record+=("$relative")
      done
      gallery_metadata_cache_store "$metadata_path" "${record[@]}"
    done < <(gallery_metadata_values_batch "${files[@]:chunk:500}")
  done
}

gallery_read_metadata() {
  local metadata_path=$1
  local -n values=$2
  values=()
  [[ -f "$metadata_path" ]] || return 0
  if [[ -n "${gallery_metadata_cache_ready["$metadata_path"]+present}" ]]; then
    values=(
      "${gallery_metadata_cache_description["$metadata_path"]}"
      "${gallery_metadata_cache_time["$metadata_path"]}"
      "${gallery_metadata_cache_make["$metadata_path"]}"
      "${gallery_metadata_cache_model["$metadata_path"]}"
      "${gallery_metadata_cache_lens["$metadata_path"]}"
      "${gallery_metadata_cache_exposure["$metadata_path"]}"
      "${gallery_metadata_cache_fnumber["$metadata_path"]}"
      "${gallery_metadata_cache_iso["$metadata_path"]}"
      "${gallery_metadata_cache_focal_length["$metadata_path"]}"
      "${gallery_metadata_cache_flash["$metadata_path"]}"
      "${gallery_metadata_cache_latitude["$metadata_path"]}"
      "${gallery_metadata_cache_longitude["$metadata_path"]}"
    )
    return 0
  fi
  mapfile -t values < <(gallery_metadata_values "$metadata_path")
  gallery_metadata_cache_store "$metadata_path" "${values[@]}"
}

gallery_render_media_item() {
  local source=$1 album_dir=$2 album_rel=$3 thumbs_dir=$4 metadata_dir=$5 item_index=$6
  local relative metadata_path thumb_path medium_path web_video_path media_url medium_url thumb_url medium_relative
  local web_video_url variant variant_url js_variant_url viewer_variants=''
  local -a variants=()
  local title exif_location exif_model exif_time exif_lens exif_focal_length exif_fstop exif_iso exif_exposure exif_flash viewer_url
  local -a metadata_values=()

  relative=${source#"$album_dir"}; relative=${relative#/}
  thumb_path="$thumbs_dir/$album_rel/$relative.webp"
  medium_path="${thumb_path%.webp}_me.webp"
  gallery_url_escape_path_to media_url "$album_rel/$relative"
  media_url="/media/$media_url"
  medium_relative="${relative}.webp"
  medium_relative="${medium_relative%.webp}_me.webp"
  gallery_thumbnail_url_to medium_url "$medium_path" "$album_rel/$medium_relative"
  gallery_thumbnail_url_to thumb_url "$thumb_path" "$album_rel/$relative.webp"
  title=${relative##*/}; title=${title%.*}

  metadata_path="$metadata_dir/$album_rel/$relative.json"
  exif_location=''; exif_model=''; exif_time=''; exif_lens=''; exif_focal_length=''
  exif_fstop=''; exif_iso=''; exif_exposure=''; exif_flash=''
  gallery_read_metadata "$metadata_path" metadata_values
  if ((${#metadata_values[@]})); then
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
    if [[ -n "${metadata_values[10]:-}" && -n "${metadata_values[11]:-}" ]]; then
      exif_location="${metadata_values[10]}, ${metadata_values[11]}"
    fi
  fi

  # "src" is the _me image; NanoGallery swaps in srcXS/SM/LA/XL by viewport
  # width when present. XL is the original when browsers can show its format
  # (also what downloadURL serves), else the converted _xl.webp.
  viewer_url=$medium_url
  if ! photina_is_video "$source"; then
    photina_viewer_variants_to variants "$source"
    for variant in "${variants[@]}"; do
      [[ "$variant" == me ]] && continue
      gallery_thumbnail_url_to variant_url "${thumb_path%.webp}_$variant.webp" "$album_rel/${relative}_$variant.webp"
      gallery_js_escape_to js_variant_url "$variant_url"
      viewer_variants+=",\"src${variant^^}\":\"$js_variant_url\""
    done
    if photina_browser_image "$source"; then
      gallery_js_escape_to js_variant_url "$media_url"
      viewer_variants+=",\"srcXL\":\"$js_variant_url\""
    fi
  fi
  if photina_is_video "$source"; then
    if photina_needs_web_video "$source"; then
      web_video_path="${thumb_path%.webp}.web.mp4"
      gallery_thumbnail_url_to web_video_url "$web_video_path" "$album_rel/$relative.web.mp4"
      viewer_url=$web_video_url
    else
      viewer_url=$media_url
    fi
  fi

  local js_thumb js_viewer js_media js_title js_model js_time js_focal js_fstop js_iso js_exposure js_flash js_location js_lens
  gallery_js_escape_to js_thumb "$thumb_url"; gallery_js_escape_to js_viewer "$viewer_url"
  gallery_js_escape_to js_media "$media_url"; gallery_js_escape_to js_title "$title"
  gallery_js_escape_to js_model "$exif_model"; gallery_js_escape_to js_time "$exif_time"
  gallery_js_escape_to js_focal "$exif_focal_length"; gallery_js_escape_to js_fstop "$exif_fstop"
  gallery_js_escape_to js_iso "$exif_iso"; gallery_js_escape_to js_exposure "$exif_exposure"
  gallery_js_escape_to js_flash "$exif_flash"; gallery_js_escape_to js_location "$exif_location"
  gallery_js_escape_to js_lens "$exif_lens"

  (( item_index > 0 )) && printf ','
  if [[ -n "$exif_lens" || -n "$exif_location" || -n "$exif_model" || -n "$exif_time" || \
          -n "$exif_focal_length" || -n "$exif_fstop" || -n "$exif_iso" || \
          -n "$exif_exposure" || -n "$exif_flash" ]]; then
    gallery_print_template item-with-metadata.html \
      "$js_thumb" "$js_viewer" "$viewer_variants" "$js_media" "$js_title" "$js_model" "$js_time" \
      "$js_focal" "$js_fstop" "$js_iso" "$js_exposure" "$js_flash" "$js_location" "$js_lens"
  else
    gallery_print_template item.html \
      "$js_thumb" "$js_viewer" "$viewer_variants" "$js_media" "$js_title" "$js_model" "$js_time" \
      "$js_focal" "$js_fstop" "$js_iso" "$js_location"
  fi

  gallery_image_count=$((gallery_image_count + 1))
}
