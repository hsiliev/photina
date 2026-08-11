#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_file=${PHOTINA_CONFIG:-$script_dir/photina.conf}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
warn() { printf 'warning: %s\n' "$*" >&2; }

[[ $# -eq 0 ]] || die 'usage: eliminate-duplicates.sh'
[[ -f "$config_file" ]] || die "configuration file does not exist: $config_file"

# shellcheck source=photina.conf
# shellcheck disable=SC1091
source "$config_file"

albums_dir=$(realpath -m -- "${ALBUMS_DIR:-/mnt/gallery/albums}")
thumbs_dir=$(realpath -m -- "${THUMBNAILS_DIR:-/mnt/gallery/thumbnails}")
metadata_dir=$(realpath -m -- "${METADATA_DIR:-/mnt/gallery/metadata}")
command -v find >/dev/null || die 'find is required'
command -v ln >/dev/null || die 'ln is required'
command -v mv >/dev/null || die 'mv is required'

mapfile -d '' -t manifests < <(find -P "$metadata_dir" -type f -name 'md5sums.txt' -print0 | sort -z)
if ((${#manifests[@]} == 0)); then
  printf 'No md5sums.txt manifests found in %s\n' "$metadata_dir"
  exit 0
fi

replace_with_hardlink() {
  local original=$1 duplicate=$2 temporary
  [[ -f "$original" ]] || { warn "original generated file is missing: $original"; return 0; }
  mkdir -p -- "$(dirname -- "$duplicate")"
  temporary="$duplicate.link.$$"
  rm -f -- "$temporary"
  ln -- "$original" "$temporary"
  mv -f -- "$temporary" "$duplicate"
}

link_duplicate_artifacts() {
  local original=$1 duplicate=$2 original_thumb duplicate_thumb
  local original_medium duplicate_medium original_metadata duplicate_metadata

  original_thumb="$thumbs_dir/$3/$4.webp"
  duplicate_thumb="$thumbs_dir/$5/$6.webp"
  original_medium="${original_thumb%.webp}_medium.webp"
  duplicate_medium="${duplicate_thumb%.webp}_medium.webp"
  original_metadata="$metadata_dir/$3/$4.json"
  duplicate_metadata="$metadata_dir/$5/$6.json"

  replace_with_hardlink "$original_thumb" "$duplicate_thumb"
  replace_with_hardlink "$original_medium" "$duplicate_medium"
  replace_with_hardlink "$original_metadata" "$duplicate_metadata"
}

declare -A first_source=() first_album=() first_relative=()
duplicate_count=0

for manifest in "${manifests[@]}"; do
  album_name=${manifest#"$metadata_dir"/}
  album_name=${album_name%/md5sums.txt}
  while IFS= read -r line || [[ -n "$line" ]]; do
    hash=${line%% *}
    [[ ${#hash} -eq 32 && "$hash" =~ ^[[:xdigit:]]+$ ]] || continue
    relative=${line#"$hash"}
    relative=${relative#  }
    source="$albums_dir/$album_name/$relative"
    if [[ -z ${first_source["$hash"]+present} ]]; then
      first_source["$hash"]=$source
      first_album["$hash"]=$album_name
      first_relative["$hash"]=$relative
      continue
    fi

    original=${first_source["$hash"]}
    [[ -f "$source" ]] || die "duplicate source file does not exist: $source"
    printf 'Duplicate MD5 %s:\n' "$hash"
    printf '  Keeping: %s\n' "$original"
    printf '  Linking: %s\n' "$source"
    replace_with_hardlink "$original" "$source"
    link_duplicate_artifacts "$original" "$source" \
      "${first_album["$hash"]}" "${first_relative["$hash"]}" "$album_name" "$relative"
    duplicate_count=$((duplicate_count + 1))
  done <"$manifest"
done

if ((duplicate_count == 0)); then
  printf 'No duplicate files found.\n'
else
  printf 'Eliminated %d duplicate file(s).\n' "$duplicate_count"
fi
