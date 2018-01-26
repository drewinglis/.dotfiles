# Include bash and zsh common stuff
source ~/.commonshellrc

readonly GREEN_ESCAPE_START='\[\e[0;32m\]'
readonly BLUE_ESCAPE_START='\[\e[0;34m\]'
readonly ESCAPE_END='\[\e[m\]'

parse_git_branch() {
  git branch 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/ [\1]/'
}

export PS1="${GREEN_ESCAPE_START}\u@\h\n\w${ESCAPE_END}\$(parse_git_branch)\n${BLUE_ESCAPE_START}\A \$${ESCAPE_END} "

[[ -f ~/local.conf.d/bashrc ]] && source ~/local.conf.d/bashrc
