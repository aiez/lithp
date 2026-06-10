; vim: set ft=lisp ts=2 sw=2 et :
(defstruct settings
  (seed 1234567891) (pp 2) (bins 7) (depth 4) (round 2)
  (file "../optimiz/auto93.csv"))
(defvar *the* (make-settings))

(defstruct (data (:constructor %make-data)) rows cols)
(defstruct (cols (:constructor %make-cols)) x y all)
(defstruct sym (at 0) (txt "") (n 0) has)
(defstruct (num (:constructor %make-num))
  (at 0) (txt " ") (n 0) (mu 0) (m2 0) (sd 0) (goal 1))

;--------------------------------------------------------------------
(set-macro-character #\$
  (lambda (s _) (declare (ignore _))
    `(slot-value i ',(read s t nil t))))

(defmacro ?  (x &rest a)
  (if a `(? (slot-value ,x ',(car a)) ,@(cdr a)) x))

(defmacro ?? (x) `(? *the* ,x))

(defmacro has (x lst)
  `(cdr (or (assoc ,x ,lst :test #'equal)
            (car (push (cons ,x 0) ,lst)))))

;--------------------------------------------------------------------
(defun ch (s n &aux (z (string s)))
  (char z (if (minusp n) (+ (length z) n) n)))

(defun thing (s &aux (*read-eval* nil)
                     (v (ignore-errors (read-from-string s))))
  (if (numberp v) v s))

(defun words (s &optional (sep #\,))
  (loop for a = 0 then (1+ b)
        for b = (position sep s :start a)
        collect (thing (subseq s a b)) while b))

(defun with-csv (f)
  (with-open-file (s f)
    (loop for l = (read-line s nil) while l collect (words l))))

;--------------------------------------------------------------------
(defun make-num (&key (txt " ") (at 0))
  (let ((i (%make-num :txt txt :at at)))
    (setf $goal (if (char= (ch txt -1) #\-) 0 1)) i))

(defun make-cols (names &aux (i (%make-cols)) (n -1))
  (dolist (s names)
    (let ((c (funcall (if (upper-case-p (ch s 0))
                          #'make-num #'make-sym)
                      :at (incf n) :txt s)))
      (push c $all)
      (cond ((member (ch s -1) '(#\- #\+ #\!)) (push c $y))
            ((char/= (ch s -1) #\X) (push c $x)))))
  (setf $all (nreverse $all) $x (nreverse $x)
        $y (nreverse $y)) i)

(defun make-data (src)
  (if (stringp src) (make-data (with-csv src))
      (let ((i (%make-data :cols (make-cols (car src)))))
        (dolist (row (cdr src) i) (add i row)))))

;--------------------------------------------------------------------
(defmethod add ((i data) row &optional w) (declare (ignore w))
  (mapcar (lambda (c v) (add c v)) (cols-all $cols) row)
  (push row $rows) i)

(defmethod add ((i sym) v &optional (w 1))
  (unless (equal v "?") (incf $n w) (incf (has v $has) w)) i)

(defmethod add ((i num) v &optional (w 1))
  (unless (equal v "?")
    (incf $n w)
    (let ((d (- v $mu)))
      (incf $mu (* w (/ d $n)))
      (incf $m2 (* w d (- v $mu)))
      (setf $sd (if (< $n 2) 0
                    (sqrt (/ (max 0 $m2) (- $n 1))))))) i)

(let ((d (make-data (?? file))))
  (format t "~&rows ~a~%" (length (data-rows d)))
  (dolist (c (cols-y (data-cols d)))
    (format t "~8a mu=~7,2f sd=~6,2f~%"
            (num-txt c) (num-mu c) (num-sd c))))
