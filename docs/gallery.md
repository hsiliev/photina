# Gallery generation

Gallery generator architecture, fragments, previews, and performance
notes. Part of the project notes in [AGENTS.md](../AGENTS.md).

## Performance notes (fork avoidance)

- `thumbnail_filter_pending` drops media whose thumbnail, viewer images, and
  required web video already exist before `xargs` starts workers, so unchanged
  files cost no bash process. `thumbnail_process_item` still re-checks.
- `gallery_preload_metadata` reads every metadata JSON of an album with one
  `jq` run per 500 files (`gallery_metadata_values_batch`, NUL-delimited
  records) and fills the metadata cache. `gallery_read_metadata` falls back to
  one `jq` per file only for files that were not preloaded. The jq field
  definitions are shared in `gallery_metadata_jq_values`.
- `gallery_preload_file_versions` caches thumbnail mtimes for an album with a
  single `find -printf`; `gallery_file_version_to` falls back to `stat`.
- Hot-path string helpers have forkless `*_to VARNAME value` variants
  (`gallery_js_escape_to`, `gallery_url_escape_path_to`,
  `gallery_thumbnail_url_to`); the printing versions wrap them. Do not use
  `$(...)` around these inside per-image loops. Avoid names `result`, `value`,
  `escaped`, `version` for variables passed as the target name.
- Templates are read once and cached in `gallery_template_cache`.
- Global caches use `declare -gA` so they stay global when the libraries are
  sourced inside a function (as the BATS `setup` does).
- Measured on 300 small photos: gallery generation 15.7s -> 1.3s, output
  byte-identical (besides the output directory name). Verify performance
  changes by diffing generated output against the previous version.

## Gallery generation architecture

- `lib/gallery/generate.sh` validates configuration, invokes the gallery
  generator, updates Caddy configuration, and reloads Caddy.
- `lib/gallery/generator.sh` builds the index, fragments, album URLs, preview
  URLs, and fragment reuse checks.
- `lib/gallery/albums.sh` renders album summaries and the current album's own
  media gallery.
- `lib/gallery/media.sh` renders the NanoGallery item JSON and caches metadata
  values during generation.
- `lib/gallery/core.sh` provides media discovery, URL escaping, metadata date
  lookup, and common helpers.

Index generation inserts the accumulated album JSON by concatenating the
template prefix and suffix around `__ALBUM_LIST__`. Do not use Bash pattern
replacement for this insertion: `&` in an album name has special replacement
semantics and can reinsert the marker into the generated index.

All album, media, and thumbnail URL path components must pass through
`gallery_url_escape_path`; this includes encoding ampersands as `%26` so nested
album preview URLs remain valid in HTML attributes, JavaScript, and Caddy
requests.

Caddy template markers are inserted by literal prefix/suffix concatenation.
This is required for guest album paths and other configured values containing
`&`, which must not cause a neighboring marker to be reinserted.

Each gallery generation removes stale `.html` fragments whose corresponding
album directory no longer exists, then removes empty fragment directories.
The index and current fragments are generated afterward.

Generated fragments are intentionally shallow: a fragment contains the
current album's own image gallery and immediate child album summaries. Child
summaries carry a fragment URL and load their contents only when opened in the
browser. This prevents opening a parent such as `SAP` or `Държави` from loading
all descendant image galleries.

The child templates are:

- `templates/gallery/album-lazy-parent.html`
- `templates/gallery/album-lazy-parent-preview.html`
- `templates/gallery/album-lazy-leaf.html`
- `templates/gallery/album-lazy-leaf-preview.html`

The browser logic is embedded in `templates/index.html.template`. Album cover
images use `data-src` and are activated only for visible/immediate albums.
NanoGallery scripts are initialized only when their containing album opens.

Gallery thumbnail dimensions use NanoGallery 3.0.5's native responsive syntax:
`SIZE XS120 SM180`, capped by `THUMBNAIL_SIZE` if it is smaller. XS applies
below 480px viewport width; SM applies from 480px to below 992px. Desktop
uses the configured size. Cascading keeps height `auto`; justified keeps
width `auto`. NanoGallery handles relayout on viewport resizing. Generated
thumbnail and metadata formats are unchanged. Below 992px, nested albums
have no cumulative indentation; phones also use smaller page padding and
summary text. Long album titles wrap without pushing the gallery offscreen.
Regenerate both galleries to apply these settings; fragment version 11
invalidates the previous fixed-size fragments.

Responsive options are documented at
https://nanogallery2.nanostudio.org/documentation.html#ngy2_gallery_thumbnails_resp.

## Progressive publication

`generate_gallery()` writes a valid empty index skeleton before scanning all
albums. It atomically rewrites `index.html` after each top-level album is
prepared. Parent album entries are published before their descendant fragments
finish, so an already configured Caddy can serve the partial gallery during a
long run. Individual fragments are written to temporary files and moved into
place atomically.

Because parent entries can appear before child fragments finish, a newly
published child link may briefly return 404 until that fragment is generated.

## Fragment invalidation

Each fragment begins with internal comments like:

```html
<!-- photina-fragment-version: 13 -->
<!-- photina-media-manifest: CHECKSUM:SIZE -->
<!-- photina-children: CHECKSUM:SIZE -->
```

`gallery_fragment_version` in `lib/gallery/generator.sh` must be incremented
when fragment structure or lazy-loading markup changes. Fragments are reused
only when the version matches, the manifest checksum matches the current
`md5sums.txt`, and the `photina-children` checksum (of the visible immediate
child album names, `gallery_children_signature`) matches. The last check exists
because a fragment embeds its child summaries: a new sub-album under an album
whose own media did not change (e.g. `Семейство/Мая/45. ...`) was otherwise
missing from the reused parent fragment. Run `update-thumbnails.sh` first so the manifest and metadata
are current.

The manifest marker is an internal HTML comment; it does not change metadata,
thumbnail, or generated NanoGallery item formats.

## Album previews

An explicit `album.jpg` directly inside an album has priority when the album's
content is allowed. If it is absent or the album's content is not permitted (such
as in guest mode when only sub-albums are granted), preview resolution recurses
through visible child albums in sorted order to pick the first accessible child
preview. `cover.jpg` is not special. Preview URLs point to generated thumbnail
files and may initially have a zero timestamp if thumbnail generation has not
completed yet.

## Performance considerations

Gallery generation is mostly filesystem and shell/process overhead. Thumbnail
generation is separate and is CPU-intensive due to ImageMagick/FFmpeg.

Thumbnail updates collect one sorted NUL-delimited media list per album and
reuse it for thumbnail generation, metadata extraction, checksum handling, and
missing-thumbnail checks. Media whose thumbnail and viewer images all exist are skipped, and
metadata extraction is limited to files without an existing metadata record.

Current gallery-generation optimizations include:

- Shallow fragments and browser-side child loading.
- Metadata parsed once per image during a generation pass and reused for date
  sorting and EXIF rendering.
- Per-fragment `md5sums.txt` manifest checks instead of a per-image fingerprint
  scan.
- Atomic progressive index and fragment publication.
- Parallel nested fragment generation, capped at `min(5, available CPU cores)`.
- Deterministic path-derived gallery IDs so parallel workers cannot collide.
- Unchanged album fragments are reused when their version and media manifest
  markers still match.

Do not change metadata or thumbnail formats when optimizing gallery generation.
Sibling albums are ordered alphabetically by their complete names. Names that
begin with a year/date pattern such as `2007_03_17 - Album`,
`2007_06_22,23,24 - Team building`, `2026-08-01 - Trip`, or `2024` are
grouped as date-based albums and sorted newest first. The first complete date
is used for ranges and comma-separated day lists;
ordinary names are sorted ascending. Top-level album ordering remains
deterministic. Parent entries are published
before their descendant fragments; an album with both direct images and child
albums publishes after its own fragment is ready, then generates child
fragments.

Progress output uses one newline-terminated message per fragment. Do not add
per-image dots because parallel workers would garble the output. The separate
`check-missing-thumbnails.sh` command prints `Checking for missing thumbnails
...` before listing any missing outputs.
Reused gallery fragments do not print an additional `skipped` line.
