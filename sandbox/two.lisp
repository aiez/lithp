; vim: set lispwords+=loop,aif :
(load "lib")

(defstruct (settings (:conc-name))
  (--seed 1234567891) (--p 2) (--bins 7) (--depth 4)
  (--leaf 3) (--budget 50) (--cap 1024) (--check 5) (--grow 4)
  (--keepf 0.66) (--landscape "active")
  (--file  "../../optimiz/auto93.csv") (--big 1E32))

(defvar my (make-settings))

;---------------------------------------------------------------
(defstruct sym (at 0) (txt " ") (n 0) (w 1) (has (o)))
(defstruct num (at 0) (txt " ") (n 0) (w 1) (mu 0.0) (m2 0.0))

(defstruct (cols (:constructor %make-cols)) names all x y)
(defstruct (data (:constructor %make-data)) cols rows)

;---------------------------------------------------------------
(defmethod add ((i sym) v &optional (w 1))
  (incf $n  w)
  (incf (ats $has v 0) w)
  v)

(defmethod add ((i num) v &optional (w 1))
  (incf $n w)
  (if (>= $n 1)
    (let ((d (- v $mu)))
      (incf $mu (/ (* w d) $n))
      (incf $m2 (* w d (- v $mu)))))
  v)

(defun adds (lst &optional (i (make-num)))
  (dolist (v lst i) (add i v)))

;---------------------------------------------------------------
(defmethod mid ((i num)) $mu)

(defmethod mid ((i sym) &aux best (most -1e30))
  (labels ((most (k v) (if (> v most) (setf most v best k))))
    (maphash #'most $has)
    best))

(defmethod spread ((i sym))
  (loop for v being the hash-values of $has 
    sum (* (/ v $n) (log (/ $n v) 2))))

(defmethod spread ((i num))
  (if (< $n 2) 0
      (sqrt (/ (max 0 $m2) (1- $n)))))

(defmethod norm ((i num) v)
  (let ((z (/ (- v $mu ) (+ (spread i) 1e-32))))
    (/ 1 (+ 1 (exp (* -1.7 (max -3 (min 3 z))))))))

(defmethod minus ((i num) (j num) &aux (k (make-num)))
  (let ((n (- $n (? j n)))
        (d (- (? j mu) $mu)))
    (when (plusp n)
      (setf (? k n)  n
            (? k mu) (/ (- (* $n $mu) (* (? j n) (? j mu))) n)
            (? k m2) (max 0 (- $m2 (? j m2)
                               (/ (* d d $n (? j n)) n)))))
    k))

(defmethod minus ((i sym) (j sym) &aux (k (make-sym)))
  (setf (? k n) (- $n (? j n)))
  (maphash (lambda (x c &aux (c1 (- c (ats (? j has) x 0))))
             (if (plusp c1) (setf (ats (? k has) x) c1)))
           $has)
  k)

;---------------------------------------------------------------
(defun make-cols (names &optional (i (%make-cols :names names)))
  (loop for s across names for at from 0 do
    (let* ((a (char s 0))
           (z (char s (1- (length s))))
           (col (if (upper-case-p a)
                  (make-num :at at :txt s)
                  (make-sym :at at :txt s))))
      (push col $all)
      (cond ((find z "-+!")
             (setf (? col w) (if (eql z #\+) 1 0))
             (push col $y))
            ((not (eql z #\X)) (push col $x)))))
  (setf $all (nreverse $all) $x (nreverse $x) $y (nreverse $y))
  i)

;---------------------------------------------------------------
(defun make-data (&optional src &aux (i (%make-data)))
  (labels ((inc (row) (add i row)))
    (if (stringp src) (mapcsv #'inc src) (mapc #'inc src))
    i))

(defun clone (data rows)
  (make-data (cons (? data cols names) rows)))

(defmethod add ((i data) row &optional (w 1))
  (if (not $cols)
    (return-from add (setf $cols (make-cols row))))
  (dolist (col (? $cols all))
    (let ((v (elt row (? col at))))
      (unless (eq v '?) (add col v w))))
  (push row $rows)
  row)

;---------------------------------------------------------------
(defun minkowski (row cols fun &aux (n 1e-32) (d 0))
  (dolist (col cols (expt (/ d n) (/ 1 (? my --p))))
    (let ((v (elt row (? col at))))
      (unless (eq v '?)
        (setf n (1+ n)
              d (+ d (expt (funcall fun col v)
                           (? my --p))))))))

(defmethod gap ((i sym) u v) (if (equal u v) 0 1))

(defmethod gap ((i num) u v)
  (let* ((u (norm i u))
         (v (if (eq v '?)
              (if (< u .5) 1 0)
              (norm i v))))
    (abs (- u v))))

(defun disty (data row)
  (minkowski row (? data cols y)
    (lambda (col v) (abs (- (norm col v) (? col w))))))

(defun distx (data r1 r2)
  (minkowski r1 (? data cols x)
    (lambda (col u) (gap col u (elt r2 (? col at))))))

;---------------------------------------------------------------
(defun project (rows x y)
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
  (labels ((y (r)   (disty data r))
           (x (a b) (distx data a b)))
    (let ((cap  (- (? my --budget) (? my --check)))
          (rows (? data rows)))
      (sort (if (equal (? my --landscape) "random")
              (few rows cap)
              (active (shuffle rows) cap #'x #'y))
            #'< :key #'y))))

(defun active (pool cap x y &aux (lab (o)))
  (loop while (and (< (hash-table-count lab) cap)
                   (>= (length pool) (* 2 (? my --leaf))))
        do
    (let ((here (grow! pool lab cap)))
      (when (< (hash-table-count lab) cap)
        (let ((n (max 1 (floor (* (- 1 (? my --keepf))
                                  (length pool))))))
          (setf pool
                (nthcdr n (sort pool #'<
                                :key (project here x y))))))))
  (loop for r being the hash-values of lab collect r))

(defun grow! (pool lab cap &aux here (grown 0))
  (dolist (r pool (nreverse here))
    (when (and (not (ats lab r))
               (< grown (? my --grow))
               (< (hash-table-count lab) cap))
      (setf (ats lab r) r)
      (incf grown))
    (if (ats lab r) (push r here))))

;---------------------------------------------------------------
(defun wins (data)
  (let* ((ys (sort (mapcar (lambda (r) (disty data r))
                           (? data rows))
                   #'<))
         (lo (first ys))
         (b4 (elt ys (floor (length ys) 2))))
    (lambda (r)
      (max -100 (min 100 (* 100 
        (- 1 (/ (- (disty data r) lo) (+ (- b4 lo) 1e-32)))))))))

(defun holdout (data)
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

;---------------------------------------------------------------
(defmethod has? ((i sym) w v) (or (eq w '?) (equal w v)))
(defmethod has? ((i num) w v) (or (eq w '?) (<= w v)))

(defun split (data rows y &optional (accum #'make-num)
                   (keeper (keep-best-cut)))
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
  (loop for k being the hash-keys of $has
        using (hash-value this) do
    (funcall keeper this ys at k)))

(defmethod cuts ((i num) xy ys at accum keeper
                 &aux (this (funcall accum)))
  (loop for ((x . y) . rest) on (sort xy #'< :key #'car) do
    (add this y)
    (if (and rest (not (eql x (caar rest))))
      (funcall keeper this ys at x))))

;---------------------------------------------------------------
(defstruct node at v n mid rows yes no)

(defun tree (data rows y &optional (accum #'make-num) (lvl 0))
  (let ((i (make-node :n (length rows) :rows rows
                      :mid (mid (adds (mapcar y rows)
                                      (funcall accum))))))
    (if (grow? rows lvl) (branch data i rows y accum lvl))
    i))

(defun grow? (rows lvl)
  (and (>= (length rows) (* 2 (? my --leaf)))
       (< lvl (? my --depth))))

(defun branch (data i rows y accum lvl &aux yes no)
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

(defun col-at (data at) (elt (? data cols all) at))

(defun leaf (data i row)
  (if $at
    (leaf data
          (if (has? (col-at data $at) (elt row $at) $v)
            $yes
            $no)
          row)
    $mid))

(defun leaves (i)
  (if $at
    (append (leaves $yes) (leaves $no))
    (list i)))

;---------------------------------------------------------------
(defun cond-txt (data i yes)
  (let ((col (col-at data $at)))
    (format nil "~a ~a ~a" (? col txt)
            (if (sym-p col) (if yes "==" "!=") (if yes "<=" ">"))
            $v)))

(defun show (data i &optional (pad "") (edge ""))
  (format t "~&~5d ~8,2f  ~a~a~%" $n $mid pad edge)
  (when $at
    (let ((pad2 (if (equal edge "") pad (cat pad "|  "))))
      (show data $yes pad2 (cond-txt data i t))
      (show data $no  pad2 (cond-txt data i nil)))))

(defun used (i)
  (if $at (remove-duplicates
            (cons $at (append (used $yes) (used $no))))))

(defun about (data i)
  (format t "~&leaves= ~a, x= ~a of ~a~%"
          (length (leaves i))
          (length (used i))
          (length (? data cols x))))
