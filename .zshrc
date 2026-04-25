# ── 1. p10k instant prompt — ПЕРВАЯ СТРОКА ────────────────────────────────────
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ── 2. Oh-My-Zsh ───────────────────────────────────────────────────────────────
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(
  git
  ssh-agent
  sudo
  aliases
  common-aliases
  zsh-autosuggestions
  zsh-syntax-highlighting
  history-substring-search
  colored-man-pages
  command-not-found
  extract
  copyfile
  copypath
  systemd
  fzf-tab
)

zstyle :omz:plugins:ssh-agent identities id_rsa id_ed25519
zstyle :omz:plugins:ssh-agent lifetime 4h
zstyle :omz:plugins:ssh-agent lazy yes
zstyle ':omz:plugins:aliases' verbose yes

source $ZSH/oh-my-zsh.sh

# ── 3. История ─────────────────────────────────────────────────────────────────
HISTSIZE=50000
SAVEHIST=50000
HISTFILE=~/.zsh_history
setopt EXTENDED_HISTORY SHARE_HISTORY APPEND_HISTORY INC_APPEND_HISTORY
setopt HIST_IGNORE_DUPS HIST_IGNORE_ALL_DUPS HIST_FIND_NO_DUPS
setopt HIST_IGNORE_SPACE HIST_SAVE_NO_DUPS HIST_REDUCE_BLANKS

# ── 4. Completion ──────────────────────────────────────────────────────────────
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.zsh/cache
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'

# fzf-tab превью
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls -la $realpath'
zstyle ':fzf-tab:complete:*' fzf-preview 'echo $realpath'

# ── 5. fzf ─────────────────────────────────────────────────────────────────────
eval "$(fzf --zsh)"

# ── 6. carapace ────────────────────────────────────────────────────────────────
if command -v carapace &>/dev/null; then
  export CARAPACE_BRIDGES='zsh,fish,bash'
  source <(carapace _carapace)
fi

# ── 7. zoxide ──────────────────────────────────────────────────────────────────
eval "$(zoxide init --cmd cd zsh)"

# ── 8. Навигация ───────────────────────────────────────────────────────────────
setopt AUTO_CD

# ── 9. Функции ─────────────────────────────────────────────────────────────────
flatdelete() {
  local app_id=$(flatpak list --columns=application | grep -i "$1" | head -n 1)
  if [ -n "$app_id" ]; then
    flatpak remove "$app_id"
  else
    echo "Приложение по запросу '$1' не найдено"
  fi
}
gitget() { git clone "https://github.com/$1.git" }
ghprs() {
  local author="${1:-$(gh api user --jq .login)}"
  gh pr list --author "$author" --json number,title,headRefName,baseRefName,commits \
    | jq -r '.[] |
        "#\(.number) \(.title)",
        "  \(.headRefName) → \(.baseRefName)  [\(.commits | length) commit(s)]",
        "  latest: \(.commits[-1].messageHeadline)",
        ""'
}
todos() {
  leasot -S --reporter json $(git ls-files) "$@" 2>/dev/null | \
  jq -r '.[] | "\(.tag | if . == "TODO" then "\u001b[33mTODO\u001b[0m" else . end): \(.text) \u001b[33m\(.file):\(.line)\u001b[0m"'
}

# ── 10. Алиасы ────────────────────────────────────────────────────────────────
alias cl='clear'
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'

alias gs='git status'
alias ga='git add'
alias gaa='git add --all'
alias gc='git commit'
alias gcm='git commit -m'
alias gp='git push'
alias gpl='git pull'
alias gd='git diff'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gb='git branch'
alias gbd='git branch -d'
alias glog='git log --oneline --decorate --graph --all'
alias gclean='git clean -fd'
alias gstash='git stash'
alias gpop='git stash pop'
alias cdr='cd "$(git rev-parse --show-toplevel)"'
alias helios='ssh s408766@helios.cs.ifmo.ru -P 2222'

# ── 11. PATH ──────────────────────────────────────────────────────────────────
export PATH=$HOME/.local/bin:$PATH
export PATH=/home/glebkiva/.opencode/bin:$PATH
export PATH="$PATH:$HOME/go/bin"
export PATH="$PATH:$HOME/Devtools/flutter/bin"
export PATH="/home/glebkiva/fvm/bin:$PATH"
export PATH="$HOME/.local/kitty.app/bin:$PATH"

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
