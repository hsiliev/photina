# Validation

How to check changes: syntax, lint, tests, and manual browser checks. Part of
the project notes in [AGENTS.md](../AGENTS.md).

## Validation

Shellcheck (0.11) is clean. Suppressions are limited to namerefs (arrays
passed by name), globals shared between sourced libraries, and the jq program
string; each carries a reason comment. Keep new code warning-free rather than
adding blanket disables.

Useful checks:

```bash
bash -n ./*.sh lib/*.sh lib/thumbnails/*.sh lib/gallery/*.sh
shellcheck -x -P SCRIPTDIR ./*.sh lib/*.sh lib/thumbnails/*.sh lib/gallery/*.sh
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
preview resolution with restricted permissions, viewer-variant expected outputs,
per-breakpoint gallery item sources, `du-thumbnails.sh` grouping, real
`thumbnail_make` output widths, duplicate detection and
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
