#!/bin/sh

mkdir -p "${HOME}/.gnupg"
chmod 700 "${HOME}/.gnupg"

git submodule update --init --recursive
RCRC=~/.dotfiles/rcrc rcup -x install.sh -x README.md
