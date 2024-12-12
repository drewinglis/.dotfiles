[[ -f ~/.bashrc ]] && source ~/.bashrc

[[ -f ~/local.conf.d/bash_profile ]] && source ~/local.conf.d/bash_profile

if [[ -z "${SSH_AUTH_SOCK}" && -n "${PS1}" ]]; then
  ssh-add
fi
