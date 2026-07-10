; vim: set lispwords+=loop,aif,set-macro-character :
; SPDX-License-Identifier: MIT
; (c) 2026 Tim Menzies <timm@ieee.org>

(defpackage :ezr2 (:use :common-lisp))
(in-package :ezr2)

#+sbcl (declaim (sb-ext:muffle-conditions
                  warning style-warning))

(defvar *help* "
ezr2.lisp: landscape analysis for XAI and optimization CSVs.
(c) 2026 Tim Menzies <timm@ieee.org>, MIT license.

USAGE: sbcl --script ezr2.lisp [--key val ...] [--test ...]

Data files are CSVs whose header names the column roles:
leading uppercase = numeric; trailing +/- = goal to
maximize/minimize; trailing X = ignore; ? cells = missing.

Set any option with --key val (e.g. --seed 1 --file x.csv).
Run any test or study by its flag (e.g. --tree --delta).")

;   _  _|_  ._        _  _|_   _
;  _>   |_  |   |_|  (_   |_  _>

(defstruct (settings (:conc-name))
  (--seed 1234567891) (--p 2) (--bins 7) (--depth 4)
  (--leaf 3) (--budget 50) (--cap 1024) (--check 5) (--grow 4)
  (--keepf 0.66) (--landscape "active")
  (--file  "../../optimiz/auto93.csv") (--big 1E32))

(defvar my (make-settings))

(defstruct sym (at 0) (txt " ") (n 0) (w 1) (has (o)))
(defstruct num (at 0) (txt " ") (n 0) (w 1) (mu 0.0) (m2 0.0))

(defstruct (cols (:constructor %make-cols)) names all x y)
(defstruct (data (:constructor %make-data)) cols rows)

(defstruct node at v n mid rows yes no)

;  ._ _    _.   _  ._   _    _
;  | | |  (_|  (_  |   (_)  _>

(defmacro ? (x k &rest ks)
  "nested slot/hash access: (? data cols x)"
  (if ks `(? (ats ,x ',k) ,@ks) `(ats ,x ',k)))

(defmacro aif (test then &optional else)
  "anaphoric if: `it` holds the test value"
  `(let ((it ,test))
     (if it ,then ,else)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (set-macro-character #\$
    (lambda (stream ch)
      (declare (ignore ch)) `(ats i ',(read stream t nil t)))))

(defun ats (x k &optional d)
  "get k from a hash (default d) or a struct slot"
  (if (hash-table-p x) (gethash k x d) (slot-value x k)))

(defun (setf ats) (v x k &optional d)
  "set k in a hash or a struct slot"
  (declare (ignore d))
  (if (hash-table-p x)
      (setf (gethash k x) v)
      (setf (slot-value x k) v)))

(defun ats! (x k new)
  "get x's k, else stash and return a fresh (new)"
  (or (ats x k) (setf (ats x k) (funcall new))))

(defun o (&rest kvs)
  "fresh equal hash-table, optionally primed with k v pairs"
  (let ((h (make-hash-table :test #'equal)))
    (loop for (k v) on kvs by #'cddr do (setf (gethash k h) v))
    h))

;   _|   _.  _|_   _.
;  (_|  (_|   |_  (_|

(defmethod add ((i sym) v &optional (w 1))
  "count v (weight w); return v"
  (incf $n  w)
  (incf (ats $has v 0) w)
  v)

(defmethod add ((i num) v &optional (w 1))
  "fold v into mu,m2 by Welford (w<0 removes); return v"
  (incf $n w)
  (if (>= $n 1)
    (let ((d (- v $mu)))
      (incf $mu (/ (* w d) $n))
      (incf $m2 (* w d (- v $mu)))))
  v)

(defun adds (lst &optional (i (make-num)))
  "fold a list into a summary; return the summary"
  (dolist (v lst i) (add i v)))

(defmethod mid ((i num))
  "central tendency of a num"
  $mu)

(defmethod mid ((i sym) &aux best (most -1e30))
  "most common symbol"
  (labels ((most (k v) (if (> v most) (setf most v best k))))
    (maphash #'most $has)
    best))

(defmethod spread ((i sym))
  "entropy of a sym's counts"
  (loop for v being the hash-values of $has
    sum (* (/ v $n) (log (/ $n v) 2))))

(defmethod spread ((i num))
  "standard deviation of a num"
  (if (< $n 2) 0
      (sqrt (/ (max 0 $m2) (1- $n)))))

(defmethod norm ((i num) v)
  "map v to 0..1 via a logistic over its z-score"
  (let ((z (/ (- v $mu ) (+ (spread i) 1e-32))))
    (/ 1 (+ 1 (exp (* -1.7 (max -3 (min 3 z))))))))

(defmethod minus ((i num) (j num) &aux (k (make-num)))
  "num summarizing i's data without j's"
  (let ((n (- $n (? j n)))
        (d (- (? j mu) $mu)))
    (when (plusp n)
      (setf (? k n)  n
            (? k mu) (/ (- (* $n $mu) (* (? j n) (? j mu))) n)
            (? k m2) (max 0 (- $m2 (? j m2)
                               (/ (* d d $n (? j n)) n)))))
    k))

(defmethod minus ((i sym) (j sym) &aux (k (make-sym)))
  "sym summarizing i's data without j's"
  (setf (? k n) (- $n (? j n)))
  (maphash (lambda (x c &aux (c1 (- c (ats (? j has) x 0))))
             (if (plusp c1) (setf (ats (? k has) x) c1)))
           $has)
  k)

(defun make-cols (names &optional (i (%make-cols :names names)))
  "columns from header names; fill all, x, y"
  (loop for s across names for at from 0 do
    (let* ((a (char s 0))
           (z (char s (1- (length s))))
           (col (if (upper-case-p a)
                  (make-num :at at :txt s)
                  (make-sym :at at :txt s))))
      (push col $all)
      (cond ((find z "-+!")
             (if (eql z #\-) (setf (? col w) 0))
             (push col $y))
            ((not (eql z #\X)) (push col $x)))))
  (setf $all (nreverse $all) $x (nreverse $x) $y (nreverse $y))
  i)

(defun make-data (&optional src &aux (i (%make-data)))
  "table from a csv file name or a list of rows"
  (labels ((inc (row) (add i row)))
    (if (stringp src) (mapcsv #'inc src) (mapc #'inc src))
    i))

(defun clone (data rows)
  "fresh data over a subset of rows"
  (make-data (cons (? data cols names) rows)))

(defmethod add ((i data) row &optional (w 1))
  "first row makes cols; later rows update them"
  (if $cols
    (dolist (col (? $cols all) (push row $rows))
      (let ((v (elt row (? col at))))
        (unless (eq v '?) (add col v w))))
    (setf $cols (make-cols row)))
  row)

;   _|  o   _  _|_
;  (_|  |  _>   |_

(defun minkowski (row cols fun &aux (n 1e-32) (d 0))
  "p-norm of (fun col cell) over cols; missing cells skipped"
  (dolist (col cols (expt (/ d n) (/ 1 (? my --p))))
    (let ((v (elt row (? col at))))
      (unless (eq v '?)
        (setf n (1+ n)
              d (+ d (expt (funcall fun col v)
                           (? my --p))))))))

(defmethod gap ((i sym) u v)
  "distance between two sym values"
  (if (equal u v) 0 1))

(defmethod gap ((i num) u v)
  "distance between two num values; missing v = far pole"
  (let* ((u (norm i u))
         (v (if (eq v '?)
              (if (< u .5) 1 0)
              (norm i v))))
    (abs (- u v))))

(defun disty (data row)
  "row's distance to the best goals (0 = ideal)"
  (minkowski row (? data cols y)
    (lambda (col v) (abs (- (norm col v) (? col w))))))

(defun distx (data r1 r2)
  "distance between two rows over the x cols"
  (minkowski r1 (? data cols x)
    (lambda (col u) (gap col u (elt r2 (? col at))))))

;  |   _.  ._    _|   _   _   _.  ._    _
;  |  (_|  | |  (_|  _>  (_  (_|  |_)  (/_
;                                 |

(defun project (rows x y)
  "row -> position on the east-west line (x=dist, y=goal)"
  (labels ((far (r) (argmax (lambda (z) (funcall x z r)) rows)))
    (let* ((east (far (first rows)))
           (west (far east))
           (c    (+ (funcall x east west) 1e-32)))
      (if (< (funcall y east) (funcall y west))
        (rotatef east west))
      (lambda (r)
        (/ (+ (expt (funcall x east r) 2) (* c c)
              (- (expt (funcall x west r) 2)))
           (* 2 c))))))

(defun landscape (data)
  "label <= budget-check rows, best first"
  (labels ((y (r)   (disty data r))
           (x (a b) (distx data a b)))
    (let ((cap  (- (? my --budget) (? my --check)))
          (rows (shuffle (? data rows))))
      (sort (if (equal (? my --landscape) "random")
              (subseq rows 0 (min cap (length rows)))
              (active rows cap #'x #'y))
            #'< :key #'y))))

(defun active (pool cap x y &aux lab)
  "label pool heads; cull pool's bad third; repeat"
  (loop while (and (< (length lab) cap)
                   (>= (length pool) (* 2 (? my --leaf))))
        do
    (dotimes (k (min (? my --grow) (- cap (length lab))))
      (push (pop pool) lab))
    (if (< (length lab) cap)
      (setf pool
            (nthcdr (max 1 (floor (* (- 1 (? my --keepf))
                                     (length pool))))
                    (sort pool #'< :key (project lab x y))))))
  lab)

;   _       _|_   _
;  (_  |_|   |_  _>

(defmethod has? ((i sym) w v)
  "row value w on the yes-side of cut v? (? = yes)"
  (or (eq w '?) (equal w v)))

(defmethod has? ((i num) w v)
  "row value w on the yes-side of cut v? (? = yes)"
  (or (eq w '?) (<= w v)))

(defun split (data rows y &optional (accum #'make-num)
                   (keeper (keep-best-cut)))
  "best (cost at v) cut over all x cols"
  (dolist (col (? data cols x) (funcall keeper))
    (let ((at  (? col at))
          (ys  (funcall accum))
          (xs  (if (sym-p col) (make-sym) (make-num)))
          xy)
      (loop for r in rows for x = (elt r at) do
        (unless (eq x '?)
          (if (sym-p col)
            (add (ats! (? xs has) x accum)
                 (add ys (funcall y r)))
            (push (cons x (add ys (funcall y r))) xy))))
      (cuts xs xy ys at accum keeper))))

(defun keep-best-cut (&aux (lo 1e32) kept)
  "closure: offer (this ys at v); () returns cheapest cut"
  (labels
    ((big? (m n) (<= (? my --leaf) m (- n (? my --leaf))))
     (score (a b)
       (/ (+ (* (spread a) (? a n)) (* (spread b) (? b n)))
          (+ (? a n) (? b n) 1e-32))))
    (lambda (&optional this ys at v)
      (when (and this (big? (? this n) (? ys n)))
        (let ((c (score this (minus ys this))))
          (if (< c lo) (setf lo c kept (list c at v)))))
      kept)))

(defmethod cuts ((i sym) xy ys at accum keeper)
  "offer each key's y-summary as a candidate cut"
  (loop for k being the hash-keys of $has
        using (hash-value this) do
    (funcall keeper this ys at k)))

(defmethod cuts ((i num) xy ys at accum keeper
                 &aux (this (funcall accum)))
  "offer a candidate cut at each change in sorted x"
  (loop for ((x . y) . rest) on (sort xy #'< :key #'car) do
    (add this y)
    (if (and rest (not (eql x (caar rest))))
      (funcall keeper this ys at x))))

;  _|_  ._   _    _
;   |_  |   (/_  (/_

(defun tree (data rows y &optional (accum #'make-num) (lvl 0))
  "recursively split rows on the min-cost cut"
  (let ((i (make-node :n (length rows) :rows rows
                      :mid (mid (adds (mapcar y rows)
                                      (funcall accum))))))
    (if (grow? rows lvl) (branch data i rows y accum lvl))
    i))

(defun grow? (rows lvl)
  "enough rows and shallow enough to split again?"
  (and (>= (length rows) (* 2 (? my --leaf)))
       (< lvl (? my --depth))))

(defun branch (data i rows y accum lvl &aux yes no)
  "if best cut divides rows, grow yes/no subtrees"
  (aif (split data rows y accum)
    (let ((at (second it)) (v (third it)))
      (dolist (r rows)
        (if (has? (col-at data at) (elt r at) v)
          (push r yes)
          (push r no)))
      (when (and yes no)
        (setf $at  at
              $v   v
              $yes (tree data yes y accum (1+ lvl))
              $no  (tree data no  y accum (1+ lvl)))))))

(defun col-at (data at)
  "the column summary at index `at`"
  (elt (? data cols all) at))

(defun leaf (data i row)
  "walk row down the tree; return its leaf's mid"
  (if $at
    (leaf data
          (if (has? (col-at data $at) (elt row $at) $v)
            $yes
            $no)
          row)
    $mid))

(defun leaves (i)
  "list of every leaf node"
  (if $at
    (append (leaves $yes) (leaves $no))
    (list i)))

(defun cond-txt (data i yes)
  "one branch test as text, e.g. |Volume <= 183|"
  (let ((col (col-at data $at)))
    (format nil "~a ~a ~a" (? col txt)
            (if (sym-p col) (if yes "==" "!=") (if yes "<=" ">"))
            $v)))

(defun show (data i &optional (pad "") (edge ""))
  "print tree: n, mid, indented branch conditions"
  (format t "~&~5d ~8,2f  ~a~a~%" $n $mid pad edge)
  (when $at
    (let ((pad2 (if (equal edge "") pad (cat pad "|  "))))
      (show data $yes pad2 (cond-txt data i t))
      (show data $no  pad2 (cond-txt data i nil)))))

(defun used (i)
  "x col indexes tested anywhere in the tree"
  (if $at (remove-duplicates
            (cons $at (append (used $yes) (used $no))))))

(defun about (data i)
  "one line per tree: leaves, x cols used"
  (format t "~&leaves= ~a, x= ~a of ~a~%"
          (length (leaves i))
          (length (used i))
          (length (? data cols x))))

;   _  _|_   _.  _|_   _
;  _>   |_  (_|   |_  _>

(defun wins (data)
  "grader: row -> % of gap to best closed, [-100,100]"
  (let* ((ys (sort (mapcar (lambda (r) (disty data r))
                           (? data rows))
                   #'<))
         (lo (first ys))
         (b4 (elt ys (floor (length ys) 2))))
    (lambda (r)
      (max -100 (min 100 (* 100
        (- 1 (/ (- (disty data r) lo) (+ (- b4 lo) 1e-32)))))))))

(defun cliffs (xs ys &aux (gt 0) (lt 0))
  "Cliff's delta effect size, 0..1 (0 = identical)"
  (dolist (x xs)
    (dolist (y ys)
      (cond ((> x y) (incf gt))
            ((< x y) (incf lt)))))
  (/ (abs (- gt lt))
     (+ (* (length xs) (length ys)) 1e-32)))

(defun ks (xs ys)
  "Kolmogorov-Smirnov: max gap between the two CDFs"
  (labels ((cdf (v lst)
             (/ (count-if (lambda (z) (<= z v)) lst)
                (length lst))))
    (loop for v in (append xs ys)
          maximize (abs (- (cdf v xs) (cdf v ys))))))

(defun cohen (xs ys &optional (eps 0.35))
  "small effect: |mean gap| <= eps * pooled sd"
  (let* ((x (adds xs)) (y (adds ys))
         (n (? x n))   (m (? y n))
         (sd (sqrt (/ (+ (* (1- n) (expt (spread x) 2))
                         (* (1- m) (expt (spread y) 2)))
                      (+ n m -2)))))
    (<= (abs (- (mid x) (mid y))) (* eps (+ sd 1e-32)))))

(defun same (xs ys &optional (cliff 0.195) (conf 1.36))
  "true if xs,ys are statistically indistinguishable"
  (and (cohen xs ys)
       (<= (cliffs xs ys) cliff)
       (let ((n (length xs)) (m (length ys)))
         (<= (ks xs ys)
             (* conf (sqrt (/ (+ n m) (* n m))))))))

(defun holdout (data)
  "budget rig: landscape train -> tree -> best test row"
  (labels ((y (r) (disty data r)))
    (let* ((rows  (shuffle (? data rows)))
           (half  (floor (length rows) 2))
           (train (subseq rows 0 half))
           (test  (nthcdr half rows))
           (got   (landscape (clone data train)))
           (tr    (tree data got #'y)))
      (argmin #'y
              (subseq (sort test #'<
                            :key (lambda (r) (leaf data tr r)))
                      0 (? my --check))))))

;  |  o  |_
;  |  |  |_)

(defun slot-names (x)
  "slot names of a struct instance or type"
  (mapcar #+sbcl  #'sb-mop:slot-definition-name
          #+clisp #'clos:slot-definition-name
          (#+sbcl  sb-mop:class-slots
           #+clisp clos:class-slots
           (find-class (if (symbolp x) x (type-of x))))))

(defun trim (s)
  "strip spaces, tabs, returns"
  (string-trim '(#\space #\tab #\return) s))

(defun thing (s &aux (opt '(("?" . ?) ("True" . t) ("False"))))
  "string -> number | ? | t | nil | trimmed string"
  (let ((s (trim s))
        (*read-eval*))
  (aif (assoc s opt :test #'equal)
    (cdr it)
    (let ((x (ignore-errors (read-from-string s nil))))
      (if (numberp x) x s)))))

(defun things (s &optional (ch #\,) (start 0))
  "split s on ch; coerce each cell with thing"
  (aif (position ch s :start start)
    (cons (thing (subseq s start it)) (things s ch (1+ it)))
    (list (thing (subseq s start)))))

(defun mapcsv (fun file)
  "call fun on each csv row (skipping blanks, # comments)"
  (labels ((line (s &aux (s1 (trim s)))
             (unless (or (equal s1 "") (eql (char s1 0) #\#))
               (funcall fun (coerce (things s1) 'vector)))))
    (with-open-file (s file)
      (loop (line (or (read-line s nil) (return)))))))

(defvar *seed* 1234567891)

(defun rand (&optional (n 1))
  "next 0..n from a 16807 Lehmer generator"
  (setf *seed* (mod (* 16807 *seed*) 2147483647))
  (* n (/ *seed* 2147483647.0)))

(defun rint (&optional (n 2))
  "random integer 0 <= i < n"
  (floor (rand n)))

(defun cat (&rest xs)
  "concatenate the printed forms of xs"
  (format nil "~{~a~}" xs))

(defun argmin (fun lst &aux best (lo 1e32))
  "element of lst minimizing (fun x)"
  (dolist (x lst best)
    (let ((v (funcall fun x)))
      (if (< v lo) (setf lo v best x)))))

(defun argmax (fun lst &aux best (hi -1e32))
  "element of lst maximizing (fun x)"
  (dolist (x lst best)
    (let ((v (funcall fun x)))
      (if (> v hi) (setf hi v best x)))))

(defun shuffle (lst &aux (v (coerce lst 'vector)))
  "Fisher-Yates, driven by the seeded rand"
  (loop for i from (1- (length v)) downto 1 do
    (rotatef (elt v i) (elt v (rint (1+ i)))))
  (coerce v 'list))

(defun few (lst k)
  "k items picked at random"
  (subseq (shuffle lst) 0 (min k (length lst))))

;   _    _    _
;  (/_  (_|  _>
;        _|

(defun eg--my ()
  "print the settings"
  (format t "~&~s~%" my)
  (assert (settings-p my)))

(defun eg--thing ()
  "string coercion round-trip"
  (let ((got (mapcar #'thing '(" 23 " "3.14" "-1e2"
                               "?" "True" "False" "abc"))))
    (print got)
    (assert (equal got '(23 3.14 -100.0 ? t nil "abc")))))

(defun eg--rand (&aux a b)
  "seeded rand is deterministic and in (0,1)"
  (setf *seed* 1 a (rand)
        *seed* 1 b (rand))
  (format t "~&rand ~,3f rint ~a~%" a (rint 10))
  (assert (= a b))
  (assert (< 0 a 1)))

(defun eg--num (&aux (i (make-num)))
  "Irwin-Hall: 10k samples -> mean 0, sd 1"
  (dotimes (k 10000)
    (add i (/ (- (+ (rand) (rand) (rand)) 1.5) 0.5)))
  (format t "~&num mu ~,3f sd ~,3f~%" (mid i) (spread i))
  (assert (< (abs (mid i)) 0.05))
  (assert (< (abs (- (spread i) 1)) 0.05)))

(defun eg--sym (&aux (i (make-sym)))
  "sym mode and entropy on a known distribution"
  (dolist (v '(a a a a b b c)) (add i v))
  (format t "~&sym mid ~a ent ~,3f~%" (mid i) (spread i))
  (assert (eq (mid i) 'a))
  (assert (< (abs (- (spread i) 1.379)) 0.01)))

(defun eg--csv (&aux (n 0))
  "csv reader: row shapes and count"
  (mapcsv (lambda (row)
            (if (< (incf n) 4) (print row))
            (assert (= (length row) 8)))
          (? my --file))
  (format t "~&rows ~a~%" n)
  (assert (= n 399)))

(defun eg--data (&aux (i (make-data (? my --file))))
  "data build: col roles and goal stats"
  (format t "~&rows ~a |x| ~a |y| ~a~%"
          (length (? i rows))
          (length (? i cols x))
          (length (? i cols y)))
  (dolist (col (? i cols y))
    (format t "~a mid ~,2f div ~,2f~%"
            (? col txt) (mid col) (spread col)))
  (when (search "auto93" (? my --file))
    (assert (= (length (? i rows)) 398))
    (assert (= (length (? i cols all)) 8))
    (assert (= (length (? i cols x)) 4))
    (assert (= (length (? i cols y)) 3))
    (let ((mpg (elt (? i cols y) 2)))
      (assert (< (abs (- (mid mpg) 23.84)) 0.1))
      (assert (< (abs (- (spread mpg) 8.34)) 0.1)))))

(defun eg--cuts (&aux (i (make-data (? my --file))))
  "best single cut beats the unsplit spread"
  (let* ((rows (? i rows))
         (goal (car (last (? i cols y))))
         (best (split i rows
                      (lambda (r) (elt r (? goal at))))))
    (format t "~&best ~,2f at ~a v ~a (sd ~,2f)~%"
            (first best)
            (? (elt (? i cols all) (second best)) txt)
            (third best) (spread goal))
    (assert (< (first best) (spread goal)))
    (if (search "auto93" (? my --file))
      (assert (eql (third best) 183)))))

(defun eg--tree (&aux (i (make-data (? my --file))))
  "tree build: show, partition, walk"
  (setf (? i rows) (few (? i rows) (? my --cap)))
  (let* ((rows (? i rows))
         (goal (car (last (? i cols y))))
         (tr   (tree i rows
                     (lambda (r) (elt r (? goal at))))))
    (show i tr)
    (about i tr)
    (let ((lvs (leaves tr)))
      (assert (? tr at))
      (assert (> (length lvs) 3))
      (assert (= (length rows)
                 (loop for l in lvs sum (? l n))))
      (assert (<= 1 (length (used tr))
                  (length (? i cols x))))
      (assert (numberp (leaf i tr (first rows)))))))

(defun eg--dists (&aux (i (make-data (? my --file))))
  "disty in [0,1]; distx zero-self, symmetric, bounded"
  (let* ((rows (? i rows))
         (ys   (sort (mapcar (lambda (r) (disty i r)) rows)
                     #'<))
         (r1   (first rows))
         (r2   (second rows)))
    (format t "~&disty lo ~,3f hi ~,3f~%"
            (first ys) (car (last ys)))
    (assert (<= 0 (first ys) (car (last ys)) 1))
    (assert (= 0 (distx i r1 r1)))
    (assert (< (abs (- (distx i r1 r2) (distx i r2 r1)))
               1e-6))
    (assert (<= 0 (distx i r1 r2) 1))))

(defun eg--land (&aux (i (make-data (? my --file))))
  "landscape labels few rows, sorted best first"
  (let* ((lab (landscape i))
         (ys  (mapcar (lambda (r) (disty i r)) lab)))
    (format t "~&labelled ~a best ~,3f worst ~,3f~%"
            (length lab) (first ys) (car (last ys)))
    (assert (<= (length lab)
                (- (? my --budget) (? my --check))))
    (assert (equal ys (sort (copy-list ys) #'<)))
    (assert (< (first ys) 0.4))))

(defun eg--wins (&aux (i (make-data (? my --file))))
  "wins grader: best row = 100, all in [-100,100]"
  (let* ((w    (wins i))
         (rows (? i rows))
         (best (argmin (lambda (r) (disty i r)) rows)))
    (format t "~&win(best)= ~a win(worst)= ~a~%"
            (round (funcall w best))
            (round (funcall w (argmax
                                (lambda (r) (disty i r))
                                rows))))
    (assert (= 100 (round (funcall w best))))
    (dolist (r (few rows 30))
      (assert (<= -100 (funcall w r) 100)))))

(defun eg--same (&aux xs)
  "same: true for a nudge, false for a shift"
  (dotimes (k 20) (push (rand) xs))
  (let ((ys (mapcar (lambda (x) (+ x 0.02)) xs))
        (zs (mapcar (lambda (x) (+ x 1)) xs)))
    (format t "~&same: self ~a nudged ~a shifted ~a~%"
            (same xs xs) (same xs ys) (same xs zs))
    (assert (same xs xs))
    (assert (same xs ys))
    (assert (not (same xs zs)))))

(defun eg--holdout (&aux (i (make-data (? my --file))))
  "one holdout run: pick a good test row"
  (setf (? i rows) (few (? i rows) (? my --cap)))
  (let* ((got (holdout i))
         (w   (round (funcall (wins i) got))))
    (format t "~&picked ~s~%win= ~a disty= ~,3f~%"
            got w (disty i got))
    (assert (vectorp got))
    (assert (<= -100 w 100))
    (if (search "auto93" (? my --file))
      (assert (> w 0)))))

;   _  _|_        _|  o   _    _
;  _>   |_  |_|  (_|  |  (/_  _>

(defun study--holdouts (&aux (i (make-data (? my --file)))
                          w (n (make-num)))
  "rq0: mean win over 20 holdouts"
  (setf (? i rows) (few (? i rows) (? my --cap))
        w (wins i))
  (dotimes (k 20)
    (add n (funcall w (holdout i))))
  (format t "~&mu ~5,1f sd ~5,1f ~a~%"
          (mid n) (spread n) (? my --file))
  (assert (<= -100 (mid n) 100))
  (if (search "auto93" (? my --file))
    (assert (> (mid n) 50))))

(defun deltas (i knob v1 v2 &aux (w (wins i)) (v0 (ats my knob)))
  "20 paired holdouts per knob value; 0 if same, else win gap"
  (labels ((runs (v &aux out)
             (setf (ats my knob) v)
             (dotimes (k 20 out)
               (setf *seed* (+ (? my --seed) k))
               (push (funcall w (holdout i)) out))))
    (let* ((a (runs v1))
           (b (runs v2))
           (d (if (same a b) 0
                (- (mid (adds a)) (mid (adds b))))))
      (setf (ats my knob) v0)
      (format t "~&~6,1f ~a~%" d (? my --file)))))

(defun study--delta (&aux (i (make-data (? my --file))))
  "rq2: active vs random labelling, budget 50"
  (setf (? i rows) (few (? i rows) (? my --cap)))
  (deltas i '--landscape "active" "random"))

(defun study--budgets (&aux (i (make-data (? my --file))))
  "rq1: budget 50 vs 20, both active"
  (setf (? i rows) (few (? i rows) (? my --cap)))
  (deltas i '--budget 50 20))

(defun study--saturate (&aux (i (make-data (? my --file))))
  "rq1 caveat: budget 200 vs 50 (sampler stops near 40)"
  (setf (? i rows) (few (? i rows) (? my --cap)))
  (deltas i '--budget 200 50))

;  ._ _    _.  o  ._
;  | | |  (_|  |  | |

(defun egs (prefix)
  "sorted fbound symbols starting with prefix"
  (sort (loop for s being the present-symbols of *package*
              when (and (fboundp s)
                        (eql 0 (search prefix (string s)))
                        (not (member s '(eg--all eg--study))))
              collect s)
        #'string< :key #'string))

(defun run-egs (lst)
  "run each test, reseeding before each"
  (dolist (s lst)
    (format t "~&~%; ~(~a~)~%" s)
    (setf *seed* (? my --seed))
    (funcall s)))

(defun eg--all ()
  "run every unit test"
  (run-egs (egs "EG--")))

(defun eg--study ()
  "run every study"
  (run-egs (egs "STUDY--")))

(defun args ()
  "command-line args after the script name"
  #+sbcl  (cdr sb-ext:*posix-argv*)
  #+clisp ext:*args*)

(defun help ()
  "print options (with defaults), tests, studies"
  (format t "~a~%~%OPTIONS:~%" *help*)
  (dolist (s (slot-names my))
    (format t "  ~(~a~) ~a~%" s (ats my s)))
  (format t "~%TESTS: (run by flag, e.g. --tree)~%")
  (dolist (s (egs "EG--"))
    (format t "  ~(~a~)~26t~a~%" (subseq (string s) 2)
            (documentation s 'function)))
  (format t "~%STUDIES:~%")
  (dolist (s (egs "STUDY--"))
    (format t "  ~(~a~)~26t~a~%" (subseq (string s) 5)
            (documentation s 'function))))

(defun cli (my)
  "set settings slots from flags, then run named tests"
  (let ((args (args)))
    (loop for (f v) on args do
      (dolist (slot (slot-names my))
        (if (equalp f (string slot))
          (setf (slot-value my slot) (thing v)))))
    (loop for s in args do
      (dolist (pre '("EG" "STUDY"))
        (let ((fun (intern (format nil "~a~:@(~a~)" pre s))))
          (when (fboundp fun)
            (setf *seed* (? my --seed))
            (funcall fun)))))))

(if (member "-h" (args) :test #'equal)
  (help)
  (cli my))
