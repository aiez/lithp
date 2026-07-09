# vim: ts=2 sw=2 sts=2 et :
include ../Makefile

DATA ?= ../../optimiz

holdouts: ## 20-holdout mean per $(DATA) csv, 10-way parallel
	@ls $(DATA)/*.csv | (gshuf 2>/dev/null || sort -R) | \
	 xargs -P 10 -I{} sbcl --script test_two.lisp \
	   --file {} --holdouts 2>/dev/null

deltas: ## rq2: active-vs-random win gap (0 = same), sorted
	@ls $(DATA)/*.csv | \
	 xargs -P 10 -I{} sbcl --script test_two.lisp \
	   --file {} --delta 2>/dev/null | sort -n

budgets: ## rq1: budget 200-vs-50 win gap (0 = same), sorted
	@ls $(DATA)/*.csv | \
	 xargs -P 10 -I{} sbcl --script test_two.lisp \
	   --file {} --budgets 2>/dev/null | sort -n
