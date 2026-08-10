# Static gallery generator

`generate-gallery.sh` builds a static gallery from a directory of albums. Each
immediate subdirectory is an album; media files may be nested inside it.
Image thumbnails are created with ImageMagick and video thumbnails with
`ffmpegthumbnailer`. The thumbnail cache is a separate directory from the
albums directory.

```bash
# Uses /mnt/gallery/albums, /mnt/gallery/dist, and /mnt/gallery/thumbnails
./generate-gallery.sh

# Or override the defaults positionally
./generate-gallery.sh /photos/albums ./gallery-site /photos/gallery-thumbnails
```

The generated `gallery-site/index.html` and `gallery-site/media` can be served
by any static web server. Keep the thumbnail directory at the same relative
location when deploying, because the HTML references it directly. The page
loads nanogallery2 and jQuery from their CDNs.

Required commands: `bash`, `find`, `realpath`, ImageMagick (`magick` or
`convert`), and `ffmpegthumbnailer`.
