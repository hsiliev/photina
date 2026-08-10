#!/usr/bin/env bash

# Public entry point for the gallery generator. Keep the implementation split
# by responsibility so the renderer can be changed without touching discovery
# or index generation.
gallery_lib_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# shellcheck source=lib/gallery/core.sh
source "$gallery_lib_dir/core.sh"
# shellcheck source=lib/gallery/media.sh
source "$gallery_lib_dir/media.sh"
# shellcheck source=lib/gallery/albums.sh
source "$gallery_lib_dir/albums.sh"
# shellcheck source=lib/gallery/generator.sh
source "$gallery_lib_dir/generator.sh"
