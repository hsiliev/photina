#!/usr/bin/env bash

# shellcheck source=lib/common.sh
source "${BASH_SOURCE[0]%/*}/../common.sh"

gallery_html_escape() {
  local value=$1
  value=${value//&/&amp;}; value=${value//</&lt;}; value=${value//>/&gt;}
  value=${value//\"/&quot;}; value=${value//\'/&#39;}
  printf '%s' "$value"
}

# The *_to variants store their result in the variable named by $1 so hot loops
# avoid a command-substitution fork per string.
gallery_url_escape_path_to() {
  local -n result=$1
  local value=$2
  value=${value//%/%25}; value=${value//\ /%20}; value=${value//\#/%23}
  value=${value//\?/%3F}; value=${value//\&/%26}; value=${value//\"/%22}; value=${value//\'/%27}
  result=$value
}

gallery_url_escape_path() {
  local escaped
  gallery_url_escape_path_to escaped "$1"
  printf '%s' "$escaped"
}

# Thumbnail mtimes cached per album by gallery_preload_file_versions; falls
# back to stat for files that were not preloaded.
declare -gA gallery_file_version_cache=()

gallery_preload_file_versions() {
  local directory=$1 path mtime
  [[ -d "$directory" ]] || return 0
  while IFS= read -r -d '' path && IFS= read -r -d '' mtime; do
    gallery_file_version_cache["$path"]=${mtime%.*}
  done < <(find -P "$directory" -maxdepth 1 -type f -printf '%p\0%T@\0')
}

gallery_file_version_to() {
  local -n result=$1
  if [[ -n ${gallery_file_version_cache["$2"]+present} ]]; then
    result=${gallery_file_version_cache["$2"]}
  else
    result=$(stat -c '%Y' -- "$2" 2>/dev/null) || result=0
  fi
}

gallery_file_version() {
  local version
  gallery_file_version_to version "$1"
  printf '%s' "$version"
}

gallery_thumbnail_url_to() {
  local -n result=$1
  local thumbnail_path=$2 thumbnail_rel=$3 escaped version
  gallery_url_escape_path_to escaped "$thumbnail_rel"
  gallery_file_version_to version "$thumbnail_path"
  result="/thumbnails/$escaped?v=$version"
}

gallery_thumbnail_url() {
  local url
  gallery_thumbnail_url_to url "$1" "$2"
  printf '%s' "$url"
}

gallery_js_escape_to() {
  local -n result=$1
  local value=$2
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  # shellcheck disable=SC2034 # nameref assigns the caller variable
  result=$value
}

gallery_js_escape() {
  local escaped
  gallery_js_escape_to escaped "$1"
  printf '%s' "$escaped"
}

# shellcheck disable=SC2016 # jq program, not shell expansion
gallery_metadata_jq_values='
  def value($m; $tag): ([ $m | to_entries[] |
    select(.key == $tag or (.key | endswith(":" + $tag))) | .value ][0] // "") | tostring;
  def values($m): value($m; "Description"), value($m; "DateTimeOriginal"), value($m; "Make"),
    value($m; "Model"), value($m; "LensModel"), value($m; "ExposureTime"), value($m; "FNumber"),
    value($m; "ISO"), value($m; "FocalLength"), value($m; "Flash"), value($m; "GPSLatitude"),
    value($m; "GPSLongitude");
'

gallery_metadata_values() {
  jq -r "$gallery_metadata_jq_values"'values(.[0])' -- "$1" 2>/dev/null
}

# Emit "path NUL 12 values NUL-separated" for every metadata file given as an
# argument, using one jq process for the whole batch.
gallery_metadata_values_batch() {
  jq -j "$gallery_metadata_jq_values"'input_filename, "\u0000", (values(.[0]) | ., "\u0000")' -- "$@" 2>/dev/null
}

declare -gA gallery_template_cache=()

gallery_print_template() {
  local template_name=$1
  shift
  if [[ -z ${gallery_template_cache["$template_name"]+present} ]]; then
    # shellcheck disable=SC2154 # set by generate_gallery
    gallery_template_cache["$template_name"]=$(<"$gallery_template_dir/$template_name")
  fi
  # shellcheck disable=SC2059
  printf "${gallery_template_cache["$template_name"]}" "$@"
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
  gallery_find_media "$1" direct | head -z -n 1
}

gallery_find_media_by_date() {
  local album_dir=$1 album_rel=$2 metadata_dir=$3
  local source relative taken_at sort_key
  local -a metadata_values=()

  while IFS= read -r -d '' source; do
    relative=${source#"$album_dir"}; relative=${relative#/}
    gallery_read_metadata "$metadata_dir/$album_rel/$relative.json" metadata_values
    taken_at=${metadata_values[1]:-}
    if [[ "$taken_at" =~ ^[0-9]{4}:[0-9]{2}:[0-9]{2}[[:space:]][0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
      sort_key=$taken_at
    else
      sort_key='9999:99:99 99:99:99'
    fi
    printf '%s\t%s\0' "$sort_key" "$source"
  done < <(gallery_find_media "$album_dir") | sort -z -t $'\t' -k1,1 -k2,2 | while IFS= read -r -d '' source; do
    printf '%s\0' "${source#*$'\t'}"
  done
}

gallery_find_album_cover() {
  find -P "$1" -mindepth 1 -maxdepth 1 -type f -iname 'album.jpg' -print0 | sort -z | head -z -n 1
}

gallery_find_child_albums() {
  local child child_name year month day date_key
  local -a date_albums=() ordinary_albums=()

  while IFS= read -r -d '' child; do
    child_name=${child##*/}
    # Use the first complete date in a name. This covers date ranges and
    # comma-separated day lists such as 2007_06_22,23,24.
    if [[ "$child_name" =~ ^([0-9]{4})[-_]([0-9]{1,2})[-_]([0-9]{1,2})([^0-9]|$) ]]; then
      year=${BASH_REMATCH[1]}
      month=${BASH_REMATCH[2]#0}; [[ -n "$month" ]] || month=0
      day=${BASH_REMATCH[3]#0}; [[ -n "$day" ]] || day=0
      if ((month >= 1 && month <= 12 && day >= 1 && day <= 31)); then
        printf -v date_key '%04d%02d%02d' "$year" "$month" "$day"
        date_albums+=("$date_key"$'\t'"$child_name"$'\t'"$child")
      else
        ordinary_albums+=("$child_name"$'\t'"$child")
      fi
    elif [[ "$child_name" =~ ^([0-9]{4})([^0-9]|$) ]]; then
      date_albums+=("${BASH_REMATCH[1]}000000"$'\t'"$child_name"$'\t'"$child")
    else
      ordinary_albums+=("$child_name"$'\t'"$child")
    fi
  done < <(find -P "$1" -mindepth 1 -maxdepth 1 -type d -print0)

  if ((${#date_albums[@]})); then
    printf '%s\0' "${date_albums[@]}" | LC_ALL=C sort -z -r |
      while IFS= read -r -d '' child; do
        child=${child#*$'\t'}
        printf '%s\0' "${child#*$'\t'}"
      done
  fi
  if ((${#ordinary_albums[@]})); then
    printf '%s\0' "${ordinary_albums[@]}" | LC_ALL=C sort -z |
      while IFS= read -r -d '' child; do printf '%s\0' "${child#*$'\t'}"; done
  fi
}
