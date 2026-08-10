# Photina

Photina creates a browsable photo and video gallery from folders of media.
Albums can contain nested albums.

## Configure

On Ubuntu, install the required tools with:

```bash
./install-dependencies.sh
```

Edit `photina.conf` and set the folders, Caddy address, and passwords. The
example configuration uses:

```bash
ALBUMS_DIR=/mnt/gallery/albums
OUTPUT_DIR=/mnt/gallery/dist
THUMBNAILS_DIR=/mnt/gallery/thumbnails
METADATA_DIR=/mnt/gallery/metadata
MEDIUM_SIZE=1600
```

Image and video extensions can also be adjusted in `photina.conf`.
`HOST` and `PORT` default to `localhost` and `80`; set them in the environment
to override those defaults.

Keep the passwords in `photina.conf` private.

To limit guest access, add album paths to `GUEST_ALBUMS`. Nested album paths
are supported, for example:

```bash
GUEST_ALBUMS=(
  "Greece/2026-08-01 - Σπήλαιο Πετραλώνων"
)
```

## Generate the gallery

When media is added or removed, run:

```bash
./update-thumbnails.sh
./update-gallery.sh
```

`update-gallery.sh` keeps existing gallery fragments and generates only missing
ones.

Thumbnail updates can be interrupted and resumed. Existing thumbnails are
reused, obsolete thumbnails are removed, and new thumbnails are generated in
parallel.

### Recreate generated data

Check `photina.conf` before deleting anything and make sure the configured
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

To recreate the gallery, delete the configured output directory before updating it:

```bash
./delete-gallery.sh
./update-gallery.sh
```

## Gallery behavior

The gallery starts with the album list. Select an album to view its media;
nested folders appear as nested albums. 

### Album thumbnails
To choose an album preview, place an image named `album.jpg` directly in that 
album’s folder. It is converted to a thumbnail and used instead of the first 
media item; nested albums fall back to their first available media when no 
cover is present.
