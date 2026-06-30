#!/usr/bin/env bash
script_dir="$(dirname "$0")"
if [[ -x "${script_dir}/vpn.bash" ]]; then
  exec "${script_dir}/vpn.bash" suspend
fi
exec "${HOME}/.dotfiles/scripts/vpn.bash" suspend
