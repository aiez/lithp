; vim: set lispwords+=loop,aif,set-macro-character :

(set-macro-character #\$ 
  (lambda (stream ch)
    (declare (ignore ch)) `(ats i ',(read stream t nil t))))

(defun slot-names (x)
  (mapcar #+sbcl  #'sb-mop:slot-definition-name
          #+clisp #'clos:slot-definition-name
          (#+sbcl  sb-mop:class-slots
           #+clisp clos:class-slots
           (find-class (if (symbolp x) x (type-of x))))))

(defmacro aif (test then else)
  `(let ((it ,test))
     (if it ,then ,else)))

(defun trim (s) (string-trim '(#\space #\tab #\return) s))

(defun thing (s &aux (opt '(("?" . ?) ("True" . t) ("False"))))
  (let ((s (trim s))
        (*read-eval*))
  (aif (assoc s opt :test #'equal)
    (cdr it)
    (let ((x (read-from-string s nil)))
      (if (numberp x) x s)))))

(defun things (s &optional (ch #\,) (start 0))
  (aif (position ch s :start start)
    (cons (thing (subseq s start it)) (things s ch (1+ it)))
    (list (thing (subseq s start)))))

(defun mapcsv (fun file)
  (labels ((fun (s &aux (s1 (trim s)))
                (unless (or (equal s1 "") (eql (char s1 0) #\#))
                  (funcall fun (coerce (things s1) 'vector)))))
    (with-open-file (s file)
      (loop (fun (or (read-line s nil) (return)))))))

(defun ats (x k &optional d)
  (if (hash-table-p x) (gethash k x d) (slot-value x k)))

(defun (setf ats) (v x k &optional d)
  (declare (ignore d))
  (if (hash-table-p x)
      (setf (gethash k x) v)
      (setf (slot-value x k) v)))

(defun cli (it)
  (let ((args #+sbcl (cdr sb-ext:*posix-argv*)
              #+clisp ext:*args*))
    (loop for (f v) on args do
      (dolist (slot (slot-names it))
        (if (equalp f (string slot))
          (setf (slot-value it slot) (thing v)))))
    (loop for s in args do
      (let ((fun (intern (format nil "~{~a~}" s))))
        (when (fboundp fun)
          (setf *seed* (--seed it))
          (funcall fun)))))
    i)

(defvar *seed* 1234567891)
(defun rint (&optional (n 2)) (floor (rand n)))

(defun rand (&optional (n 1))
  (setf *seed* (mod (* 16807 *seed*) 2147483647))
  (* n (/ *seed* 2147483647.0)))

(defun o (&rest kvs)
  (let ((h (make-hash-table :test #'equal)))
    (loop for (k v) on kvs by #'cddr do (setf (gethash k h) v))
    h))

(defun vec (&rest xs)
  (make-array (length xs) 
    :fill-pointer t :adjustable t :initial-contents xs))
