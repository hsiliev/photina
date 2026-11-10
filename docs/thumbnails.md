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
(`MEDIUM_SIZE`, default 1600; `WIDTHx` in cascading/justified, `WxW>` in grid modes), `_la.webp` (2400).
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

`update_thumbnails` prints "Listing albums in ..." before the album loop,
because the first `find | sort -z` is silent until it finishes. Adding the new
sizes makes existing photos pending once.
