# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="powerlevel10k/powerlevel10k"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
   git                      # Git алиасы и автодополнение
   ssh-agent               # Автозагрузка SSH ключей
   sudo                    # ESC дважды = добавить sudo к команде
   aliases                 # Поиск и управление алиасами
   common-aliases          # Куча полезных алиасов
   zsh-autosuggestions     # Подсказки из истории (серые)
   zsh-syntax-highlighting # Подсветка синтаксиса команд
   history-substring-search # Поиск по истории через стрелки
   colored-man-pages       # Цветные man страницы
   command-not-found       # Подсказки при неправильной команде
   extract                 # Универсальная распаковка архивов
   copyfile                # Копировать содержимое файла в буфер
   copypath                # Копировать путь к файлу в буфер
   npm
   yarn
   systemd
)

zstyle :omz:plugins:ssh-agent identities id_rsa id_ed25519
zstyle :omz:plugins:ssh-agent lifetime 4h
zstyle :omz:plugins:ssh-agent lazy yes  # Ленивая загрузка (быстрее старт)

zstyle ':omz:plugins:aliases' verbose yes  # Показывать команду при использовании алиаса

source $ZSH/oh-my-zsh.sh

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi


HISTSIZE=50000
SAVEHIST=50000
HISTFILE=~/.zsh_history

# Опции истории
setopt EXTENDED_HISTORY          # Записывать timestamp
setopt SHARE_HISTORY            # Делить историю между сессиями
setopt APPEND_HISTORY           # Добавлять, не перезаписывать
setopt INC_APPEND_HISTORY       # Добавлять сразу
setopt HIST_IGNORE_DUPS         # Игнорировать дубликаты
setopt HIST_IGNORE_ALL_DUPS     # Удалять старые дубликаты
setopt HIST_FIND_NO_DUPS        # Не показывать дубликаты при поиске
setopt HIST_IGNORE_SPACE        # Игнорировать команды с пробелом в начале
setopt HIST_SAVE_NO_DUPS        # Не сохранять дубликаты
setopt HIST_REDUCE_BLANKS       # Убирать лишние пробелы

# Автокомолит
autoload -Uz compinit
compinit
# Кэширование автодополнения
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.zsh/cache
# Регистронезависимое автодополнение
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
# Меню выбора при автодополнении
zstyle ':completion:*' menu select
# Цвета в автодополнении
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# навигация
setopt AUTO_CD

# алиасы
# Системные
flatdelete() {
    local app_id=$(flatpak list --columns=application | grep -i "$1" | head -n 1)

    if [ -n "$app_id" ]; then
        flatpak remove "$app_id"
    else
        echo "Приложение по запросу '$1' не найдено"
    fi
}

alias cl='clear'
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'
# Git
gitget() {
  git clone "https://github.com/$1.git"
}
ghprs() {
  local author="${1:-$(gh api user --jq .login)}"
  gh pr list --author "$author" --json number,title,headRefName,baseRefName,commits \
    | jq -r '.[] |
        "#\(.number) \(.title)",
        "  \(.headRefName) → \(.baseRefName)  [\(.commits | length) commit(s)]",
        "  latest: \(.commits[-1].messageHeadline)",
        ""'
}

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
#ssh (todo)
alias helios='ssh s408766@helios.cs.ifmo.ru -P 2222'




# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
export PATH=$HOME/.local/bin:$PATH

# opencode
export PATH=/home/glebkiva/.opencode/bin:$PATH
# export PATH="/home/.local/bin:$PATH"
