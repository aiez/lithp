; vim: set lispwords+=loop,aif :
(load "two")

;----------------------------------------------------------------
(defun eg--it ()
  (format t "~&~s~%" it)
  (assert (settings-p it)))

(defun eg--thing ()
  (let ((got (mapcar #'thing '(" 23 " "3.14" "-1e2"
                               "?" "True" "False" "abc"))))
    (print got)
    (assert (equal got '(23 3.14 -100.0 ? t nil "abc")))))

(defun eg--rand (&aux a b)
  (setf *seed* 1 a (rand)
        *seed* 1 b (rand))
  (format t "~&rand ~,3f rint ~a~%" a (rint 10))
  (assert (= a b))
  (assert (< 0 a 1)))

(defun eg--num (&aux (i (make-num)))
  (dotimes (k 10000)
    (add i (/ (- (+ (rand) (rand) (rand)) 1.5) 0.5)))
  (format t "~&num mu ~,3f sd ~,3f~%" (mid i) (spread i))
  (assert (< (abs (mid i)) 0.05))
  (assert (< (abs (- (spread i) 1)) 0.05)))

(defun eg--sym (&aux (i (make-sym)))
  (dolist (v '(a a a a b b c)) (add i v))
  (format t "~&sym mid ~a ent ~,3f~%" (mid i) (spread i))
  (assert (eq (mid i) 'a))
  (assert (< (abs (- (spread i) 1.379)) 0.01)))

(defun eg--csv (&aux (n 0))
  (mapcsv (lambda (row)
            (if (< (incf n) 4) (print row))
            (assert (= (length row) 8)))
          (? it --file))
  (format t "~&rows ~a~%" n)
  (assert (= n 399)))

(defun eg--data (&aux (i (make-data (? it --file))))
  (format t "~&rows ~a |x| ~a |y| ~a~%"
          (length (? i rows))
          (length (? i cols x))
          (length (? i cols y)))
  (loop for col across (? i cols y) do
    (format t "~a mid ~,2f div ~,2f~%"
            (? col txt) (mid col) (spread col)))
  (assert (= (length (? i rows)) 398))
  (assert (= (length (? i cols all)) 8))
  (assert (= (length (? i cols x)) 4))
  (assert (= (length (? i cols y)) 3))
  (let ((mpg (elt (? i cols y) 2)))
    (assert (< (abs (- (mid mpg) 23.84)) 0.1))
    (assert (< (abs (- (spread mpg) 8.34)) 0.1))))

(defun egs ()
  (sort (loop for s being the present-symbols of *package*
              when (and (fboundp s)
                        (eql 0 (search "EG--" (string s)))
                        (not (eq s 'eg--all)))
              collect s)
        #'string< :key #'string))

(defun eg--all ()
  (dolist (s (egs))
    (format t "~&~%; ~(~a~)~%" s)
    (setf *seed* (? it --seed))
    (funcall s)))

;----------------------------------------------------------------
(cli it)
