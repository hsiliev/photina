#!/usr/bin/env bash

set -euo pipefail

# --- INPUT VALIDATION ---
if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 <flickr_dir> <media_dir|whereisit_xml>"
  echo "  <flickr_dir>    : Directory with readable EXIF data (files to rename)"
  echo "  <media_dir>     : Directory with correct filenames (top-level files)"
  echo "  <whereisit_xml> : WhereIsIt report export with filenames and metadata"
  exit 1
fi

FLICKR_DIR="$1"
MEDIA_DIR="$2"

if [[ ! -d "$FLICKR_DIR" ]]; then
  echo "Error: Flickr directory '$FLICKR_DIR' does not exist."
  exit 1
fi

if [[ ! -d "$MEDIA_DIR" && ! -f "$MEDIA_DIR" ]]; then
  echo "Error: Media directory or XML file '$MEDIA_DIR' does not exist."
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/fix/target-input.sh"

# ------------------------

declare -a target_names=()
declare -a target_size_keys=()
declare -a target_mtimes=()
declare -a target_birthtimes=()
declare -a target_mtime_dates=()
declare -a target_birth_dates=()
declare -a target_filename_dates=()
declare -a target_used=()
declare -A target_name_indexes=()
declare -A target_size_counts=()
declare -A target_size_single_indexes=()
declare -A target_size_indexes=()
declare -A target_epoch_indexes=()
declare -A target_calendar_indexes=()
declare -A target_filename_date_indexes=()
declare -A target_filename_calendar_indexes=()
date_indexes_built=0
target_count=0
source_count=0
declare -a unrenamed_sources=()
declare -a unrenamed_reasons=()
declare -a unrenamed_sizes=()
declare -a unrenamed_date1=()
declare -a unrenamed_date2=()
declare -a unrenamed_date3=()

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
  local exif_date target_date date_difference

  for exif_date in "$@"; do
    [[ -n "$exif_date" ]] || continue
    if [[ "$exif_date" == DATE:* ]]; then
      exif_date="${exif_date#DATE:}"
      if [[ "$exif_date" == "${target_mtime_dates[$target_index]}" ||
            "$exif_date" == "${target_birth_dates[$target_index]}" ||
            "${target_filename_dates[$target_index]:0:8}" == "${exif_date//:/}" ]]; then
        return 0
      fi
    elif [[ "$exif_date" == NAME:* ]]; then
      [[ "${target_filename_dates[$target_index]}" == "${exif_date#NAME:}" ]] && return 0
    elif [[ "$exif_date" =~ ^[0-9]+$ ]]; then
      for target_date in "${target_mtimes[$target_index]}" "${target_birthtimes[$target_index]}"; do
        [[ "$target_date" =~ ^[0-9]+$ ]] || continue
        if (( target_date >= exif_date )); then
          date_difference=$((target_date - exif_date))
        else
          date_difference=$((exif_date - target_date))
        fi
        (( date_difference <= 1 )) && return 0
      done
    fi
  done
  return 1
}

filename_date_matches_source() {
  local target_index="$1"
  shift
  local exif_date filename_date filename_epoch date_only

  [[ -n "${target_filename_dates[$target_index]}" ]] || return 1
  for exif_date in "$@"; do
    if [[ "$exif_date" == DATE:* ]]; then
      date_only="${exif_date#DATE:}"
      date_only="${date_only//:/}"
      [[ "${target_filename_dates[$target_index]:0:8}" == "$date_only" ]] && return 0
    elif [[ "$exif_date" =~ ^[0-9]+$ ]]; then
      for filename_epoch in "$((exif_date - 1))" "$exif_date" "$((exif_date + 1))"; do
        filename_date="$(date -d "@${filename_epoch}" +%Y%m%d%H%M%S 2>/dev/null)" || continue
        [[ "${target_filename_dates[$target_index]}" == "$filename_date" ]] && return 0
      done
    fi
  done
  return 1
}

find_date_match() {
  local size_key="$1"
  shift
  local -a exif_dates=("$@")
  local match_index="" index candidate_key exif_date filename_date
  local -A candidate_indexes=()
  local -a candidate_dates=("${exif_dates[@]}")

  if [[ "$date_indexes_built" -eq 0 ]]; then
    for index in "${!target_names[@]}"; do
      for target_epoch in "${target_mtimes[$index]}" "${target_birthtimes[$index]}"; do
        [[ "$target_epoch" =~ ^[0-9]+$ ]] || continue
        for epoch_key in "$((target_epoch - 1))" "$target_epoch" "$((target_epoch + 1))"; do
          target_epoch_indexes["$epoch_key"]+="$index"$'\n'
        done
      done
      for target_calendar in "${target_mtime_dates[$index]}" "${target_birth_dates[$index]}"; do
        [[ "$target_calendar" =~ ^[0-9]{4}:[0-9]{2}:[0-9]{2}$ ]] || continue
        target_calendar_indexes["$target_calendar"]+="$index"$'\n'
      done
    done
    date_indexes_built=1
  fi

  if [[ -n "$size_key" ]]; then
    while IFS= read -r index; do
      [[ -n "$index" ]] && candidate_indexes["$index"]=1
    done <<< "${target_size_indexes[$size_key]:-}"
  else
    for exif_date in "${exif_dates[@]}"; do
      if [[ "$exif_date" == DATE:* ]]; then
        candidate_key="${exif_date#DATE:}"
        while IFS= read -r index; do
          [[ -n "$index" ]] && candidate_indexes["$index"]=1
        done <<< "${target_calendar_indexes[$candidate_key]:-}"
        candidate_key="${candidate_key//:/}"
        while IFS= read -r index; do
          [[ -n "$index" ]] && candidate_indexes["$index"]=1
        done <<< "${target_filename_calendar_indexes[$candidate_key]:-}"
      elif [[ "$exif_date" =~ ^[0-9]+$ ]]; then
        for candidate_key in "$((exif_date - 1))" "$exif_date" "$((exif_date + 1))"; do
          while IFS= read -r index; do
            [[ -n "$index" ]] && candidate_indexes["$index"]=1
          done <<< "${target_epoch_indexes[$candidate_key]:-}"
        done
        for filename_epoch in "$((exif_date - 1))" "$exif_date" "$((exif_date + 1))"; do
          filename_date="$(date -d "@${filename_epoch}" +%Y%m%d%H%M%S 2>/dev/null)" || filename_date=""
          if [[ -n "$filename_date" ]]; then
            candidate_dates+=("NAME:$filename_date")
            while IFS= read -r index; do
              [[ -n "$index" ]] && candidate_indexes["$index"]=1
            done <<< "${target_filename_date_indexes[$filename_date]:-}"
            while IFS= read -r index; do
              [[ -n "$index" ]] && candidate_indexes["$index"]=1
            done <<< "${target_filename_calendar_indexes[${filename_date:0:8}]:-}"
          fi
        done
      fi
    done
  fi

  for index in "${!candidate_indexes[@]}"; do
    [[ "${target_used[$index]}" -eq 0 ]] || continue
    [[ -z "$size_key" || "${target_size_keys[$index]}" == "$size_key" ]] || continue
    date_matches_target "$index" "${candidate_dates[@]}" || continue
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

find_filename_date_match() {
  local -a exif_dates=("$@")
  local index filename_date filename_epoch exif_date candidate_key
  local match_index="" candidate_indexes_name
  local -A exact_candidates=() nearby_candidates=()

  for exif_date in "${exif_dates[@]}"; do
    if [[ "$exif_date" == DATE:* ]]; then
      candidate_key="${exif_date#DATE:}"
      candidate_key="${candidate_key//:/}"
      while IFS= read -r index; do
        [[ -n "$index" ]] && exact_candidates["$index"]=1
      done <<< "${target_filename_calendar_indexes[$candidate_key]:-}"
    elif [[ "$exif_date" =~ ^[0-9]+$ ]]; then
      filename_date="$(date -d "@${exif_date}" +%Y%m%d%H%M%S 2>/dev/null)" || filename_date=""
      if [[ -n "$filename_date" ]]; then
        while IFS= read -r index; do
          [[ -n "$index" ]] && exact_candidates["$index"]=1
        done <<< "${target_filename_date_indexes[$filename_date]:-}"
      fi
      for filename_epoch in "$((exif_date - 1))" "$((exif_date + 1))"; do
        filename_date="$(date -d "@${filename_epoch}" +%Y%m%d%H%M%S 2>/dev/null)" || continue
        while IFS= read -r index; do
          [[ -n "$index" ]] && nearby_candidates["$index"]=1
        done <<< "${target_filename_date_indexes[$filename_date]:-}"
      done
    fi
  done

  for candidate_indexes_name in exact_candidates nearby_candidates; do
    local -n candidate_indexes="$candidate_indexes_name"
    match_index=""
    for index in "${!candidate_indexes[@]}"; do
      [[ "${target_used[$index]}" -eq 0 ]] || continue
      filename_date_matches_source "$index" "${exif_dates[@]}" || continue
      if [[ -n "$match_index" ]]; then
        return 2
      fi
      match_index="$index"
    done
    [[ -n "$match_index" ]] && break
  done
  [[ -n "$match_index" ]] || return 1
  printf '%s\n' "$match_index"
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

  echo "   Investigating ${source_name} (${reason}); queuing closest-match analysis ..."
  unrenamed_sources+=("$source_name")
  unrenamed_reasons+=("$reason")
  unrenamed_sizes+=("$source_size")
  unrenamed_date1+=("${1:-}")
  unrenamed_date2+=("${2:-}")
  unrenamed_date3+=("${3:-}")
}

echo "Indexing media directory (unreadable files names)..."
# Only MEDIA_DIR filesystem dates participate in date matching.  The Flickr
# pass below reads embedded EXIF dates, never FileModifyDate/FileCreateDate.
target_input=(fix_emit_target_records "$MEDIA_DIR" "$SCRIPT_DIR")
while IFS=$'\t' read -r filename filesize target_mtime target_birthtime target_mtime_date target_birth_date target_path; do
  [[ -z "$filename" ]] && continue

  target_names+=("$filename")
  target_size_keys+=("$filesize")
  target_mtimes+=("${target_mtime%%.*}")
  target_birthtimes+=("${target_birthtime%%.*}")
  target_mtime_dates+=("$target_mtime_date")
  target_birth_dates+=("$target_birth_date")
  if [[ "$filename" =~ (^|[^0-9])([12][0-9]{3}[01][0-9][0-3][0-9])[_-]?([0-2][0-9][0-5][0-9][0-5][0-9])([^0-9]|$) ]]; then
    target_filename_dates+=("${BASH_REMATCH[2]}${BASH_REMATCH[3]}")
  else
    target_filename_dates+=("")
  fi
  target_used+=(0)
  target_index=$((${#target_names[@]} - 1))
  if [[ -n "${target_name_indexes[$filename]:-}" ]]; then
    target_name_indexes["$filename"]+=$'\n'"$target_index"
  else
    target_name_indexes["$filename"]="$target_index"
  fi
  if [[ -n "${target_size_counts[$filesize]+present}" ]]; then
    if [[ "${target_size_counts[$filesize]}" -eq 1 ]]; then
      target_size_indexes["$filesize"]="${target_size_single_indexes[$filesize]}"$'\n'
    fi
    target_size_indexes["$filesize"]+="$target_index"$'\n'
    target_size_counts["$filesize"]=$((target_size_counts[$filesize] + 1))
    unset 'target_size_single_indexes[$filesize]'
  else
    target_size_counts["$filesize"]=1
    target_size_single_indexes["$filesize"]="$target_index"
  fi
  if [[ -n "${target_filename_dates[$target_index]}" ]]; then
    target_filename_date_indexes["${target_filename_dates[$target_index]}"]+="$target_index"$'\n'
    target_filename_calendar_indexes["${target_filename_dates[$target_index]:0:8}"]+="$target_index"$'\n'
  fi

done < <("${target_input[@]}")
target_count="${#target_names[@]}"
echo "   Indexed ${target_count} target files."

echo "Matching and renaming flickr directory ..."
echo "   Reading Flickr metadata and matching files ..."
flickr_metadata="$(exiftool -q -q -r- -j -filepath -filesize# \
  -OriginalFileName -PreservedFileName \
  -EXIF:DateTimeOriginal -EXIF:CreateDate -EXIF:ModifyDate \
  -GPSDateStamp -d '%s' "$FLICKR_DIR")"
mapfile -t flickr_records < <(jq -r '.[] |
  [.SourceFile, (.FileSize // "NA"), (.OriginalFileName // "NA"),
   (.PreservedFileName // "NA"), (.DateTimeOriginal // "NA"),
   (.CreateDate // "NA"), (.ModifyDate // "NA"),
   (.GPSDateStamp // "NA")] | @tsv' <<< "$flickr_metadata")
unset flickr_metadata
echo "   Flickr metadata batch read (${#flickr_records[@]} files)."
echo "   Matching in-memory Flickr metadata ..."

for flickr_record in "${flickr_records[@]}"; do
  IFS=$'\t' read -r src_filepath filesize exif_original_filename exif_preserved_filename date_original date_created date_modified gps_date <<< "$flickr_record"
  [[ -z "$src_filepath" ]] && continue
  source_count=$((source_count + 1))
  if (( source_count % 100 == 0 )); then
    echo "   Processed ${source_count} Flickr files."
  fi

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
    match_index="$(find_filename_date_match "${exif_dates[@]}")" || {
      status=$?
      if [[ "$status" -eq 2 ]]; then
        record_unrenamed "$(basename "$src_filepath")" "multiple targets match filename date" "$filesize" "${exif_dates[@]}"
        continue
      fi
      match_index=""
    }
    if [[ -n "$match_index" ]]; then
      match_basis="filename date"
    fi
  fi

  if [[ -z "$match_index" ]]; then
    size_match_count="${target_size_counts[$key]:-0}"
    if [[ "$size_match_count" -eq 1 ]]; then
      match_index="${target_size_single_indexes[$key]}"
      [[ "${target_used[$match_index]}" -eq 0 ]] || {
        size_match_count=0
        match_index=""
      }
    elif [[ "$size_match_count" -gt 1 ]]; then
      size_match_count=0
      while IFS= read -r index; do
        [[ -n "$index" ]] || continue
        [[ "${target_used[$index]}" -eq 0 ]] || continue
        size_match_count=$((size_match_count + 1))
        match_index="$index"
      done <<< "${target_size_indexes[$key]:-}"
    fi

    if [[ "$size_match_count" -ne 1 ]]; then
      if [[ "$size_match_count" -gt 1 ]]; then
        match_index="$(find_date_match "$key" "${exif_dates[@]}")" || {
          status=$?
          if [[ "$status" -eq 1 ]]; then
            # A filename timestamp can identify the target even when its
            # size differs and the source size is shared by other targets.
            match_index="$(find_date_match '' "${exif_dates[@]}")" || status=$?
          fi
          if [[ -z "$match_index" ]]; then
            if [[ "$status" -eq 2 ]]; then
              record_unrenamed "$(basename "$src_filepath")" "multiple targets match size (${key}) and dates" "$filesize" "${exif_dates[@]}"
            else
              record_unrenamed "$(basename "$src_filepath")" "multiple targets match size (${key})" "$filesize" "${exif_dates[@]}"
            fi
            continue
          fi
        }
        if filename_date_matches_source "$match_index" "${exif_dates[@]}"; then
          [[ -n "$match_basis" ]] || match_basis="filename date"
        else
          [[ -n "$match_basis" ]] || match_basis="created/modified date"
        fi
      else
        match_index="$(find_date_match '' "${exif_dates[@]}")" || {
          record_unrenamed "$(basename "$src_filepath")" "no size or date match" "$filesize" "${exif_dates[@]}"
          continue
        }
        if filename_date_matches_source "$match_index" "${exif_dates[@]}"; then
          [[ -n "$match_basis" ]] || match_basis="filename date"
        else
          [[ -n "$match_basis" ]] || match_basis="created/modified date"
        fi
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

done

echo "   Processed ${source_count} Flickr files."

if ((${#unrenamed_sources[@]} > 0)); then
  echo
  echo "Files that could not be renamed:"
  echo "   Calculating closest matches for ${#unrenamed_sources[@]} files ..."
  awk -F '\t' '
    function abs(value) { return value < 0 ? -value : value }
    function calendar_epoch(value, fields) {
      if (value !~ /^[0-9][0-9][0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/) return ""
      split(value, fields, ":")
      return mktime(fields[1] " " fields[2] " " fields[3] " 00 00 00")
    }
    function filename_epoch(value, fields) {
      if (value !~ /^[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]$/) return ""
      return mktime(substr(value, 1, 4) " " substr(value, 5, 2) " " substr(value, 7, 2) " " substr(value, 9, 2) " " substr(value, 11, 2) " " substr(value, 13, 2))
    }
    function consider_date(target_epoch, source_epoch, target_name, difference) {
      if (target_epoch == "" || source_epoch == "") return
      difference = abs(target_epoch - source_epoch)
      if (closest_date_difference < 0 || difference < closest_date_difference) {
        closest_date_difference = difference
        closest_date_name = target_name
      }
    }
    $1 == "T" {
      target_count++
      target_name[target_count] = $2
      target_size[target_count] = $3
      target_mtime[target_count] = ($4 ~ /^[0-9]+$/ ? $4 : "")
      target_birth[target_count] = ($5 ~ /^[0-9]+$/ ? $5 : "")
      target_mtime_date[target_count] = calendar_epoch($6)
      target_birth_date[target_count] = calendar_epoch($7)
      target_filename_date[target_count] = $8
      target_filename_epoch[target_count] = filename_epoch($8)
      next
    }
    $1 == "F" {
      closest_size_difference = -1
      closest_size_name = ""
      closest_date_difference = -1
      closest_date_name = ""
      for (i = 1; i <= target_count; i++) {
        if ($4 ~ /^[0-9]+$/ && target_size[i] ~ /^[0-9]+$/) {
          difference = abs(target_size[i] - $4)
          if (closest_size_difference < 0 || difference < closest_size_difference) {
            closest_size_difference = difference
            closest_size_name = target_name[i]
          }
        }
        for (field = 5; field <= 7; field++) {
          source_date = $(field)
          if (source_date ~ /^DATE:/) {
            source_calendar = substr(source_date, 6)
            source_epoch = calendar_epoch(source_calendar)
            consider_date(target_mtime_date[i], source_epoch, target_name[i])
            consider_date(target_birth_date[i], source_epoch, target_name[i])
            if (target_filename_date[i] != "" && substr(target_filename_date[i], 1, 8) == substr(source_calendar, 1, 4) substr(source_calendar, 6, 2) substr(source_calendar, 9, 2))
              consider_date(target_filename_epoch[i], source_epoch, target_name[i])
          } else if (source_date ~ /^[0-9]+$/) {
            consider_date(target_mtime[i], source_date, target_name[i])
            consider_date(target_birth[i], source_date, target_name[i])
            consider_date(target_filename_epoch[i], source_date, target_name[i])
          }
        }
      }
      printf "Cannot rename: %s (%s)\n", $2, $3
      printf "Closest matches for %s:\n", $2
      if (closest_size_name != "") printf "  size: %s (%s bytes difference)\n", closest_size_name, closest_size_difference
      else printf "  size: unavailable\n"
      if (closest_date_name != "") printf "  time: %s (%s seconds difference)\n\n", closest_date_name, closest_date_difference
      else printf "  time: unavailable\n\n"
      next
    }
    ' < <(
      for index in "${!target_names[@]}"; do
        printf 'T\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
          "${target_names[$index]}" "${target_size_keys[$index]}" \
          "${target_mtimes[$index]}" "${target_birthtimes[$index]}" \
          "${target_mtime_dates[$index]}" "${target_birth_dates[$index]}" \
          "${target_used[$index]}" "${target_filename_dates[$index]}"
      done
      for index in "${!unrenamed_sources[@]}"; do
        printf 'F\t%s\t%s\t%s\t%s\t%s\t%s\n' \
          "${unrenamed_sources[$index]}" "${unrenamed_reasons[$index]}" \
          "${unrenamed_sizes[$index]}" "${unrenamed_date1[$index]}" \
          "${unrenamed_date2[$index]}" "${unrenamed_date3[$index]}"
      done
    )
  echo "   Closest-match analysis complete."
fi

echo "Done."
