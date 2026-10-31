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

## Project layout

```text
*.sh                      user-facing commands (listed under Main commands)
lib/common.sh             shared die/warn/config/core-count/video helpers
lib/thumbnails.sh         thumbnail, medium, web-video, metadata, checksum, cleanup
lib/caddy.sh              generate_caddyfile: merges the managed Caddy block
lib/gallery/              gallery generator (main, core, media, albums, generator,
                          generate = CLI entry for admin|guest, delete)
templates/                index.html.template (browser logic), Caddyfile.template,
                          photina.conf.template, gallery/*.html printf fragments
assets/favicon.png        copied into each generated gallery
tests/                    BATS suites: gallery, scripts
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

## Main commands

- `./update-thumbnails.sh` generates/reuses thumbnails, medium images, web
  video previews, EXIF metadata, and `md5sums.txt` manifests. It also removes
  stale thumbnail/metadata files and empty thumbnail/metadata directories for
  deleted albums.
  Before processing it warns (does not fail) when the `nls_utf8` kernel module
  is neither loaded, built in, nor loadable via `modprobe -n`. CIFS mounts
  with `iocharset=utf8` (as on the production Storage Box mount) fail to
  mount without it, and vfat/exfat/ntfs need it for non-ASCII names.
  `thumbnail_make` never feeds unreadable media to ImageMagick or `mv`: a
  video frame comes from `ffmpegthumbnailer`, falling back to `ffmpeg`; if
  no non-empty frame or no non-empty thumbnail/medium results, it prints a
  `skipping unreadable ...` warning, removes temp files and returns 0 so the
  batch continues (the file stays pending and is retried next run). A failed
  web-video conversion only warns; thumbnails are still published. `warn` is
  exported to the `xargs` workers for this.
  Stale cleanup is automatic but never trusts the album scan alone, because
  a flaky CIFS mount once returned incomplete listings and a run deleted a
  large part of the cache. A thumbnail not in the scanned set is removed only
  when its original is verified missing on disk: `thumbnail_original_relative`
  strips `.web.mp4`, `_medium.webp`, or `.webp` (thumbnails are named
  `<original name>.webp`, e.g. `IMG_1.JPG.webp`; originals are rarely `.webp`
  themselves, though `pic.webp` -> `pic.webp.webp` also works). If the
  original exists, the file is kept and counted in a "Kept N ..." line.
  Metadata `.json` files get the same check. Cleanup is skipped entirely when
  any album failed to scan or update (the skip message lists each failed
  album with the failed stage as the reason: thumbnail generation, EXIF
  metadata extraction, or md5 checksums, set by `thumbnail_update_album` in
  the global `THUMBNAIL_FAILURE_REASON`; details are in the warnings above it), and refused when the albums directory is empty
  (`thumbnail_albums_dir_is_populated`, e.g. an unmounted share). There is no
  override flag and no percentage limit. Do not remove these checks.
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
- `./install-dependencies.sh` installs the dependencies and the Caddy
  package repository on Ubuntu only, and installs the default
  `/etc/photina/photina.conf` (mode 600) if none exists.
  On `-generic` kernels it also installs `linux-image-generic`, which depends
  on `linux-modules-extra-<version>`, so every kernel upgrade keeps the
  `nls_utf8` module (the minimal `linux-image-virtual` does not). It then
  tries `modprobe nls_utf8`; if that fails (typically because a newer kernel
  was just installed) it stops with an error asking for a reboot and a rerun,
  before Caddy and the config are installed.
  It finally appends `set -g mouse on` to `~/.tmux.conf` (created if missing)
  unless a `set -g mouse on` line already exists, so reruns stay idempotent.
- `./update-caddy.sh` regenerates Photina's managed Caddy block (from
  `templates/Caddyfile.template`, via `lib/caddy.sh`) and reloads Caddy
  without regenerating galleries. Gallery generation also does this.
- `./check-duplicates.sh` reads all `METADATA_DIR/**/md5sums.txt` manifests
  and lists files sharing an MD5; exits 1 if duplicates exist. It never
  modifies files.
- `./eliminate-duplicates.sh` finds the same duplicates and replaces the
  duplicate files' generated thumbnails, medium images, and metadata with
  hard links to the first copy's; the album sources are not changed.
- `./split-by-year.sh DIRECTORY` moves images directly inside DIRECTORY into
  `YYYY` subdirectories using EXIF `DateTimeOriginal`, `CreateDate`, or
  `CreationDate`; images without a usable date stay in place with a warning.
  It requires only `exiftool` and `find`, not the Photina config. It uses
  `mv -f`, so an existing file of the same name in the year directory is
  overwritten.
- `./fix-names.sh [-n|--dry-run] DIRECTORY` makes names SMB-safe. It renames
  files and directories below DIRECTORY whose names end with spaces or dots,
  deepest entries first (`find -depth`) so parent renames never invalidate
  pending paths. DIRECTORY itself is not renamed. Names that would become
  empty or collide with an existing entry are skipped with a warning. It also
  reports (never renames) names containing characters SMB cannot store:
  `\ : * ? " < > |`, control characters, and the private-use characters
  U+F020-U+F029 (UTF-8 `EF 80 A0-A9`) that Linux CIFS with `mapposix` shows in
  their place. `find` prefilters candidates with `-name` patterns in a single
  traversal; bash classifies them with `has_forbidden_character`, so keep the
  two lists in sync. Names are checked after trimming. It first deletes empty (0 byte) regular files
  (symlinks are never touched; `--dry-run` only reports them; a separate
  `find -type f -empty` pass runs before the rename scan and does not affect
  the exit status). Test fixtures must therefore have content. It also
  shortens names longer than
  `--max-length N` characters (default 100, minimum 8) by replacing the middle
  of the stem with `…` (U+2026); a short file extension is kept (not for
  directories) and the result stays within 255 bytes (`shorten_name`). The
  script forces `LC_ALL=C.UTF-8` so lengths and slicing count characters; the
  `find` prefilter uses a `-regex` on basename length. Shortened-name
  collisions are skipped like other collisions. Exit status is 1 when
  anything was skipped or forbidden. It never overwrites and does not read the
  Photina config. Names the SMB server cannot represent (trailing space or
  dot, illegal characters) are exposed by a CIFS mount only as Samba-mangled
  aliases such as `2KT24Y~W`, which cannot be opened; the real name never
  reaches the client, so it cannot be shown or renamed through that mount.
  The script reports such entries as `mangled:` (pattern
  `XXXXXX~Y[.ext]` with `[A-Z0-9]`, and only if the path is not accessible, so
  a legitimate lookalike is not flagged) and exits 1. To actually rename
  them, run the script against an FTP/SFTP view (for example the gvfs mount
  of the Storage Box) or the server's own filesystem, where the real names
  are visible. Rerun `update-thumbnails.sh` afterwards, since renamed media
  get new thumbnails and the old ones become stale.
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

## Locking

`photina_acquire_lock KIND TARGET` (in `lib/common.sh`) takes a non-blocking
`flock` on fd 9 for the life of the script and writes the holder's PID and
script name into the lock file. Two kinds exist:

- `cache` (`photina_acquire_cache_lock THUMBNAILS_DIR`): `update-thumbnails.sh`,
  `cleanup-thumbnails-and-metadata.sh`, `delete-all-...` and `delete-album-...`
  so they never run concurrently on the same cache (two `update-thumbnails.sh`
  runs were once seen at the same time on the server).
- `gallery` (`photina_acquire_gallery_lock OUTPUT_DIR`): gallery generation
  (`lib/gallery/generate.sh`, so admin, guest, and the shared Caddyfile are
  serialized), `delete-*-gallery.sh` (`lib/gallery/delete.sh`), and
  `update-caddy.sh`.

Lock files are `${TMPDIR:-/tmp}/photina-<kind>-<cksum of the directory>.lock`,
outside the protected directories so cleanup and deletion never see them.
Requires `flock` (util-linux). A second job prints a warning with the lock
file path and holder, and the command `rm -- '<lock file>'` to override it
manually when no job is really running, then exits with `another Photina job
is already using the <kind> ...`. flock locks vanish when the holder exits, so
a leftover file never blocks by itself; deleting the file while a job runs
lets a second job start. Tests set `TMPDIR` to keep locks isolated.

## Shared library layout

- `lib/common.sh` holds `die`, `warn`, `photina_load_config` (sources the
  config file and warns if it is not private), `photina_core_count`, and the
  video helpers `photina_is_video` / `photina_needs_web_video`. Command scripts
  source it before loading the config; `lib/thumbnails.sh` and
  `lib/gallery/core.sh` source it themselves. Every config-reading command
  uses `photina_load_config`; only `split-by-year.sh` and
  `install-dependencies.sh` (no Photina config) keep a local `die`. Do not reintroduce per-script or
  per-library copies of these helpers.
- `lib/thumbnails.sh` exposes `thumbnail_list_media` (sorted images+videos for
  one album), `thumbnail_media_source` (precomputed list or fresh scan),
  `thumbnail_list_albums` (every album directory under each top-level album),
  and `thumbnail_update_album` (thumbnails, metadata, checksums for one album).
  The update, cleanup, and missing-check scripts all reuse them.
  `thumbnail_make` builds one ImageMagick command for images and video frames;
  only the input (`-auto-orient` for images) and medium quality differ.
  Relative-path expansion stays inline (`${source#"$album_path"}`) because a
  command substitution per file would fork in hot loops.

## Performance notes (fork avoidance)

- `thumbnail_filter_pending` drops media whose thumbnail, medium image, and
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
<!-- photina-fragment-version: 11 -->
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

## Validation

Shellcheck (0.11) is clean. Suppressions are limited to namerefs (arrays
passed by name), globals shared between sourced libraries, and the jq program
string; each carries a reason comment. Keep new code warning-free rather than
adding blanket disables.

Useful checks:

```bash
bash -n ./*.sh lib/*.sh lib/gallery/*.sh
shellcheck -x -P SCRIPTDIR ./*.sh lib/*.sh lib/gallery/*.sh
git diff --check
bats tests
```

The index writer should be tested with an album title containing `&`; the
generated index must contain the literal ampersand and no `__ALBUM_LIST__`
marker. A parent whose preview comes from an `&` sub-album should produce a
thumbnail URL containing `%26`.

The BATS suite is self-contained: each test uses a temporary directory and
does not modify configured gallery data. It covers gallery URL/index helpers,
shallow multi-level fragments, manifest checksum invalidation, template
JavaScript validation, missing-thumbnail checks, direct-directory comparison,
selected and all cache deletion, admin and guest gallery deletion, guest parent
preview resolution with restricted permissions, duplicate detection and
elimination, EXIF year splitting, and `fix-names.sh` (trailing space/dot trimming,
forbidden/mangled names, long-name shortening, empty-file deletion).

The inline JavaScript can be extracted from `templates/index.html.template`
and checked with `node --check`. Focused tests should generate temporary
three-level album trees and verify that fragments contain only immediate child
summaries, have balanced `<details>` tags, and that adding a media file changes
the manifest and regenerates the fragment. Album-order tests should include
ordinary names and `YYYY`, `YYYY-MM-DD`, and `YYYY_MM_DD` names, verifying that
date-based names are newest-first and ordinary names are ascending.

Responsive layout validation should open a three-level album with portrait
and landscape photos at 320px, 390px, 768px, and 1280px viewport widths.
Check multiple thumbnail columns for cascading/grid layouts, all media being
reachable, no horizontal page overflow, resize/orientation relayout, and
closing/reopening albums. Check justified layout and smaller custom thumbnail
sizes as well. Run `bats tests` and extract generated inline scripts for
`node --check` after changing gallery options.

The responsive change was checked in Chromium using a temporary generated
three-level album with 12 alternating landscape/portrait photos. Cascading
showed 2 columns at 320px, 3 at 390px, 4 at 768px, and 4 at 1280px, with no
horizontal overflow. Resizing back to 320px restored 2 columns. Reopening
and scrolling loaded all 12 photos, and a long unbroken title stayed within
the viewport. Grid and justified layouts also fit at 320px; a custom 90px
size remained 90px and produced 3 cascading columns. The 30 BATS tests, Bash syntax checks, generated JavaScript
syntax checks, and `git diff --check` passed.
