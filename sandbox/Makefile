# vim: ts=2 sw=2 sts=2 et :
include ../Makefile

DATA ?= ../../optimiz

tests: ## unit tests, sbcl only
	@sbcl --script ezr2.lisp --all

study: ## the four studies, default file, sbcl
	@sbcl --script ezr2.lisp --study

ezr2.fasl: ezr2.lisp ## compile for the big sweeps
	@sbcl --non-interactive \
	  --eval '(compile-file "ezr2.lisp")' >/dev/null

holdouts: ## 20-holdout mean per $(DATA) csv, 10-way parallel
	@ls $(DATA)/*.csv | (gshuf 2>/dev/null || sort -R) | \
	 xargs -P 10 -I{} sbcl --script ezr2.lisp \
	   --file {} --holdouts 2>/dev/null

deltas: ## rq2: active-vs-random win gap (0 = same), sorted
	@ls $(DATA)/*.csv | \
	 xargs -P 10 -I{} sbcl --script ezr2.lisp \
	   --file {} --delta 2>/dev/null | sort -n

budgets: ## rq1: budget 200-vs-50 win gap (0 = same), sorted
	@ls $(DATA)/*.csv | \
	 xargs -P 10 -I{} sbcl --script ezr2.lisp \
	   --file {} --budgets 2>/dev/null | sort -n
