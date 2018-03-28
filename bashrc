# Include bash and zsh common stuff
source ~/.commonshellrc

readonly GREEN_ESCAPE='\001\e[0;32m\002'
readonly YELLOW_ESCAPE='\001\e[0;33m\002'
readonly BLUE_ESCAPE='\001\e[0;34m\002'
readonly ESCAPE_END='\001\e[m\002'

alias parse_git_branch="git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/'"

function display_git_branch() {
  local -r BRANCH=$(parse_git_branch)
  if [[ ${BRANCH} != '' ]]; then
    local color=${GREEN_ESCAPE}
    if [[ `git status --porcelain 2>/dev/null` ]]; then
      color=${YELLOW_ESCAPE}
    fi
    echo -e " [${color}${BRANCH}${ESCAPE_END}]"
  fi
}

function prompt_command() {
  # this is a fucking stupid hack
  if [[ ! -z "$TMUX" ]]; then
    tmux refresh-client
    tmux refresh-client
  fi
}
PROMPT_COMMAND=prompt_command

export PS1="${GREEN_ESCAPE}\u@\h\n\w${ESCAPE_END}\$(display_git_branch)\n${BLUE_ESCAPE}\A \$${ESCAPE_END} "

[[ -f ~/local.conf.d/bashrc ]] && source ~/local.conf.d/bashrc
