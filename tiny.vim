" tiny.vim -- nvim support for the tiny.lisp dialect.
" Install: in init.vim/init.lua add
"   au FileType lisp source ~/gists/lisp-plus/tiny.vim
" Gives: highlight for tiny.lisp keywords, plus 2-space
" body indent (never align under the car symbol).

" ---- indent: always 2 past the enclosing paren ----
setlocal nolisp autoindent
setlocal indentexpr=TinyLispIndent(v:lnum)
" if ftplugin re-enables 'lisp', let indentexpr still win
if exists('+lispoptions')
  setlocal lispoptions=expr:1
endif

function! TinyLispIndent(ln) abort
  let save = getpos('.')
  call cursor(a:ln, 1)
  let [l, c] = searchpairpos('(', '', ')', 'bW',
        \ 'synIDattr(synID(line("."), col("."), 0), "name")'
        \ . ' =~? "string\\|comment"')
  call setpos('.', save)
  return l == 0 ? 0 : c + 1
endfunction

" ---- syntax: tiny.lisp keywords ----
" stock lisp syntax owns the inside of every (...) via
" contains= clusters, so our groups need containedin=
let s:in = 'containedin=ALLBUT,lispString,lispComment'
" definers: own color, distinct from stock lisp words
exe 'syn keyword tinyDef def def+' s:in
" other tiny macros: second color
exe 'syn keyword tinyMac let+ f_ ff_' s:in
exe 'syn match   tinyMac "(\@1<=[!?]\_s\@="' s:in
exe 'syn keyword tinyFun o ats keys cat prn least most' s:in
exe 'syn keyword tinyFun thing cells csv args cli' s:in
exe 'syn keyword tinyFun rand rint shuffle few' s:in
exe 'syn match   tinyAt  "[@$]\k\+"' s:in
exe 'syn match   tinyBrk "[{}]"' s:in

" tiny keywords: muted teal (definers bold, macros plain)
hi tinyDef ctermfg=73 guifg=#5fafaf cterm=bold gui=bold
hi tinyMac ctermfg=73 guifg=#5fafaf
hi def link tinyFun Function
hi def link tinyAt  Identifier
hi def link tinyBrk Delimiter
