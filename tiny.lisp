; vim: set ft=lisp ts=2 sw=2 et :
; tiny.lisp -- least macros that most shrink Common Lisp.
; (c) 2026 Tim Menzies timm@ieee.org, MIT license.
;
; Macros:
;   (def f (x) ...)        short defun
;   (def+ f ((x cls)) ..)  short defmethod
;   (f_ ...) (ff_ ...)     lambda of _, of _ __
;   (! f x)                funcall
;   (? x a b)              chained field access, setf-able
;   (let+ ((x 1)                    var
;          ((a b) lst)              destructure
;          (f (z) (* z 2))) ...)    local function
; Reader macros:
;   {k v ...}              equal-hash literal, keys quoted
;   @key                   (? *the* key) -- app settings
;   $slot                  (ats i 'slot) -- i = self
; Utils:
;   o ats keys cat prn least most
;   thing cells csv args cli
;   rand rint shuffle few

#+sbcl (declaim (sb-ext:muffle-conditions
                  warning style-warning))
(setf *read-default-float-format* 'double-float)

(defvar *the* nil)
(defvar *seed* 1234567891)

;;; ----- macros ----------------------------------------------
(defmacro def (name args &body body)
  `(defun ,name ,args ,@body))

(defmacro f_ (&body b)
  `(lambda (_) (declare (ignorable _)) ,@b))

(defmacro ff_ (&body b)
  `(lambda (_ __) (declare (ignorable _ __)) ,@b))

(defmacro ! (f &rest a) `(funcall ,f ,@a))

(defmacro ? (x k &rest ks)
  (if ks `(? (ats ,x ',k) ,@ks) `(ats ,x ',k)))

(defmacro let+ ((b &rest bs) &body body)
  (let ((tail (if bs `((let+ ,bs ,@body)) body)))
    (cond ((consp (first b))
           `(destructuring-bind ,(first b) ,(second b)
              ,@tail))
          ((cddr b)
           `(labels ((,(first b) ,@(rest b))) ,@tail))
          (t
           `(let ((,(first b) ,(second b))) ,@tail)))))

(defmacro def+ (name args &body body)
  `(defmethod ,name ,args ,@body))

;;; ----- hashes as records -----------------------------------
(def o (&rest kvs)
  (let ((h (make-hash-table :test #'equal)))
    (loop for (k v) on kvs by #'cddr
          do (setf (gethash k h) v))
    h))

(def ats (x k &optional d)
  (if (hash-table-p x) (gethash k x d) (slot-value x k)))

(def (setf ats) (v x k &optional d)
  (declare (ignore d))
  (if (hash-table-p x)
      (setf (gethash k x) v)
      (setf (slot-value x k) v)))

(def keys (h)
  (loop for k being the hash-keys of h collect k))

;;; ----- reader macros ---------------------------------------
(set-macro-character #\{
  (lambda (s c)
    (declare (ignore c))
    (let ((l (read-delimited-list #\} s t)))
      `(o ,@(loop for (k v) on l by #'cddr
                  append (list `',k v)))))
  t)

(set-macro-character #\} (get-macro-character #\)) nil)

(set-macro-character #\@
  (lambda (s c)
    (declare (ignore c))
    `(ats *the* ',(read s t nil t)))
  t)

(set-macro-character #\$
  (lambda (s c)
    (declare (ignore c))
    `(ats i ',(read s t nil t)))
  t)

;;; ----- little things ----------------------------------------
(def cat (&rest l) (format nil "~{~a~}" l))

(def prn (f &rest a) (format t "~?~%" f a))

(def least (l f)
  (reduce (ff_ (if (<= (! f _) (! f __)) _ __)) l))

(def most (l f)
  (reduce (ff_ (if (>= (! f _) (! f __)) _ __)) l))

;;; ----- strings to things -----------------------------------
(def thing (s)
  (let ((s (string-trim " " s)))
    (cond ((equal s "?")     '?)
          ((equal s "True")  t)
          ((equal s "False") nil)
          (t (multiple-value-bind (x n)
                 (let ((*read-eval* nil))
                   (read-from-string s nil))
               (if (and (numberp x) (= n (length s)))
                   x
                   s))))))

(def cells (s)
  (loop for a = 0 then (1+ b)
        for b = (position #\, s :start a)
        collect (string-trim " " (subseq s a b))
        while b))

(def csv (file)
  (with-open-file (in file)
    (loop for ln = (read-line in nil)
          while ln
          for l = (string-trim '(#\space #\tab #\return)
                               ln)
          unless (or (equal l "")
                     (eql (char l 0) #\#))
          collect (mapcar #'thing (cells l)))))

;;; ----- cli ---------------------------------------------------
(def args ()
  #+sbcl (cdr sb-ext:*posix-argv*)
  #+clisp ext:*args*)

(def cli ()
  (loop for (f v) on (args) do
    (dolist (k (keys *the*))
      (when (equal f (cat "-" (char (string-downcase k)
                                    0)))
        (setf (ats *the* k) (thing v))))))

;;; ----- random ------------------------------------------------
(def rand (&optional (n 1))
  (setf *seed* (mod (* 16807 *seed*) 2147483647))
  (* n (/ *seed* 2147483647.0)))

(def rint (&optional (n 2)) (floor (rand n)))

(def shuffle (l)
  (let ((v (coerce l 'vector)))
    (loop for i from (1- (length v)) downto 1
          do (rotatef (aref v i) (aref v (rint (1+ i)))))
    (coerce v 'list)))

(def few (l n) (subseq (shuffle l) 0 n))
