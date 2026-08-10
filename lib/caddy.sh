#!/usr/bin/env bash

generate_caddyfile() {
  local script_dir=$1 caddyfile=$2 albums_dir=$3 output_dir=$4 thumbs_dir=$5
  local caddy_host=$6 caddy_port=$7 admin_password=$8 guest_password=$9
  local admin_password_hash guest_password_hash caddyfile_tmp album escaped_album
  local output_parent thumbs_parent caddy_template guest_media_block guest_thumbnails_block
  local existing_config managed_block merged_config managed_start managed_end
  shift 9
  local -a guest_albums=("$@")

  admin_password_hash=$(caddy hash-password --plaintext "$admin_password")
  guest_password_hash=$(caddy hash-password --plaintext "$guest_password")
  output_parent=$(dirname -- "$output_dir")
  thumbs_parent=$(dirname -- "$thumbs_dir")

  mkdir -p -- "$(dirname -- "$caddyfile")"
  caddyfile_tmp=$(mktemp "${caddyfile}.XXXXXX")
  trap 'rm -f -- "${caddyfile_tmp:-}"' EXIT
  guest_media_block=
  guest_thumbnails_block=
  if ((${#guest_albums[@]})); then
    guest_media_block=$'\t@guest_allowed_media {\n\t\texpression `{http.auth.user.id} == "guest"`\n\t\tpath'
    guest_thumbnails_block=$'\t@guest_allowed_thumbnails {\n\t\texpression `{http.auth.user.id} == "guest"`\n\t\tpath'
    for album in "${guest_albums[@]}"; do
      escaped_album=${album//\\/\\\\}
      escaped_album=${escaped_album//\"/\\\"}
      guest_media_block+=$(printf ' "/media/%s/*"' "$escaped_album")
      guest_thumbnails_block+=$(printf ' "/thumbnails/%s/*"' "$escaped_album")
    done
    guest_media_block+=$'\n\t}\n\thandle @guest_allowed_media {\n\t\thandle_path /media/* {\n\t\t\troot * "'"$albums_dir"$'"\n\t\t\tfile_server\n\t\t}\n\t}\n'
    guest_thumbnails_block+=$'\n\t}\n\thandle @guest_allowed_thumbnails {\n\t\thandle_path /thumbnails/* {\n\t\t\troot * "'"$thumbs_dir"$'"\n\t\t\tfile_server\n\t\t}\n\t}\n'
  fi

  caddy_template=$(<"$script_dir/templates/Caddyfile.template")
  caddy_template=${caddy_template//__ADMIN_PASSWORD_HASH__/$admin_password_hash}
  caddy_template=${caddy_template//__GUEST_PASSWORD_HASH__/$guest_password_hash}
  caddy_template=${caddy_template//__GUEST_ALLOWED_MEDIA__/$guest_media_block}
  caddy_template=${caddy_template//__GUEST_ALLOWED_THUMBNAILS__/$guest_thumbnails_block}
  caddy_template=${caddy_template//__ALBUMS_DIR__/$albums_dir}
  caddy_template=${caddy_template//__OUTPUT_DIR__/$output_dir}
  caddy_template=${caddy_template//__OUTPUT_PARENT__/$output_parent}
  caddy_template=${caddy_template//__THUMBNAILS_PARENT__/$thumbs_parent}
  caddy_template=${caddy_template//__CADDY_HOST__/$caddy_host}
  caddy_template=${caddy_template//__CADDY_PORT__/$caddy_port}
  managed_start='# BEGIN PHOTINA MANAGED'
  managed_end='# END PHOTINA MANAGED'
  managed_block=$(printf '%s\n%s\n%s' "$managed_start" "$caddy_template" "$managed_end")

  if [[ -f "$caddyfile" ]]; then
    existing_config=$(<"$caddyfile")
    if [[ "$existing_config" == *"$managed_start"* && "$existing_config" == *"$managed_end"* ]]; then
      local before_managed after_start
      before_managed=${existing_config%%"$managed_start"*}
      after_start=${existing_config#*"$managed_start"}
      after_start=${after_start#*"$managed_end"}
      merged_config="$before_managed$managed_block$after_start"
    else
      merged_config="$existing_config"$'\n\n'"$managed_block"
    fi
  else
    merged_config=$managed_block
  fi

  printf '%s\n' "$merged_config" >"$caddyfile_tmp"
  mv -f -- "$caddyfile_tmp" "$caddyfile"
  trap - EXIT
  printf 'Caddy configuration written to %s\n' "$caddyfile"
}
