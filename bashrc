# Include bash and zsh common stuff
source ~/.commonshellrc

export PS1="\[\e[0;32m\]\u@\h\n\w\[\e[m\]\n\[\e[0;34m\]\A $\[\e[m\] "

[[ -f ~/local.conf.d/bashrc ]] && source ~/local.conf.d/bashrc
