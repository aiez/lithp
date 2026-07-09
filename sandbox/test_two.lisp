; vim: set lispwords+=loop,aif :
(load "two")

;----------------------------------------------------------------
(defun eg--my ()
  (format t "~&~s~%" my)
  (assert (settings-p my)))

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
          (? my --file))
  (format t "~&rows ~a~%" n)
  (assert (= n 399)))

(defun eg--data (&aux (i (make-data (? my --file))))
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
  (let* ((lab (landscape i))
         (ys  (mapcar (lambda (r) (disty i r)) lab)))
    (format t "~&labelled ~a best ~,3f worst ~,3f~%"
            (length lab) (first ys) (car (last ys)))
    (assert (<= (length lab)
                (- (? my --budget) (? my --check))))
    (assert (equal ys (sort (copy-list ys) #'<)))
    (assert (< (first ys) 0.4))))

(defun eg--wins (&aux (i (make-data (? my --file))))
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

(defun eg--holdout (&aux (i (make-data (? my --file))))
  (setf (? i rows) (few (? i rows) (? my --cap)))
  (let* ((got (holdout i))
         (w   (round (funcall (wins i) got))))
    (format t "~&picked ~s~%win= ~a disty= ~,3f~%"
            got w (disty i got))
    (assert (vectorp got))
    (assert (<= -100 w 100))
    (if (search "auto93" (? my --file))
      (assert (> w 0)))))

(defun eg--holdouts (&aux (i (make-data (? my --file)))
                          w (n (make-num)))
  (setf (? i rows) (few (? i rows) (? my --cap))
        w (wins i))
  (dotimes (k 20)
    (add n (funcall w (holdout i))))
  (format t "~&mu ~5,1f sd ~5,1f ~a~%"
          (mid n) (spread n) (? my --file))
  (assert (<= -100 (mid n) 100))
  (if (search "auto93" (? my --file))
    (assert (> (mid n) 50))))

(defun eg--same (&aux xs)
  (dotimes (k 20) (push (rand) xs))
  (let ((ys (mapcar (lambda (x) (+ x 0.02)) xs))
        (zs (mapcar (lambda (x) (+ x 1)) xs)))
    (format t "~&same: self ~a nudged ~a shifted ~a~%"
            (same xs xs) (same xs ys) (same xs zs))
    (assert (same xs xs))
    (assert (same xs ys))
    (assert (not (same xs zs)))))

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

(defun eg--delta (&aux (i (make-data (? my --file))))
  "rq2: active vs random labelling, budget 50"
  (setf (? i rows) (few (? i rows) (? my --cap)))
  (deltas i '--landscape "active" "random"))

(defun eg--budgets (&aux (i (make-data (? my --file))))
  "rq1: budget 50 vs 20, both active"
  (setf (? i rows) (few (? i rows) (? my --cap)))
  (deltas i '--budget 50 20))

(defun eg--saturate (&aux (i (make-data (? my --file))))
  "rq1 caveat: budget 200 vs 50 (sampler stops near 40)"
  (setf (? i rows) (few (? i rows) (? my --cap)))
  (deltas i '--budget 200 50))

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
    (setf *seed* (? my --seed))
    (funcall s)))

;----------------------------------------------------------------
(cli my)
