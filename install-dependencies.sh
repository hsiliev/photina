#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ -r /etc/os-release ]] || die 'cannot identify the operating system'
# shellcheck source=/etc/os-release
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == ubuntu ]] || die 'this installer supports Ubuntu only'
command -v sudo >/dev/null || die 'sudo is required'
command -v apt-get >/dev/null || die 'apt-get is required'

echo 'Updating Ubuntu package lists'
sudo apt-get update

echo 'Installing gallery dependencies'
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
  bash findutils coreutils sudo imagemagick libimage-exiftool-perl jq ffmpeg ffmpegthumbnailer curl gnupg \
  ca-certificates debian-keyring debian-archive-keyring apt-transport-https

if ! apt-cache policy caddy | grep -q '^  Candidate: [^ (]'; then
  echo 'Adding the official Caddy package repository'
  sudo install -d -m 0755 /usr/share/keyrings
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' |
    sudo gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' |
    sudo tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  sudo apt-get update
fi

# nls_utf8 (UTF-8 filenames on vfat/exfat/ntfs mounts) ships in the kernel's
# extra-modules package. linux-image-generic depends on the extras package of
# the current kernel version, so future kernel upgrades install it too, unlike
# the minimal linux-image-virtual metapackage.
kernel=$(uname -r)
if [[ "$kernel" == *-generic ]]; then
  echo 'Installing linux-image-generic so kernel updates keep the nls_utf8 module'
  sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y linux-image-generic
  if ! sudo modprobe nls_utf8 2>/dev/null; then
    die "nls_utf8 is not loadable for the running kernel $kernel; reboot into the newest installed kernel, then run $0 again"
  fi
else
  echo "Skipping nls_utf8 setup: kernel $kernel is not a -generic kernel"
fi

echo 'Installing Caddy'
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y caddy

if [[ ! -e /etc/photina/photina.conf ]]; then
  echo 'Installing the default Photina configuration'
  sudo install -d -m 0755 /etc/photina
  sudo install -m 0600 "$script_dir/templates/photina.conf.template" /etc/photina/photina.conf
else
  echo 'Keeping existing /etc/photina/photina.conf'
fi

tmux_conf=$HOME/.tmux.conf
if ! grep -qsE '^[[:space:]]*set(-option)?[[:space:]]+-g[[:space:]]+mouse[[:space:]]+on' "$tmux_conf"; then
  echo "Enabling tmux mouse support in $tmux_conf"
  printf 'set -g mouse on\n' >>"$tmux_conf"
else
  echo "Keeping existing tmux mouse setting in $tmux_conf"
fi

echo 'Dependencies installed'
