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

# ---- tests: one UPPERCASE rule per mode; `test` discovers all -----
# strip wall-clock noise (e.g. "0.042 s -> 4.2 ms") so benchmark
# variants compare on deterministic content (tree count, etc.)
_scrub = sed -E 's/[0-9]+\.[0-9]+ s -> [0-9]+\.[0-9]+ ms//'

define _diff
sbcl --script to_small.lisp $(1) | $(_scrub) > /tmp/2small.out; \
for f in small fft yuck; do \
  sbcl --script $$f.lisp $(1) | $(_scrub) > /tmp/$$f.out; \
  diff -q /tmp/2small.out /tmp/$$f.out >/dev/null \
    && echo "  $$f SAME" || echo "  $$f DIFF"; done
endef

MAIN:  ## test: default mode, all variants byte-identical
	$(call need,sbcl,MAIN)
	@$(call _diff,)

GROWS: ## test: --grows mode, all variants byte-identical
	$(call need,sbcl,GROWS)
	@$(call _diff,--grows)

TREES: ## test: --trees mode, all variants byte-identical
	$(call need,sbcl,TREES)
	@$(call _diff,--trees)

test: ## run every UPPERCASE rule (= one test per mode)
	@gawk -F: '/^[A-Z][A-Z_]*:[^=]/ {print $$1}' $(MAKEFILE_LIST) | \
	  sort -u | while read t; do \
	    printf "\n=== %s ===\n" "$$t"; $(MAKE) -s $$t; done
