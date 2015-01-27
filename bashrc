# This is used to only load certain things on certain systems.
ensure_command(){
  which $1 > /dev/null
}

source ~/.exportrc

source ~/.aliasrc

# Add RVM to PATH for scripting, if it exists.
[[ -s $HOME/.rvm/bin ]] && PATH=$PATH:$HOME/.rvm/bin

source ~/.bashrc.local
