vim9script

set nocompatible

if filereadable($HOME .. '/local.conf.d/vimrc')
  source $HOME .. '/local.conf.d/vimrc'
endif

execute pathogen#infect()

syntax enable
filetype plugin indent on       # load file type plugins + indentation
g:mapleader = " "

set autochdir                   # Change working directory to current file
set autoread                    # Reload file changes from disk
set background=dark             # Use the dark background color scheme
set backspace=indent,eol,start  # Backspace through everything in insert mode
set breakindent                 # Use breakindent (if enabled)
set encoding=utf-8              # Use UTF-8
set expandtab                   # Use spaces, not tabs
set hlsearch                    # Highlight matches
set ignorecase                  # Searches are case insensitive
set incsearch                   # Incremental searching
set nomodeline                  # Hashtag security
set number                      # Show line numbers
set showbreak=\ \               # Set the indent for breakindent
set showcmd                     # Display incomplete commands
set smartcase                   # Searches case-sensitive if they're mixed-case
set splitbelow                  # Open new horizontal splits on the bottom
set splitright                  # Open new vertical splits to the right
set tabstop=2 shiftwidth=2      # A tab is two spaces
set tags=.git/tags;             # See git_template/hooks for more details
set textwidth=80                # I like 80 chars for the default tw value
set visualbell

colorscheme solarized           # Use the solarized dark colorscheme

# Highlight long lines with a 'black' background.
highlight ColorColumn ctermbg=Black
highlight OverLength ctermbg=Black

# remove training wheels
nnoremap <Left> <Nop>
nnoremap <Right> <Nop>
nnoremap <Up> <Nop>
nnoremap <Down> <Nop>
inoremap <Up> <NOP>
inoremap <Down> <NOP>
inoremap <Left> <NOP>
inoremap <Right> <NOP>

# Look for a file to edit in the current directory
nnoremap <leader>e :e ./<CR>

nnoremap <leader>w :w<CR>
nnoremap <leader>n :n<CR>

# Cycle through most recently used buffers
nnoremap <leader>up :BuffergatorMruCyclePrev<CR>
nnoremap <leader>un :BuffergatorMruCycleNext<CR>

# Create new splits
nnoremap <leader>sv :vsp<CR>
nnoremap <leader>sh :sp<CR>

# Hacky go-to relative file commands. Only works for java-like projects.
nnoremap <leader>fc :execute "e ".substitute(expand("%:p"), '/test/\(.*\)_test\.\(.*\)', '/src/\1.\2', "")<CR>
nnoremap <leader>ft :execute "e ".substitute(expand("%:p"), '/src/\(.*\)\.\(.*\)', '/test/\1_test.\2', "")<CR>

# lsp config, used below in LspAddServer
var lspServers = [
  {
    name: 'golang',
    filetype: ['go', 'gomod'],
    path: $HOME .. '/.goenv/shims/gopls',
    args: ['serve'],
    syncInit: v:true,
  },
]

# vimcomplete config, used below in VimCompleteOptionsSet
var vimcompleteOptions = {
  completor: {
    noNewlineInCompletionEver: true,
  },
}
g:vimcomplete_tab_enable = 1

augroup drewinglis_generic_autocmds
  autocmd!
  # remove all whitespace at the end of lines
  autocmd BufWritePre * :%s/\s\+$//e

  # automatically reload files that change on disk
  autocmd BufEnter,BufWinEnter,CursorHold * :checktime

  # set .hamlc ft
  autocmd BufRead,BufNewFile *.hamlc setfiletype haml

  # set .proto.jinja ft
  autocmd BufRead,BufNewFile *.proto.jinja setfiletype proto

  # Git config specific styles
  autocmd BufRead,BufNewFile .gitmodules setlocal noexpandtab

  # Go specific styles. I can tolerate tabs, but not 8-width tabs.
  autocmd FileType go setlocal tabstop=2 shiftwidth=2 noexpandtab textwidth=1000

  # Fix to edit crontab files in place
  autocmd BufEnter crontab.* setlocal backupcopy=yes

  autocmd VimEnter * g:LspAddServer(lspServers)
  autocmd VimEnter * g:VimCompleteOptionsSet(vimcompleteOptions)
augroup END

augroup drewinglis_overlength
  autocmd!

  # Highlight lines that are too long.
  def OverLength(m: number): number
    if m > 0
      matchdelete(m)
    endif
    if &textwidth > 0
      var pattern = '\%' .. (&textwidth + 1)->string() .. 'v.\+'
      return matchadd('OverLength', pattern, 100)
    endif
    return 0
  enddef

  w:m = 0
  autocmd WinNew * w:m = 0
  autocmd FileType,BufEnter * w:m = OverLength(get(w:, 'm', 0))
augroup END
