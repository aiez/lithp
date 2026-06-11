; vim: set ft=lisp ts=2 sw=2 et :
; to_small.lisp -- fast-frugal multi-objective tree.
; (c) 2026 Tim Menzies timm@ieee.org, MIT license.
; Port of ../semble/fft.py, built on tiny.lisp.

(load "tiny.lisp")

(setf *the* {seed 1234567891 p 2 bins 7 depth 4
             file "../optimiz/auto93.csv"})
(defvar big 1e32)

;;; 1. columns -------------------------------------------------
(defstruct (num (:conc-name) (:constructor num
              (&optional (n 0) (mu 0.0) (m2 0.0))))
  n mu m2)

(def sym () (o))

(def sd (i)
  (if (< $n 2) 0 (sqrt (/ (max 0 $m2) (1- $n)))))

(def welford (i v &optional (w 1))
  (incf $n w)
  (if (< $n 1) (num)
      (let ((d (- v $mu)))
        (incf $mu (/ (* w d) $n))
        (incf $m2 (* w d (- v $mu))) i)))

(def norm (i v)
  (let ((z (/ (- v $mu) (+ (sd i) 1e-32))))
    (/ 1 (+ 1 (exp (* -1.7 (max -3 (min 3 z))))))))

(def+ mix ((i hash-table) j &optional (w 1))
  (let ((out (o)))
    (maphash (ff_ (incf (ats out _ 0) __)) i)
    (maphash (ff_ (incf (ats out _ 0) (* w __))) j)
    out))

(def+ mix ((i num) j &optional (w 1))
  (let ((m (+ $n (* w (n j)))) (d (- (mu j) $mu)))
    (if (< m 1) (num)
        (num m
             (/ (+ (* $n $mu) (* w (n j) (mu j))) m)
             (+ $m2 (* w (m2 j))
                (/ (* w d d $n (n j)) m))))))

;;; 2. data ----------------------------------------------------
(defstruct (data (:conc-name) (:constructor %data))
  names x y (goal (o)) (cols (o)) rows)

(def data (src)
  (let ((i (%data :names (car src) :rows (cdr src))))
    (loop for s in $names for at from 0
          for r = (roles i s at)
          when (eq r 'x) collect at into xs
          when (eq r 'y) collect at into ys
          finally (setf $x xs $y ys))
    (dolist (row $rows i)
      (loop for v in row for at from 0
            do (add (ats $cols at) v)))))

(def roles (i s at)
  (let ((z (char s (1- (length s)))))
    (setf (ats $cols at)
          (if (lower-case-p (char s 0)) (sym) (num)))
    (cond ((find z "-+!")
           (setf (ats $goal at) (if (eql z #\+) 1 0))
           'y)
          ((not (eql z #\X)) 'x))))

(def add (it v &optional (w 1))
  (if (eq v '?) it (add+ it v w)))

(def+ add+ ((it hash-table) v w)
  (incf (ats it v 0) w) it)
(def+ add+ ((it num) v w) (welford it v w))

(def adds (lst &optional (it (num)))
  (dolist (v lst it) (setf it (add it v))))

;;; 3. discretization ------------------------------------------
(def col (i at) (ats $cols at))

(def+ bin ((c hash-table) v) v)
(def+ bin ((c num) v) (floor (* @bins (norm c v))))

(def+ top ((c hash-table) v old) v)
(def+ top ((c num) v old) (max (or old (- big)) v))

(def cuts (i lst y)
  (let ((ys (mapcar y lst)))
    (loop for at in $x
          append (cuts-at (col i at) lst ys at))))

(def cuts-at (c lst ys at)
  (let ((bins (o)) (hi (o)))
    (loop for r in lst for y1 in ys
          for v = (nth at r) unless (eq v '?) do
      (let ((k (bin c v)))
        (setf (ats bins k) (add (or (ats bins k) (num)) y1)
              (ats hi k)   (top c v (ats hi k)))))
    (cuts-of c bins hi at)))

(def+ cuts-of ((c hash-table) bins hi at)
  (mapcar (f_ (list at (ats hi _) (ats hi _) (ats bins _)))
          (keys bins)))

(def+ cuts-of ((c num) bins hi at)
  (let ((l (num)))
    (mapcar (f_ (setf l (mix l (ats bins _)))
                (list at (- big) (ats hi _) l))
            (butlast (sort (keys bins) #'<)))))

;;; 4. grow trees ----------------------------------------------
(def disty (i row)
  (expt (/ (loop for at in $y sum
                 (expt (abs (- (norm (col i at)
                                     (nth at row))
                               (ats $goal at)))
                       @p))
           (length $y))
        (/ 1.0 @p)))

(def+ has ((v symbol) lo hi) t)
(def+ has ((v string) lo hi) (equal v lo))
(def+ has ((v number) lo hi) (<= lo v hi))

(def splits (i y root)
  (let+ ((enough (expt (length (rows root)) .33))
         (cs (remove-if (f_ (<= (n (fourth _)) enough))
                        (cuts i $rows y))))
    (when cs
      (loop for (bit pick) in `((0 ,#'least) (1 ,#'most)) append
        (let+ (((at lo hi leaf)
                (! pick cs (f_ (mu (fourth _)))))
               (no (remove-if (f_ (has (nth at _) lo hi))
                              $rows)))
          (when no
            (list (list bit
                        {at at lo lo hi hi left leaf}
                        no))))))))

(def grows (i y root &optional (d 0))
  (or (when (< d @depth)
        (loop for (bit node no) in (splits i y root)
              for kid = (data (cons $names no)) append
          (loop for (bias r) in (grows kid y root (1+ d))
                collect (list (cat bit bias)
                              (branch node r)))))
      `(("" ,(adds (mapcar y $rows))))))

(def branch (nd right)
  {at (? nd at) lo (? nd lo) hi (? nd hi)
   left (? nd left) right right})

;;; 5. use trees -----------------------------------------------
(def+ predict ((i num) row) $mu)
(def+ predict ((i hash-table) row)
  (predict (if (has (nth $at row) $lo $hi) $left $right) row))

(def err (tr lst y)
  (/ (loop for r in lst sum (abs (- (! y r) (predict tr r))))
     (length lst)))

(def tune (cands lst y) (least cands (f_ (err _ lst y))))

(def rule (i tr)
  (let ((s (nth (? tr at) $names))
        (lo (? tr lo)) (hi (? tr hi)))
    (cond ((equal lo hi)  (cat s " == " lo))
          ((= lo (- big)) (cat s " <= " hi))
          (t              (cat s " >= " lo)))))

(def+ show (i (tr num))
  (prn "~33a leaf  d2h ~,2f n=~d" "" (mu tr) (n tr)))

(def+ show (i (tr hash-table))
  (let ((l (? tr left)))
    (prn "if ~30a then d2h ~,2f n=~d"
         (rule i tr) (mu l) (n l))
    (show i (? tr right))))

;;; 6. demos ---------------------------------------------------
(def eg-main ()
  (let+ ((i  (data (csv @file)))
         (y  (f_ (disty i _)))
         (ts (mapcar #'second (grows i y i))))
    (show i (tune ts $rows y))))

(def eg-trees ()
  (let+ ((i (data (csv @file)))
         (y (f_ (disty i _))))
    (loop for (bias tr) in (grows i y i) for k from 1 do
      (prn "===== tree ~2d   bias ~5a   err ~,3f ====="
           k bias (err tr $rows y))
      (show i tr) (terpri))))

(def eg-grows (&optional (reps 10) (k 100))
  (let ((all (csv @file)) (m 0)
        (t0 (get-internal-real-time)))
    (loop repeat reps do
      (let ((i (data (cons (car all) (few (cdr all) k)))))
        (setf m (length (grows i (f_ (disty i _)) i)))))
    (let ((s (/ (- (get-internal-real-time) t0)
                internal-time-units-per-second)))
      (prn "~dx (sample ~d, ~d trees): ~,3f s -> ~,1f ms"
           reps k m s (* 1000 (/ s reps))))))

;;; 7. start ---------------------------------------------------
(cli)
(setf *seed* @seed)
(cond ((member "--grows" (args) :test #'equal) (eg-grows))
      ((member "--trees" (args) :test #'equal) (eg-trees))
      (t (eg-main)))
