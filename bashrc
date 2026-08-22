# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# Include common shell stuff
source ~/.commonshellrc

GREEN_ESCAPE='\001\e[0;32m\002'
YELLOW_ESCAPE='\001\e[0;33m\002'
BLUE_ESCAPE='\001\e[0;34m\002'
ESCAPE_END='\001\e[m\002'

# One `git status` yields both the branch and whether the tree is dirty.
function display_git_branch() {
  local status
  status=$(git status --porcelain -b 2>/dev/null) || return

  local branch=${status%%$'\n'*}
  branch=${branch#'## '}
  branch=${branch#'No commits yet on '}
  branch=${branch%' (no branch)'}
  branch=${branch%%...*}

  local color=${GREEN_ESCAPE}
  [[ ${status} == *$'\n'* ]] && color=${YELLOW_ESCAPE}

  printf ' [%b%s%b]' "${color}" "${branch}" "${ESCAPE_END}"
}

function prompt_command() {
  # this is a fucking stupid hack
  if [[ ! -z "$TMUX" ]]; then
    tmux refresh-client
  fi
}
PROMPT_COMMAND=prompt_command

function maybe_display_hostname() {
  if [[ -n "$SSH_CONNECTION" ]]; then
    printf "\\h: "
  fi
}

export PS1="${GREEN_ESCAPE}\w${ESCAPE_END}\$(display_git_branch)\n${BLUE_ESCAPE}$(maybe_display_hostname)\A \$${ESCAPE_END} "

if is_darwin; then
  switch-java () {
    export JAVA_HOME=$(/usr/libexec/java_home -v $1)

    [[ -n $2 ]] || java -version
  }
fi

[[ -f ~/local.conf.d/bashrc ]] && source ~/local.conf.d/bashrc

[[ -x '/usr/bin/terraform' ]] && complete -C /usr/bin/terraform terraform
