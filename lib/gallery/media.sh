#!/usr/bin/env bash

gallery_read_metadata() {
  local metadata_path=$1
  local -n values=$2
  values=()
  [[ -f "$metadata_path" ]] || return 0
  mapfile -t values < <(gallery_metadata_values "$metadata_path")
}

gallery_render_media_item() {
  local source=$1 album_dir=$2 album_rel=$3 thumbs_dir=$4 metadata_dir=$5 output_dir=$6 item_index=$7
  local relative metadata_path thumb_path medium_path web_video_path media_url medium_url thumb_url medium_relative
  local web_video_url
  local title exif_location exif_model exif_time exif_lens exif_focal_length exif_fstop exif_iso exif_exposure exif_flash viewer_url
  local -a metadata_values=()

  relative=${source#"$album_dir"}; relative=${relative#/}
  thumb_path="$thumbs_dir/$album_rel/$relative.webp"
  medium_path="${thumb_path%.webp}_medium.webp"
  media_url="/media/$(gallery_url_escape_path "$album_rel/$relative")"
  medium_relative="${relative}.webp"
  medium_relative="${medium_relative%.webp}_medium.webp"
  medium_url=$(gallery_thumbnail_url "$medium_path" "$album_rel/$medium_relative")
  thumb_url=$(gallery_thumbnail_url "$thumb_path" "$album_rel/$relative.webp")
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
    exif_location=$(gallery_metadata_location "${metadata_values[10]:-}" "${metadata_values[11]:-}")
  fi

  viewer_url=$medium_url
  if gallery_is_video "$source"; then
    if gallery_needs_web_video "$source"; then
      web_video_path="${thumb_path%.webp}.web.mp4"
      web_video_url=$(gallery_thumbnail_url "$web_video_path" "$album_rel/$relative.web.mp4")
      viewer_url=$web_video_url
    else
      viewer_url=$media_url
    fi
  fi

  (( item_index > 0 )) && printf ','
  if [[ -n "$exif_lens" || -n "$exif_location" || -n "$exif_model" || -n "$exif_time" || \
          -n "$exif_focal_length" || -n "$exif_fstop" || -n "$exif_iso" || \
          -n "$exif_exposure" || -n "$exif_flash" ]]; then
    gallery_print_template item-with-metadata.html \
      "$(gallery_js_escape "$thumb_url")" "$(gallery_js_escape "$viewer_url")" \
      "$(gallery_js_escape "$media_url")" "$(gallery_js_escape "$media_url")" \
      "$(gallery_js_escape "$title")" "$(gallery_js_escape "$exif_model")" \
      "$(gallery_js_escape "$exif_time")" "$(gallery_js_escape "$exif_focal_length")" \
      "$(gallery_js_escape "$exif_fstop")" "$(gallery_js_escape "$exif_iso")" \
      "$(gallery_js_escape "$exif_exposure")" "$(gallery_js_escape "$exif_flash")" \
      "$(gallery_js_escape "$exif_location")" "$(gallery_js_escape "$exif_lens")"
  else
    gallery_print_template item.html \
      "$(gallery_js_escape "$thumb_url")" "$(gallery_js_escape "$viewer_url")" \
      "$(gallery_js_escape "$media_url")" "$(gallery_js_escape "$media_url")" \
      "$(gallery_js_escape "$title")" "$(gallery_js_escape "$exif_model")" \
      "$(gallery_js_escape "$exif_time")" "$(gallery_js_escape "$exif_focal_length")" \
      "$(gallery_js_escape "$exif_fstop")" "$(gallery_js_escape "$exif_iso")" \
      "$(gallery_js_escape "$exif_location")"
  fi

  gallery_image_count=$((gallery_image_count + 1))
  if (( gallery_image_count % 10 == 0 )); then
    printf '.' >&3
  fi
}
