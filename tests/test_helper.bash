#!/usr/bin/env bash

PROJECT_ROOT=$(cd -- "$BATS_TEST_DIRNAME/.." && pwd)

setup() {
  test_root="$BATS_TEST_TMPDIR/photina"
  mkdir -p -- "$test_root"
  source "$PROJECT_ROOT/lib/gallery/main.sh"
  source "$PROJECT_ROOT/lib/thumbnails.sh"
  IMAGE_EXTENSIONS=(jpg)
  VIDEO_EXTENSIONS=()
}

teardown() {
  rm -rf -- "$test_root"
}
