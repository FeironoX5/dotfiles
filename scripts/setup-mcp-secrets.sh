#!/usr/bin/env bash
# =============================================================================
# setup-mcp-secrets.sh — bootstrap local MCP server secrets
#
# Creates ~/.config/secrets/ (chmod 700) and writes one token per file.
# This directory is intentionally outside the dotfiles repo — never commit it.
#
# Usage:
#   bash ~/.dotfiles/scripts/setup-mcp-secrets.sh
# =============================================================================
set -euo pipefail

# ── Colours ───────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; RESET=''
fi

info()    { echo -e "${CYAN}${BOLD}::${RESET} $*"; }
success() { echo -e "${GREEN}✓${RESET}  $*"; }
warn()    { echo -e "${YELLOW}!${RESET}  $*"; }
error()   { echo -e "${RED}✗${RESET}  $*" >&2; }
die()     { error "$*"; exit 1; }

# ── Paths ─────────────────────────────────────────────────────────────────────
SECRETS_DIR="$HOME/.config/secrets"
WRAPPERS_DIR="$HOME/.config/zed/mcp-wrappers"
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Helpers ───────────────────────────────────────────────────────────────────

# Prompt for a secret, hiding input. Writes result to the named variable.
read_secret() {
  local prompt="$1" var="$2"
  local value
  while true; do
    read -rsp "  ${prompt}: " value
    echo
    [[ -n "$value" ]] && break
    warn "Value cannot be empty. Try again."
  done
  printf -v "$var" '%s' "$value"
}

# Write a token to a file with safe permissions (600).
write_token() {
  local file="$1" token="$2"
  printf '%s' "$token" > "$file"
  chmod 600 "$file"
}

# Ask yes/no. Returns 0 for yes, 1 for no.
confirm() {
  local prompt="$1"
  local answer
  read -rp "  ${prompt} [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

# ── Main ──────────────────────────────────────────────────────────────────────

echo
echo -e "${BOLD}MCP Secrets Setup${RESET}"
echo -e "Dotfiles root : ${CYAN}${DOTFILES_DIR}${RESET}"
echo -e "Secrets dir   : ${CYAN}${SECRETS_DIR}${RESET}"
echo -e "Wrappers dir  : ${CYAN}${WRAPPERS_DIR}${RESET}"
echo

# ── 1. Create secrets directory ───────────────────────────────────────────────
if [[ -d "$SECRETS_DIR" ]]; then
  info "Secrets directory already exists — skipping creation."
else
  mkdir -p "$SECRETS_DIR"
  chmod 700 "$SECRETS_DIR"
  success "Created ${SECRETS_DIR} (chmod 700)"
fi

# ── 2. GitHub Personal Access Token ──────────────────────────────────────────
echo
info "GitHub Personal Access Token"
echo -e "  Scopes needed: ${YELLOW}repo, read:org, read:user, gist${RESET}"
echo -e "  Generate at:   ${CYAN}https://github.com/settings/tokens${RESET}"

GITHUB_FILE="$SECRETS_DIR/github_token"

if [[ -f "$GITHUB_FILE" ]]; then
  warn "Token file already exists: ${GITHUB_FILE}"
  if confirm "Overwrite?"; then
    gh_token=""
    read_secret "New GitHub PAT" gh_token
    write_token "$GITHUB_FILE" "$gh_token"
    success "GitHub token updated."
  else
    info "Keeping existing GitHub token."
  fi
else
  gh_token=""
  read_secret "GitHub PAT" gh_token
  write_token "$GITHUB_FILE" "$gh_token"
  success "GitHub token saved → ${GITHUB_FILE}"
fi

# ── 3. Todoist API Token ──────────────────────────────────────────────────────
echo
info "Todoist API Token"
echo -e "  Find it at: ${CYAN}https://app.todoist.com/app/settings/integrations/developer${RESET}"

TODOIST_FILE="$SECRETS_DIR/todoist_token"

if [[ -f "$TODOIST_FILE" ]]; then
  warn "Token file already exists: ${TODOIST_FILE}"
  if confirm "Overwrite?"; then
    td_token=""
    read_secret "New Todoist API token" td_token
    write_token "$TODOIST_FILE" "$td_token"
    success "Todoist token updated."
  else
    info "Keeping existing Todoist token."
  fi
else
  td_token=""
  read_secret "Todoist API token" td_token
  write_token "$TODOIST_FILE" "$td_token"
  success "Todoist token saved → ${TODOIST_FILE}"
fi

# ── 4. Make wrapper scripts executable ───────────────────────────────────────
echo
info "Marking wrapper scripts executable..."

if [[ -d "$WRAPPERS_DIR" ]]; then
  find "$WRAPPERS_DIR" -name '*.sh' -exec chmod +x {} \;
  success "Wrapper scripts in ${WRAPPERS_DIR} are now executable."
else
  warn "Wrappers directory not found: ${WRAPPERS_DIR}"
  warn "Have you run 'stow .' from the dotfiles root yet?"
fi

# ── 5. Verify secrets dir is not tracked by git ───────────────────────────────
echo
if git -C "$DOTFILES_DIR" check-ignore -q "$DOTFILES_DIR/.config/secrets/" 2>/dev/null; then
  success ".config/secrets/ is correctly gitignored."
else
  warn ".config/secrets/ does not appear in .gitignore."
  warn "Add the following line to ${DOTFILES_DIR}/.gitignore:"
  echo
  echo "    .config/secrets/"
  echo
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo
echo -e "${GREEN}${BOLD}All done!${RESET}"
echo -e "Restart Zed for the new MCP server configuration to take effect."
echo