#!/usr/bin/env bash

# Generating thumbnails, viewer images, and web videos.

# Every generated file expected for SOURCE whose thumbnail is THUMBNAIL: the
# thumbnail, its viewer variants (_xs/_sm/_me/_la, plus _xl for formats
# browsers cannot show), and the web video when one is needed. The array named
# by $1 receives the paths.
# shellcheck disable=SC2034 # nameref assigns the caller's array
thumbnail_expected_files_to() {
  local -n _photina_files_out=$1
  local source=$2 thumbnail=$3 variant
  local -a variants=()
  _photina_files_out=("$thumbnail")
  photina_viewer_variants_to variants "$source"
  for variant in "${variants[@]}"; do
    _photina_files_out+=("${thumbnail%.webp}_$variant.webp")
  done
  if photina_needs_web_video "$source"; then
    _photina_files_out+=("${thumbnail%.webp}.web.mp4")
  fi
}

# True when the display mode keeps each photo's aspect ratio (fixed width,
# free height). Grid modes instead crop thumbnails to squares.
thumbnail_keeps_aspect_ratio() {
  [[ "$1" == cascading || "$1" == justified ]]
}

# Extract one frame of the video SOURCE into FRAME with ffmpegthumbnailer,
# falling back to ffmpeg. Returns 1 after a warning when no non-empty frame
# results: unreadable videos (empty, truncated) must not reach ImageMagick.
thumbnail_extract_video_frame() {
  local source=$1 frame=$2 thumbnail_size=$3 display_name=$4
  if ! ffmpegthumbnailer -i "$source" -o "$frame" -s "$thumbnail_size" -q 8 -f >/dev/null 2>&1 \
    || [[ ! -s "$frame" ]]; then
    rm -f -- "$frame"
    ffmpeg -v error -i "$source" -frames:v 1 -y "$frame" >/dev/null 2>&1 || true
  fi
  if [[ ! -s "$frame" ]]; then
    rm -f -- "$frame"
    warn "skipping unreadable video: $display_name"
    return 1
  fi
}

# ImageMagick resize arguments for one viewer variant, in the array named by
# $1. xs/sm/la never enlarge; me follows MEDIUM_SIZE (ME_SIZE here) and the
# display mode; xl is full resolution (format conversion only).
# shellcheck disable=SC2034 # nameref assigns the caller's array
thumbnail_variant_resize_to() {
  local -n _photina_resize_out=$1
  local variant=$2 me_size=$3 display_mode=$4
  local width_xs=800 width_sm=1280 width_la=2400
  case "$variant" in
    xs) _photina_resize_out=(-thumbnail "${width_xs}x>") ;;
    sm) _photina_resize_out=(-thumbnail "${width_sm}x>") ;;
    la) _photina_resize_out=(-thumbnail "${width_la}x>") ;;
    me)
      if thumbnail_keeps_aspect_ratio "$display_mode"; then
        _photina_resize_out=(-thumbnail "${me_size}x")
      else
        _photina_resize_out=(-thumbnail "${me_size}x${me_size}>")
      fi ;;
    *) _photina_resize_out=() ;;
  esac
}

# Build the one ImageMagick argument list that writes the thumbnail and every
# viewer variant of SOURCE from a single decode. Fills two caller arrays:
# the arguments ($1) and the temporary files they write ($2, thumbnail first).
# Usage: thumbnail_magick_args_to ARGS TEMPS base source thumbnail_size
#        me_size display_mode quality
# shellcheck disable=SC2034 # namerefs assign the caller's arrays
thumbnail_magick_args_to() {
  local -n _photina_args_out=$1 _photina_temps_out=$2
  local base=$3 source=$4 thumbnail_size=$5 me_size=$6 display_mode=$7 quality=$8
  local variant tmp
  local -a variants=() resize=()

  _photina_temps_out=("$base.generating.webp")
  if thumbnail_keeps_aspect_ratio "$display_mode"; then
    _photina_args_out=('(' +clone -thumbnail "${thumbnail_size}x" -strip -quality 86
      -write "$base.generating.webp" +delete ')')
  else
    _photina_args_out=('(' +clone -thumbnail "${thumbnail_size}x${thumbnail_size}^"
      -gravity center -extent "$thumbnail_size"x"$thumbnail_size" -background white -alpha remove
      -alpha off -strip -quality 86 -write "$base.generating.webp" +delete ')')
  fi
  photina_viewer_variants_to variants "$source"
  for variant in "${variants[@]}"; do
    thumbnail_variant_resize_to resize "$variant" "$me_size" "$display_mode"
    tmp=${base}_$variant.generating.webp
    _photina_temps_out+=("$tmp")
    _photina_args_out+=('(' +clone "${resize[@]}" -strip -quality "$quality" -write "$tmp" +delete ')')
  done
}

# Convert SOURCE to a browser-compatible MP4 at WEB_VIDEO. A failure only
# warns: thumbnails are still published.
thumbnail_make_web_video() {
  local source=$1 web_video=$2 display_name=$3
  local web_video_tmp=${web_video%.mp4}.generating.mp4
  if ffmpeg -i "$source" -c:v libx264 -pix_fmt yuv420p -c:a aac -movflags +faststart -y "$web_video_tmp" \
    >/dev/null 2>&1 && [[ -s "$web_video_tmp" ]]; then
    mv -f -- "$web_video_tmp" "$web_video"
  else
    rm -f -- "$web_video_tmp"
    warn "web video conversion failed: $display_name"
  fi
}

# Move the finished temporary files into place: the thumbnail, then one
# <base>_<variant>.webp per variant given.
thumbnail_publish_outputs() {
  local base=$1 variant
  shift
  mv -f -- "$base.generating.webp" "$base.webp"
  for variant in "$@"; do
    mv -f -- "${base}_$variant.generating.webp" "${base}_$variant.webp"
  done
}

# Generate the thumbnail, viewer images, and (for non-MP4 videos) web video of
# one media file. Unreadable media is skipped with a warning and returns 0 so a
# batch continues; the file stays pending and is retried next run.
# Usage: thumbnail_make source thumbnail thumbnail_size image_tool
#        display_name me_size display_mode
thumbnail_make() {
  local source=$1 thumbnail=$2 thumbnail_size=$3 image_tool=$4
  local display_name=${5:-${source##*/}} me_size=$6 display_mode=$7
  local base=${thumbnail%.webp}
  local video_frame_tmp=$base.video.jpg
  local input quality=90 tmp
  local -a input_args=() variants=() magick_args=() temps=()

  mkdir -p -- "$(dirname -- "$thumbnail")"
  if photina_is_video "$source"; then
    thumbnail_extract_video_frame "$source" "$video_frame_tmp" "$thumbnail_size" "$display_name" || return 0
    input=$video_frame_tmp
    quality=86
  else
    input=$source
    input_args=(-auto-orient)
  fi

  thumbnail_magick_args_to magick_args temps "$base" "$source" "$thumbnail_size" "$me_size" "$display_mode" "$quality"
  "$image_tool" "$input" "${input_args[@]}" "${magick_args[@]}" null: || true
  rm -f -- "$video_frame_tmp"
  for tmp in "${temps[@]}"; do
    if [[ ! -s "$tmp" ]]; then
      rm -f -- "${temps[@]}"
      warn "skipping unreadable media: $display_name"
      return 0
    fi
  done

  if photina_needs_web_video "$source"; then
    thumbnail_make_web_video "$source" "$base.web.mp4" "$display_name"
  fi
  photina_viewer_variants_to variants "$source"
  thumbnail_publish_outputs "$base" "${variants[@]}"
  printf '\t%s\n' "$display_name"
}

# Generate the outputs of one media file unless they all exist already. The
# source comes last so xargs can append it to the fixed arguments.
# Usage: thumbnail_process_item album_path album_name thumbs_dir
#        thumbnail_size image_tool me_size display_mode source
thumbnail_process_item() {
  local album_path=$1 album_name=$2 thumbs_dir=$3 thumbnail_size=$4 image_tool=$5
  local me_size=$6 display_mode=$7 source=$8
  local relative thumbnail file complete=1
  local -a expected=()
  [[ -n "$source" && -f "$source" ]] || return 0
  relative=${source#"$album_path"}; relative=${relative#/}
  [[ -n "$relative" ]] || return 0
  thumbnail="$thumbs_dir/$album_name/$relative.webp"
  thumbnail_expected_files_to expected "$source" "$thumbnail"
  for file in "${expected[@]}"; do
    [[ -f "$file" ]] || { complete=0; break; }
  done
  (( complete == 0 )) || return 0
  thumbnail_make "$source" "$thumbnail" "$thumbnail_size" "$image_tool" "$relative" "$me_size" "$display_mode"
}

# Filter a NUL-delimited media list on stdin down to files with any generated
# output missing (thumbnail, viewer variants, web video). Done in-process so
# complete files do not cost a bash start each.
thumbnail_filter_pending() {
  local album_path=$1 album_name=$2 thumbs_dir=$3 source relative thumbnail file
  local -a expected=()
  while IFS= read -r -d '' source; do
    relative=${source#"$album_path"}; relative=${relative#/}
    thumbnail="$thumbs_dir/$album_name/$relative.webp"
    thumbnail_expected_files_to expected "$source" "$thumbnail"
    for file in "${expected[@]}"; do
      if [[ ! -f "$file" ]]; then
        printf '%s\0' "$source"
        break
      fi
    done
  done
}

# Generate missing outputs for the media of one album in parallel. KIND is
# image, video, or all; MEDIA_FILE is an optional precomputed NUL-delimited
# list.
# Usage: thumbnail_batch_album album_path album_name thumbs_dir thumbnail_size
#        me_size image_tool parallel_jobs kind display_mode [media_file]
# shellcheck disable=SC2016
thumbnail_batch_album() {
  local album_path=$1 album_name=$2 thumbs_dir=$3 thumbnail_size=$4 me_size=$5 image_tool=$6
  local parallel_jobs=$7 kind=$8 display_mode=$9 media_file=${10:-}
  export -f warn photina_is_video photina_needs_web_video photina_browser_image photina_viewer_variants_to \
    thumbnail_expected_files_to thumbnail_keeps_aspect_ratio thumbnail_extract_video_frame \
    thumbnail_variant_resize_to thumbnail_magick_args_to thumbnail_make_web_video \
    thumbnail_publish_outputs thumbnail_make thumbnail_process_item

  if [[ -n "$media_file" ]]; then
    cat -- "$media_file"
  elif [[ "$kind" == image ]]; then
    thumbnail_find_media "$album_path" image direct
  elif [[ "$kind" == all ]]; then
    thumbnail_list_media "$album_path"
  else
    thumbnail_find_media "$album_path" video direct
  fi | thumbnail_filter_pending "$album_path" "$album_name" "$thumbs_dir" |
    xargs -0 -r -n 1 -P "$parallel_jobs" bash -c 'thumbnail_process_item "$@"' _ \
      "$album_path" "$album_name" "$thumbs_dir" "$thumbnail_size" "$image_tool" "$me_size" "$display_mode"
}
