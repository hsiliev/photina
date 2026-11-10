# Thumbnails and viewer images

How generated thumbnails and viewer images are named, sized, and used by
the gallery. Part of the project notes in [AGENTS.md](../AGENTS.md).

## Viewer image variants

NanoGallery 3.0.5 picks `item.src<SIZE>` (falling back to `src`) from the
viewport width **once, when an album's gallery initializes** (not on later
resizes, not by device pixel ratio). Breakpoints are its defaults, which
Photina does not override: XS < 480, SM < 992, ME < 1200, LA < 1800, XL >= 1800.
`srcMax` is not read by 3.0.5 and is not emitted; downloads use `downloadURL`
(the original, `/media/...`).

For each image `thumbnail_make` writes, in one ImageMagick run next to
`<name>.webp`: `_xs.webp` (800px wide), `_sm.webp` (1280), `_me.webp`
(`MEDIUM_SIZE`, default 1600; same sizing as the old `_medium.webp`:
`WIDTHx` in cascading/justified, `WxW>` in grid modes), `_la.webp` (2400).
`xs/sm/la` use `WIDTHx>` (never enlarge). `_xl.webp` (full size, WebP) exists
only when `photina_browser_image` says browsers cannot show the original
(whitelist: jpg jpeg png gif webp avif bmp; so tif/tiff/heic/heif and unknown
extensions are converted). Otherwise `srcXL` is the original file. Videos get
only the thumbnail and a `_me.webp` frame (the viewer plays the video).
`photina_viewer_variants_to` (lib/common.sh) is the single source of which
variants exist; `thumbnail_expected_files_to` turns that into file paths and
drives pending checks, expected outputs, and check-missing. Widths `800`,
`1280`, `2400` are constants in `thumbnail_variant_resize_to`; only `MEDIUM_SIZE` is
configurable. Generation fails (skip + warning) if any variant is empty.

`thumbnail_migrate_legacy_medium` runs at the start of `update_thumbnails` and
renames `*_medium.webp` to `*_me.webp` (removing the old file if the `_me`
twin exists), so existing mediums are not regenerated. Walking a big cache is
slow and runs on every update (there is deliberately no marker file), so
progress is live: "Checking for legacy _medium.webp files ..." then each
directory (relative to the cache, `.` for the root) as it is checked, streamed
from `find -type d` with one glob per directory and no fork per directory.
There is no summary line; only rename failures warn.
`update_thumbnails` then prints "Listing albums in ..." before the album loop,
because the first `find | sort -z` is silent until it finishes. Adding the new sizes
makes existing photos pending once. Cleanup still understands `_medium.webp`.
Changing the set of variants requires bumping `gallery_fragment_version`.
