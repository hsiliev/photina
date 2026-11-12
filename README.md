# Photina

Photina creates a browsable photo and video gallery from folders of media.
Albums can contain nested albums.

Directory-first, [nanogallery](https://nanogallery2.nanostudio.org/) based, static-site generator. Supports images, videos, EXIF metadata, album sharing.

Photina can be co-hosted with other projects like [Hermes](https://github.com/hsiliev/hermes), or run independently.

## Configure

On Ubuntu, install the required tools with:

```bash
./install-dependencies.sh
```

The installer creates `/etc/photina/photina.conf` from
`templates/photina.conf.template` if that file does not already exist. Edit
`/etc/photina/photina.conf` and set the
folders, Caddy address, and passwords. The example configuration uses:

```bash
ALBUMS_DIR=/mnt/gallery/albums
OUTPUT_DIR=/mnt/gallery/dist
THUMBNAILS_DIR=/mnt/gallery/thumbnails
METADATA_DIR=/mnt/gallery/metadata
MEDIUM_SIZE=1600
```

Image and video extensions can also be adjusted in
`/etc/photina/photina.conf`. `HOST` and `PORT` default to `localhost` and `443`;
set them in the configuration to override those defaults.

Keep the passwords in `/etc/photina/photina.conf` private.

To limit guest access, add album paths to `GUEST_ALBUMS`. Nested album paths
are supported, for example:

```bash
GUEST_ALBUMS=(
  "Greece/2026-08-01 - Σπήλαιο Πετραλώνων"
)
```

## Admin and guest galleries

Photina generates two independent gallery outputs:

- Admin: `OUTPUT_DIR/admin`, available at `/admin/`
- Guest: `OUTPUT_DIR/guest`, available at `/guest/`

Opening the site root redirects an authenticated admin to `/admin/` and an
authenticated guest to `/guest/`. Guests only see the albums listed in
`GUEST_ALBUMS` in `/etc/photina/photina.conf`; nested paths are supported:

```bash
GUEST_ALBUMS=(
  "Greece/Θεσσαλονίκη"
  "Sadovetz"
)

```

Regenerate one output independently when needed:

```bash
./generate-admin-gallery.sh
./generate-guest-gallery.sh
```

The gallery generators reuse existing gallery fragments when their generated
metadata is present, and recreate fragments whose metadata is missing.
They publish a valid index skeleton before scanning albums and update it after
each top-level album, so an already configured Caddy can serve the gallery
while generation continues.

Thumbnail updates can be interrupted and resumed. Existing thumbnails are
reused, obsolete thumbnails are removed, and new thumbnails are generated in
parallel.

Besides the gallery thumbnail (`<name>.webp`), each image gets one viewer
image per screen size, chosen by the browser from the viewport width when an
album opens: `<name>_xs.webp` (800px wide, viewports under 480px),
`_sm.webp` (1280px, under 992px), `_me.webp` (`MEDIUM_SIZE`, default 1600px,
under 1200px), and `_la.webp` (2400px, under 1800px). Wider screens use the
original file when it is a format every browser can show (JPEG, PNG, GIF,
WebP, AVIF, BMP); otherwise (TIFF, HEIC, ...) a full-size `_xl.webp` is
generated. Downloads always give the original. Videos only get a thumbnail
and a `_me.webp` frame. Existing photos get the new sizes on the next update.

To see how much disk space each kind of generated image uses, run:

```bash
./du-thumbnails.sh
```

It prints the file count and disk usage for the grid thumbnails, each viewer
size (`xs`, `sm`, `me`, `la`, `xl`), and web videos, plus a total. Add
`--list` to list every file with its size first.

## Update the gallery

When media is added or removed, run both gallery generators:

```bash
./update-thumbnails.sh
./generate-admin-gallery.sh
./generate-guest-gallery.sh
```

To generate only one gallery, use:

```bash
./generate-admin-gallery.sh
./generate-guest-gallery.sh
```

To update only the managed Caddy configuration, without regenerating gallery
output:

```bash
./update-caddy.sh
```


## Recreate generated data

Check `/etc/photina/photina.conf` before deleting anything and make sure the configured
paths contain generated data only.

To recreate all thumbnails and metadata, delete the configured thumbnail and metadata directories before updating:

```bash
./delete-all-thumbnails-and-metadata.sh
./update-thumbnails.sh
```

To recreate one album, delete its matching generated subdirectories instead:

```bash
./delete-album-thumbnails-and-metadata.sh ALBUM_NAME
./update-thumbnails.sh
```

To recreate only one gallery:

```bash
./delete-admin-gallery.sh
./generate-admin-gallery.sh

./delete-guest-gallery.sh
./generate-guest-gallery.sh
```

## Duplicate management

Thumbnail updates create an `md5sums.txt` manifest for each album under the
configured metadata directory. The manifests contain checksums for the
album's images and videos, using paths relative to that album.

To check all manifests for duplicate files, run:

```bash
./check-duplicates.sh
```

The command exits with status 1 when duplicates are found.

To replace duplicate media with hard links to the first file and link their
generated thumbnails, viewer images, and metadata, run:

```bash
./eliminate-duplicates.sh
```

The source and destination paths must be on the same filesystem.

## Organizing images

To organize images in an album into year directories using their EXIF dates,
run:

```bash
./split-by-year.sh /mnt/gallery/album/Flowers
```

The script reads `DateTimeOriginal` first, then creation-date EXIF tags. It
processes images directly inside the supplied directory, leaves images without
a usable year in place, and overwrites same-named files already in a year
directory.

## Stale cache cleanup

`update-thumbnails.sh` and `cleanup-thumbnails-and-metadata.sh` remove cache
files that no longer match an album. A cache file is removed only after
checking that its original file (for example `IMG_1.JPG` for
`IMG_1.JPG.webp`) is really missing, so an incomplete listing of a network
mount cannot delete the cache of existing photos. Cleanup is skipped when an
album failed to scan or the albums directory is empty.

## Fixing names for SMB shares

To strip trailing spaces and dots from file and directory names below a
directory and list names SMB cannot store, run:

```bash
./fix-names.sh --dry-run /mnt/gallery/albums   # preview
./fix-names.sh /mnt/gallery/albums
```

Nothing is overwritten: names that would collide with an existing entry, or
that consist only of spaces and dots, are reported and skipped. Names with
characters SMB cannot hold (`\ : * ? " < > |` and control characters) are
listed as `forbidden` but not renamed. The exit status is 1 if anything was
skipped, forbidden or mangled. A name the server cannot represent (for
example one ending in a space) appears on an SMB mount only as an unopenable
alias such as `2KT24Y~W`. The script lists these as `mangled`, but the real
name is invisible through that mount: run `fix-names.sh` against an FTP/SFTP
view of the same directory, or on the server's own filesystem, to rename
them. Run `./update-thumbnails.sh` afterwards so renamed media get new
thumbnails.

## Gallery behaviour

The gallery starts with the album list. Select an album to view its media;
nested folders appear as nested albums. 
Images within an album are sorted from oldest to newest using their
`DateTimeOriginal` EXIF value. Images without a usable date appear last.

Album fragments are fetched only when an album is expanded. Gallery sections
also use browser content virtualization and lazy thumbnail loading so closed
or off-screen sections do not need to be rendered immediately.

Caddy compresses gallery responses with Zstandard or gzip. Gallery HTML is
always revalidated, while thumbnails and static assets use long-lived caching.
Thumbnail URLs include a file timestamp query parameter so regenerated
thumbnails receive a new cache key safely.

### Album thumbnails
To choose an album preview, place an image named `album.jpg` directly in that 
album’s folder. It is converted to a thumbnail and used as the album preview.
When no `album.jpg` exists, the first available image is used as a fallback.
