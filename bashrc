# Include bash and zsh common stuff
source ~/.commonshellrc

readonly GREEN_ESCAPE='\e[0;32m'
readonly YELLOW_ESCAPE='\e[0;33m'
readonly BLUE_ESCAPE='\e[0;34m'
readonly ESCAPE_END='\e[m'

function parse_git_branch () {
  local -r BRANCH=$(git branch 2>/dev/null | \
    sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/')
  if [[ ${BRANCH} != '' ]]; then
    local color=${GREEN_ESCAPE}
    if [[ `git status --porcelain 2>/dev/null` ]]; then
      color=${YELLOW_ESCAPE}
    fi
    echo -e " [${color}${BRANCH}${ESCAPE_END}]"
  fi
}

export PS1="${GREEN_ESCAPE}\u@\h\n\w${ESCAPE_END}\$(parse_git_branch)\n${BLUE_ESCAPE}\A \$${ESCAPE_END} "

[[ -f ~/local.conf.d/bashrc ]] && source ~/local.conf.d/bashrc
