; vim: set lispwords+=loop,aif,set-macro-character :
#+sbcl (declaim (sb-ext:muffle-conditions
                  warning style-warning))

(defmacro ? (x k &rest ks)
  (if ks `(? (ats ,x ',k) ,@ks) `(ats ,x ',k)))

(set-macro-character #\$ 
  (lambda (stream ch)
    (declare (ignore ch)) `(ats i ',(read stream t nil t))))

(defun slot-names (x)
  (mapcar #+sbcl  #'sb-mop:slot-definition-name
          #+clisp #'clos:slot-definition-name
          (#+sbcl  sb-mop:class-slots
           #+clisp clos:class-slots
           (find-class (if (symbolp x) x (type-of x))))))

(defmacro aif (test then &optional else)
  `(let ((it ,test))
     (if it ,then ,else)))

(defun trim (s) (string-trim '(#\space #\tab #\return) s))

(defun thing (s &aux (opt '(("?" . ?) ("True" . t) ("False"))))
  (let ((s (trim s))
        (*read-eval*))
  (aif (assoc s opt :test #'equal)
    (cdr it)
    (let ((x (ignore-errors (read-from-string s nil))))
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

(defun ats! (x k new)
  "get x's k, else stash and return a fresh (new)"
  (or (ats x k) (setf (ats x k) (funcall new))))

(defun (setf ats) (v x k &optional d)
  (declare (ignore d))
  (if (hash-table-p x)
      (setf (gethash k x) v)
      (setf (slot-value x k) v)))

(defun cli (my)
  (let ((args #+sbcl (cdr sb-ext:*posix-argv*)
              #+clisp ext:*args*))
    (loop for (f v) on args do
      (dolist (slot (slot-names my))
        (if (equalp f (string slot))
          (setf (slot-value my slot) (thing v)))))
    (loop for s in args do
      (let ((fun (intern (format nil "EG~:@(~a~)" s))))
        (when (fboundp fun)
          (setf *seed* (? my --seed))
          (funcall fun))))))

(defvar *seed* 1234567891)
(defun rint (&optional (n 2)) (floor (rand n)))

(defun rand (&optional (n 1))
  (setf *seed* (mod (* 16807 *seed*) 2147483647))
  (* n (/ *seed* 2147483647.0)))

(defun o (&rest kvs)
  (let ((h (make-hash-table :test #'equal)))
    (loop for (k v) on kvs by #'cddr do (setf (gethash k h) v))
    h))

(defun cat (&rest xs) (format nil "~{~a~}" xs))

(defun lt (a b)
  "order numbers numerically, anything else textually"
  (if (and (numberp a) (numberp b))
    (< a b)
    (string< (princ-to-string a) (princ-to-string b))))

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
