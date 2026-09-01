function abs(value) { return value < 0 ? -value : value }
function calendar_epoch(value, fields) {
  if (value !~ /^[0-9][0-9][0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/) return ""
  split(value, fields, ":")
  return mktime(fields[1] " " fields[2] " " fields[3] " 00 00 00")
}
function filename_epoch(value) {
  if (value !~ /^[0-9]{14}$/) return ""
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
      target_used[target_count] = $8
      target_filename_date[target_count] = $9
      target_filename_epoch[target_count] = filename_epoch($9)
  next
}
$1 == "F" {
  closest_size_difference = -1
  closest_size_name = ""
  closest_date_difference = -1
      closest_date_name = ""
      for (i = 1; i <= target_count; i++) {
        if (target_used[i] != "0") continue
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
