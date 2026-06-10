# Writing Succinct Lisp: an Ablation Study

<a href="http://tiny.cc/lisp-"><img align="right"
src="https://tiny.cc/tiny/qr-image/tiny.cc~lisp-~l~150.png"
alt="QR: tiny.cc/lisp-"></a>

 
One sunny day, me and claude-fable-5 went for a walk.    
This is what we found. -- Tim Menzies  (timm@ieee.org)

## Motivation: Just Enough LISP

`fft.py` is 235 lines of Python: fast-frugal trees for
multi-objective optimization (Welford stats, entropy-free
discretization, tree growing, d2h scoring). Python is the
brevity benchmark. Question: can Common Lisp beat it —
and if so, how much of the win comes from *clever macros*
versus *just writing Lisp in a smart way*?

So we built four Lisp versions of the same program, all
producing **byte-identical output** with the Python
(same seeded Park-Miller RNG in both languages, so even
the random demos match):

| file            | LOC | lib LOC | chars | dialect |
|-----------------|-----|---------|-------|---------|
| fft-yuck.lisp   | 605 | 0       | 21646 | naive CLOS port, no style guide |
| fft.py          | 235 | 0       | 6876  | python  |
| fft-small.lisp  | 261 | 130     | 8502  | plain ANSI CL (lib- utils only, no kit) |
| fft-nice.lisp   | 240 | 130     | 7608  | + 6 plain constructs (lib-.lisp) |
| fft-2small.lisp | 214 | 165     | 6875  | + reader macros (tiny.lisp) |

(*lib LOC* = required support library: lib-.lisp for
small and nice; tiny.lisp for 2small. Yuck and the Python
are self-contained.)

Runtime: sbcl 109 ms vs python 178 ms wall; 4.2 ms vs 6.3
ms per tree-growing round. **The sugar costs nothing at
runtime** — macros expand away.

## Yuck: why style guides matter

First, honesty about the bottom line: only the full
reader-macro dialect beats Python (214 vs 235), and that
is the version we end up not recommending. The sweet
spot, fft-nice, is five lines *longer* than the Python (plus some support code, which is a fair comparison since our Python system made extensive use of Python's stdlib).
The interesting number is not down there — it is the top
row. `fft-yuck.lisp` is the port an LLM (or a
diligent newcomer) writes with no style guide: full CLOS
ceremony, `:documentation` on every slot, `with-slots`,
descriptive-novel names, plist tree nodes read with
`getf`, push-then-`nreverse` everywhere, a docstring per
function. Same algorithm, same seed, same output — at
**2.6× the size of the Python** (605 lines vs 235).

One function, yuck vs tiny:

```lisp
(defun update-with-welford (column value &optional (weight 1))
  "Update COLUMN's running statistics with VALUE."
  (with-slots (item-count mean-value m2-value) column
    (incf item-count weight)
    (if (< item-count 1)
        (make-numeric-column)
        (let ((delta (- value mean-value)))
          (incf mean-value
                (/ (* weight delta) item-count))
          (incf m2-value
                (* weight delta (- value mean-value)))
          column))))
```
Too much (note the trick dollar read macros):
```lisp
(def welford (i v &optional (w 1))
  (incf $n w)
  (if (< $n 1) (num)
      (let ((d (- v $mu)))
        (incf $mu (/ (* w d) $n))
        (incf $m2 (* w d (- v $mu))) i)))
```
Just right (everything here is standard lisp):
```lisp
defun welford (i v &optional (w 1))
  (incf (n i) w)
  (if (< (n i) 1) (num)
      (let ((d (- v (mu i))))
        (incf (mu i) (/ (* w d) (n i)))
        (incf (m2 i) (* w d (- v (mu i)))) i)))
```

Nothing below is about golfing yuck into tiny. It is
about the 344 lines between yuck and small — the gap
closed
by *design choices alone*, before a single macro.

## What mattered most (ranked)

### 1. Design, not macros (~80% of the win)

We found that most of the win came from better use of
Lisp built-ins, not clever macros. The small version is
already competitive with Python because it inherits
design choices found while building 2small. All
plain ANSI CL:

- **Polymorphism over if-ladders.** Dispatch `defmethod`
  on built-in types — `hash-table` vs `num` struct vs
  `symbol`/`string`/`number`:

  ```lisp
  (defmethod has ((v symbol) lo hi) t)
  (defmethod has ((v string) lo hi) (equal v lo))
  (defmethod has ((v number) lo hi) (<= lo v hi))
  ```

- **Bare accessors + BOA constructors.** `(:conc-name)`
  gives `(n i)` not `(num-n i)`; a positional constructor
  reads like math:

  ```lisp
  (defstruct (num (:conc-name) (:constructor num
                (&optional (n 0) (mu 0.0) (m2 0.0))))
    n mu m2)
  ```

- **Hash-as-record** for heterogeneous things (tree
  nodes); structs for hot numeric records.

- **Slot defaults, not constructor noise.**
  `(goal (o)) (cols (o))` in the defstruct, not
  `:goal (o) :cols (o)` at every call.

- **Mutate-in-place adders.** `add` updates its column and
  the caller never writes `(setf x (add x v))`:

  ```lisp
  (dolist (row $rows i)
    (loop for v in row for at from 0
          do (add (ats $cols at) v)))
  ```

- **Data tables, not parallel lists.**

  ```lisp
  (loop for (bit pick) in `((0 ,#'least) (1 ,#'most)) ...)
  ```

- **`loop` destructuring and `collect ... into`** — never
  build a list backwards then reverse it ("no reverse to
  repair").

- **Delete guards the domain makes dead.** Goal columns
  are always present, so `disty` needs no `?` filter and
  no empty-list check.

### 2. A minimal kit (~half the remaining win)

Six plain constructs — no reader macros — close half the
gap to the full dialect (261 → 240 LOC, 8502 → 7608
chars). They fix Common Lisp's two genuine warts:

- **lambda noise**: `(f_ (mu (fourth _)))` instead of
  `(lambda (c) (mu (fourth c)))`. Biggest LOC win, since
  each avoided wrap is a saved line.
- **gethash noise**: `(o 'at at 'lo lo)` builds a record;
  `(ats h k)` reads hash *or* struct uniformly;
  `(? tr at)` for quoted-key access.
- plus `let+` (let / destructure / local fn in one form)
  and a 1-line app macro `(my k)` for settings.

This is `lib-.lisp` (full listing below).

### 3. Reader macros (the last ~10%, the most magic)

`$slot` → `(ats i 'slot)`, `@key` → settings, `{k v}`
hash literals. Forty uses of `$` buy real density:

```lisp
(def welford (i v &optional (w 1))      ; full dialect
  (incf $n w)
  (let ((d (- v $mu)))
    (incf $mu (/ (* w d) $n))
    (incf $m2 (* w d (- v $mu))) i))
```

But each is invisible convention (`$` assumes self is
named `i`). And `$` mostly duplicates wins you already
have: struct slots are short via `(:conc-name)` — `(n i)`
— and hash keys are short via `(? i at)`. Worse, new
read syntax breaks the toolchain: editors don't know
`{...}` or `$slot`, so the dialect ships with its own
`tiny.vim` just to highlight correctly. Honest verdict
from the ablation: reader macros are a bridge too far —
**high conceptual tax, marginal wc**. Keep them for
love, not leverage.

## Rules of the house

1. Every line < 65 chars. Many short functions.
2. The Lisp must end up *shorter than the Python*.
   (Achieved only by the reader-macro version; played
   straight, we land five lines behind.)
3. Blank line before each definition, except methods of
   the same generic, which may sit adjacent.
4. No build-then-reverse. No dead guards. No defclass
   ("too verbose") — defstruct + defmethod.
5. After **every** edit: run, and diff output against the
   Python. Byte-identical or it didn't happen.

## How to redo this (instructions to a future LLM)

1. Port function-by-function, keeping the Python's names
   and file order. One short Lisp function per Python
   method.
2. Implement the same seeded LCG
   (`seed = 16807*seed mod 2^31-1`) so outputs diff
   cleanly across languages.
3. Get plain CL working and verified first. Sugar later.
4. Add a construct only when it removes lines from the
   app *today*. Measure with `wc` after every change.
5. When tempted by a macro, try a design fix first:
   dispatch, slot default, mutate-in-place, data table.
6. Keep an ablation file (`fft-small.lisp`) so every
   macro must keep justifying its existence.

## One sample, three ways

Tree-node prediction. Plain CL:

```lisp
(defmethod predict ((i hash-table) row)
  (predict (if (has (nth (gethash 'at i) row)
                    (gethash 'lo i) (gethash 'hi i))
               (gethash 'left i)
               (gethash 'right i))
           row))
```

With the kit:

```lisp
(defmethod predict ((i hash-table) row)
  (predict (if (has (nth (? i at) row)
                    (? i lo) (? i hi))
               (? i left)
               (? i right))
           row))
```

Full dialect. Note that dollar signs that expland into `(slot-value i x)`. Cute... but ultimately not worth it.

```lisp
(def+ predict ((i hash-table) row)
  (predict (if (has (nth $at row) $lo $hi) $left $right)
           row))
```

Pick your point on that curve. The data says the middle
one is where the leverage lives; the last one is where
the fun lives.

## The moral

Read the first table top to bottom: 605 lines of naive
CL, 261 of well-designed CL, 240 with six plain macros,
214 with a custom reader. Each step costs more and buys
less. Design is free and saved 344 lines. The kit is
cheap — six ordinary macros, no new syntax — and saved
21. The reader macros saved 26 more but demand new
reading conventions, an invisible `$`-means-`i` rule,
and editor support that plain Lisp gets for free.

And note what that means for the original bet: the only
version shorter than the Python is the one whose syntax
we just disowned. Played straight — no reader magic —
Lisp lands five lines behind Python, twice as fast.

So: a few macros are genuinely useful. More hit
diminishing returns fast. You can get away with not
much — and mostly, you should.

## Appendix: lib-.lisp (the pay-rent subset, 130 lines)

```lisp
; lib-.lisp -- the pay-rent subset of tiny.lisp.
; Kit (no reader macros):
;   (f_ ...) (ff_ ...)   lambda of _, of _ __
;   (? x a b)            quoted-key chained access
;   (let+ ((x 1)                    var
;          ((a b) lst)              destructure
;          (f (z) (* z 2))) ...)    local function
;   o ats keys           hash-as-record (structs too)
; General utils:
;   cat prn least most
;   thing cells csv
;   args cli
;   rand rint shuffle few

#+sbcl (declaim (sb-ext:muffle-conditions
                  warning style-warning))
(setf *read-default-float-format* 'double-float)

(defvar *seed* 1234567891)

;;; ----- the kit ----------------------------------------------
(defmacro f_ (&body b)
  `(lambda (_) (declare (ignorable _)) ,@b))

(defmacro ff_ (&body b)
  `(lambda (_ __) (declare (ignorable _ __)) ,@b))

(defmacro ? (x k &rest ks)
  (if ks `(? (ats ,x ',k) ,@ks) `(ats ,x ',k)))

(defmacro let+ ((b &rest bs) &body body)
  (let ((tail (if bs `((let+ ,bs ,@body)) body)))
    (cond ((consp (first b))
           `(destructuring-bind ,(first b) ,(second b)
              ,@tail))
          ((cddr b)
           `(labels ((,(first b) ,@(rest b))) ,@tail))
          (t
           `(let ((,(first b) ,(second b))) ,@tail)))))

(defun o (&rest kvs)
  (let ((h (make-hash-table :test #'equal)))
    (loop for (k v) on kvs by #'cddr
          do (setf (gethash k h) v))
    h))

(defun ats (x k &optional d)
  (if (hash-table-p x) (gethash k x d) (slot-value x k)))

(defun (setf ats) (v x k &optional d)
  (declare (ignore d))
  (if (hash-table-p x)
      (setf (gethash k x) v)
      (setf (slot-value x k) v)))

(defun keys (h)
  (loop for k being the hash-keys of h collect k))

;;; ----- little things ----------------------------------------
(defun cat (&rest l) (format nil "~{~a~}" l))

(defun prn (f &rest a) (format t "~?~%" f a))

(defun least (l f)
  (reduce (ff_ (if (<= (funcall f _) (funcall f __))
                   _ __))
          l))

(defun most (l f)
  (reduce (ff_ (if (>= (funcall f _) (funcall f __))
                   _ __))
          l))

;;; ----- strings to things ------------------------------------
(defun thing (s)
  (let ((s (string-trim " " s)))
    (cond ((equal s "?")     '?)
          ((equal s "True")  t)
          ((equal s "False") nil)
          (t (multiple-value-bind (x n)
                 (let ((*read-eval* nil))
                   (read-from-string s nil))
               (if (and (numberp x) (= n (length s)))
                   x
                   s))))))

(defun cells (s)
  (loop for a = 0 then (1+ b)
        for b = (position #\, s :start a)
        collect (string-trim " " (subseq s a b))
        while b))

(defun csv (file)
  (with-open-file (in file)
    (loop for ln = (read-line in nil)
          while ln
          for l = (string-trim '(#\space #\tab #\return)
                               ln)
          unless (or (equal l "")
                     (eql (char l 0) #\#))
          collect (mapcar #'thing (cells l)))))

;;; ----- cli ---------------------------------------------------
(defun args ()
  #+sbcl (cdr sb-ext:*posix-argv*)
  #+clisp ext:*args*)

(defun cli (lst)
  (loop for (f v) on (args) do
    (dolist (kv lst)
      (when (equal f (cat "-" (char (string-downcase
                                      (car kv)) 0)))
        (setf (cdr kv) (thing v))))))

;;; ----- random ------------------------------------------------
(defun rand (&optional (n 1))
  (setf *seed* (mod (* 16807 *seed*) 2147483647))
  (* n (/ *seed* 2147483647.0)))

(defun rint (&optional (n 2)) (floor (rand n)))

(defun shuffle (l)
  (let ((v (coerce l 'vector)))
    (loop for i from (1- (length v)) downto 1
          do (rotatef (aref v i) (aref v (rint (1+ i)))))
    (coerce v 'list)))

(defun few (l n) (subseq (shuffle l) 0 n))
```
