; vim: set ft=lisp ts=2 sw=2 et :
; fft-nice.lisp -- fft-small.lisp rebuilt on lib-.lisp:
; plain ANSI CL plus only f_ ff_ ? let+ o ats, and a
; local (my k) settings macro. No reader macros, no
; def/def+/!/{} sugar.
; (c) 2026 Tim Menzies timm@ieee.org, MIT license.

(load "lib-.lisp")

(defvar *settings*
  '((seed . 1234567891) (p . 2) (bins . 7) (depth . 4)
    (file . "../optimiz/auto93.csv")))

(defmacro my (k) `(cdr (assoc ',k *settings*)))

(defvar big 1e32)

;;; 1. columns -------------------------------------------------
(defstruct (num (:conc-name) (:constructor num
              (&optional (n 0) (mu 0.0) (m2 0.0))))
  n mu m2)

(defun sym () (o))

(defun sd (i)
  (if (< (n i) 2) 0
      (sqrt (/ (max 0 (m2 i)) (1- (n i))))))

(defun welford (i v &optional (w 1))
  (incf (n i) w)
  (if (< (n i) 1) (num)
      (let ((d (- v (mu i))))
        (incf (mu i) (/ (* w d) (n i)))
        (incf (m2 i) (* w d (- v (mu i)))) i)))

(defun norm (i v)
  (let ((z (/ (- v (mu i)) (+ (sd i) 1e-32))))
    (/ 1 (+ 1 (exp (* -1.7 (max -3 (min 3 z))))))))

(defmethod mix ((i hash-table) j &optional (w 1))
  (let ((out (o)))
    (maphash (ff_ (incf (ats out _ 0) __)) i)
    (maphash (ff_ (incf (ats out _ 0) (* w __))) j)
    out))

(defmethod mix ((i num) j &optional (w 1))
  (let ((m (+ (n i) (* w (n j))))
        (d (- (mu j) (mu i))))
    (if (< m 1) (num)
        (num m
             (/ (+ (* (n i) (mu i)) (* w (n j) (mu j)))
                m)
             (+ (m2 i) (* w (m2 j))
                (/ (* w d d (n i) (n j)) m))))))

;;; 2. data ----------------------------------------------------
(defstruct (data (:conc-name) (:constructor %data))
  names x y (goal (o)) (cols (o)) rows)

(defun data (src)
  (let ((i (%data :names (car src) :rows (cdr src))))
    (loop for s in (names i) for at from 0
          for r = (roles i s at)
          when (eq r 'x) collect at into xs
          when (eq r 'y) collect at into ys
          finally (setf (x i) xs (y i) ys))
    (dolist (row (rows i) i)
      (loop for v in row for at from 0
            do (add (ats (cols i) at) v)))))

(defun roles (i s at)
  (let ((z (char s (1- (length s)))))
    (setf (ats (cols i) at)
          (if (lower-case-p (char s 0)) (sym) (num)))
    (cond ((find z "-+!")
           (setf (ats (goal i) at)
                 (if (eql z #\+) 1 0))
           'y)
          ((not (eql z #\X)) 'x))))

(defun add (it v &optional (w 1))
  (if (eq v '?) it (add+ it v w)))

(defmethod add+ ((it hash-table) v w)
  (incf (ats it v 0) w) it)
(defmethod add+ ((it num) v w) (welford it v w))

(defun adds (lst &optional (it (num)))
  (dolist (v lst it) (setf it (add it v))))

;;; 3. discretization ------------------------------------------
(defun col (i at) (ats (cols i) at))

(defmethod bin ((c hash-table) v) v)
(defmethod bin ((c num) v)
  (floor (* (my bins) (norm c v))))

(defmethod top ((c hash-table) v old) v)
(defmethod top ((c num) v old)
  (max (or old (- big)) v))

(defun cuts (i lst y)
  (let ((ys (mapcar y lst)))
    (loop for at in (x i)
          append (cuts-at (col i at) lst ys at))))

(defun cuts-at (c lst ys at)
  (let ((bins (o)) (hi (o)))
    (loop for r in lst for y1 in ys
          for v = (nth at r) unless (eq v '?) do
      (let ((k (bin c v)))
        (setf (ats bins k)
              (add (or (ats bins k) (num)) y1)
              (ats hi k) (top c v (ats hi k)))))
    (cuts-of c bins hi at)))

(defmethod cuts-of ((c hash-table) bins hi at)
  (mapcar (f_ (list at (ats hi _) (ats hi _)
                    (ats bins _)))
          (keys bins)))

(defmethod cuts-of ((c num) bins hi at)
  (let ((l (num)))
    (mapcar (f_ (setf l (mix l (ats bins _)))
                (list at (- big) (ats hi _) l))
            (butlast (sort (keys bins) #'<)))))

;;; 4. grow trees ----------------------------------------------
(defun disty (i row)
  (expt (/ (loop for at in (y i) sum
                 (expt (abs (- (norm (col i at)
                                     (nth at row))
                               (ats (goal i) at)))
                       (my p)))
           (length (y i)))
        (/ 1.0 (my p))))

(defmethod has ((v symbol) lo hi) t)
(defmethod has ((v string) lo hi) (equal v lo))
(defmethod has ((v number) lo hi) (<= lo v hi))

(defun splits (i y root)
  (let+ ((enough (expt (length (rows root)) .33))
         (cs (remove-if
               (f_ (<= (n (fourth _)) enough))
               (cuts i (rows i) y))))
    (when cs
      (loop for (bit pick) in `((0 ,#'least) (1 ,#'most))
            append
        (let+ (((at lo hi leaf)
                (funcall pick cs (f_ (mu (fourth _)))))
               (no (remove-if
                     (f_ (has (nth at _) lo hi))
                     (rows i))))
          (when no
            (list (list bit
                        (o 'at at 'lo lo 'hi hi
                           'left leaf)
                        no))))))))

(defun grows (i y root &optional (d 0))
  (or (when (< d (my depth))
        (loop for (bit nd no) in (splits i y root)
              for kid = (data (cons (names i) no))
              append
          (loop for (bias r) in (grows kid y root (1+ d))
                collect (list (cat bit bias)
                              (branch nd r)))))
      (list (list "" (adds (mapcar y (rows i)))))))

(defun branch (nd right)
  (o 'at (? nd at) 'lo (? nd lo) 'hi (? nd hi)
     'left (? nd left) 'right right))

;;; 5. use trees -----------------------------------------------
(defmethod predict ((i num) row) (mu i))
(defmethod predict ((i hash-table) row)
  (predict (if (has (nth (? i at) row)
                    (? i lo) (? i hi))
               (? i left)
               (? i right))
           row))

(defun err (tr lst y)
  (/ (loop for r in lst sum
           (abs (- (funcall y r) (predict tr r))))
     (length lst)))

(defun tune (cands lst y)
  (least cands (f_ (err _ lst y))))

(defun rule (i tr)
  (let ((s (nth (? tr at) (names i)))
        (lo (? tr lo)) (hi (? tr hi)))
    (cond ((equal lo hi)  (cat s " == " lo))
          ((= lo (- big)) (cat s " <= " hi))
          (t              (cat s " >= " lo)))))

(defmethod show (i (tr num))
  (prn "~33a leaf  d2h ~,2f n=~d" "" (mu tr) (n tr)))

(defmethod show (i (tr hash-table))
  (let ((l (? tr left)))
    (prn "if ~30a then d2h ~,2f n=~d"
         (rule i tr) (mu l) (n l))
    (show i (? tr right))))

;;; 6. demos ---------------------------------------------------
(defun eg-main ()
  (let+ ((i (data (csv (my file))))
         (y (f_ (disty i _)))
         (ts (mapcar #'second (grows i y i))))
    (show i (tune ts (rows i) y))))

(defun eg-trees ()
  (let+ ((i (data (csv (my file))))
         (y (f_ (disty i _))))
    (loop for (bias tr) in (grows i y i)
          for k from 1 do
      (prn "===== tree ~2d   bias ~5a   err ~,3f ====="
           k bias (err tr (rows i) y))
      (show i tr) (terpri))))

(defun eg-grows (&optional (reps 10) (k 100))
  (let ((all (csv (my file))) (m 0)
        (t0 (get-internal-real-time)))
    (loop repeat reps do
      (let ((i (data (cons (car all) (few (cdr all) k)))))
        (setf m (length (grows i (f_ (disty i _)) i)))))
    (let ((s (/ (- (get-internal-real-time) t0)
                internal-time-units-per-second)))
      (prn "~dx (sample ~d, ~d trees): ~,3f s -> ~,1f ms"
           reps k m s (* 1000 (/ s reps))))))

;;; 7. start ---------------------------------------------------
(cli *settings*)
(setf *seed* (my seed))
(cond ((member "--grows" (args) :test #'equal) (eg-grows))
      ((member "--trees" (args) :test #'equal) (eg-trees))
      (t (eg-main)))
