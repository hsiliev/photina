# Static gallery generator

`generate-gallery.sh` builds a static gallery from a directory of albums. Each
immediate subdirectory is an album; media files may be nested inside it.
Image thumbnails are created with ImageMagick and video thumbnails with
`ffmpegthumbnailer`. The thumbnail cache is a separate directory from the
albums directory.

```bash
# Uses /mnt/gallery/photos, /mnt/gallery/dist, and /mnt/gallery/thumbnails
./generate-gallery.sh

```

The default directories and thumbnail dimensions are configured in
`photina.conf` with `ALBUMS_DIR`, `OUTPUT_DIR`, `THUMBNAILS_DIR`, and
`THUMBNAIL_SIZE`. It also controls Caddy generation through `CADDYFILE`
(defaulting to `/etc/caddy/Caddyfile`),
`ADMIN_PASSWORD`, `GUEST_PASSWORD`, and the quoted `GUEST_ALBUMS` Bash array.
Passwords are hashed through Caddy when the gallery is generated. Keep
`photina.conf` private. Set `PHOTINA_CONFIG` to use a different config file.

Thumbnails can be updated independently with:

```bash
./update-thumbnails.sh
```

The update script also grants Caddy read/traverse access to the gallery
directories using standard permissions. This makes the gallery readable by
local users as well; use filesystem ACLs or group permissions instead if that
is not acceptable.

To regenerate every thumbnail, including existing ones, run:

```bash
./recreate-thumbnails.sh
```

Run `update-thumbnails.sh` before `generate-gallery.sh` when new media is
added. `generate-gallery.sh` only writes the gallery and Caddy configuration.

The generated Caddy configuration is merged into the configured `CADDYFILE`
between `PHOTINA MANAGED` markers. Existing configuration outside those
markers is preserved across runs.

Caddy access logs are written to `/var/log/caddy/access.log`.

The generated `gallery-site/index.html` and `gallery-site/assets` can be served
by any static web server. Original media remains in the albums directory and
thumbnails remain in the separate thumbnail directory. Keep the thumbnail
directory at the same relative location when deploying, because the HTML
references it directly. The page loads nanogallery2 and jQuery from their
CDNs.

Thumbnail generation can be interrupted and resumed. Completed thumbnails
remain at their final `.jpg` paths and are skipped on subsequent runs;
in-progress thumbnails use temporary suffixes until they are complete. New
thumbnails are generated in parallel using the available CPU cores.

For the default `/mnt/gallery` layout, the included `Caddyfile` serves the
gallery at `http://HOST/dist/`, maps its media URLs to
`/mnt/gallery/photos`, and redirects the site root there. Start Caddy from
this directory with:

```bash
caddy run --config ./Caddyfile
```

Required commands: `bash`, `find`, `realpath`, `sudo`, `caddy`, ImageMagick
(`magick` or `convert`), and `ffmpegthumbnailer`.
