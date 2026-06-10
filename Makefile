# vim: ts=2 sw=2 sts=2 et :
# knobs only; shared targets live in $(KONFIG)/Makefile
KONFIG ?= ../konfig

APP   := plus
MAIN  := plus.lisp
EXT   := lisp
LANG  := lisp
# lib.lisp uses plus's @ reader + let+/f+ macros, so load plus
# before compiling lib.
LINT  := sbcl --noinform --disable-debugger \
           --eval '(handler-bind ((warning (function muffle-warning))) \
                     (compile-file "plus.lisp") (load "plus.lisp") \
                     (compile-file "lib.lisp"))' \
           --quit
TOOLS := sbcl:run-lisp
PKG   := sbcl gawk neovim tmux

$(KONFIG)/Makefile:
	@test -f $@ || { echo "missing konfig: git clone http://tiny.cc/konfig $(KONFIG)"; exit 1; }
-include $(KONFIG)/Makefile

# ---- run: load plus.lisp into an SBCL repl ------------------------
run: ## load plus.lisp + lib.lisp into an interactive SBCL repl
	$(call need,sbcl,run)
	@sbcl --noinform --load plus.lisp --load lib.lisp

# ---- pdf: color via our plus.ssh ----------------------------------
# a2ps auto-maps *.lisp -> clisp; pretty-print=plus loads our sheet
# (clisp + $field/@key/plus-macro highlighting). Dense 3-col, width-
# filled layout (xfun-style) so the page looks packed, not washed-out.
Cols   ?= 3
Cpl    ?= 90
Orient ?= landscape

~/tmp/%.pdf : %.lisp plus.ssh ## colorful lisp pdf (a2ps + plus.ssh)
	$(call need,a2ps,pdf)
	$(call need,ps2pdf,pdf)
	@mkdir -p ~/tmp
	@echo "pdfing : $@ ..."
	@D=$$(mktemp -d); trap "rm -rf $$D" EXIT; \
	 mkdir -p $$D/.a2ps; cp plus.ssh $$D/.a2ps/plus.ssh; \
	 HOME=$$D a2ps -Br --$(Orient) --line-numbers=1 \
	   -borders=no --pro=color \
	   --file-align=fill --chars-per-line=$(Cpl) \
	   --right-footer="" --left-footer="$<" \
	   --footer="page %p." -M letter \
	   --columns $(Cols) -o - $< | ps2pdf - $@
	@$(OPEN) $@
