#!/usr/bin/env bash

# Thumbnail, viewer-image, metadata, and cache-cleanup library. The work is
# split by concern; this file loads the parts and holds the per-album and
# whole-library update steps that tie them together.

thumbnails_lib_dir=${BASH_SOURCE[0]%/*}/thumbnails

# shellcheck source=lib/common.sh
source "${BASH_SOURCE[0]%/*}/common.sh"
# shellcheck source=lib/thumbnails/discover.sh
source "$thumbnails_lib_dir/discover.sh"
# shellcheck source=lib/thumbnails/generate.sh
source "$thumbnails_lib_dir/generate.sh"
# shellcheck source=lib/thumbnails/metadata.sh
source "$thumbnails_lib_dir/metadata.sh"
# shellcheck source=lib/thumbnails/cleanup.sh
source "$thumbnails_lib_dir/cleanup.sh"

# Generate thumbnails, metadata, and checksums for one album. Sets the global
# THUMBNAIL_FAILURE_REASON and returns 1 on failure, naming the failed stage.
thumbnail_update_album() {
  local album_path=$1 album_name=$2 thumbs_dir=$3 metadata_dir=$4 thumbnail_size=$5 me_size=$6
  local image_tool=$7 parallel_jobs=$8 display_mode=$9 media_file=${10}

  thumbnail_batch_album "$album_path" "$album_name" "$thumbs_dir" "$thumbnail_size" "$me_size" \
    "$image_tool" "$parallel_jobs" all "$display_mode" "$media_file" || {
      THUMBNAIL_FAILURE_REASON='thumbnail generation failed for one or more files (see warnings above)'
      return 1
    }
  thumbnail_batch_metadata "$album_path" "$album_name" "$metadata_dir" "$media_file" || {
    THUMBNAIL_FAILURE_REASON='EXIF metadata extraction failed (exiftool/jq error above)'
    return 1
  }
  if thumbnail_checksums_need_update "$album_path" "$album_name" "$metadata_dir" "$media_file"; then
    thumbnail_generate_checksums "$album_path" "$album_name" "$metadata_dir" "$media_file" || {
      THUMBNAIL_FAILURE_REASON='md5 checksum generation failed (unreadable file?)'
      return 1
    }
  else
    printf '\tChecksums: unchanged for %s (skipped)\n' "$album_name"
  fi
}

update_thumbnails() {
  local albums_dir=$1 thumbs_dir=$2 metadata_dir=$3 thumbnail_size=$4 me_size=$5 display_mode=$6
  local image_tool parallel_jobs thumbnail_failed=0 cleanup_failed=0
  local -a failed_albums=()
  local album_path album_name media_file
  # shellcheck disable=SC2034 # passed by name to functions that use namerefs
  declare -A expected_thumbnails=() expected_metadata=() expected_checksums=()

  if command -v magick >/dev/null; then
    image_tool=magick
  elif command -v convert >/dev/null; then
    image_tool=convert
  else
    die 'ImageMagick (magick or convert) is required'
  fi
  parallel_jobs=$(photina_core_count)

  echo "Updating thumbnails in $thumbs_dir"
  echo "Updating metadata in $metadata_dir"
  echo "Image tool: $image_tool"
  echo "Thumbnail workers: $parallel_jobs"
  mkdir -p -- "$thumbs_dir" "$metadata_dir"
  thumbnail_migrate_legacy_medium "$thumbs_dir"

  while IFS= read -r -d '' album_path; do
    album_name=${album_path#"$albums_dir"/}; album_name=${album_name%/}
    media_file=$(mktemp)
    if ! thumbnail_list_media "$album_path" >"$media_file"; then
      thumbnail_failed=1
      failed_albums+=("$album_name (could not list media)")
    elif [[ -s "$media_file" ]]; then
      thumbnail_add_expected_outputs "$album_path" "$album_name" "$thumbs_dir" "$media_file" expected_thumbnails
      thumbnail_add_expected_metadata "$album_path" "$album_name" "$metadata_dir" "$media_file" expected_metadata expected_checksums
      echo "Scanning album: $album_name"
      THUMBNAIL_FAILURE_REASON='thumbnail/metadata update failed'
      thumbnail_update_album "$album_path" "$album_name" "$thumbs_dir" "$metadata_dir" "$thumbnail_size" \
        "$me_size" "$image_tool" "$parallel_jobs" "$display_mode" "$media_file" || {
          thumbnail_failed=1
          failed_albums+=("$album_name ($THUMBNAIL_FAILURE_REASON)")
        }
    fi
    rm -f -- "$media_file"
  done < <(thumbnail_list_albums "$albums_dir")
  # Never delete based on an incomplete scan: expected_* only list albums
  # whose media list was read successfully.
  if (( thumbnail_failed != 0 )); then
    echo 'Skipping stale thumbnail and metadata cleanup because some albums failed:'
    printf '\t%s\n' "${failed_albums[@]}"
  else
    thumbnail_cleanup_stale "$albums_dir" "$thumbs_dir" expected_thumbnails || cleanup_failed=1
    thumbnail_cleanup_stale_metadata "$albums_dir" "$metadata_dir" expected_metadata expected_checksums || cleanup_failed=1
  fi

  if (( thumbnail_failed != 0 )); then die 'one or more thumbnails could not be generated'; fi
  if (( cleanup_failed != 0 )); then die 'stale file cleanup was skipped because the albums directory looks empty'; fi

  echo 'Thumbnail update complete'
}
