#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PHOTINA_RECREATE=0 exec "$script_dir/generate-gallery.sh" "$@"
