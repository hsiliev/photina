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
    "$albums/2025_03_04 - Older Trip" "$albums/2007_06_22,23,24 - Team building" \
    "$albums/2007_03_17 - Album" "$albums/Zoo" "$albums/Alpha"

  mapfile -d '' -t children < <(gallery_find_child_albums "$albums")
  names=()
  for child in "${children[@]}"; do
    names+=("${child##*/}")
  done

  [ "${names[*]}" = '2026-08-01 - Trip 2025_03_04 - Older Trip 2024 2007_06_22,23,24 - Team building 2007_03_17 - Album Alpha Zoo' ]
}

@test "three-level album trees generate shallow fragments with balanced details tags" {
  albums="$test_root/albums"
  output_dir="$test_root/output"
  thumbs="$test_root/thumbnails"
  metadata="$test_root/metadata"
  mkdir -p -- "$albums/Top/Level1/Level2" "$thumbs" "$metadata"

  printf image >"$albums/Top/Level1/Level2/deep.jpg"
  printf image >"$albums/Top/Level1/middle.jpg"
  printf image >"$albums/Top/root.jpg"

  mkdir -p -- "$metadata/Top" "$metadata/Top/Level1" "$metadata/Top/Level1/Level2"
  (cd "$albums/Top" && md5sum root.jpg >"$metadata/Top/md5sums.txt")
  (cd "$albums/Top/Level1" && md5sum middle.jpg >"$metadata/Top/Level1/md5sums.txt")
  (cd "$albums/Top/Level1/Level2" && md5sum deep.jpg >"$metadata/Top/Level1/Level2/md5sums.txt")

  run generate_gallery "$PROJECT_ROOT" "$albums" "$output_dir" "$thumbs" "$metadata" 250 cascading
  [ "$status" -eq 0 ]

  # Top fragment contains immediate child Level1 summary, but no Level2 gallery or deep image
  [ -f "$output_dir/albums/Top.html" ]
  grep -qF -- 'Level1' "$output_dir/albums/Top.html"
  ! grep -qF -- 'Level2.html' "$output_dir/albums/Top.html"
  ! grep -qF -- 'deep.jpg' "$output_dir/albums/Top.html"

  # Level1 fragment contains Level2 summary and middle.jpg, but no deep.jpg media items
  [ -f "$output_dir/albums/Top/Level1.html" ]
  grep -qF -- 'Level2.html' "$output_dir/albums/Top/Level1.html"
  grep -qF -- 'middle.jpg' "$output_dir/albums/Top/Level1.html"
  ! grep -qF -- 'deep.jpg' "$output_dir/albums/Top/Level1.html"

  # Level2 fragment contains deep.jpg media items
  [ -f "$output_dir/albums/Top/Level1/Level2.html" ]
  grep -qF -- 'deep.jpg' "$output_dir/albums/Top/Level1/Level2.html"

  # Balanced <details> tags in all fragments
  for html_file in "$output_dir/albums/Top.html" "$output_dir/albums/Top/Level1.html" "$output_dir/albums/Top/Level1/Level2.html"; do
    open_count=$(grep -o '<details' "$html_file" | wc -l)
    close_count=$(grep -o '</details>' "$html_file" | wc -l)
    [ "$open_count" -gt 0 ]
    [ "$open_count" -eq "$close_count" ]
  done
}

@test "adding a media file updates manifest and regenerates gallery fragment" {
  albums="$test_root/albums"
  output_dir="$test_root/output"
  thumbs="$test_root/thumbnails"
  metadata="$test_root/metadata"
  mkdir -p -- "$albums/Album" "$thumbs" "$metadata/Album"

  printf initial >"$albums/Album/photo1.jpg"
  (cd "$albums/Album" && md5sum photo1.jpg >"$metadata/Album/md5sums.txt")

  run generate_gallery "$PROJECT_ROOT" "$albums" "$output_dir" "$thumbs" "$metadata" 250 cascading
  [ "$status" -eq 0 ]
  initial_manifest=$(gallery_album_manifest_checksum "Album" "$metadata")
  grep -qF -- "<!-- photina-media-manifest: $initial_manifest -->" "$output_dir/albums/Album.html"

  # Add second photo and update md5sums.txt
  printf second >"$albums/Album/photo2.jpg"
  (cd "$albums/Album" && md5sum photo1.jpg photo2.jpg >"$metadata/Album/md5sums.txt")
  updated_manifest=$(gallery_album_manifest_checksum "Album" "$metadata")
  [ "$initial_manifest" != "$updated_manifest" ]

  run generate_gallery "$PROJECT_ROOT" "$albums" "$output_dir" "$thumbs" "$metadata" 250 cascading
  [ "$status" -eq 0 ]
  grep -qF -- "<!-- photina-media-manifest: $updated_manifest -->" "$output_dir/albums/Album.html"
  ! grep -qF -- "<!-- photina-media-manifest: $initial_manifest -->" "$output_dir/albums/Album.html"
}

@test "index template inline JavaScript is syntactically valid" {
  which node || skip "node is required for syntax check"
  js_tmp="$test_root/inline.js"
  python3 -c '
import re, sys
with open(sys.argv[1]) as f:
    html = f.read()
scripts = re.findall(r"<script(?![^>]*src=)[^>]*>(.*?)</script>", html, re.DOTALL)
combined = "\n".join(s.replace("__ALBUM_LIST__", "[]") for s in scripts)
with open(sys.argv[2], "w") as out:
    out.write(combined)
' "$PROJECT_ROOT/templates/index.html.template" "$js_tmp"

  run node --check "$js_tmp"
  [ "$status" -eq 0 ]
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

@test "guest gallery assigns allowed child preview to parent album when parent content is not allowed" {
  albums="$test_root/albums"
  output_dir="$test_root/output"
  thumbs="$test_root/thumbnails"
  metadata="$test_root/metadata"
  mkdir -p -- "$albums/Садовец/scans" "$albums/Садовец/Scans" "$albums/Садовец/print" \
    "$albums/Садовец/restaurant" "$albums/Троян" "$thumbs" "$metadata"

  # Place direct album.jpg and media in parent Садовец (not accessible by guest)
  printf image >"$albums/Садовец/album.jpg"
  printf image >"$albums/Садовец/print/photo.jpg"
  printf image >"$albums/Садовец/restaurant/food.jpg"
  printf image >"$albums/Садовец/scans/doc.jpg"
  printf image >"$albums/Троян/troyan.jpg"

  run generate_gallery "$PROJECT_ROOT" "$albums" "$output_dir" "$thumbs" "$metadata" 250 cascading \
    "Садовец/scans" "Садовец/Scans" "Садовец/print" "Садовец/restaurant" "Троян"

  [ "$status" -eq 0 ]
  [ -f "$output_dir/index.html" ]
  # Parent Садовец should have a thumbnail from allowed child albums, not /thumbnails/Садовец/album.jpg
  ! grep -qF -- '"thumbnail":"/thumbnails/Садовец/album.jpg' "$output_dir/index.html"
  grep -qF -- '"title":"Садовец"' "$output_dir/index.html"
  grep -qE -- '"title":"Садовец","thumbnail":"/thumbnails/Садовец/(print|restaurant|scans|Scans)/' "$output_dir/index.html"
}
