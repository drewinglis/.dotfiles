" change md filetype to markdown
augroup filetypedetect
  autocmd BufNew,BufNewFile,BufRead *.md,*.markdown :setfiletype markdown
augroup END
