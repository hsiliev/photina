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
