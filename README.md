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

The gallery generators keep existing gallery fragments and generate only
missing ones.

Thumbnail updates can be interrupted and resumed. Existing thumbnails are
reused, obsolete thumbnails are removed, and new thumbnails are generated in
parallel.

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
generated thumbnails, medium images, and metadata, run:

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
album’s folder. It is converted to a thumbnail and used instead of the first 
media item; nested albums fall back to their first available media when no 
cover is present.
