#!/usr/bin/env bash

set -euo pipefail

# --- INPUT VALIDATION ---
if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 <flickr_dir> <media_dir>"
  echo "  <flickr_dir> : Directory with readable EXIF data (files to rename)"
  echo "  <media_dir>  : Directory with correct filenames (unreadable files)"
  exit 1
fi

FLICKR_DIR="$1"
MEDIA_DIR="$2"

if [[ ! -d "$FLICKR_DIR" ]]; then
  echo "Error: Flickr directory '$FLICKR_DIR' does not exist."
  exit 1
fi

if [[ ! -d "$MEDIA_DIR" ]]; then
  echo "Error: Media directory '$MEDIA_DIR' does not exist."
  exit 1
fi

# ------------------------

declare -a target_names=()
declare -a target_size_keys=()
declare -a target_mtimes=()
declare -a target_birthtimes=()
declare -a target_mtime_dates=()
declare -a target_birth_dates=()
declare -a target_used=()
declare -A target_name_indexes=()
declare -a unrenamed_reports=()

find_name_match() {
  local candidate_name="$1"
  local match_index=""

  [[ -n "${target_name_indexes[$candidate_name]+present}" ]] || return 1
  while IFS= read -r match_index; do
    [[ "${target_used[$match_index]}" -eq 0 ]] || continue
    printf '%s\n' "$match_index"
    return 0
  done <<< "${target_name_indexes[$candidate_name]}"
  return 1
}

date_matches_target() {
  local target_index="$1"
  shift
  local exif_date

  for exif_date in "$@"; do
    [[ -n "$exif_date" ]] || continue
    if [[ "$exif_date" == DATE:* ]]; then
      exif_date="${exif_date#DATE:}"
      if [[ "$exif_date" == "${target_mtime_dates[$target_index]}" ||
            "$exif_date" == "${target_birth_dates[$target_index]}" ]]; then
        return 0
      fi
    elif [[ "$exif_date" == "${target_mtimes[$target_index]}" ||
            "$exif_date" == "${target_birthtimes[$target_index]}" ]]; then
      return 0
    fi
  done
  return 1
}

find_date_match() {
  local size_key="$1"
  shift
  local -a exif_dates=("$@")
  local match_index=""
  local index

  for index in "${!target_names[@]}"; do
    [[ "${target_used[$index]}" -eq 0 ]] || continue
    [[ -z "$size_key" || "${target_size_keys[$index]}" == "$size_key" ]] || continue
    date_matches_target "$index" "${exif_dates[@]}" || continue
    if [[ -n "$match_index" ]]; then
      return 2
    fi
    match_index="$index"
  done

  if [[ -n "$match_index" ]]; then
    printf '%s\n' "$match_index"
    return 0
  fi
  return 1
}

print_closest_matches() {
  local source_name="$1"
  local source_size="$2"
  shift 2
  local -a source_dates=("$@")
  local closest_size_index=""
  local closest_size_difference=-1
  local closest_date_index=""
  local closest_date_difference=-1
  local index target_size size_difference source_date target_date date_difference
  local source_date_epoch target_date_epoch

  for index in "${!target_names[@]}"; do
    [[ "${target_used[$index]}" -eq 0 ]] || continue
    target_size="${target_size_keys[$index]}"
    if [[ "$source_size" =~ ^[0-9]+$ && "$target_size" =~ ^[0-9]+$ ]]; then
      if (( target_size >= source_size )); then
        size_difference=$((target_size - source_size))
      else
        size_difference=$((source_size - target_size))
      fi
      if (( closest_size_difference < 0 || size_difference < closest_size_difference )); then
        closest_size_difference="$size_difference"
        closest_size_index="$index"
      fi
    fi

    for source_date in "${source_dates[@]}"; do
      if [[ "$source_date" == DATE:* ]]; then
        source_date_epoch="$(date -d "${source_date#DATE:}" +%s 2>/dev/null)" || continue
        for target_date in "${target_mtime_dates[$index]}" "${target_birth_dates[$index]}"; do
          [[ "$target_date" =~ ^[0-9]{4}:[0-9]{2}:[0-9]{2}$ ]] || continue
          target_date_epoch="$(date -d "${target_date//:/-}" +%s 2>/dev/null)" || continue
          if (( target_date_epoch >= source_date_epoch )); then
            date_difference=$((target_date_epoch - source_date_epoch))
          else
            date_difference=$((source_date_epoch - target_date_epoch))
          fi
          if (( closest_date_difference < 0 || date_difference < closest_date_difference )); then
            closest_date_difference="$date_difference"
            closest_date_index="$index"
          fi
        done
        continue
      fi
      [[ "$source_date" =~ ^[0-9]+$ ]] || continue
      for target_date in "${target_mtimes[$index]}" "${target_birthtimes[$index]}"; do
        [[ "$target_date" =~ ^[0-9]+$ ]] || continue
        if (( target_date >= source_date )); then
          date_difference=$((target_date - source_date))
        else
          date_difference=$((source_date - target_date))
        fi
        if (( closest_date_difference < 0 || date_difference < closest_date_difference )); then
          closest_date_difference="$date_difference"
          closest_date_index="$index"
        fi
      done
    done
  done

  echo "Closest matches for ${source_name}:"
  if [[ -n "$closest_size_index" ]]; then
    echo "  size: ${target_names[$closest_size_index]} (${closest_size_difference} bytes difference)"
  else
    echo "  size: unavailable"
  fi
  if [[ -n "$closest_date_index" ]]; then
    echo "  time: ${target_names[$closest_date_index]} (${closest_date_difference} seconds difference)"
  else
    echo "  time: unavailable"
  fi
}

record_unrenamed() {
  local source_name="$1"
  local reason="$2"
  local source_size="$3"
  shift 3

  unrenamed_reports+=("Cannot rename: ${source_name} (${reason})
$(print_closest_matches "$source_name" "$source_size" "$@")")
}

echo "Indexing media directory (unreadable files names)..."
# Only MEDIA_DIR filesystem dates participate in date matching.  The Flickr
# pass below reads embedded EXIF dates, never FileModifyDate/FileCreateDate.
while IFS=$'\t' read -r filename filesize target_mtime target_birthtime target_mtime_date target_birth_date target_path; do
  [[ -z "$filename" ]] && continue

  target_names+=("$filename")
  target_size_keys+=("$filesize")
  target_mtimes+=("${target_mtime%%.*}")
  target_birthtimes+=("${target_birthtime%%.*}")
  target_mtime_dates+=("$target_mtime_date")
  target_birth_dates+=("$target_birth_date")
  target_used+=(0)
  target_index=$((${#target_names[@]} - 1))
  if [[ -n "${target_name_indexes[$filename]:-}" ]]; then
    target_name_indexes["$filename"]+=$'\n'"$target_index"
  else
    target_name_indexes["$filename"]="$target_index"
  fi
done < <(find "$MEDIA_DIR" -type f -printf '%f\t%s\t%T@\t%B@\t%TY:%Tm:%Td\t%BY:%Bm:%Bd\n')

echo "Matching and renaming flickr directory ..."
while IFS=$'\t' read -r src_filepath filesize exif_original_filename exif_preserved_filename date_original date_created date_modified gps_date; do
  [[ -z "$src_filepath" ]] && continue

  [[ "$exif_original_filename" == NA ]] && exif_original_filename=""
  [[ "$exif_preserved_filename" == NA ]] && exif_preserved_filename=""
  [[ "$date_original" == NA ]] && date_original=""
  [[ "$date_created" == NA ]] && date_created=""
  [[ "$date_modified" == NA ]] && date_modified=""
  [[ "$gps_date" == NA ]] && gps_date=""

  key="$filesize"
  exif_dates=()
  for exif_date in "$date_original" "$date_created" "$date_modified"; do
    [[ -n "$exif_date" ]] && exif_dates+=("$exif_date")
  done
  if ((${#exif_dates[@]} == 0)) && [[ -n "$gps_date" ]]; then
    exif_dates=("DATE:$gps_date")
  fi
  match_index=""
  match_basis=""

  for exif_name in "$exif_original_filename" "$exif_preserved_filename"; do
    [[ -n "$exif_name" ]] || continue
    exif_name="$(basename -- "$exif_name")"
    match_index="$(find_name_match "$exif_name")" || {
      status=$?
      if [[ "$status" -eq 2 ]]; then
        record_unrenamed "$(basename "$src_filepath")" "multiple targets have EXIF name '${exif_name}'" "$filesize" "${exif_dates[@]}"
        continue 2
      fi
      match_index=""
      continue
    }
    match_basis="EXIF filename"
    break
  done

  if [[ -z "$match_index" ]]; then
    size_match_count=0

    for index in "${!target_names[@]}"; do
      [[ "${target_used[$index]}" -eq 0 ]] || continue
      [[ "${target_size_keys[$index]}" == "$key" ]] || continue
      size_match_count=$((size_match_count + 1))
      match_index="$index"
    done

    if [[ "$size_match_count" -ne 1 ]]; then
      if [[ "$size_match_count" -gt 1 ]]; then
        match_index="$(find_date_match "$key" "${exif_dates[@]}")" || {
          status=$?
          if [[ "$status" -eq 2 ]]; then
            record_unrenamed "$(basename "$src_filepath")" "multiple targets match size (${key}) and dates" "$filesize" "${exif_dates[@]}"
          else
            record_unrenamed "$(basename "$src_filepath")" "multiple targets match size (${key})" "$filesize" "${exif_dates[@]}"
          fi
          continue
        }
        [[ -n "$match_basis" ]] || match_basis="created/modified date"
      else
        match_index="$(find_date_match '' "${exif_dates[@]}")" || {
          record_unrenamed "$(basename "$src_filepath")" "no size or date match" "$filesize" "${exif_dates[@]}"
          continue
        }
        [[ -n "$match_basis" ]] || match_basis="created/modified date"
      fi
    else
      match_basis="size"
    fi
  fi

  target_name="${target_names[$match_index]}"
  src_dir="$(dirname "$src_filepath")"
  new_filepath="${src_dir}/${target_name}"

  if [[ "$src_filepath" == "$new_filepath" ]]; then
    continue
  fi

  if [[ -e "$new_filepath" ]]; then
    record_unrenamed "$(basename "$src_filepath")" "target '${target_name}' already exists" "$filesize" "${exif_dates[@]}"
    continue
  fi

  mv "$src_filepath" "$new_filepath"
  target_used[$match_index]=1
  echo "Renamed: $(basename "$src_filepath") -> ${target_name} (matched by ${match_basis})"

done < <(exiftool -q -q -j -filepath -filesize# \
  -OriginalFileName -PreservedFileName \
  -EXIF:DateTimeOriginal -EXIF:CreateDate -EXIF:ModifyDate \
  -GPSDateStamp \
  -d '%s' "$FLICKR_DIR" |
  jq -r '.[] |
    [.SourceFile, (.FileSize // "NA"), (.OriginalFileName // "NA"),
     (.PreservedFileName // "NA"), (.DateTimeOriginal // "NA"),
     (.CreateDate // "NA"), (.ModifyDate // "NA"),
     (.GPSDateStamp // "NA")] | @tsv')

if ((${#unrenamed_reports[@]} > 0)); then
  echo
  echo "Files that could not be renamed:"
  for report in "${unrenamed_reports[@]}"; do
    printf '%s\n\n' "$report"
  done
fi

echo "Done."
