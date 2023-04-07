#!/bin/sh

git submodule update --init --recursive
RCRC=~/.dotfiles/rcrc rcup -x install.sh -x README.md
