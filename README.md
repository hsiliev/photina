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
MEDIUM_SIZE=1600
```

Image and video extensions can also be adjusted in `photina.conf`.
`HOST` and `PORT` default to `localhost` and `80`; set them in the environment
to override those defaults.

Keep the passwords in `photina.conf` private.

## Generate the gallery

When media is added or removed, run:

```bash
./update-thumbnails.sh
./generate-gallery.sh
```

Thumbnail updates can be interrupted and resumed. Existing thumbnails are
reused, obsolete thumbnails are removed, and new thumbnails are generated in
parallel. To recreate every thumbnail:

```bash
./recreate-thumbnails.sh
```

The gallery uses small thumbnails for the grid, medium images in the viewer,
and the original media for full-resolution viewing and download. Generated
thumbnail and medium assets use WebP format.

Each image can be downloaded in its original form.

`generate-gallery.sh` creates the gallery and updates the Caddy configuration,
then reloads Caddy.

## Gallery behavior

The gallery starts with the album list. Select an album to view its media;
nested folders appear as nested albums. 

### Album thumbnails
To choose an album preview, place an image named `album.jpg` directly in that 
album’s folder. It is converted to a thumbnail and used instead of the first 
media item; nested albums fall back to their first available media when no 
cover is present.
