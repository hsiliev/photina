#!/usr/bin/env bats

load test_helper

setup() {
  test_root="$BATS_TEST_TMPDIR/photina"
  mkdir -p -- "$test_root"
  which convert >/dev/null || skip "convert is required for flickr test images"
  which exiftool >/dev/null || skip "exiftool is required"
  which jq >/dev/null || skip "jq is required"
  which python3 >/dev/null || skip "python3 is required"
}

@test "fix-flickr-names renames by embedded EXIF OriginalFileName and PreservedFileName" {
  flickr="$test_root/flickr"
  media="$test_root/media"
  mkdir -p -- "$flickr" "$media"

  touch -- "$media/TARGET_1.JPG" "$media/TARGET_2.JPG"
  convert -size 10x10 xc:white "$flickr/source1.jpg"
  convert -size 10x10 xc:white "$flickr/source2.jpg"

  exiftool -overwrite_original -OriginalFileName='TARGET_1.JPG' "$flickr/source1.jpg" >/dev/null
  exiftool -overwrite_original -PreservedFileName='TARGET_2.JPG' "$flickr/source2.jpg" >/dev/null

  run "$PROJECT_ROOT/fix-flickr-names.sh" "$flickr" "$media"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Renamed: source1.jpg -> TARGET_1.JPG (matched by EXIF filename)'* ]]
  [[ "$output" == *'Renamed: source2.jpg -> TARGET_2.JPG (matched by EXIF filename)'* ]]
  [ -f "$flickr/TARGET_1.JPG" ]
  [ -f "$flickr/TARGET_2.JPG" ]
}

@test "fix-flickr-names renames by unique file size" {
  flickr="$test_root/flickr"
  media="$test_root/media"
  mkdir -p -- "$flickr" "$media"

  convert -size 10x10 xc:white "$flickr/source_size.jpg"
  source_size=$(stat -c '%s' -- "$flickr/source_size.jpg")

  # Target 1 matches exact size, Target 2 has different size
  truncate -s "$source_size" "$media/TARGET_UNIQUE_SIZE.JPG"
  truncate -s $((source_size + 100)) "$media/OTHER.JPG"

  run "$PROJECT_ROOT/fix-flickr-names.sh" "$flickr" "$media"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Renamed: source_size.jpg -> TARGET_UNIQUE_SIZE.JPG (matched by size)'* ]]
  [ -f "$flickr/TARGET_UNIQUE_SIZE.JPG" ]
}

@test "fix-flickr-names renames by target filename timestamp YYYYMMDD_HHMMSS" {
  flickr="$test_root/flickr"
  media="$test_root/media"
  mkdir -p -- "$flickr" "$media"

  touch -- "$media/IMG_20140418_113534.jpg"
  convert -size 10x10 xc:white "$flickr/source_ts.jpg"
  exiftool -overwrite_original -DateTimeOriginal='2014:04:18 11:35:34' "$flickr/source_ts.jpg" >/dev/null

  run "$PROJECT_ROOT/fix-flickr-names.sh" "$flickr" "$media"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Renamed: source_ts.jpg -> IMG_20140418_113534.jpg (matched by filename date)'* ]]
  [ -f "$flickr/IMG_20140418_113534.jpg" ]
}

@test "fix-flickr-names renames by EXIF date fallback within one-second tolerance" {
  flickr="$test_root/flickr"
  media="$test_root/media"
  mkdir -p -- "$flickr" "$media"

  # Target has modification date differing by 1 second
  touch -d '2018-09-12 14:30:01' "$media/TARGET_DATE.JPG"
  convert -size 10x10 xc:white "$flickr/source_date.jpg"
  exiftool -overwrite_original -DateTimeOriginal='2018:09:12 14:30:00' "$flickr/source_date.jpg" >/dev/null

  run "$PROJECT_ROOT/fix-flickr-names.sh" "$flickr" "$media"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Renamed: source_date.jpg -> TARGET_DATE.JPG (matched by created/modified date)'* ]]
  [ -f "$flickr/TARGET_DATE.JPG" ]
}

@test "fix-flickr-names renames by GPS date fallback against target calendar date" {
  flickr="$test_root/flickr"
  media="$test_root/media"
  mkdir -p -- "$flickr" "$media"

  touch -d '2020-07-15 08:12:34' "$media/TARGET_GPS.JPG"
  convert -size 10x10 xc:white "$flickr/source_gps.jpg"
  exiftool -overwrite_original -GPSDateStamp='2020:07:15' "$flickr/source_gps.jpg" >/dev/null

  run "$PROJECT_ROOT/fix-flickr-names.sh" "$flickr" "$media"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Renamed: source_gps.jpg -> TARGET_GPS.JPG (matched by created/modified date)'* ]]
  [ -f "$flickr/TARGET_GPS.JPG" ]
}

@test "fix-flickr-names consumes target on rename preventing duplicate assignment" {
  flickr="$test_root/flickr"
  media="$test_root/media"
  mkdir -p -- "$flickr" "$media"

  touch -d '2018-09-12 14:30:00' "$media/SHARED_TARGET.JPG"
  convert -size 10x10 xc:white "$flickr/first.jpg"
  convert -size 10x10 xc:white "$flickr/second.jpg"
  exiftool -overwrite_original -DateTimeOriginal='2018:09:12 14:30:00' "$flickr/first.jpg" >/dev/null
  exiftool -overwrite_original -DateTimeOriginal='2018:09:12 14:30:00' "$flickr/second.jpg" >/dev/null

  run "$PROJECT_ROOT/fix-flickr-names.sh" "$flickr" "$media"
  [ "$status" -eq 0 ]
  [ -f "$flickr/SHARED_TARGET.JPG" ]
  # One source was renamed, the other could not be renamed and remains
  [[ "$output" == *'Renamed: first.jpg -> SHARED_TARGET.JPG'* || "$output" == *'Renamed: second.jpg -> SHARED_TARGET.JPG'* ]]
  [[ "$output" == *'Cannot rename:'* ]]
}

@test "fix-flickr-names ignores subdirectories in both flickr and media directories" {
  flickr="$test_root/flickr"
  media="$test_root/media"
  mkdir -p -- "$flickr/subdir" "$media/subdir"

  touch -- "$media/subdir/NESTED_TARGET.JPG"
  touch -- "$media/VALID_TARGET.JPG"
  convert -size 10x10 xc:white "$flickr/subdir/nested_source.jpg"
  convert -size 10x10 xc:white "$flickr/valid_source.jpg"

  exiftool -overwrite_original -OriginalFileName='VALID_TARGET.JPG' "$flickr/valid_source.jpg" >/dev/null
  exiftool -overwrite_original -OriginalFileName='NESTED_TARGET.JPG' "$flickr/subdir/nested_source.jpg" >/dev/null

  run "$PROJECT_ROOT/fix-flickr-names.sh" "$flickr" "$media"
  [ "$status" -eq 0 ]
  [ -f "$flickr/VALID_TARGET.JPG" ]
  [ -f "$flickr/subdir/nested_source.jpg" ]
}

@test "fix-flickr-names reports closest size and time matches for unrenamed files" {
  flickr="$test_root/flickr"
  media="$test_root/media"
  mkdir -p -- "$flickr" "$media"

  truncate -s 1000 "$media/CLOSE_SIZE.JPG"
  touch -d '2019-01-01 10:00:00' "$media/CLOSE_SIZE.JPG"

  truncate -s 2000 "$media/CLOSE_TIME.JPG"
  touch -d '2019-06-01 12:00:00' "$media/CLOSE_TIME.JPG"

  convert -size 10x10 xc:white "$flickr/unmatched.jpg"
  exiftool -overwrite_original -DateTimeOriginal='2020:01:01 10:00:00' "$flickr/unmatched.jpg" >/dev/null

  run "$PROJECT_ROOT/fix-flickr-names.sh" "$flickr" "$media"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Cannot rename: unmatched.jpg (no size or date match)'* ]]
  [[ "$output" == *'Closest matches for unmatched.jpg:'* ]]
  [[ "$output" == *'size: CLOSE_SIZE.JPG'* ]]
  [[ "$output" == *'time: CLOSE_TIME.JPG'* ]]
}

@test "fix-flickr-names matches targets from WhereIsIt XML export" {
  flickr="$test_root/flickr"
  xml_file="$test_root/report.xml"
  mkdir -p -- "$flickr"

  cat > "$xml_file" << "EOF"
<?xml version="1.0" encoding="UTF-8"?>
<REPORT>
  <ITEM ItemType="File">
    <NAME>TARGET_FROM_XML.JPG</NAME>
    <EXT>JPG</EXT>
    <SIZE>3500</SIZE>
    <DESCRIPTION>Camera Date and Time: 2022:04:15 10:20:30</DESCRIPTION>
    <DATE>2022-04-15</DATE>
    <PATH>Photos/2022</PATH>
  </ITEM>
</REPORT>
EOF

  convert -size 10x10 xc:white "$flickr/flickr_input.jpg"
  exiftool -overwrite_original -DateTimeOriginal='2022:04:15 10:20:30' "$flickr/flickr_input.jpg" >/dev/null

  run "$PROJECT_ROOT/fix-flickr-names.sh" "$flickr" "$xml_file"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Renamed: flickr_input.jpg -> TARGET_FROM_XML.JPG'* ]]
  [ -f "$flickr/TARGET_FROM_XML.JPG" ]
}
