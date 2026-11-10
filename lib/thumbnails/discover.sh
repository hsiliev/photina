#!/usr/bin/env bash

# Finding albums and the media files inside them.

thumbnail_find_media() {
  local directory=$1 kind=$2 scope=${3:-direct}
  local -a extensions find_args
  if [[ "$kind" == image ]]; then
    extensions=("${IMAGE_EXTENSIONS[@]}")
  else
    extensions=("${VIDEO_EXTENSIONS[@]}")
  fi
  find_args=(-P "$directory")
  [[ "$scope" == direct ]] && find_args+=(-mindepth 1 -maxdepth 1)
  find_args+=(-type f '(')
  local extension first=1
  for extension in "${extensions[@]}"; do
    (( first )) || find_args+=(-o)
    find_args+=(-iname "*.$extension")
    first=0
  done
  find_args+=(')' -print0)
  find "${find_args[@]}"
}

# Sorted NUL-delimited list of all media files directly inside an album.
thumbnail_list_media() {
  { thumbnail_find_media "$1" image direct; thumbnail_find_media "$1" video direct; } | sort -z
}

# NUL-delimited media list: the precomputed file when given, else a fresh scan.
thumbnail_media_source() {
  local album_path=$1 media_file=${2:-}
  if [[ -n "$media_file" ]]; then cat -- "$media_file"; else thumbnail_list_media "$album_path"; fi
}

# NUL-delimited album directories (every directory below each top-level album).
thumbnail_list_albums() {
  local albums_dir=$1 root
  for root in "$albums_dir"/*/; do
    [[ -d "$root" ]] || continue
    find -P "$root" -type d -print0 | sort -z
  done
}
