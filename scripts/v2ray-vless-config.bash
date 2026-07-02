#!/usr/bin/env bash
set -euo pipefail

script_source="${BASH_SOURCE[0]:-$0}"
script_path="$(readlink -f "$script_source" 2>/dev/null || printf '%s' "$script_source")"
script_dir="$(dirname "$script_path")"

exec "${script_dir}/xray-vless-config.bash" "$@"
