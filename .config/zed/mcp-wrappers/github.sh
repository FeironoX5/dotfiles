#!/usr/bin/env bash
# GitHub MCP server wrapper — reads token from ~/.config/secrets/github_token
# The token itself is NEVER stored in dotfiles.
# Run scripts/setup-mcp-secrets.sh to initialise your local secrets.
set -euo pipefail

TOKEN_FILE="$HOME/.config/secrets/github_token"

if [[ ! -f "$TOKEN_FILE" ]]; then
  echo "Error: $TOKEN_FILE not found." >&2
  echo "Run: bash ~/.dotfiles/scripts/setup-mcp-secrets.sh" >&2
  exit 1
fi

export GITHUB_PERSONAL_ACCESS_TOKEN
GITHUB_PERSONAL_ACCESS_TOKEN="$(< "$TOKEN_FILE")"

exec npx -y @modelcontextprotocol/server-github