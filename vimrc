set nocompatible

if filereadable($HOME . '/.vimrc')
  source ~/.vimrc.local
endif

execute pathogen#infect()

" most of this stolen from: http://mislav.uniqpath.com/2011/12/vim-revisited/
syntax enable
set encoding=utf-8
set showcmd                     " display incomplete commands
filetype plugin indent on       " load file type plugins + indentation

"" Whitespace
" set nowrap                    " don't wrap lines
set tabstop=2 shiftwidth=2      " a tab is two spaces
set expandtab                   " use spaces, not tabs (optional)
set backspace=indent,eol,start  " backspace through everything in insert mode

"" Searching
set hlsearch                    " highlight matches
set incsearch                   " incremental searching
set ignorecase                  " searches are case insensitive...
set smartcase                   " ... unless they contain a capital letter
" end stolen block

set number                      " show line numbers
set splitright                  " open new vertical splits to the right
set splitbelow                  " open new horizontal splits on the bottom

" Use breakindent patch to automatically indent wrapping lines
" Get it here: https://github.com/drewinglis/vim-breakindent
set breakindent
set showbreak=\ \ " comment so that the whitespace works >.>

" Use the solarized colorscheme
set background=dark
colorscheme solarized

" remove all whitespace at the end of lines
autocmd BufWritePre * :%s/\s\+$//e

" automatically reload files that change on disk
set autoread
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

" set .hamlc ft
au BufRead,BufNewFile *.hamlc set ft=haml

" Git config specific styles
autocmd BufRead,BufNewFile .gitmodules setlocal noexpandtab

" Fix to edit crontab files in place
au BufEnter crontab.* setl backupcopy=yes

" Highlight lines over 80 characters
highlight OverLength ctermbg=Black
autocmd BufRead,BufNewFile * match OverLength /\%81v.\+/
