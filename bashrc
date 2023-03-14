# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# Include bash and zsh common stuff
source ~/.commonshellrc

readonly GREEN_ESCAPE='\001\e[0;32m\002'
readonly YELLOW_ESCAPE='\001\e[0;33m\002'
readonly BLUE_ESCAPE='\001\e[0;34m\002'
readonly ESCAPE_END='\001\e[m\002'

alias parse_git_branch="git rev-parse --abbrev-ref HEAD 2>/dev/null"

function display_git_branch() {
  local -r BRANCH=$(parse_git_branch)
  if [[ ${BRANCH} != '' ]]; then
    local color=${GREEN_ESCAPE}
    if [[ `git status --porcelain 2>/dev/null` ]]; then
      color=${YELLOW_ESCAPE}
    fi
    printf " [${color}${BRANCH}${ESCAPE_END}]"
  fi
}
export -f display_git_branch

function prompt_command() {
  # this is a fucking stupid hack
  if [[ ! -z "$TMUX" ]]; then
    tmux refresh-client
  fi
}
PROMPT_COMMAND=prompt_command

export PS1="${GREEN_ESCAPE}\w${ESCAPE_END}\$(display_git_branch)\n${BLUE_ESCAPE}\A \$${ESCAPE_END} "

switch-java () {
  export JAVA_HOME=$(/usr/libexec/java_home -v $1)
  java -version
}

[[ -f ~/local.conf.d/bashrc ]] && source ~/local.conf.d/bashrc

complete -C /usr/local/bin/vault vault
