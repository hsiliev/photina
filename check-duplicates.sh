#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_file=${PHOTINA_CONFIG:-$script_dir/photina.conf}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ $# -eq 0 ]] || die 'usage: check-duplicates.sh'
[[ -f "$config_file" ]] || die "configuration file does not exist: $config_file"

# shellcheck source=photina.conf
# shellcheck disable=SC1091
source "$config_file"
metadata_dir=$(realpath -m -- "${METADATA_DIR:-/mnt/gallery/metadata}")
command -v find >/dev/null || die 'find is required'
command -v awk >/dev/null || die 'awk is required'

mapfile -d '' -t manifests < <(find -P "$metadata_dir" -type f -name 'md5sums.txt' -print0 | sort -z)
if ((${#manifests[@]} == 0)); then
  printf 'No md5sums.txt manifests found in %s\n' "$metadata_dir"
  exit 0
fi

printf 'Checking %d checksum manifest(s) in %s\n' "${#manifests[@]}" "$metadata_dir"
if awk -v metadata_dir="$metadata_dir" '
  function manifest_album(manifest) {
    sub("^" metadata_dir "/", "", manifest)
    sub("/md5sums[.]txt$", "", manifest)
    return manifest
  }
  length($1) == 32 {
    hash = tolower($1)
    path = $0
    sub(/^[^[:space:]]+[[:space:]]+/, "", path)
    location = manifest_album(FILENAME) "/" path
    locations[hash] = locations[hash] "\n  " location
    counts[hash]++
  }
  END {
    duplicate_count = 0
    for (hash in counts) {
      if (counts[hash] > 1) {
        duplicate_count++
        printf "\nDuplicate MD5: %s (%d files)%s\n", hash, counts[hash], locations[hash]
      }
    }
    if (duplicate_count == 0)
      print "No duplicate files found."
    exit (duplicate_count > 0 ? 1 : 0)
  }
' "${manifests[@]}"; then
  exit 0
else
  exit 1
fi
