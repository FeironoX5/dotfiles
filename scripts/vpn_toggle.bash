#!/usr/bin/env bash
script_dir="$(dirname "$0")"
if [[ -x "${script_dir}/vpn.bash" ]]; then
  exec "${script_dir}/vpn.bash" "${1:-toggle}" "${@:2}"
fi
exec "${HOME}/.dotfiles/scripts/vpn.bash" "${1:-toggle}" "${@:2}"
