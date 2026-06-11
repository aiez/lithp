;;;; yuck.lisp -- a deliberately naive first-pass port of
;;;; fft.py to Common Lisp: the code an LLM (or a newcomer)
;;;; writes before any style guide. CLOS ceremony, long names,
;;;; plist tree nodes, push/nreverse everywhere, getf config.
;;;; Same algorithm and seed as to_small.lisp: same output.
;;;; Kept as the "before" exhibit for blog.md.

#+sbcl (declaim (sb-ext:muffle-conditions
                  warning style-warning))
(setf *read-default-float-format* 'double-float)

;;; ----------------------------------------------------------
;;; Configuration
;;; ----------------------------------------------------------

(defparameter *config*
  (list :seed 1234567891
        :p 2
        :bins 7
        :depth 4
        :file "../optimiz/auto93.csv"))

(defun get-config (key)
  "Return the configuration value stored under KEY."
  (getf *config* key))

(defparameter *random-state-value* 1234567891)
(defparameter *big-number* 1e32)

;;; ----------------------------------------------------------
;;; Random numbers (Park-Miller, same as the Python)
;;; ----------------------------------------------------------

(defun random-float (&optional (n 1))
  "Return a pseudo-random float in [0, n)."
  (setf *random-state-value*
        (mod (* 16807 *random-state-value*) 2147483647))
  (* n (/ *random-state-value* 2147483647.0)))

(defun random-integer (&optional (n 2))
  "Return a pseudo-random integer in [0, n)."
  (floor (random-float n)))

(defun shuffle-list (input-list)
  "Return a shuffled copy of INPUT-LIST."
  (let ((vec (coerce input-list 'vector)))
    (loop for i from (1- (length vec)) downto 1
          do (rotatef (aref vec i)
                      (aref vec (random-integer (1+ i)))))
    (coerce vec 'list)))

(defun take-first-n (input-list n)
  "Return N random items from INPUT-LIST."
  (subseq (shuffle-list input-list) 0 n))

;;; ----------------------------------------------------------
;;; Reading CSV files
;;; ----------------------------------------------------------

(defun parse-cell (string)
  "Convert a CSV cell into a number, symbol, or string."
  (let ((trimmed (string-trim " " string)))
    (cond ((string= trimmed "?") '?)
          ((string= trimmed "True") t)
          ((string= trimmed "False") nil)
          (t (multiple-value-bind (value position)
                 (let ((*read-eval* nil))
                   (read-from-string trimmed nil))
               (if (and (numberp value)
                        (= position (length trimmed)))
                   value
                   trimmed))))))

(defun split-line-on-commas (line)
  "Split LINE into trimmed substrings at commas."
  (let ((result '())
        (start 0))
    (loop
      (let ((comma (position #\, line :start start)))
        (push (string-trim " " (subseq line start comma))
              result)
        (if comma
            (setf start (1+ comma))
            (return (nreverse result)))))))

(defun read-csv-file (filename)
  "Read FILENAME, returning a list of parsed rows."
  (let ((rows '()))
    (with-open-file (stream filename)
      (loop for line = (read-line stream nil)
            while line
            do (let ((clean (string-trim
                              '(#\space #\tab #\return)
                              line)))
                 (unless (or (string= clean "")
                             (char= (char clean 0) #\#))
                   (push (mapcar #'parse-cell
                                 (split-line-on-commas clean))
                         rows)))))
    (nreverse rows)))

;;; ----------------------------------------------------------
;;; Column classes
;;; ----------------------------------------------------------

(defclass numeric-column ()
  ((item-count :initform 0
               :initarg :item-count
               :accessor item-count
               :documentation "How many items were added.")
   (mean-value :initform 0.0
               :initarg :mean-value
               :accessor mean-value
               :documentation "Running mean of the items.")
   (m2-value :initform 0.0
             :initarg :m2-value
             :accessor m2-value
             :documentation "Sum of squared differences.")))

(defun make-numeric-column (&optional (n 0) (mu 0.0) (m2 0.0))
  (make-instance 'numeric-column
                 :item-count n
                 :mean-value mu
                 :m2-value m2))

(defclass symbolic-column ()
  ((value-counts :initform (make-hash-table :test #'equal)
                 :accessor value-counts
                 :documentation "Counts for each seen value.")))

(defun make-symbolic-column ()
  (make-instance 'symbolic-column))

(defun standard-deviation (column)
  "Return the standard deviation of a numeric COLUMN."
  (with-slots (item-count m2-value) column
    (if (< item-count 2)
        0
        (sqrt (/ (max 0 m2-value) (1- item-count))))))

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

(defun normalize (column value)
  "Map VALUE into 0..1 using a logistic squash."
  (let ((z (/ (- value (mean-value column))
              (+ (standard-deviation column) 1e-32))))
    (/ 1 (+ 1 (exp (* -1.7 (max -3 (min 3 z))))))))

(defgeneric mix-columns (a b &optional weight)
  (:documentation "Pool the statistics of two columns."))

(defmethod mix-columns ((a symbolic-column) b
                        &optional (weight 1))
  (let ((merged (make-symbolic-column)))
    (maphash (lambda (key count)
               (incf (gethash key (value-counts merged) 0)
                     count))
             (value-counts a))
    (maphash (lambda (key count)
               (incf (gethash key (value-counts merged) 0)
                     (* weight count)))
             (value-counts b))
    merged))

(defmethod mix-columns ((a numeric-column) b
                        &optional (weight 1))
  (let ((m (+ (item-count a) (* weight (item-count b))))
        (d (- (mean-value b) (mean-value a))))
    (if (< m 1)
        (make-numeric-column)
        (make-numeric-column
          m
          (/ (+ (* (item-count a) (mean-value a))
                (* weight (item-count b) (mean-value b)))
             m)
          (+ (m2-value a)
             (* weight (m2-value b))
             (/ (* weight d d (item-count a) (item-count b))
                m))))))

;;; ----------------------------------------------------------
;;; The data table
;;; ----------------------------------------------------------

(defclass data-table ()
  ((column-names :initarg :column-names
                 :accessor column-names)
   (x-columns :initform '()
              :accessor x-columns
              :documentation "Indexes of independent columns.")
   (y-columns :initform '()
              :accessor y-columns
              :documentation "Indexes of goal columns.")
   (goal-table :initform (make-hash-table :test #'equal)
               :accessor goal-table)
   (column-table :initform (make-hash-table :test #'equal)
                 :accessor column-table)
   (data-rows :initarg :data-rows
              :accessor data-rows)))

(defun assign-column-role (table name index)
  "Create a column object for NAME; return its role."
  (let ((last-char (char name (1- (length name)))))
    (setf (gethash index (column-table table))
          (if (lower-case-p (char name 0))
              (make-symbolic-column)
              (make-numeric-column)))
    (cond ((find last-char "-+!")
           (setf (gethash index (goal-table table))
                 (if (char= last-char #\+) 1 0))
           'y)
          ((not (char= last-char #\X)) 'x))))

(defun make-data-table (csv-rows)
  "Build a data table from parsed CSV-ROWS."
  (let ((table (make-instance 'data-table
                              :column-names (first csv-rows)
                              :data-rows (rest csv-rows)))
        (xs '())
        (ys '()))
    (let ((index 0))
      (dolist (name (column-names table))
        (let ((role (assign-column-role table name index)))
          (cond ((eq role 'x) (push index xs))
                ((eq role 'y) (push index ys))))
        (incf index)))
    (setf (x-columns table) (nreverse xs))
    (setf (y-columns table) (nreverse ys))
    (dolist (row (data-rows table) table)
      (let ((index 0))
        (dolist (value row)
          (setf (gethash index (column-table table))
                (add-value
                  (gethash index (column-table table))
                  value))
          (incf index))))))

(defun add-value (column value &optional (weight 1))
  "Add VALUE to COLUMN, ignoring missing values."
  (if (eq value '?)
      column
      (etypecase column
        (symbolic-column
          (incf (gethash value (value-counts column) 0)
                weight)
          column)
        (numeric-column
          (update-with-welford column value weight)))))

(defun add-all-values (values &optional
                       (column (make-numeric-column)))
  "Add every item in VALUES to COLUMN."
  (dolist (value values column)
    (setf column (add-value column value))))

(defun get-column (table index)
  (gethash index (column-table table)))

;;; ----------------------------------------------------------
;;; Discretization
;;; ----------------------------------------------------------

(defun bin-for-value (column value)
  "Return the bin that VALUE falls into."
  (etypecase column
    (symbolic-column value)
    (numeric-column
      (floor (* (get-config :bins)
                (normalize column value))))))

(defun top-for-value (column value old)
  "Track the highest value seen in a bin."
  (etypecase column
    (symbolic-column value)
    (numeric-column
      (max (or old (- *big-number*)) value))))

(defun hash-table-key-list (table)
  "Return the keys of TABLE as a list."
  (let ((keys '()))
    (maphash (lambda (key value)
               (declare (ignore value))
               (push key keys))
             table)
    (nreverse keys)))

(defun cuts-for-column (column rows scores index)
  "Return candidate cuts for one column."
  (let ((bin-stats (make-hash-table :test #'equal))
        (bin-highs (make-hash-table :test #'equal)))
    (loop for row in rows
          for score in scores
          do (let ((value (nth index row)))
               (unless (eq value '?)
                 (let ((key (bin-for-value column value)))
                   (setf (gethash key bin-stats)
                         (add-value
                           (or (gethash key bin-stats)
                               (make-numeric-column))
                           score))
                   (setf (gethash key bin-highs)
                         (top-for-value
                           column value
                           (gethash key bin-highs)))))))
    (cuts-from-bins column bin-stats bin-highs index)))

(defun cuts-from-bins (column bin-stats bin-highs index)
  "Turn binned statistics into (index lo hi stats) cuts."
  (etypecase column
    (symbolic-column
      (let ((result '()))
        (dolist (key (hash-table-key-list bin-stats)
                 (nreverse result))
          (push (list index
                      (gethash key bin-highs)
                      (gethash key bin-highs)
                      (gethash key bin-stats))
                result))))
    (numeric-column
      (let ((running (make-numeric-column))
            (result '()))
        (dolist (key (butlast
                       (sort (hash-table-key-list bin-stats)
                             #'<))
                 (nreverse result))
          (setf running
                (mix-columns running
                             (gethash key bin-stats)))
          (push (list index
                      (- *big-number*)
                      (gethash key bin-highs)
                      running)
                result))))))

(defun all-cuts (table rows score-function)
  "Return every candidate cut over every x column."
  (let ((scores (mapcar score-function rows))
        (result '()))
    (dolist (index (x-columns table) (nreverse result))
      (dolist (cut (cuts-for-column (get-column table index)
                                    rows scores index))
        (push cut result)))))

;;; ----------------------------------------------------------
;;; Growing trees
;;; ----------------------------------------------------------

(defun distance-to-heaven (table row)
  "Distance of ROW's goals from their best values."
  (let ((total 0))
    (dolist (index (y-columns table))
      (incf total
            (expt (abs (- (normalize
                            (get-column table index)
                            (nth index row))
                          (gethash index
                                   (goal-table table))))
                  (get-config :p))))
    (expt (/ total (length (y-columns table)))
          (/ 1.0 (get-config :p)))))

(defun value-in-range-p (value low high)
  "Does VALUE select this branch?"
  (cond ((symbolp value) t)
        ((stringp value) (equal value low))
        ((numberp value) (<= low value high))))

(defun find-best-cut (cuts comparison)
  "Return the cut whose leaf mean wins under COMPARISON."
  (let ((best (first cuts)))
    (dolist (cut (rest cuts) best)
      (when (funcall comparison
                     (mean-value (fourth cut))
                     (mean-value (fourth best)))
        (setf best cut)))))

(defun find-splits (table score-function root)
  "Return up to two (bit node rows) splits of TABLE."
  (let ((enough (expt (length (data-rows root)) .33))
        (candidates '()))
    (dolist (cut (all-cuts table (data-rows table)
                           score-function))
      (when (> (item-count (fourth cut)) enough)
        (push cut candidates)))
    (setf candidates (nreverse candidates))
    (when candidates
      (let ((result '()))
        (dolist (spec (list (list 0 #'<) (list 1 #'>))
                 (nreverse result))
          (let* ((bit (first spec))
                 (best (find-best-cut candidates
                                      (second spec)))
                 (col-index (first best))
                 (low (second best))
                 (high (third best))
                 (leaf (fourth best))
                 (remaining '()))
            (dolist (row (data-rows table))
              (unless (value-in-range-p
                        (nth col-index row) low high)
                (push row remaining)))
            (setf remaining (nreverse remaining))
            (when remaining
              (push (list bit
                          (list :at col-index
                                :lo low
                                :hi high
                                :left leaf)
                          remaining)
                    result))))))))

(defun attach-branch (node right)
  "Copy NODE, attaching RIGHT as its right child."
  (list :at (getf node :at)
        :lo (getf node :lo)
        :hi (getf node :hi)
        :left (getf node :left)
        :right right))

(defun grow-trees (table score-function root
                   &optional (depth 0))
  "Recursively grow all trees from TABLE."
  (let ((result '()))
    (when (< depth (get-config :depth))
      (dolist (split (find-splits table score-function
                                  root))
        (let* ((bit (first split))
               (node (second split))
               (rest-rows (third split))
               (kid (make-data-table
                      (cons (column-names table)
                            rest-rows))))
          (dolist (pair (grow-trees kid score-function
                                    root (1+ depth)))
            (push (list (format nil "~a~a"
                                bit (first pair))
                        (attach-branch node
                                       (second pair)))
                  result)))))
    (if result
        (nreverse result)
        (list (list ""
                    (add-all-values
                      (mapcar score-function
                              (data-rows table))))))))

;;; ----------------------------------------------------------
;;; Using trees
;;; ----------------------------------------------------------

(defun predict-row (tree row)
  "Walk TREE with ROW; return the leaf's mean."
  (if (typep tree 'numeric-column)
      (mean-value tree)
      (predict-row
        (if (value-in-range-p (nth (getf tree :at) row)
                              (getf tree :lo)
                              (getf tree :hi))
            (getf tree :left)
            (getf tree :right))
        row)))

(defun tree-error (tree rows score-function)
  "Mean absolute error of TREE's predictions over ROWS."
  (let ((total 0))
    (dolist (row rows)
      (incf total
            (abs (- (funcall score-function row)
                    (predict-row tree row)))))
    (/ total (length rows))))

(defun best-tree (trees rows score-function)
  "Return the tree with the lowest error."
  (let ((best (first trees)))
    (dolist (tree (rest trees) best)
      (when (< (tree-error tree rows score-function)
               (tree-error best rows score-function))
        (setf best tree)))))

(defun rule-as-string (table tree)
  "Render TREE's test as a human-readable rule."
  (let ((name (nth (getf tree :at) (column-names table)))
        (low (getf tree :lo))
        (high (getf tree :hi)))
    (cond ((equal low high)
           (format nil "~a == ~a" name low))
          ((= low (- *big-number*))
           (format nil "~a <= ~a" name high))
          (t
           (format nil "~a >= ~a" name low)))))

(defun show-tree (table tree)
  "Pretty print TREE, one rule per line."
  (if (typep tree 'numeric-column)
      (format t "~33a leaf  d2h ~,2f n=~d~%"
              "" (mean-value tree) (item-count tree))
      (let ((leaf (getf tree :left)))
        (format t "if ~30a then d2h ~,2f n=~d~%"
                (rule-as-string table tree)
                (mean-value leaf)
                (item-count leaf))
        (show-tree table (getf tree :right)))))

;;; ----------------------------------------------------------
;;; Demos
;;; ----------------------------------------------------------

(defun demo-main ()
  (let* ((table (make-data-table
                  (read-csv-file (get-config :file))))
         (score (lambda (row)
                  (distance-to-heaven table row)))
         (trees (mapcar #'second
                        (grow-trees table score table))))
    (show-tree table
               (best-tree trees (data-rows table) score))))

(defun demo-trees ()
  (let* ((table (make-data-table
                  (read-csv-file (get-config :file))))
         (score (lambda (row)
                  (distance-to-heaven table row)))
         (k 0))
    (dolist (pair (grow-trees table score table))
      (incf k)
      (format t
        "===== tree ~2d   bias ~5a   err ~,3f =====~%"
        k (first pair)
        (tree-error (second pair) (data-rows table)
                    score))
      (show-tree table (second pair))
      (terpri))))

(defun demo-grows (&optional (repeats 10) (sample-size 100))
  (let ((all-rows (read-csv-file (get-config :file)))
        (tree-count 0)
        (start-time (get-internal-real-time)))
    (loop repeat repeats
          do (let ((table (make-data-table
                            (cons (first all-rows)
                                  (take-first-n
                                    (rest all-rows)
                                    sample-size)))))
               (setf tree-count
                     (length
                       (grow-trees
                         table
                         (lambda (row)
                           (distance-to-heaven table row))
                         table)))))
    (let ((seconds (/ (- (get-internal-real-time)
                         start-time)
                      internal-time-units-per-second)))
      (format t
        "~dx (sample ~d, ~d trees): ~,3f s -> ~,1f ms~%"
        repeats sample-size tree-count seconds
        (* 1000 (/ seconds repeats))))))

;;; ----------------------------------------------------------
;;; Command line
;;; ----------------------------------------------------------

(defun command-line-arguments ()
  #+sbcl (cdr sb-ext:*posix-argv*)
  #+clisp ext:*args*)

(defun parse-command-line ()
  (let ((arguments (command-line-arguments)))
    (loop for (flag value) on arguments do
      (cond ((equal flag "-s")
             (setf (getf *config* :seed)
                   (parse-cell value)))
            ((equal flag "-p")
             (setf (getf *config* :p)
                   (parse-cell value)))
            ((equal flag "-b")
             (setf (getf *config* :bins)
                   (parse-cell value)))
            ((equal flag "-d")
             (setf (getf *config* :depth)
                   (parse-cell value)))
            ((equal flag "-f")
             (setf (getf *config* :file)
                   (parse-cell value)))))))

(parse-command-line)
(setf *random-state-value* (get-config :seed))
(cond ((member "--grows" (command-line-arguments)
               :test #'equal)
       (demo-grows))
      ((member "--trees" (command-line-arguments)
               :test #'equal)
       (demo-trees))
      (t (demo-main)))
