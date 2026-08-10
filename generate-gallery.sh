#!/usr/bin/env bash
set -Eeuo pipefail

# Generate a static nanogallery2 site from a directory whose immediate
# subdirectories are albums.  Thumbnail files are deliberately kept in a
# separate directory from the source albums.

usage() {
  cat <<'EOF'
Usage: generate-gallery.sh [ALBUMS_DIR] [OUTPUT_DIR] [THUMBNAILS_DIR]

Arguments are optional and default to:
  ALBUMS_DIR     /mnt/gallery/albums
  OUTPUT_DIR     /mnt/gallery/dist
  THUMBNAILS_DIR /mnt/gallery/thumbnails

ALBUMS_DIR     Directory containing one subdirectory per album.
OUTPUT_DIR     Directory for index.html, copied media, and site assets.
THUMBNAILS_DIR Persistent thumbnail cache; must not be inside ALBUMS_DIR.

The generated site uses CDN-hosted nanogallery2 assets.  It supports common
image formats and videos handled by ffmpegthumbnailer.
EOF
}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ $# -le 3 ]] || { usage >&2; exit 2; }
albums_dir=$(realpath -m -- "${1:-/mnt/gallery/albums}")
output_dir=$(realpath -m -- "${2:-/mnt/gallery/dist}")
thumbs_dir=$(realpath -m -- "${3:-/mnt/gallery/thumbnails}")

[[ -d "$albums_dir" ]] || die "albums directory does not exist: $albums_dir"
[[ "$output_dir/" != "$albums_dir/"* ]] || die "output directory must be outside albums directory"
[[ "$thumbs_dir/" != "$albums_dir/"* ]] || die "thumbnail directory must be outside albums directory"

command -v find >/dev/null || die "find is required"
command -v realpath >/dev/null || die "realpath is required"
command -v ffmpegthumbnailer >/dev/null || die "ffmpegthumbnailer is required"
if command -v magick >/dev/null; then
  image_tool=(magick)
elif command -v convert >/dev/null; then
  image_tool=(convert)
else
  die "ImageMagick (magick or convert) is required"
fi

mkdir -p -- "$output_dir/media" "$output_dir/assets" "$thumbs_dir"

# These helpers escape content for HTML and URLs.  Media names are also
# percent-encoded sufficiently for normal static-server URLs.
html_escape() {
  local value=$1
  value=${value//&/&amp;}; value=${value//</&lt;}; value=${value//>/&gt;}
  value=${value//\"/&quot;}; value=${value//\'/&#39;}
  printf '%s' "$value"
}

url_escape_path() {
  # Keep path separators, encode characters that commonly break HTML URLs.
  local value=$1
  value=${value//%/%25}; value=${value//\ /%20}; value=${value//\#/%23}
  value=${value//\?/%3F}; value=${value//\"/%22}; value=${value//\'/%27}
  printf '%s' "$value"
}

is_video() {
  case "${1##*.}" in
    mp4|m4v|mov|mkv|webm|avi|mpeg|mpg|ts|mts) return 0 ;;
    *) return 1 ;;
  esac
}

make_thumbnail() {
  local source=$1 thumbnail=$2
  mkdir -p -- "$(dirname -- "$thumbnail")"
  if is_video "$source"; then
    ffmpegthumbnailer -i "$source" -o "$thumbnail" -s 640 -q 8 -f >/dev/null 2>&1
  else
    "${image_tool[@]}" "$source" -auto-orient -thumbnail '640x640^' \
      -gravity center -extent 640x640 -background white -alpha remove \
      -alpha off -strip -quality 86 "$thumbnail"
  fi
}

copy_media() {
  local source=$1 destination=$2
  mkdir -p -- "$(dirname -- "$destination")"
  # cp preserves the original file bytes and works for filenames with spaces.
  cp -f -- "$source" "$destination"
}

index_tmp=$(mktemp)
trap 'rm -f -- "$index_tmp"' EXIT
{
  cat <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Photo gallery</title>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/nanogallery2/3.0.5/css/nanogallery2.min.css">
  <style>body{margin:0;padding:2rem;font:16px system-ui,sans-serif;background:#f5f5f5;color:#222}main{max-width:1400px;margin:auto}.album{margin:2rem 0 3rem}h1{font-weight:500}h2{font-weight:400}</style>
  <script src="https://code.jquery.com/jquery-3.7.1.min.js"></script>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/nanogallery2/3.0.5/jquery.nanogallery2.min.js"></script>
</head>
<body><main><h1>Photo gallery</h1>
HTML

  shopt -s nullglob
  album_found=0
  for album_path in "$albums_dir"/*/; do
    [[ -d "$album_path" ]] || continue
    album_found=1
    album_name=${album_path%/}; album_name=${album_name##*/}
    printf '  <section class="album"><h2>%s</h2>\n' "$(html_escape "$album_name")"
    printf "    <div data-nanogallery2='{\"thumbnailHeight\":180,\"thumbnailWidth\":180,\"thumbnailLabel\":{\"display\":true},\"viewerTools\":{\"topLeft\":\"label\"}}'>\n"

    while IFS= read -r -d '' source; do
      relative=${source#"$album_path"}
      relative=${relative#/}
      thumb_path="$thumbs_dir/$album_name/$relative.jpg"
      media_path="$output_dir/media/$album_name/$relative"
      make_thumbnail "$source" "$thumb_path"
      copy_media "$source" "$media_path"
      media_url="media/$(url_escape_path "$album_name/$relative")"
      # The thumbnail URL is relative from OUTPUT_DIR to THUMBNAILS_DIR.
      thumb_url="$(realpath --relative-to="$output_dir" "$thumb_path")"
      thumb_url=$(url_escape_path "$thumb_url")
      title=${relative##*/}; title=${title%.*}
      printf '      <a href="%s" data-ngthumb="%s" data-ngdesc="%s">%s</a>\n' \
        "$(html_escape "$media_url")" "$(html_escape "$thumb_url")" \
        "$(html_escape "$title")" "$(html_escape "$title")"
    done < <(find -P "$album_path" -type f \( \
      -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.webp' \
      -o -iname '*.bmp' -o -iname '*.tif' -o -iname '*.tiff' -o -iname '*.avif' -o -iname '*.heic' -o -iname '*.heif' \
      -o -iname '*.mp4' -o -iname '*.m4v' -o -iname '*.mov' -o -iname '*.mkv' -o -iname '*.webm' \
      -o -iname '*.avi' -o -iname '*.mpeg' -o -iname '*.mpg' -o -iname '*.ts' -o -iname '*.mts' \) -print0 | sort -z)
    printf '    </div></section>\n'
  done
  (( album_found )) || printf '  <p>No albums found.</p>\n'
  cat <<'HTML'
</main></body>
</html>
HTML
} >"$index_tmp"

mv -f -- "$index_tmp" "$output_dir/index.html"
trap - EXIT
printf 'Gallery written to %s\nThumbnails written to %s\n' "$output_dir/index.html" "$thumbs_dir"
