; vim: set lispwords+=loop,aif :
(load "lib")

(defstruct (settings (:conc-name))
  (--seed 1234567891) (--p 2) (--bins 7) (--depth 4) 
  (--file  "../../optimiz/auto93.csv") (--big 1E32))

(defvar it (make-settings))

;---------------------------------------------------------------
(defstruct sym (at 0) (txt " ") (n 0) (w 1) (has (o)))
(defstruct num (at 0) (txt " ") (n 0) (w 1) (mu 0.0) (m2 0.0))

(defstruct (cols (:constructor %make-cols))
  names (all (vec)) (x (vec)) (y (vec)))
(defstruct (data (:constructor %make-data)) cols (rows (vec)))

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

(defmethod add ((i sym) v &optional (w 1))
  (incf $n  w)
  (incf (ats $has v 0) w))

(defmethod add ((i num) v &optional (w 1))
  (incf $n w)
  (if (>= $n 1) 
    (let ((d (- v $mu)))
      (incf $mu (/ (* w d) $n))
      (incf $m2 (* w d (- v $mu))))))

(defmethod norm ((i num) v)
  (let ((z (/ (- v $mu ) (+ (spread i) 1e-32))))
    (/ 1 (+ 1 (exp (* -1.7 (max -3 (min 3 z))))))))

;---------------------------------------------------------------
(defun make-data (&optional src &aux (i (%make-data)))
  (labels ((inc (row) (add i row)))
    (if (stringp src) (mapcsv #'inc src) (mapc #'inc src))
    i))

(defun make-cols (names &optional (i (%make-cols :names names)))
  (loop for s across names for at from 0 do
    (let* ((a (char s 0))
           (z (char s (1- (length s))))
           (col (if (upper-case-p a)
                  (make-num :at at :txt s)
                  (make-sym :at at :txt s))))
      (end! $all col)
      (cond ((find z "-+!")
             (setf (? col w) (if (eql z #\+) 1 0))
             (end! $y  col))
            ((not (eql z #\X)) (end! $x col)))))
  i)

(defmethod add ((i data) row &optional (w 1))
  (declare (ignore w))
  (if (not $cols)
    (return-from add (setf $cols (make-cols row))))
  (loop for col across (? $cols all) do
    (let ((v (elt row (? col at))))
      (unless (eq v '?) (add col v w))))
  (end! $rows row))


