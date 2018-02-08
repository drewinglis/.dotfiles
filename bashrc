# Include bash and zsh common stuff
source ~/.commonshellrc

readonly GREEN_ESCAPE='\[\e[0;32m\]'
readonly YELLOW_ESCAPE='\[\e[0;33m\]'
readonly BLUE_ESCAPE='\[\e[0;34m\]'
readonly ESCAPE_END='\[\e[m\]'

alias parse_git_branch="git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/'"

# I had this in a function, but I was having a hard time getting the escape
# characters to work correctly with echo.
readonly BRANCH=$(parse_git_branch)
git_display=''
if [[ ${BRANCH} != '' ]]; then
  color=${GREEN_ESCAPE}
  if [[ `git status --porcelain 2>/dev/null` ]]; then
    color=${YELLOW_ESCAPE}
  fi
  git_display=" [${color}${BRANCH}${ESCAPE_END}]"
fi

export PS1="${GREEN_ESCAPE}\u@\h\n\w${ESCAPE_END}${git_display}\n${BLUE_ESCAPE}\A \$${ESCAPE_END} "

[[ -f ~/local.conf.d/bashrc ]] && source ~/local.conf.d/bashrc
