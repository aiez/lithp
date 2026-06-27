<!-- Copyright (c) 2026 Tim Menzies, MIT License https://opensource.org/licenses/MIT -->
<img src="https://img.shields.io/badge/Purpose-Succinct·Lisp-7b68ee?logo=githubcopilot&logoColor=white" alt="Purpose"> <a href="https://timm.fyi"> <img src="https://img.shields.io/badge/Author-timm-dc143c?logo=readme&logoColor=white" alt="Author"></a> <img src="https://img.shields.io/badge/Language-Common%20Lisp-000080?logo=commonlisp&logoColor=white" alt="Language"><a href="https://choosealicense.com/licenses/mit/"> <img src="https://img.shields.io/badge/License-MIT-32cd32?logo=open-source-initiative&logoColor=white" alt="License"></a>

### [https://github.com/aiez/lithp](https://github.com/aiez/lithp)

<a href="https://github.com/aiez/lithp"><img align="right" src="https://tiny.cc/tiny/qr-image/tiny.cc~lithp~l~150.png" alt="QR"></a>

`lithp` is **less library**: the smallest set of Common Lisp
add-ons that measurably shrinks application code — five plain
constructs plus a handful of utilities, ~130 lines total, no
reader macros, no dependencies. Found by ablation: we wrote
the same machine-learner four ways and kept only what paid
rent. **The why, the data, and the style rules are in
 [blog.md](https://gist.github.com/timm/729164d89ae32ca4b6a83483be9e761b#file-blog-md)** — this file is just the manual.

```bash
git clone https://github.com/aiez/optimiz # access test data
git clone https://github.com/aiez/lithp && cd lithp
sbcl --script fft.lisp          # the sweet-spot version
sbcl --script fft.lisp --trees  # show all grown trees
sbcl --script fft.lisp --grows  # timing benchmark
```

**Sections:** [NAME](#name) | [SYNOPSIS](#synopsis) | [KIT](#the-kit-five-constructs) | [UTILITIES](#utilities) | [FILES](#files) | [LICENSE](#license)

**Files:** [lithp.lisp](https://github.com/aiez/lithp#file-lithp-lisp) | [blog.md](https://github.com/aiez/lithp#file-blog-md) | [fft.lisp](https://github.com/aiez/lithp#file-fft-lisp) | [small.lisp](https://github.com/aiez/lithp#file-small-lisp) | [to_small.lisp](https://github.com/aiez/lithp#file-to_small-lisp) | [yuck.lisp](https://github.com/aiez/lithp#file-yuck-lisp) | [tiny.lisp](https://github.com/aiez/lithp#file-tiny-lisp) | [tiny.vim](https://github.com/aiez/lithp#file-tiny-vim) | [Makefile](https://github.com/aiez/lithp#file-makefile)

## NAME

    lithp — less library: the pay-rent subset (130 lines, no deps)

## SYNOPSIS

    (load "lithp.lisp")
    (defvar *settings* '((seed . 1234567891) (file . "data.csv")))
    (defmacro my (k) `(cdr (assoc ',k *settings*)))
    (cli *settings*)                ; -s 42 on argv updates seed
    (setf *seed* (my seed))

## THE KIT (five constructs)

| form | meaning |
|------|---------|
| `(fn expr)`  | variadic lambda; refer to args as `$1`..`$9` as used |
| `(? x a b)`  | quoted-key chained access: `(ats (ats x 'a) 'b)` |
| `(let+ (...) ...)` | one binder: `(x 1)` let, `((a b) lst)` destructure, `(f (z) ...)` local fn |
| `(o 'k1 v1 'k2 v2)` | build equal-hash record |
| `(ats x k)`  | read hash *or* struct slot uniformly; setf-able |

Plus `(keys h)` — list of hash keys.

## UTILITIES

| group | functions |
|-------|-----------|
| print  | `(cat ...)` strings together; `(prn fmt args...)` format + newline |
| pick   | `(least lst f)` / `(most lst f)` — min/max by key fn |
| parse  | `(thing s)` string→number/symbol; `(cells s)` split csv line; `(csv file)` rows of things |
| cli    | `(args)` argv; `(cli alist)` `-x val` sets first-char-matching key |
| random | `(rand n)` `(rint n)` `(shuffle lst)` `(few lst n)` — seeded Park-Miller (`*seed*`), reproducible across languages |

## FILES

| file | what |
|------|------|
| `lithp.lisp`      | this library |
| `blog.md`        | the ablation study: why these and only these |
| `yuck.lisp`     | naive CLOS port, 605 lines — the cautionary tale |
| `small.lisp`    | plain ANSI CL, design only, 261 lines |
| `fft.lisp`      | + the kit, 240 lines — **the sweet spot** |
| `to_small.lisp` | + reader macros via `tiny.lisp`, 214 lines — fun, not leverage |
| `tiny.lisp` / `tiny.vim` | the full dialect and its required editor support |

All four programs (`fft`, `small`, `to_small`, `yuck`) produce byte-identical output
(same seeded RNG as the Python original they port).

## LICENSE

MIT. (c) 2026 Tim Menzies, timm@ieee.org
