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

@test "delete-guest-gallery removes only the guest output" {
  output_dir="$test_root/output"
  config="$test_root/photina.conf"
  mkdir -p -- "$output_dir/admin" "$output_dir/guest"
  printf generated >"$output_dir/admin/index.html"
  printf generated >"$output_dir/guest/index.html"
  printf "OUTPUT_DIR='$output_dir'\n" >"$config"
  chmod 600 -- "$config"

  run env PHOTINA_CONFIG="$config" "$PROJECT_ROOT/delete-guest-gallery.sh"

  [ "$status" -eq 0 ]
  [ ! -e "$output_dir/guest" ]
  [ -e "$output_dir/admin/index.html" ]
}

@test "check-duplicates reports duplicate md5 checksums across manifests" {
  metadata="$test_root/metadata"
  config="$test_root/photina.conf"
  mkdir -p -- "$metadata/Album1" "$metadata/Album2"
  printf "METADATA_DIR='$metadata'\n" >"$config"
  chmod 600 -- "$config"

  # Case 1: No duplicates
  cat >"$metadata/Album1/md5sums.txt" <<EOF
d41d8cd98f00b204e9800998ecf8427e  photo1.jpg
EOF
  cat >"$metadata/Album2/md5sums.txt" <<EOF
098f6bcd4621d373cade4e832627b4f6  photo2.jpg
EOF

  run env PHOTINA_CONFIG="$config" "$PROJECT_ROOT/check-duplicates.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *'No duplicate files found.'* ]]

  # Case 2: Duplicates present
  cat >"$metadata/Album2/md5sums.txt" <<EOF
d41d8cd98f00b204e9800998ecf8427e  duplicate.jpg
EOF

  run env PHOTINA_CONFIG="$config" "$PROJECT_ROOT/check-duplicates.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *'Duplicate MD5: d41d8cd98f00b204e9800998ecf8427e'* ]]
  [[ "$output" == *'Album1/photo1.jpg'* ]]
  [[ "$output" == *'Album2/duplicate.jpg'* ]]
}

@test "eliminate-duplicates replaces duplicate files and artifacts with hardlinks" {
  albums="$test_root/albums"
  thumbs="$test_root/thumbnails"
  metadata="$test_root/metadata"
  config="$test_root/photina.conf"
  mkdir -p -- "$albums/Album1" "$albums/Album2" "$thumbs/Album1" "$thumbs/Album2" "$metadata/Album1" "$metadata/Album2"
  printf "same-content" >"$albums/Album1/photo.jpg"
  printf "same-content" >"$albums/Album2/copy.jpg"
  printf "thumb1" >"$thumbs/Album1/photo.jpg.webp"
  printf "thumb2" >"$thumbs/Album2/copy.jpg.webp"
  printf "medium1" >"$thumbs/Album1/photo.jpg_medium.webp"
  printf "medium2" >"$thumbs/Album2/copy.jpg_medium.webp"
  printf "meta1" >"$metadata/Album1/photo.jpg.json"
  printf "meta2" >"$metadata/Album2/copy.jpg.json"

  cat >"$config" <<EOF
ALBUMS_DIR='$albums'
THUMBNAILS_DIR='$thumbs'
METADATA_DIR='$metadata'
EOF
  chmod 600 -- "$config"

  hash=$(md5sum "$albums/Album1/photo.jpg" | awk '{print $1}')
  printf '%s  photo.jpg\n' "$hash" >"$metadata/Album1/md5sums.txt"
  printf '%s  copy.jpg\n' "$hash" >"$metadata/Album2/md5sums.txt"

  run env PHOTINA_CONFIG="$config" "$PROJECT_ROOT/eliminate-duplicates.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Eliminated 1 duplicate file(s).'* ]]

  # Inode check: duplicate should now be a hardlink to original
  original_inode=$(stat -c '%i' -- "$albums/Album1/photo.jpg")
  duplicate_inode=$(stat -c '%i' -- "$albums/Album2/copy.jpg")
  [ "$original_inode" -eq "$duplicate_inode" ]

  # Check thumbnails and metadata are also hardlinked
  thumb1_inode=$(stat -c '%i' -- "$thumbs/Album1/photo.jpg.webp")
  thumb2_inode=$(stat -c '%i' -- "$thumbs/Album2/copy.jpg.webp")
  [ "$thumb1_inode" -eq "$thumb2_inode" ]
}

@test "split-by-year organizes images by EXIF date into year subdirectories" {
  which convert >/dev/null || skip "convert is required"
  which exiftool >/dev/null || skip "exiftool is required"

  staging="$test_root/staging"
  mkdir -p -- "$staging"
  convert -size 10x10 xc:white "$staging/photo2021.jpg"
  convert -size 10x10 xc:white "$staging/photo2023.jpg"
  convert -size 10x10 xc:white "$staging/undated.jpg"

  exiftool -overwrite_original -DateTimeOriginal='2021:05:10 12:00:00' "$staging/photo2021.jpg" >/dev/null
  exiftool -overwrite_original -CreateDate='2023:08:20 15:30:00' "$staging/photo2023.jpg" >/dev/null

  run "$PROJECT_ROOT/split-by-year.sh" "$staging"
  [ "$status" -eq 0 ]
  [ -f "$staging/2021/photo2021.jpg" ]
  [ -f "$staging/2023/photo2023.jpg" ]
  [ -f "$staging/undated.jpg" ]
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

# Create non-empty files (fix-names deletes empty ones).
mkfile() {
  local f
  for f in "$@"; do printf x >"$f"; done
}

@test "fix-names renames nested files and directories and skips conflicts" {
  root="$test_root/trim"
  mkdir -p -- "$root/Album  /Sub " "$root/Keep"
  mkfile "$root/Album  /Sub /photo.jpg " "$root/Album  /clean.jpg" "$root/dup" "$root/dup " "$root/   "

  run "$PROJECT_ROOT/fix-names.sh" --dry-run "$root"
  [ "$status" -eq 1 ]
  [[ "$output" == *'Would rename'* ]]
  [ -d "$root/Album  " ]

  run "$PROJECT_ROOT/fix-names.sh" "$root"

  [ "$status" -eq 1 ]
  [ -f "$root/Album/Sub/photo.jpg" ]
  [ -f "$root/Album/clean.jpg" ]
  [ -d "$root/Keep" ]
  [ -f "$root/dup" ]
  [ -f "$root/dup " ]
  [ -f "$root/   " ]
  [[ "$output" == *'target already exists'* ]]
  [[ "$output" == *'consists only of spaces or dots'* ]]
}

@test "fix-names succeeds when nothing needs renaming" {
  mkdir -p -- "$test_root/clean/a"

  run "$PROJECT_ROOT/fix-names.sh" "$test_root/clean"

  [ "$status" -eq 0 ]
  [[ "$output" == *'Renamed 0 item(s); skipped 0; forbidden 0; mangled 0.'* ]]
}

@test "fix-names also trims trailing dots" {
  root="$test_root/dots"
  mkdir -p -- "$root/Trip.. "
  mkfile "$root/Trip.. /photo.jpg."

  run "$PROJECT_ROOT/fix-names.sh" "$root"

  [ "$status" -eq 0 ]
  [ -f "$root/Trip/photo.jpg" ]
}

@test "fix-names reports names with characters SMB cannot store" {
  root="$test_root/forbidden"
  mkdir -p -- "$root/Album"
  mkfile "$root/Album/a:b.jpg" "$root/Album/what?.jpg" "$root/Album/pipe|name.jpg" \
    "$root/Album/ctl"$'\x01'".jpg" "$root/Album/mapped"$'\xef\x80\xa2'".jpg" \
    "$root/Album/fine.jpg" "$root/Album/q:trail "

  run "$PROJECT_ROOT/fix-names.sh" "$root"

  [ "$status" -eq 1 ]
  [[ "$output" == *"forbidden: $root/Album/a:b.jpg"* ]]
  [[ "$output" == *"forbidden: $root/Album/what?.jpg"* ]]
  [[ "$output" == *"forbidden: $root/Album/pipe|name.jpg"* ]]
  [[ "$output" == *'forbidden: '*'ctl'* ]]
  [[ "$output" == *'forbidden: '*'mapped'* ]]
  [[ "$output" == *"forbidden: $root/Album/q:trail"* ]]
  [[ "$output" != *'forbidden: '*'fine.jpg'* ]]
  [ -f "$root/Album/a:b.jpg" ]
  [ -f "$root/Album/q:trail" ]
}

@test "thumbnail_make skips an empty video without errors or stray files" {
  source "$PROJECT_ROOT/lib/thumbnails.sh"
  mkdir -p -- "$test_root/thumbs"
  : >"$test_root/empty.avi"

  run thumbnail_make "$test_root/empty.avi" "$test_root/thumbs/empty.avi.webp" 120 convert empty.avi 400 cascading

  [ "$status" -eq 0 ]
  [[ "$output" == *'skipping unreadable video: empty.avi'* ]]
  [[ "$output" != *'insufficient image data'* && "$output" != *'cannot stat'* ]]
  [ -z "$(ls -A -- "$test_root/thumbs")" ]
}

@test "fix-names reports unopenable SMB-mangled aliases but not accessible lookalikes" {
  root="$test_root/mangled"
  shim="$test_root/shim"
  mkdir -p -- "$root/Album" "$shim"
  touch -- "$root/Album/ABC123~4"
  real_find=$(command -v find)
  # Simulate the CIFS listing: find also yields an alias that cannot be opened.
  printf '#!/usr/bin/env bash\n%s "$@"\nprintf "%%s\\0" "%s/Album/2KT24Y~W"\n' \
    "$real_find" "$root" >"$shim/find"
  chmod +x -- "$shim/find"

  PATH="$shim:$PATH" run "$PROJECT_ROOT/fix-names.sh" "$root"

  [ "$status" -eq 1 ]
  [[ "$output" == *"mangled: $root/Album/2KT24Y~W"* ]]
  [[ "$output" != *"mangled: $root/Album/ABC123~4"* ]]
  [[ "$output" == *'mangled 1.'* ]]
}

@test "cleanup keeps thumbnails whose originals exist even if the scan missed them" {
  albums="$test_root/albums"; thumbs="$test_root/thumbs"
  mkdir -p -- "$albums/Album" "$thumbs/Album"
  for i in $(seq 150); do
    touch -- "$albums/Album/IMG_$i.JPG"
    printf x >"$thumbs/Album/IMG_$i.JPG.webp"
    printf x >"$thumbs/Album/IMG_${i}.JPG_medium.webp"
  done
  touch -- "$albums/Album/clip.avi" "$albums/Album/pic.webp"
  printf x >"$thumbs/Album/clip.avi.webp"; printf x >"$thumbs/Album/clip.avi.web.mp4"
  printf x >"$thumbs/Album/pic.webp.webp"; printf x >"$thumbs/Album/pic.webp_medium.webp"
  declare -A nothing_expected=()

  run thumbnail_cleanup_stale "$albums" "$thumbs" nothing_expected

  [ "$status" -eq 0 ]
  [ "$(find "$thumbs" -type f | wc -l)" -eq 304 ]
  [[ "$output" == *'Kept 304 thumbnail(s)'* ]]
  [[ "$output" != *'Removing stale thumbnail'* ]]
}

@test "cleanup automatically removes thumbnails whose originals are really gone" {
  albums="$test_root/albums"; thumbs="$test_root/thumbs"
  mkdir -p -- "$albums/Album" "$thumbs/Album" "$thumbs/Gone"
  touch -- "$albums/Album/keep.JPG"
  for i in $(seq 150); do
    printf x >"$thumbs/Album/old$i.JPG.webp"
    printf x >"$thumbs/Gone/g$i.png_medium.webp"
  done
  printf x >"$thumbs/Album/keep.JPG.webp"
  printf x >"$thumbs/Album/oldclip.avi.web.mp4"
  declare -A expected_files=()
  expected_files["$thumbs/Album/keep.JPG.webp"]=1

  run thumbnail_cleanup_stale "$albums" "$thumbs" expected_files

  [ "$status" -eq 0 ]
  [ -e "$thumbs/Album/keep.JPG.webp" ]
  [ "$(find "$thumbs" -type f | wc -l)" -eq 1 ]
  [[ "$output" == *'old1.JPG.webp (no such original image)'* ]]
  [[ "$output" == *'Gone/g1.png_medium.webp (no such original album)'* ]]
  [[ "$output" == *'oldclip.avi.web.mp4 (no such original image)'* ]]
}

@test "cleanup refuses to run when the albums directory is empty" {
  albums="$test_root/albums"; thumbs="$test_root/thumbs"
  mkdir -p -- "$albums" "$thumbs/Album"
  printf x >"$thumbs/Album/a.jpg.webp"
  declare -A nothing_expected=()

  run thumbnail_cleanup_stale "$albums" "$thumbs" nothing_expected

  [ "$status" -ne 0 ]
  [[ "$output" == *'is empty or unreadable'* ]]
  [ -e "$thumbs/Album/a.jpg.webp" ]
}

@test "cleanup keeps metadata of existing originals and removes metadata of missing ones" {
  albums="$test_root/albums"; metadata="$test_root/metadata"
  mkdir -p -- "$albums/Album" "$metadata/Album"
  touch -- "$albums/Album/here.jpg"
  printf x >"$metadata/Album/here.jpg.json"
  printf x >"$metadata/Album/gone.jpg.json"
  declare -A meta_expected=() sums_expected=()

  run thumbnail_cleanup_stale_metadata "$albums" "$metadata" meta_expected sums_expected

  [ "$status" -eq 0 ]
  [ -e "$metadata/Album/here.jpg.json" ]
  [ ! -e "$metadata/Album/gone.jpg.json" ]
}

@test "update_thumbnails skips cleanup when an album scan fails" {
  albums="$test_root/albums"; thumbnails="$test_root/thumbnails"; metadata="$test_root/metadata"
  mkdir -p -- "$albums/Album" "$thumbnails/Album" "$metadata"
  touch -- "$albums/Album/keep.jpg"
  printf x >"$thumbnails/Album/gone.jpg.webp"
  thumbnail_list_media() { return 1; }

  run update_thumbnails "$albums" "$thumbnails" "$metadata" 250 1600 cascading

  [ "$status" -ne 0 ]
  [[ "$output" == *'Skipping stale thumbnail and metadata cleanup'* ]]
  [ -e "$thumbnails/Album/gone.jpg.webp" ]
}

@test "a held lock produces a warning naming the lock file and how to remove it" {
  thumbnails="$test_root/thumbnails"; config="$test_root/photina.conf"
  mkdir -p -- "$test_root/albums/A" "$thumbnails"
  touch -- "$test_root/albums/A/p.jpg"
  printf "ALBUMS_DIR='$test_root/albums'\nTHUMBNAILS_DIR='$thumbnails'\nMETADATA_DIR='$test_root/metadata'\n" >"$config"
  chmod 600 -- "$config"
  export TMPDIR="$test_root"
  lock=$(photina_lock_path cache "$thumbnails")
  exec 8>>"$lock"; flock -n 8; printf '4242 other-job.sh\n' >"$lock"

  run env PHOTINA_CONFIG="$config" "$PROJECT_ROOT/cleanup-thumbnails-and-metadata.sh"

  exec 8>&-
  [ "$status" -ne 0 ]
  [[ "$output" == *"warning: lock file $lock is held by: 4242 other-job.sh"* ]]
  [[ "$output" == *"delete the lock file and rerun: rm -- '$lock'"* ]]
}

@test "gallery generation and deletion take the gallery lock" {
  output_root="$test_root/dist"; config="$test_root/photina.conf"
  mkdir -p -- "$output_root/admin" "$test_root/albums/A"
  touch -- "$output_root/admin/index.html"
  printf "ALBUMS_DIR='$test_root/albums'\nTHUMBNAILS_DIR='$test_root/thumbs'\nMETADATA_DIR='$test_root/metadata'\nOUTPUT_DIR='$output_root'\nADMIN_PASSWORD=a\nGUEST_PASSWORD=g\n" >"$config"
  chmod 600 -- "$config"
  export TMPDIR="$test_root"
  exec 8>>"$(photina_lock_path gallery "$output_root")"
  flock -n 8

  run env PHOTINA_CONFIG="$config" "$PROJECT_ROOT/delete-admin-gallery.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *'another Photina job is already using the gallery'* ]]
  [ -e "$output_root/admin/index.html" ]

  run env PHOTINA_CONFIG="$config" "$PROJECT_ROOT/generate-admin-gallery.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *'another Photina job is already using the gallery'* ]]

  exec 8>&-
  run env PHOTINA_CONFIG="$config" "$PROJECT_ROOT/delete-admin-gallery.sh"
  [ "$status" -eq 0 ]
  [ ! -e "$output_root/admin" ]
}

@test "fix-names shortens long names with a middle ellipsis and keeps extensions" {
  root="$test_root/long"
  mkdir -p -- "$root"
  long=$(printf 'абвгд%.0s' {1..10})   # 50 characters
  mkfile "$root/${long}.jpg" "$root/short.jpg"
  mkdir -- "$root/$long"

  run "$PROJECT_ROOT/fix-names.sh" --max-length 20 "$root"

  [ "$status" -eq 0 ]
  [ -f "$root/short.jpg" ]
  [ -f "$root/абвгдабв…гдабвгд.jpg" ]
  [ -d "$root/абвгдабвгд…бвгдабвгд" ]
  [[ "$output" == *'Renamed 2 item(s)'* ]]
}

@test "fix-names deletes empty files but not symlinks, and honors dry-run" {
  root="$test_root/empty"
  mkdir -p -- "$root/sub"
  : >"$root/sub/zero.jpg"
  printf x >"$root/keep.jpg"
  ln -s zero.jpg "$root/sub/link.jpg"

  run "$PROJECT_ROOT/fix-names.sh" --dry-run "$root"
  [ "$status" -eq 0 ]
  [ -e "$root/sub/zero.jpg" ]
  [[ "$output" == *'Would delete 1 empty file(s).'* ]]

  run "$PROJECT_ROOT/fix-names.sh" "$root"
  [ "$status" -eq 0 ]
  [ ! -e "$root/sub/zero.jpg" ]
  [ -f "$root/keep.jpg" ]
  [ -L "$root/sub/link.jpg" ]
  [[ "$output" == *'Deleted 1 empty file(s).'* ]]
}
