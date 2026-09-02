#!/usr/bin/env bats

load test_helper

@test "compare-dirs reports direct files missing on either side" {
  first="$test_root/first"
  second="$test_root/second"
  mkdir -p -- "$first/nested" "$second"
  touch -- "$first/only-first.jpg" "$first/shared.jpg" "$first/nested/ignored.jpg"
  touch -- "$second/only-second.jpg" "$second/shared.jpg"

  run "$PROJECT_ROOT/compare-dirs.sh" "$first" "$second"

  [ "$status" -eq 0 ]
  [[ "$output" == *'only-first.jpg'* ]]
  [[ "$output" == *'only-second.jpg'* ]]
  [[ "$output" != *'ignored.jpg'* ]]
}

@test "check-missing-thumbnails detects and then accepts a generated thumbnail" {
  albums="$test_root/albums"
  thumbnails="$test_root/thumbnails"
  config="$test_root/photina.conf"
  mkdir -p -- "$albums/Album" "$thumbnails"
  printf image >"$albums/Album/photo.jpg"
  cat >"$config" <<EOF
ALBUMS_DIR='$albums'
THUMBNAILS_DIR='$thumbnails'
IMAGE_EXTENSIONS=(jpg)
VIDEO_EXTENSIONS=(mp4)
EOF
  chmod 600 -- "$config"

  run env PHOTINA_CONFIG="$config" "$PROJECT_ROOT/check-missing-thumbnails.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *'Missing thumbnail: Album/photo.jpg.webp'* ]]

  mkdir -p -- "$thumbnails/Album"
  printf thumbnail >"$thumbnails/Album/photo.jpg.webp"
  printf medium >"$thumbnails/Album/photo.jpg_medium.webp"
  run env PHOTINA_CONFIG="$config" "$PROJECT_ROOT/check-missing-thumbnails.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *'No missing thumbnails found'* ]]
}

@test "delete-album-thumbnails-and-metadata only deletes the selected album" {
  thumbnails="$test_root/thumbnails"
  metadata="$test_root/metadata"
  config="$test_root/photina.conf"
  mkdir -p -- "$thumbnails/Album & Friends" "$thumbnails/Keep" \
    "$metadata/Album & Friends" "$metadata/Keep"
  printf generated >"$thumbnails/Album & Friends/thumb.webp"
  printf generated >"$thumbnails/Keep/thumb.webp"
  printf generated >"$metadata/Album & Friends/photo.json"
  printf generated >"$metadata/Keep/photo.json"
  cat >"$config" <<EOF
THUMBNAILS_DIR='$thumbnails'
METADATA_DIR='$metadata'
EOF
  chmod 600 -- "$config"

  run env PHOTINA_CONFIG="$config" "$PROJECT_ROOT/delete-album-thumbnails-and-metadata.sh" 'Album & Friends'

  [ "$status" -eq 0 ]
  [ ! -e "$thumbnails/Album & Friends" ]
  [ ! -e "$metadata/Album & Friends" ]
  [ -e "$thumbnails/Keep/thumb.webp" ]
  [ -e "$metadata/Keep/photo.json" ]
}

@test "delete-admin-gallery removes only the admin output" {
  output_dir="$test_root/output"
  config="$test_root/photina.conf"
  mkdir -p -- "$output_dir/admin" "$output_dir/guest"
  printf generated >"$output_dir/admin/index.html"
  printf generated >"$output_dir/guest/index.html"
  printf "OUTPUT_DIR='$output_dir'\n" >"$config"
  chmod 600 -- "$config"

  run env PHOTINA_CONFIG="$config" "$PROJECT_ROOT/delete-admin-gallery.sh"

  [ "$status" -eq 0 ]
  [ ! -e "$output_dir/admin" ]
  [ -e "$output_dir/guest/index.html" ]
}

@test "delete-all-thumbnails-and-metadata removes both configured caches" {
  thumbnails="$test_root/thumbnails"
  metadata="$test_root/metadata"
  config="$test_root/photina.conf"
  mkdir -p -- "$thumbnails/Album" "$metadata/Album"
  printf generated >"$thumbnails/Album/thumb.webp"
  printf generated >"$metadata/Album/photo.json"
  printf "THUMBNAILS_DIR='$thumbnails'\nMETADATA_DIR='$metadata'\n" >"$config"
  chmod 600 -- "$config"

  run env PHOTINA_CONFIG="$config" "$PROJECT_ROOT/delete-all-thumbnails-and-metadata.sh"

  [ "$status" -eq 0 ]
  [ ! -e "$thumbnails" ]
  [ ! -e "$metadata" ]
}

@test "delete-album-thumbnails-and-metadata rejects traversal" {
  config="$test_root/photina.conf"
  printf "THUMBNAILS_DIR='$test_root/thumbnails'\nMETADATA_DIR='$test_root/metadata'\n" >"$config"
  chmod 600 -- "$config"

  run env PHOTINA_CONFIG="$config" "$PROJECT_ROOT/delete-album-thumbnails-and-metadata.sh" '../outside'

  [ "$status" -eq 1 ]
  [[ "$output" == *'album name must stay inside the configured directories'* ]]
}

@test "cleanup removes stale thumbnail and metadata files" {
  albums="$test_root/albums"
  thumbnails="$test_root/thumbnails"
  metadata="$test_root/metadata"
  config="$test_root/photina.conf"
  mkdir -p -- "$albums/Album" "$thumbnails/Album" "$metadata/Album"
  printf image >"$albums/Album/photo.jpg"
  printf current >"$thumbnails/Album/photo.jpg.webp"
  printf stale >"$thumbnails/Album/old.webp"
  printf stale >"$metadata/Album/old.json"
  printf stale >"$metadata/Album/old.md5"
  printf "ALBUMS_DIR='$albums'\nTHUMBNAILS_DIR='$thumbnails'\nMETADATA_DIR='$metadata'\nIMAGE_EXTENSIONS=(jpg)\nVIDEO_EXTENSIONS=(mp4)\n" >"$config"
  chmod 600 -- "$config"

  run env PHOTINA_CONFIG="$config" "$PROJECT_ROOT/cleanup-thumbnails-and-metadata.sh"

  [ "$status" -eq 0 ]
  [ -e "$thumbnails/Album/photo.jpg.webp" ]
  [ ! -e "$thumbnails/Album/old.webp" ]
  [ ! -e "$metadata/Album/old.json" ]
  [ ! -e "$metadata/Album/old.md5" ]
}

@test "Caddy configuration quotes guest album paths containing ampersands" {
  caddy() { printf 'HASH'; }
  source "$PROJECT_ROOT/lib/caddy.sh"
  caddyfile="$test_root/Caddyfile"
  mkdir -p -- "$test_root/albums" "$test_root/admin" "$test_root/guest" "$test_root/thumbnails"

  run generate_caddyfile "$PROJECT_ROOT" "$caddyfile" "$test_root/albums" \
    "$test_root/admin" "$test_root/guest" "$test_root/thumbnails" \
    example.test 443 adminpass guestpass 'Album & Friends'

  [ "$status" -eq 0 ]
  grep -qF -- '"/media/Album & Friends/*"' "$caddyfile"
  grep -qF -- '"/thumbnails/Album & Friends/*"' "$caddyfile"
}
