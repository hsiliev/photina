# Commands and locking

Reference for every user-facing command and the lock protocol. Part of
the project notes in [AGENTS.md](../AGENTS.md); keep both in sync.

## Main commands

- `./update-thumbnails.sh` generates/reuses thumbnails, viewer images (see
  "Viewer image variants"), web video previews, EXIF metadata, and
  `md5sums.txt` manifests. It also removes
  stale thumbnail/metadata files and empty thumbnail/metadata directories for
  deleted albums.
  Before processing it warns (does not fail) when the `nls_utf8` kernel module
  is neither loaded, built in, nor loadable via `modprobe -n`. CIFS mounts
  with `iocharset=utf8` (as on the production Storage Box mount) fail to
  mount without it, and vfat/exfat/ntfs need it for non-ASCII names.
  `thumbnail_make` never feeds unreadable media to ImageMagick or `mv`: a
  video frame comes from `ffmpegthumbnailer`, falling back to `ffmpeg`; if
  no non-empty frame or any missing/empty thumbnail or viewer image, it prints a
  `skipping unreadable ...` warning, removes temp files and returns 0 so the
  batch continues (the file stays pending and is retried next run). A failed
  web-video conversion only warns; thumbnails are still published. `warn` is
  exported to the `xargs` workers for this.
  Stale cleanup is automatic but never trusts the album scan alone, because
  a flaky CIFS mount once returned incomplete listings and a run deleted a
  large part of the cache. A thumbnail not in the scanned set is removed only
  when its original is verified missing on disk: `thumbnail_original_relative`
  strips `.web.mp4`, `_me|_xs|_sm|_la|_xl|_medium.webp`, or `.webp`
  (thumbnails are named
  `<original name>.webp`, e.g. `IMG_1.JPG.webp`; originals are rarely `.webp`
  themselves, though `pic.webp` -> `pic.webp.webp` also works). If the
  original exists, the file is kept and counted in a "Kept N ..." line.
  The stale-cleanup phase messages ("Checking for stale ...", "Removing ...",
  "Kept ...") are printed at the first level (no tab indent), unlike the
  per-album lines, which are indented under "Scanning album:".
  Metadata `.json` files get the same check. Cleanup is skipped entirely when
  any album failed to scan or update (the skip message lists each failed
  album with the failed stage as the reason: thumbnail generation, EXIF
  metadata extraction, or md5 checksums, set by `thumbnail_update_album` in
  the global `THUMBNAIL_FAILURE_REASON`; details are in the warnings above it), and refused when the albums directory is empty
  (`thumbnail_albums_dir_is_populated`, e.g. an unmounted share). There is no
  override flag and no percentage limit. Do not remove these checks.
- `./check-missing-thumbnails.sh` independently checks and lists missing
  thumbnail, viewer-image, and web-video outputs. It exits with status 1 if any are
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
  duplicate files' generated thumbnails, viewer images (`_me` always; `_xs`,
  `_sm`, `_la`, `_xl` when the first copy has them), and metadata with
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
