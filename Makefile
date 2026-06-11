# vim: ts=2 sw=2 sts=2 et :
# knobs only; shared targets live in $(KONFIG)/Makefile
KONFIG ?= ../konfig

APP   := lisp-
MAIN  := fft.lisp
EXT   := lisp
LANG  := lisp
LINT  := sbcl --noinform --disable-debugger \
           --eval '(handler-bind ((warning (function muffle-warning))) \
                     (compile-file "lib-.lisp"))' \
           --quit
TOOLS := sbcl:run-lisp
PKG   := sbcl gawk neovim tmux

$(KONFIG)/Makefile:
	@test -f $@ || { echo "missing konfig: git clone http://tiny.cc/konfig $(KONFIG)"; exit 1; }
-include $(KONFIG)/Makefile

# ---- run: the ablation suite --------------------------------------
run: ## run the sweet-spot version
	$(call need,sbcl,run)
	@sbcl --script fft.lisp

check: ## all four versions must print byte-identical output
	$(call need,sbcl,check)
	@sbcl --script to_small.lisp > /tmp/2small.out
	@for f in small fft yuck; do \
	   sbcl --script $$f.lisp > /tmp/$$f.out; \
	   diff -q /tmp/2small.out /tmp/$$f.out >/dev/null \
	     && echo "$$f SAME" || echo "$$f DIFF"; done
