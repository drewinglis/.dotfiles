execute pathogen#infect()

" most of this stolen from: http://mislav.uniqpath.com/2011/12/vim-revisited/
set nocompatible                " choose no compatibility with legacy vi
syntax enable
set encoding=utf-8
set showcmd                     " display incomplete commands
filetype plugin indent on       " load file type plugins + indentation

"" Whitespace
" set nowrap                      " don't wrap lines
set tabstop=2 shiftwidth=2      " a tab is two spaces (or set this to 4)
set expandtab                   " use spaces, not tabs (optional)
set backspace=indent,eol,start  " backspace through everything in insert mode

"" Searching
set hlsearch                    " highlight matches
set incsearch                   " incremental searching
set ignorecase                  " searches are case insensitive...
set smartcase                   " ... unless they contain at least one capital letter
" end stolen block

set number

" remove all whitespace at the end of lines
autocmd BufWritePre * :%s/\s\+$//e

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

" function to test-var the current toplevel form (vim-fireplace
" doesn't yet have good built-in clojure.test support)
function! TestToplevel() abort
        "Eval the toplevel clojure form (a deftest) and then test-var the
        "result."
        normal! ^
        let line1 = searchpair('(','',')', 'bcrn', g:fireplace#skip)
        let line2 = searchpair('(','',')', 'rn', g:fireplace#skip)
        let expr = join(getline(line1, line2), "\n")
        let var = fireplace#session_eval(expr)
        let result =
fireplace#echo_session_eval("(clojure.test/test-var " . var . ")")
        return result
endfunction
