# Photina project notes

## Maintenance requirement

After every code or behavior change, update this `AGENTS.md` in the same
change. Record any new commands, architectural behavior, invariants,
performance decisions, compatibility requirements, and validation steps. Keep
the document consistent with the actual implementation before completing the
task.

## Purpose

Photina is a Bash-based static photo/video gallery generator. Source media is
stored under `ALBUMS_DIR`; generated thumbnails and metadata are stored in
`THUMBNAILS_DIR` and `METADATA_DIR`; gallery HTML is written under
`OUTPUT_DIR/admin` and `OUTPUT_DIR/guest`.

## Main commands

- `./update-thumbnails.sh` generates/reuses thumbnails, medium images, web
  video previews, EXIF metadata, and `md5sums.txt` manifests. It also removes
  stale thumbnail/metadata files and empty thumbnail/metadata directories for
  deleted albums.
- `./check-missing-thumbnails.sh` independently checks and lists missing
  thumbnail, medium, and web-video outputs. It exits with status 1 if any are
  missing; it does not modify the thumbnail tree.
- `./cleanup-thumbnails-and-metadata.sh` removes thumbnail files and empty thumbnail
  directories that no longer correspond to albums or media files. It does not
  modify album content, removes redundant metadata files and empty metadata
  directories, and prints one progress line for each album it processes.
  Cleanup output identifies whether each stale thumbnail is from a missing
  original album or image for files. The thumbnail and metadata cache directories contain
  generated content only, so stale-thumbnail cleanup compares every file under
  the thumbnail cache, regardless of filename extension, and reports progress
  for file and directory cleanup phases.
  Expected thumbnail paths are built by a shared helper used by the update,
  cleanup, and missing-thumbnail-check scripts.
- `./generate-admin-gallery.sh` generates the admin gallery.
- `./generate-guest-gallery.sh` generates the guest gallery using `GUEST_ALBUMS`.
- `./delete-admin-gallery.sh` and `./delete-guest-gallery.sh` delete only the
  corresponding generated output directory.
- `./delete-all-thumbnails-and-metadata.sh` deletes thumbnail and metadata
  caches; `./delete-album-thumbnails-and-metadata.sh ALBUM` deletes one album's
  caches.
- `./fix-flickr-names.sh FLICKR_DIR MEDIA_DIR_OR_XML` renames readable Flickr
  files to the names of unreadable target files. The second argument may be a
  media directory or a WhereIsIt XML export. XML mode reads target names,
  sizes, and camera/digitized dates from the report and never opens the
  referenced media files. An embedded EXIF original/preserved
  filename metadata takes priority; otherwise it first uses a unique filesize
  match. The filename metadata lookup uses `OriginalFileName` and
  `PreservedFileName`, never the source filesystem `FileName`. Only regular
  files directly inside `MEDIA_DIR` are target candidates; its subdirectories
  are ignored.
  If that is unavailable, it first checks an unambiguous timestamp encoded in
  target names matching `YYYYMMDD_HHMMSS` (for example,
  `IMG_20140418_113534.jpg`), then uses filesize. If the size is unavailable,
  non-unique, or does not identify a target, it compares the source EXIF
  `DateTimeOriginal`, `CreateDate`, and `ModifyDate` values with target
  filesystem modification and creation times. Filename timestamps are also
  considered during this date fallback. An exact filename timestamp is always
  preferred over a filename timestamp that differs by one second.
  If those EXIF dates are absent, `GPSDateStamp` is used as a date-only
  fallback against the target file calendar dates.
  It skips ambiguous matches and reports them as unmatched or collisions.
  Successful rename output identifies whether the match used EXIF filename,
  filename date, size, or created/modified date. Files that cannot be renamed are collected
  and printed together at the end, with the closest target by byte-size
  difference and timestamp difference. A target is consumed after a successful
  rename and is excluded from all later matching and closest-match listings.
  Date-time matches allow a difference of up to one epoch second; date-only
  GPS fallback matches remain calendar-date exact.
- `./compare-dirs.sh DIRECTORY1 DIRECTORY2` compares the filenames of regular
  files directly inside two directories and reports files missing from either
  side.

The normal update sequence is:

```bash
./update-thumbnails.sh
./generate-admin-gallery.sh
./generate-guest-gallery.sh
```

Run `update-thumbnails.sh` before gallery generation. Gallery regeneration uses
the per-album `METADATA_DIR/<album>/md5sums.txt` manifest to detect added,
removed, or changed media.

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
<!-- photina-fragment-version: 8 -->
<!-- photina-media-manifest: CHECKSUM:SIZE -->
```

`gallery_fragment_version` in `lib/gallery/generator.sh` must be incremented
when fragment structure or lazy-loading markup changes. Fragments are reused
only when the version matches, the manifest checksum matches the current
`md5sums.txt`. Run `update-thumbnails.sh` first so the manifest and metadata
are current.

The manifest marker is an internal HTML comment; it does not change metadata,
thumbnail, or generated NanoGallery item formats.

## Album previews

An explicit `album.jpg` directly inside an album has priority. If it is absent,
the first available media item is used as a fallback preview. `cover.jpg` is
not special. Preview URLs point to generated thumbnail files and may initially
have a zero timestamp if thumbnail generation has not completed yet.

## Performance considerations

Gallery generation is mostly filesystem and shell/process overhead. Thumbnail
generation is separate and is CPU-intensive due to ImageMagick/FFmpeg.

Thumbnail updates collect one sorted NUL-delimited media list per album and
reuse it for thumbnail generation, metadata extraction, checksum handling, and
missing-thumbnail checks. Complete thumbnail/medium pairs are skipped, and
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
Sibling albums are ordered by their complete names in descending byte order,
so a dated name such as `2007_03_17 - Album` sorts before `2004`. Top-level
album ordering remains deterministic. Parent entries are published
before their descendant fragments; an album with both direct images and child
albums publishes after its own fragment is ready, then generates child
fragments.

Progress output uses one newline-terminated message per fragment. Do not add
per-image dots because parallel workers would garble the output. The separate
`check-missing-thumbnails.sh` command prints `Checking for missing thumbnails
...` before listing any missing outputs.
Reused gallery fragments do not print an additional `skipped` line.

## Validation

Useful checks:

```bash
bash -n ./*.sh lib/*.sh lib/gallery/*.sh
git diff --check
```

`fix-flickr-names.sh` requires GNU `find`, `awk`, `exiftool`, `jq`, and
`python3`; its date
 fallback uses epoch-second comparisons with a one-second tolerance and treats
 either target mtime or birth time as a match. Date-only GPS fallback remains
 exact. Target files are indexed in one `find` traversal for names,
byte sizes, modification times, and creation times. The Flickr traversal reads
  embedded EXIF filename/date fields and never uses Flickr source filesystem
  dates. The Flickr source scan is also limited to regular files directly
  inside `FLICKR_DIR`; source subdirectories are ignored. No content or EXIF
  is read from target files; only the initial `find` metadata scan is performed
  for `MEDIA_DIR`.
Matching uses in-memory Bash associative indexes for target sizes, timestamp
buckets, and exact calendar dates, so normal size/date matching does not scan
the complete target list for every Flickr file. Date indexes are built lazily
only when date fallback is first needed, and duplicate-size lists are built
only for sizes that actually repeat. The diagnostic fallback still scans
unused targets only when a file cannot be renamed. The one-second timestamp
buckets preserve the date matching tolerance without changing rename
behavior; filename timestamps use the same one-second tolerance and GPS-only
dates use exact calendar-date matching. Flickr metadata is read in one
ExifTool JSON batch, parsed by `jq`, and retained as an in-memory Bash record
array before matching starts. The script logs indexing, batch completion,
every 100 processed source files, and final counts. These progress messages
are indented by three spaces beneath the main phase headings.
During matching, files needing failure diagnostics print a queueing message.
After matching, one `awk` pass calculates closest size/time matches for all
queued failures, avoiding a separate full Bash target scan and repeated date
subprocesses for every failed file. The batch diagnostic phase prints its own
start and completion messages.
Closest-match diagnostics receive and honor each target's consumed flag, so
they never report a target that was already used by an earlier successful
rename.
A filename-date match is also attempted across all targets when a shared file
size has no matching date, allowing the filename timestamp to resolve a target
whose size differs from the Flickr copy.
A unique size match remains sufficient and does not require matching dates.

Target-record source selection is implemented in `lib/fix/target-input.sh`;
WhereIsIt XML parsing is implemented in `lib/fix/parse-whereisit-xml.py`; and
the closest-match AWK program is maintained in `lib/fix/closest-matches.awk`.

The inline JavaScript can be extracted from `templates/index.html.template`
and checked with `node --check`. Focused tests should generate temporary
three-level album trees and verify that fragments contain only immediate child
summaries, have balanced `<details>` tags, and that adding a media file changes
the manifest and regenerates the fragment.
