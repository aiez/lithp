; fft.scm -- Fast-and-Frugal Trees, rebuilt on the claim
; that data mining is four verbs over a column monoid:
;   fold  build a summary / score / total   (accumulate)
;   keep  select the rows a cut admits      (filter)
;   arg   pick the extreme cut / tree        (argmin/argmax)
;   label tag each thing: value->bin, row->y, row->leaf (map)
; A column is not a struct you type-test; it is a monoid
; (empty+add+merge) that answers messages. No dispatch.
; Same output as fft.lisp -- the algebra changed, not math.
; (c) 2026 Tim Menzies timm@ieee.org, MIT license.
(import (scheme base) (scheme file) (scheme write)
        (scheme inexact) (scheme process-context)
        (scheme char) (scheme cxr) (srfi 69) (srfi 1))

;;; ===== the four verbs =======================================
(define (fold f a xs)                   ; the only loop we keep
  (if (null? xs) a (fold f (f (car xs) a) (cdr xs))))
(define (keep p xs) (filter p xs))      ; select
(define (label f xs) (map f xs))        ; tag each
(define (arg ok? key xs)                ; extreme by key
  (fold (lambda (x b) (if (ok? (key b) (key x)) b x))
        (car xs) (cdr xs)))
(define (arg-min key xs) (arg <= key xs))
(define (arg-max key xs) (arg >= key xs))

;;; ===== a column is a monoid that answers messages ===========
;; Num: online Welford. add mutates & returns self (so it folds);
;; merge is the monoid combine (parallel-variance), returns new.
(define (num-from n mu m2)
  (define (sd) (if (< n 2) 0 (sqrt (/ (max 0 m2) (- n 1)))))
  (define (norm v)
    (let ((z (/ (- v mu) (+ (sd) 1e-32))))
      (/ 1 (+ 1 (exp (* -1.7 (max -3 (min 3 z))))))))
  (lambda (m . a)
    (case m
      ((kind) 'num)  ((n) n)  ((mid) mu)
      ((norm) (norm (car a)))
      ((bin)  (exact (floor (* (my 'bins) (norm (car a))))))
      ((top)  (let ((old (cadr a)) (v (car a)))  ; keep arg, no coercion
                (cond ((not old) v) ((> v old) v) (else old))))
      ((stats) (list n mu m2))
      ((add)
       (let ((v (car a)))
         (if (eq? v '?) (num-from n mu m2)
             (let* ((n1 (+ n 1)) (d (- v mu))
                    (mu1 (+ mu (/ d n1))))
               (num-from n1 mu1 (+ m2 (* d (- v mu1))))))))
      ((merge)
       (let* ((s ((car a) 'stats)) (on (car s)) (omu (cadr s))
              (om2 (caddr s)) (k (+ n on)) (d (- omu mu)))
         (if (< k 1) (Num)
             (num-from k (/ (+ (* n mu) (* on omu)) k)
                       (+ m2 om2 (/ (* d d n on) k)))))))))
(define (Num) (num-from 0 0.0 0.0))

;; Sym: categorical x-column. Only ever asked to bin/top a value.
(define (Sym)
  (lambda (m . a)
    (case m
      ((kind) 'sym) ((add) (Sym))
      ((bin) (car a)) ((top) (car a)))))

;; A value satisfies a cut's [lo,hi] window (select predicate).
(define (within v lo hi)
  (cond ((symbol? v) #t)
        ((string? v) (equal? v lo))
        (else (<= lo v hi))))

;;; ===== a table: names + columns; rows fold into columns =====
(define-record-type Table (table names cols xs ys goal rows) tbl?
  (names t-names) (cols t-cols) (xs t-xs) (ys t-ys)
  (goal t-goal) (rows t-rows))

(define (col t at) (list-ref (t-cols t) at))

(define (read-table src)
  (let* ((names (car src)) (rows (cdr src))
         (cols (label (lambda (s)
                        (if (char-lower-case? (string-ref s 0))
                            (Sym) (Num))) names))
         (goal (make-hash-table eqv?)) (xs '()) (ys '()))
    (for-each
      (lambda (at s)
        (let ((z (string-ref s (- (string-length s) 1))))
          (cond ((memv z '(#\- #\+ #\!))
                 (hash-table-set! goal at (if (char=? z #\+) 1 0))
                 (set! ys (cons at ys)))
                ((not (char=? z #\X)) (set! xs (cons at xs))))))
      (iota (length names)) names)
    ;; the load itself is a fold of rows through the columns
    (table names
           (fold (lambda (row cs)
                   (map (lambda (c v) (c 'add v)) cs row))
                 cols rows)
           (reverse xs) (reverse ys) goal rows)))

;; distance-to-heaven: label a row with its goal distance
(define (disty t row)
  (mink (label (lambda (a)
                 (- ((col t a) 'norm (list-ref row a))
                    (hash-table-ref (t-goal t) a)))
               (t-ys t))))

;;; ===== cuts: a cut is a window + the y-summary it would make =
(define-record-type Cut (cut at lo hi y) cut?
  (at cut-at) (lo cut-lo) (hi cut-hi) (y cut-y))

(define (cuts t y)                      ; all candidate cuts
  (append-map (lambda (at) (col-cuts t at y)) (t-xs t)))

(define (col-cuts t at y)
  (let ((c (col t at)) (bins (o)) (hi (o)))
    ;; fold each row's y into the bin its x-value labels
    (for-each
      (lambda (row)
        (let ((v (list-ref row at)))
          (unless (eq? v '?)
            (let ((k (c 'bin v)))
              (ats! bins k ((or (ats bins k) (Num)) 'add (y row)))
              (ats! hi k (c 'top v (ats hi k)))))))
      (t-rows t))
    (if (eq? (c 'kind) 'sym)
        ;; categorical: one cut per value
        (label (lambda (k) (cut at (ats hi k) (ats hi k) (ats bins k)))
               (keys bins))
        ;; numeric: running merge gives "<= hi" thresholds
        (let ((l (Num)))
          (label (lambda (k)
                   (set! l (l 'merge (ats bins k)))
                   (cut at (- big) (ats hi k) l))
                 (drop-right (sorted (keys bins) <) 1))))))

;;; ===== grow: select rows by the best cut, recurse ===========
(define (splits t y root)
  (let* ((enough (expt (length (t-rows root)) .33))
         (cs (keep (lambda (k) (> ((cut-y k) 'n) enough))
                   (cuts t y))))
    (if (null? cs) '()
        (append-map
          (lambda (bit+arg)
            (let* ((bit (car bit+arg))
                   (best ((cadr bit+arg)
                            (lambda (k) ((cut-y k) 'mid)) cs))
                   (rest (keep (lambda (r)
                                 (not (within (list-ref r (cut-at best))
                                              (cut-lo best) (cut-hi best))))
                               (t-rows t))))
              (if (null? rest) '() (list (list bit best rest)))))
          (list (list "0" arg-min) (list "1" arg-max))))))

(define-record-type Node (node* at lo hi left right) node?
  (at n-at) (lo n-lo) (hi n-hi) (left n-left) (right n-right))
(define (node k right)                  ; a Cut + its right subtree
  (node* (cut-at k) (cut-lo k) (cut-hi k) (cut-y k) right))

(define (leaf t y)                      ; fold all y's into one Num
  (fold (lambda (r c) (c 'add (y r))) (Num) (t-rows t)))

(define (grow t y root d)               ; -> list of (bias . tree)
  (or (and (< d (my 'depth))
           (let ((sp (splits t y root)))
             (and (pair? sp)
               (append-map
                 (lambda (s)
                   (let* ((bit (car s)) (best (cadr s))
                          (kid (read-table (cons (t-names t) (caddr s)))))
                     (label (lambda (b)
                              (cons (string-append bit (car b))
                                    (node best (cdr b))))
                            (grow kid y root (+ d 1)))))
                 sp))))
      (list (cons "" (leaf t y)))))

;;; ===== use: predict, rank trees by error, show ==============
(define (predict tr row)
  (if (node? tr)
      (predict (if (within (list-ref row (n-at tr))
                           (n-lo tr) (n-hi tr))
                   (n-left tr) (n-right tr)) row)
      (tr 'mid)))

(define (err tr t y)
  (/ (fold + 0 (label (lambda (r) (abs (- (y r) (predict tr r))))
                      (t-rows t)))
     (length (t-rows t))))
(define (tune trees t y) (arg-min (lambda (tr) (err tr t y)) trees))

(define (rule t tr)
  (let ((s (list-ref (t-names t) (n-at tr)))
        (lo (n-lo tr)) (hi (n-hi tr)))
    (cond ((equal? lo hi) (cat s " == " lo))
          ((= lo (- big)) (cat s " <= " hi))
          (else           (cat s " >= " lo)))))

(define (show t tr)
  (if (node? tr)
      (let ((l (n-left tr)))
        (display (cat "if " (pad (rule t tr) 30) " then d2h "
                      (dec (l 'mid) 2) " n=" (l 'n) "\n"))
        (show t (n-right tr)))
      (display (cat (pad "" 33) " leaf  d2h " (dec (tr 'mid) 2)
                    " n=" (tr 'n) "\n"))))

(define (eg-main)
  (let* ((t (read-table (csv (my 'file))))
         (y (lambda (r) (disty t r)))
         (trees (label cdr (grow t y t 0))))
    (show t (tune trees t y))))

(define (eg-trees)
  (let* ((t (read-table (csv (my 'file))))
         (y (lambda (r) (disty t r))))
    (for-each
      (lambda (b+tr k)
        (display (cat "===== tree " (lpad k 2) "   bias "
                      (pad (car b+tr) 5) "   err "
                      (dec (err (cdr b+tr) t y) 3) " =====\n"))
        (show t (cdr b+tr)) (newline))
      (grow t y t 0) (iota 999 1))))

;;; ===== plumbing (the unglamorous half of any port) ==========
(define big 1e32)
(define (mink xs)
  (let ((p (my 'p)) (n (length xs)))
    (expt (/ (fold + 0 (label (lambda (x) (expt (abs x) p)) xs)) n)
          (/ 1.0 p))))
(define (sorted xs <?)                  ; insertion sort, tiny n
  (if (null? xs) xs
      (let ins ((x (car xs)) (r (sorted (cdr xs) <?)))
        (cond ((null? r) (list x)) ((<? x (car r)) (cons x r))
              (else (cons (car r) (ins x (cdr r))))))))
;; o/ats: a hash used as a record
(define (o . kv)
  (let ((h (make-hash-table equal?)))
    (let lp ((kv kv))
      (if (null? kv) h
          (begin (hash-table-set! h (car kv) (cadr kv))
                 (lp (cddr kv)))))))
(define (ats x k . d)
  (hash-table-ref x k (lambda () (if (null? d) #f (car d)))))
(define (ats! x k v) (hash-table-set! x k v))
(define (keys h) (hash-table-keys h))
(define (cat . l) (apply string-append (label ->str l)))
(define (->str x)
  (cond ((string? x) x) ((symbol? x) (symbol->string x))
        ((number? x) (number->string x)) ((char? x) (string x))
        ((eq? x #t) "True") ((eq? x #f) "False") (else "?")))
(define (dec x places)                  ; fixed-point string
  (let* ((neg (< x 0)) (x (abs x)) (s (expt 10 places))
         (z (exact (round (* x s)))) (i (quotient z s))
         (f (modulo z s)) (fs (->str f)))
    (cat (if neg "-" "") i "."
         (make-string (- places (string-length fs)) #\0) fs)))
(define (pad x n)                       ; left-justify
  (let ((s (->str x)))
    (if (>= (string-length s) n) s
        (string-append s
          (make-string (- n (string-length s)) #\space)))))
(define (lpad x n)                      ; right-justify
  (let ((s (->str x)))
    (if (>= (string-length s) n) s
        (string-append
          (make-string (- n (string-length s)) #\space) s))))
(define (strip s)
  (let* ((n (string-length s))
         (a (let lp ((i 0)) (if (and (< i n)
              (char-whitespace? (string-ref s i))) (lp (+ i 1)) i)))
         (b (let lp ((i n)) (if (and (> i a)
              (char-whitespace? (string-ref s (- i 1)))) (lp (- i 1)) i))))
    (substring s a b)))
(define (thing s)
  (let ((s (strip s)))
    (cond ((string=? s "?") '?) ((string=? s "True") #t)
          ((string=? s "False") #f)
          ((string->number s) => (lambda (n) n)) (else s))))
(define (cells s)
  (let lp ((i 0) (a 0) (out '()))
    (cond ((= i (string-length s))
           (reverse (cons (strip (substring s a i)) out)))
          ((char=? (string-ref s i) #\,)
           (lp (+ i 1) (+ i 1) (cons (strip (substring s a i)) out)))
          (else (lp (+ i 1) a out)))))
(define (csv file)
  (call-with-input-file file
    (lambda (in)
      (let lp ((out '()))
        (let ((ln (read-line in)))
          (if (eof-object? ln) (reverse out)
              (let ((l (strip ln)))
                (if (or (string=? l "") (char=? (string-ref l 0) #\#))
                    (lp out) (lp (cons (label thing (cells l)) out))))))))))
(define *settings*
  (o 'seed 1234567891 'p 2 'bins 7 'depth 4
     'file "../optimiz/auto93.csv"))
(define (my k) (ats *settings* k))
(define (args) (cdr (command-line)))
(define (cli)
  (let lp ((a (args)))
    (when (and (pair? a) (pair? (cdr a)))
      (for-each (lambda (k)
        (when (string=? (car a)
                (cat "-" (string (char-downcase
                          (string-ref (->str k) 0)))))
          (ats! *settings* k (thing (cadr a))))) (keys *settings*))
      (lp (cdr a)))))

;;; ===== start ================================================
(cli)
(cond ((member "--trees" (args)) (eg-trees))
      (else (eg-main)))
