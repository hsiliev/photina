#!/usr/bin/env bash

# EXIF metadata records and per-album md5 manifests.

thumbnail_batch_metadata() {
  local album_path=$1 album_name=$2 metadata_dir=$3 media_file=${4:-}
  local source relative metadata metadata_tmp batch_tmp records_tmp record
  local -a sources=()

  while IFS= read -r -d '' source; do
    relative=${source#"$album_path"}; relative=${relative#/}
    metadata="$metadata_dir/$album_name/$relative.json"
    if [[ ! -f "$metadata" ]]; then
      sources+=("$source")
    fi
  done < <(
    thumbnail_media_source "$album_path" "$media_file"
  )

  if ((${#sources[@]} == 0)); then
    printf '\tMetadata: no new files for %s\n' "$album_name"
    return 0
  fi
  printf '\tMetadata: extracting EXIF from %d files in %s\n' "${#sources[@]}" "$album_name"
  mkdir -p -- "$metadata_dir/$album_name"
  batch_tmp=$(mktemp)
  if ! exiftool -j -G1 -n -- "${sources[@]}" >"$batch_tmp"; then
    printf '\tMetadata: EXIF extraction failed for %s\n' "$album_name" >&2
    rm -f -- "$batch_tmp"
    return 1
  fi
  printf '\tMetadata: EXIF extraction complete for %s\n' "$album_name"
  records_tmp=$(mktemp)
  if ! jq -jr '.[] | .SourceFile, "\u0000", (tojson), "\u0000"' -- "$batch_tmp" >"$records_tmp"; then
    printf '\tMetadata: JSON conversion failed for %s\n' "$album_name" >&2
    rm -f -- "$batch_tmp" "$records_tmp"
    return 1
  fi

  while IFS= read -r -d '' source && IFS= read -r -d '' record; do
    relative=${source#"$album_path"}; relative=${relative#/}
    metadata="$metadata_dir/$album_name/$relative.json"
    metadata_tmp=${metadata%.json}.generating.json
    mkdir -p -- "$(dirname -- "$metadata")"
    printf '[%s]\n' "$record" >"$metadata_tmp"
    mv -f -- "$metadata_tmp" "$metadata"
  done <"$records_tmp"
  rm -f -- "$batch_tmp" "$records_tmp"
}

thumbnail_generate_checksums() {
  local album_path=$1 album_name=$2 metadata_dir=$3 media_file=${4:-}
  local source relative checksum_file checksum_tmp checksum_count=0
  local -a relative_sources=()

  checksum_file="$metadata_dir/$album_name/md5sums.txt"
  checksum_tmp="$checksum_file.generating"
  printf '\tChecksums: starting for %s\n' "$album_name"
  mkdir -p -- "$(dirname -- "$checksum_file")"
  while IFS= read -r -d '' source; do
    relative=${source#"$album_path"}; relative=${relative#/}
    relative_sources+=("$relative")
    checksum_count=$((checksum_count + 1))
  done < <(
    thumbnail_media_source "$album_path" "$media_file"
  )

  if ((${#relative_sources[@]})); then
    if ! printf '%s\0' "${relative_sources[@]}" |
      (cd -- "$album_path" && xargs -0 -r md5sum --) >"$checksum_tmp"; then
      rm -f -- "$checksum_tmp"
      return 1
    fi
  else
    : >"$checksum_tmp"
  fi
  mv -f -- "$checksum_tmp" "$checksum_file"
  printf '\tChecksums: completed for %s (%d records)\n' "$album_name" "$checksum_count"
}

thumbnail_checksums_need_update() {
  local album_path=$1 album_name=$2 metadata_dir=$3 media_file=${4:-}
  local checksum_file=$metadata_dir/$album_name/md5sums.txt
  local line relative source current_count=0 manifest_count=0
  local -A manifest_sources=()

  [[ -f "$checksum_file" ]] || return 0

  while IFS= read -r line; do
    [[ ${#line} -ge 34 ]] || return 0
    relative=${line:34}
    [[ -n "$relative" ]] || return 0
    manifest_sources["$relative"]=1
    manifest_count=$((manifest_count + 1))
  done <"$checksum_file"

  while IFS= read -r -d '' source; do
    relative=${source#"$album_path"}; relative=${relative#/}
    [[ -n ${manifest_sources["$relative"]+present} ]] || return 0
    current_count=$((current_count + 1))
  done < <(
    thumbnail_media_source "$album_path" "$media_file"
  )

  ((current_count == manifest_count)) || return 0

  while IFS= read -r -d '' source; do
    [[ "$source" -nt "$checksum_file" ]] && return 0
  done < <(
    thumbnail_media_source "$album_path" "$media_file"
  )

  return 1
}
