set nocompatible

if filereadable($HOME . '/.vimrc.local')
  source ~/.vimrc.local
endif

execute pathogen#infect()

syntax enable
filetype plugin indent on       " load file type plugins + indentation
let mapleader=" "

set autochdir                   " Change working directory to current file
set autoread                    " Reload file changes from disk
set background=dark             " Use the dark background color scheme
set backspace=indent,eol,start  " Backspace through everything in insert mode
set breakindent                 " Use breakindent (if enabled)
set encoding=utf-8              " Use UTF-8
set expandtab                   " Use spaces, not tabs
set hlsearch                    " Highlight matches
set ignorecase                  " Searches are case insensitive
set incsearch                   " Incremental searching
set number                      " Show line numbers
set showbreak=\ \               " Set the indent for breakindent
set showcmd                     " Display incomplete commands
set smartcase                   " Searches case-sensitive if they're mixed-case
set splitbelow                  " Open new horizontal splits on the bottom
set splitright                  " Open new vertical splits to the right
set tabstop=2 shiftwidth=2      " A tab is two spaces

colorscheme solarized           " Use the solarized dark colorscheme

" remove all whitespace at the end of lines
autocmd BufWritePre * :%s/\s\+$//e

" automatically reload files that change on disk
autocmd BufEnter,BufWinEnter,CursorHold * :checktime

" remap arrow keys
map <Left> <Nop>
map <Right> <Nop>
map <Up> <Nop>
map <Down> <Nop>
inoremap  <Up>     <NOP>
inoremap  <Down>   <NOP>
inoremap  <Left>   <NOP>
inoremap  <Right>  <NOP>

" Look for a file to edit in the current directory
nmap <leader>e :e ./<CR>

" Write out the current buffer
nmap <leader>w :w<CR>

" Cycle through most recently used buffers
nmap <leader>up :BuffergatorMruCyclePrev<CR>
nmap <leader>un :BuffergatorMruCycleNext<CR>

" set .hamlc ft
autocmd BufRead,BufNewFile *.hamlc set ft=haml

" Git config specific styles
autocmd BufRead,BufNewFile .gitmodules setlocal noexpandtab

" Fix to edit crontab files in place
autocmd BufEnter crontab.* setlocal backupcopy=yes

" Highlight lines over 80 characters
highlight OverLength ctermbg=Black
autocmd BufRead,BufNewFile,BufEnter,BufWinEnter * match OverLength /\%81v.\+/
