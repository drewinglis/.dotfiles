augroup drewinglis_ftdetect_rcfiles
  autocmd!
  autocmd BufRead,BufNewFile *aliasrc set filetype=sh
  autocmd BufRead,BufNewFile *commonshellrc set filetype=sh
  autocmd BufRead,BufNewFile *ctags set filetype=sh
  autocmd BufRead,BufNewFile *exportrc set filetype=sh
augroup END
