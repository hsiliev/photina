# Photina project notes

## Maintenance requirement

After every code or behavior change, update this `AGENTS.md` and the matching
page under `docs/` (see the index below) in the same change. Record any new
commands, architectural behavior, invariants, performance decisions,
compatibility requirements, and validation steps. Keep the documents
consistent with the actual implementation before completing the task.

## Documentation index

- [docs/commands.md](docs/commands.md): every command's behavior, and the
  locking protocol.
- [docs/thumbnails.md](docs/thumbnails.md): thumbnail and viewer-image
  variants (`_xs/_sm/_me/_la/_xl`), sizing, and the legacy `_medium` rename.
- [docs/gallery.md](docs/gallery.md): gallery generator architecture,
  fragments and invalidation, album previews, performance notes.
- [docs/validation.md](docs/validation.md): syntax/lint/test commands and
  manual browser checks.

## Purpose

Photina is a Bash-based static photo/video gallery generator. Source media is
stored under `ALBUMS_DIR`; generated thumbnails and metadata are stored in
`THUMBNAILS_DIR` and `METADATA_DIR`; gallery HTML is written under
`OUTPUT_DIR/admin` and `OUTPUT_DIR/guest`.

## Project layout

```text
*.sh                      user-facing commands (see docs/commands.md)
lib/common.sh             shared die/warn/config/core-count/video/viewer-variant helpers
lib/thumbnails.sh         loads lib/thumbnails/*; per-album and whole-library update
lib/thumbnails/           discover (find media/albums), generate (thumbnails, viewer
                          images, web video), metadata (EXIF, md5 manifests),
                          cleanup (expected outputs, stale-file removal)
lib/caddy.sh              generate_caddyfile: merges the managed Caddy block
lib/gallery/              gallery generator (main, core, media, albums, generator,
                          generate = CLI entry for admin|guest, delete)
templates/                index.html.template (browser logic), Caddyfile.template,
                          photina.conf.template, gallery/*.html printf fragments
assets/favicon.png        copied into each generated gallery
tests/                    BATS suites: gallery, scripts
docs/                     detailed project notes (see Documentation index)
README.md                 end-user installation and usage
```

## Configuration

Commands read `PHOTINA_CONFIG` (default `/etc/photina/photina.conf`, a Bash
file; a warning is printed unless it is mode 600). Keys, with the template in
`templates/photina.conf.template`: `ALBUMS_DIR`, `OUTPUT_DIR`,
`THUMBNAILS_DIR`, `METADATA_DIR`, `CADDYFILE`, `HOST`, `PORT`,
`ADMIN_PASSWORD`, `GUEST_PASSWORD` (hashed with `caddy hash-password`, never
written in plaintext), `GUEST_ALBUMS` (array of album paths guests may open),
`THUMBNAIL_SIZE`, `MEDIUM_SIZE`, `IMAGE_EXTENSIONS`, `VIDEO_EXTENSIONS`, and
`THUMBNAIL_DISPLAY_MODE` (`cascading`, `justified`, or a grid mode). Output
directories must lie outside `ALBUMS_DIR`.

Runtime dependencies: bash 4.4+ (namerefs, `read -d`), GNU `find`/coreutils,
ImageMagick (`magick` or `convert`), `exiftool`, `jq`, `ffmpeg`,
`ffmpegthumbnailer`, `md5sum`, `cksum`, and `caddy`/`sudo`/`systemctl` for
serving.
`bats` is needed only for tests.

## Shared library layout

- `lib/common.sh` holds `die`, `warn`, `photina_load_config` (sources the
  config file and warns if it is not private), `photina_require_config NAME...`
  (dies unless each named variable is set), `photina_core_count`, the video
  helpers `photina_is_video` / `photina_needs_web_video`, and the image helpers
  `photina_browser_image` / `photina_viewer_variants_to`. Command scripts
  source it before loading the config; `lib/thumbnails.sh` and
  `lib/gallery/core.sh` source it themselves. Every config-reading command
  uses `photina_load_config`; only `split-by-year.sh` and
  `install-dependencies.sh` (no Photina config) keep a local `die`. Do not reintroduce per-script or
  per-library copies of these helpers.
- `lib/thumbnails.sh` loads the parts in `lib/thumbnails/` and holds
  `thumbnail_update_album` (thumbnails, metadata, checksums for one album) and
  `update_thumbnails`. `discover.sh` has `thumbnail_list_media` (sorted
  images+videos for one album), `thumbnail_media_source` (precomputed list or
  fresh scan), and `thumbnail_list_albums` (every album directory under each
  top-level album). `cleanup.sh` has `thumbnail_collect_expected`, the shared
  "scan all albums and record expected outputs" loop used by the cleanup and
  missing-check scripts.
  `thumbnail_make` (generate.sh) is a short sequence of helpers:
  `thumbnail_extract_video_frame`, `thumbnail_magick_args_to` (one ImageMagick
  argument list for the thumbnail plus every viewer variant, using
  `thumbnail_variant_resize_to`), `thumbnail_make_web_video`, and
  `thumbnail_publish_outputs`. Only the input (`-auto-orient` for images) and
  viewer-image quality (90, 86 for video frames) differ between images and
  video frames. Each helper that `xargs` workers need must be listed in the
  `export -f` line of `thumbnail_batch_album`.
  Relative-path expansion stays inline (`${source#"$album_path"}`) because a
  command substitution per file would fork in hot loops.

## Code conventions

- Functions with more than three positional arguments start with a
  `# Usage:` comment naming them in order. `thumbnail_process_item` takes the
  media file last so `xargs` can append it to the fixed arguments.
- Functions that fill a caller's array through a nameref name it
  `_photina_<purpose>_out` (for example `_photina_files_out`) so it cannot
  collide with the caller's variable, and carry a shellcheck SC2034 reason.
  The gallery `*_to` helpers keep their older `result` nameref (see the
  fork-avoidance notes in docs/gallery.md).
- The 1600px viewer image is called `me` in code (`me_size`, `me_path`,
  `me_url`) to match `_me.webp`; the configuration key stays `MEDIUM_SIZE`.
- Do not copy configuration checks: use `photina_require_config`.
