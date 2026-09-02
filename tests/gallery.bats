#!/usr/bin/env bats

load test_helper

@test "URL path escaping encodes ampersands" {
  run gallery_url_escape_path 'Child & Friends/photo.jpg.webp'

  [ "$status" -eq 0 ]
  [ "$output" = 'Child%20%26%20Friends/photo.jpg.webp' ]
}

@test "index insertion preserves ampersands without its marker" {
  output_dir="$test_root/output"
  mkdir -p -- "$output_dir"
  album_list='{"title":"Summer & Friends"}'

  run gallery_write_index "$output_dir" 'before __ALBUM_LIST__ after'

  [ "$status" -eq 0 ]
  [ "$(<"$output_dir/index.html")" = 'before {"title":"Summer & Friends"} after' ]
  ! grep -qF -- '__ALBUM_LIST__' "$output_dir/index.html"
}

@test "parent preview uses a thumbnail from an ampersand sub-album" {
  albums="$test_root/albums"
  thumbnails="$test_root/thumbnails"
  mkdir -p -- "$albums/Parent/Child & Friends" "$thumbnails/Parent/Child & Friends"
  printf image >"$albums/Parent/Child & Friends/photo.jpg"
  printf thumbnail >"$thumbnails/Parent/Child & Friends/photo.jpg.webp"

  run gallery_nested_album_preview_url "$albums/Parent" Parent "$thumbnails"

  [ "$status" -eq 0 ]
  [[ "$output" == '/thumbnails/Parent/Child%20%26%20Friends/photo.jpg.webp?v='* ]]
}

@test "child albums sort dated names newest first and ordinary names alphabetically" {
  albums="$test_root/albums"
  mkdir -p -- "$albums/2024" "$albums/2026-08-01 - Trip" \
    "$albums/2025_03_04 - Older Trip" "$albums/Zoo" "$albums/Alpha"

  mapfile -d '' -t children < <(gallery_find_child_albums "$albums")
  names=()
  for child in "${children[@]}"; do
    names+=("${child##*/}")
  done

  [ "${names[*]}" = '2026-08-01 - Trip 2025_03_04 - Older Trip 2024 Alpha Zoo' ]
}

@test "stale gallery fragments are removed while current fragments remain" {
  albums="$test_root/albums"
  fragments="$test_root/fragments"
  mkdir -p -- "$albums/Current" "$fragments/Current" "$fragments/Removed"
  printf current >"$fragments/Current.html"
  printf stale >"$fragments/Removed.html"
  printf nested-stale >"$fragments/Removed/Child.html"

  run gallery_cleanup_stale_fragments "$albums" "$fragments"

  [ "$status" -eq 0 ]
  [ -e "$fragments/Current.html" ]
  [ ! -e "$fragments/Removed.html" ]
  [ ! -e "$fragments/Removed/Child.html" ]
  [ ! -d "$fragments/Removed" ]
}

@test "expected thumbnail outputs include medium and web-video files" {
  album="$test_root/albums/Album"
  thumbnails="$test_root/thumbnails"
  mkdir -p -- "$album"
  printf image >"$album/photo.jpg"
  printf video >"$album/movie.mov"
  media_file="$test_root/media.list"
  printf '%s\0%s\0' "$album/photo.jpg" "$album/movie.mov" >"$media_file"
  declare -A expected=()

  thumbnail_add_expected_outputs "$album" Album "$thumbnails" "$media_file" expected

  [ -n "${expected["$thumbnails/Album/photo.jpg.webp"]+present}" ]
  [ -n "${expected["$thumbnails/Album/photo.jpg_medium.webp"]+present}" ]
  [ -n "${expected["$thumbnails/Album/movie.mov.webp"]+present}" ]
  [ -n "${expected["$thumbnails/Album/movie.mov_medium.webp"]+present}" ]
  [ -n "${expected["$thumbnails/Album/movie.mov.web.mp4"]+present}" ]
}
