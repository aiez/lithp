<!-- Copyright (c) 2026 Tim Menzies, MIT License https://opensource.org/licenses/MIT -->
<img xalign="right" src="https://img.shields.io/badge/Purpose-Tiny·Lisp·Dialect-7b68ee?logo=githubcopilot&logoColor=white" alt="Purpose"> <a href="https://timm.fyi"> <img xalign="right" src="https://img.shields.io/badge/Author-timm-dc143c?logo=readme&logoColor=white" alt="Author"></a> <img xalign="right" src="https://img.shields.io/badge/Language-Common%20Lisp-000080?logo=commonlisp&logoColor=white" alt="Language"><a href="https://choosealicense.com/licenses/mit/"> <img xalign="right" src="https://img.shields.io/badge/License-MIT-32cd32?logo=open-source-initiative&logoColor=white" alt="License"></a>

### [http://tiny.cc/lisp-plus](http://tiny.cc/lisp-plus)

<a href="http://tiny.cc/lisp-plus"><img align="right" src="https://tiny.cc/tiny/qr-image/tiny.cc~lisp-plus~l~150.png" alt="QR"></a>

`plus` is a **tiny Common Lisp dialect**: reader-macro anaphora,
Python-style `__init__` structs with methods, list comprehensions,
sequential bindings, lambda shortcuts, and a flag-dispatch CLI
framework — in `plus.lisp`. A companion `lib.lisp` ships the battery
(stats, reproducible random, list/string/CSV helpers). No deps; loads
into SBCL or CLISP.

```bash
git clone http://tiny.cc/lisp-plus && cd lisp-plus
sbcl --noinform --load plus.lisp --load lib.lisp   # load both
make run                             # same, via Makefile
make check                           # compile-file lint (plus, then lib)
```

Load order matters: `plus.lisp` first (it installs the `$`/`@` reader
macros and defines `let+`/`f+`), then `lib.lisp` (which uses them).

## NAME

    plus - tiny Common Lisp dialect (single-file, no deps)

## SYNOPSIS

    (load "plus")                ; macros + reader + CLI framework
    (load "lib")                 ; the battery (stats, csv, random...)
    (defvar *the* ...)           ; app config, read by @key
    (setf *seed* @seed)          ; seed the reproducible RNG
    ... define eg-- functions ...
    (cli *the*)                  ; walk argv, dispatch flags

## MACRO GRAPH

Node = macro. `→` = "expands into / depends on". Most macros are leaves
(expand straight to host Lisp); the arrows show the only inter-macro
edges plus the key runtime calls each macro emits.

    defread ── reader-macro installer
      ├─ $field   →  (slot-value i 'field)         ; i = self
      └─ @key     →  (second (assoc 'key *the*))    ; app config

    ?  if+  !            ── access / anaphora / call   (leaf)
    f+  ff+  fff+        ── lambda shortcuts (_ __ ___) (leaf)

    plus ── defstruct + methods
      ├─ → plus+          (forwards its method list)
      ├─ emits %make-NAME (private constructor)
      └─ emits  make-NAME (public ctor / __init__ hook)
    plus+ ── defmethod adder, methods dispatch on `i`  (leaf)
    new+  ── (new+ cls k v) → (make-cls k v)           (leaf)

    for+ ── list comprehension over `loop`             (leaf)
    let+ ── sequential bind (let / mvb / dbind / labels)
      └─ → let+          (recurses over remaining clauses)

    defeg ── defines eg--NAME (a CLI example)
      ├─ → let+
      ├─ calls read-csv   (battery)
      └─ calls make-data  (app struct)

## LANGUAGE REFERENCE

### Reader macros & anaphora

    $field        -> (slot-value i 'field)          ; i is self
    @key          -> (second (assoc 'key *the*))     ; config lookup
    (? x a b c)   -> nested slot-value chain
    (if+ t x y)   -> bind `it` to t's value in x/y
    (! f a b)     -> (funcall f a b)

### OO helpers

    (plus name [doc] slots (m args body)...)
        defstruct + a defmethod per method, each on `i`.
        Pseudo-methods (make works like Python __init__:
        body configures i, never returns it; plus does):
          (make () BODY...)        post-init; i auto-returned
          (make (ARGS) BODY...)    custom args; bind i in &aux
          (:opts ((opt ...) ...))  extra defstruct options
        Always adds (:constructor %make-NAME).
    (plus+ name (m args body)...)  add methods to a struct
    (new+ cls k v ...)             -> (make-cls k v ...)

### Lambda shortcuts

    (f+   body)  = (lambda (_)        body)
    (ff+  body)  = (lambda (_ __)     body)
    (fff+ body)  = (lambda (_ __ ___) body)

### List comprehension

    (for+ EXPR for var in lst [if TEST] ...)        ; nil results skipped
    (for+ (* x x) for x in '(1 2 3 4 5) if (oddp x)) ==> (1 9 25)

### Sequential bindings

    (let+ ((var val)         ; let
           ((a b) form)      ; multiple-value-bind (flat symbols)
           ((a (b c)) v)     ; destructuring-bind  (nested pattern)
           (name args body)) ; labels
      ...)
    Caveat: dbind on a flat-symbol pattern conflicts; use plain
    destructuring-bind in that case.

## BATTERY (lib.lisp)

    stats   adds sub dist sortby %extremum-by %stride
    random  rand rint shuffle          ; reproducible, seeded by *seed*
    chars   ch                         ; (ch s n c): is char n of s = c?
    strings cells thing read-csv

Lives in `lib.lisp`; load it after `plus.lisp`. `dist` uses the `@`
reader, `%extremum-by`/`%stride` use `let+`/`f+`, and the random
helpers share plus's `*seed*` — all defined in `plus.lisp`.

## CLI FRAMEWORK

    @key reads from *the* (the app must define it).
    defeg     define an eg--NAME example; binds rs + i (data)
    run       dispatch --flag to the EG-FLAG function
    cli       walk argv as (flag arg) pairs: dispatch or update *the*
    eg--all   run every eg-- function
    eg-s      set the seed

    Apps: (load "plus"), define *the*, (setf *seed* @seed),
    define eg-- functions, call (cli *the*).

## FILES

    plus.lisp        the dialect: reader macros, OO, CLI framework
    lib.lisp         battery: stats, random, list/string/CSV helpers
    Makefile         knobs + run/check; shared targets via $(KONFIG)
    ,lisp-plus.md    this help page

## SEE ALSO

    http://tiny.cc/luk       Lua sibling (.luk transpiler)
    http://tiny.cc/konfig    shared Makefile + shell config

## LICENSE

    MIT. (c) 2026 Tim Menzies.

## AUTHOR

    Tim Menzies <timm@ieee.org>
