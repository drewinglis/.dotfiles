function! StripClojureNamespace(word)
  return (split(a:word, '/')[-1])
endfunction

nnoremap <C-]> :exe ":tag ".StripClojureNamespace(expand("<cword>"))<CR>
