; vim: set ft=lisp ts=2 sw=2 et :

; plus.lisp -- tiny Common Lisp dialect: struct+methods,
;              anaphora, slot access, list comprehension,
;              CLI framework. General utilities live in lib.lisp.
; (c) 2026 Tim Menzies, timm@ieee.org, MIT license.
;
; READER MACROS & ANAPHORA
;   $field  -> (slot-value i 'field)   ; i = self
;   @key    -> (second (assoc 'key *the*))
;   (? x a) -> (slot-value x 'a); chains: (? x a b c)
;   (if+ t x y)  binds `it` to t's value in x/y
;   (! f a b)    -> (funcall f a b)
;
; OO HELPERS
;   (plus name [doc] slots (m args body)...)
;     defstruct + defmethod each method on `i`.
;     Pseudo-methods (make works like Python __init__:
;     body configures i, never returns it; plus does):
;       (make () BODY...)        post-init; i auto-returned
;       (make (ARGS) BODY...)    custom args; bind i in &aux
;       (:opts ((opt ...) ...))  extra defstruct options
;     The macro always adds (:constructor %make-NAME).
;   (plus+ name (m args body)...)  add methods to a struct
;   (new+ cls k v ...)             -> (make-cls k v ...)
;
; LAMBDA SHORTCUTS
;   (f+   body)  = (lambda (_)        body)
;   (ff+  body)  = (lambda (_ __)     body)
;   (fff+ body)  = (lambda (_ __ ___) body)
;
; LIST COMPREHENSION
;   (for+ EXPR for var in lst [if TEST] ...)
;
; SEQUENTIAL BINDINGS
;   (let+ ((var val)        ; let
;          ((a b) form)     ; multiple-value-bind (flat symbols)
;          ((a (b c)) v)    ; destructuring-bind  (nested pattern)
;          (name args body)) ; labels
;     ...)
;   Caveat: dbind on a flat-symbol pattern conflicts; use
;   plain destructuring-bind in that case.
;
; UTILITIES (moved to lib.lisp -- load AFTER this file)
;   stats:   adds sub dist sortby %extremum-by %stride
;   random:  rand rint shuffle
;   strings: ch cells thing read-csv
;
; CLI FRAMEWORK
;   @key reader macro reads from *the* (app must define).
;   run, args, cli, defeg, eg--all, eg-s
;
;   Apps: (load "plus") (load "lib"), define *the*, set
;   *seed* to @seed, define eg-- functions, call (cli *the*).

;## simplify debugging
#+sbcl (declaim (sb-ext:muffle-conditions
                  warning style-warning))
#+sbcl (setf sb-ext:*invoke-debugger-hook*
             (lambda (c h) (declare (ignore h))
               (format *error-output* "~&[ERROR] ~a~%" c)
               (sb-ext:exit :code 1)))

;; =============================================
;; Macros
;; =============================================

(defmacro defread (name (stream) &body body)
  "Install BODY as reader-macro for char NAME."
  `(set-macro-character
     ,(character (symbol-name name))
     (lambda (,stream c) (declare (ignore c)) ,@body)
     t))

(defread $(s)
  `(slot-value i ',(read s t nil t)))

(defvar *the*)

(defread @(s)
  `(second (assoc ',(read s t nil t) *the*)))

(defvar *seed* 1)

(defmacro ? (x &rest at)
  "Nested slot access: (? x a b)
   = (slot-value (slot-value x 'a) 'b)."
  (if at `(? (slot-value ,x ',(car at)) ,@(cdr at))
         x))

(defmacro if+ (test then &optional else)
  "Anaphoric if: bind `it` to TEST in THEN/ELSE."
  `(let ((it ,test)) (if it ,then ,else)))

(defmacro f+  (&body b) `(lambda (_)         ,@b))
(defmacro ff+  (&body b) `(lambda (_ __)      ,@b))
(defmacro fff+ (&body b) `(lambda (_ __ ___)  ,@b))

(defmacro ! (f &rest args)
  "Funcall shortcut: (! f a b) = (funcall f a b)."
  `(funcall ,f ,@args))

(defun acc (c s) (intern (format nil "~A-~A" c s)))

(defmacro new+ (cls &rest kvs)
  "(new+ num :goal 0) -> (make-num :goal 0)."
  `(,(intern (format nil "MAKE-~A" cls)) ,@kvs))

(defmacro plus+ (name &body methods)
  "Add methods to an existing struct NAME.

   Each (mname (args...) body...) becomes
     (defmethod mname ((i NAME) args...) body...).

   make is NOT accepted here -- the constructor is a
   struct-time concern. Use PLUS to define a struct with
   its make-NAME, then PLUS+ to add more methods later."
  (when (find 'make methods :key #'car)
    (error "PLUS+ does not accept make. Use PLUS."))
  `(progn
     ,@(loop for (m args . body) in methods collect
             `(defmethod ,m ((i ,name) ,@args)
                ,@body))
     ',name))

(defmacro plus (name &rest rest)
  "Defstruct + methods on NAME.

   (plus NAME [DOC] SLOTS METHODS...)

   DOC (optional string) becomes the defstruct docstring.
   SLOTS is the slot list.
   Pseudo-methods:
     (make () BODY...)         post-init hook; i auto-returned.
     (make (ARGS) BODY...)     custom args; bind i via &aux.
     (:opts ((opt ...) ...))   extra defstruct options.
   The macro always adds (:constructor %make-NAME) so the
   private form is available.  If make has no args, keyword
   arguments are forwarded to %make-NAME.  If no `make' is
   given, a thin wrapper is emitted.  The body never needs
   to return i -- plus appends it.

   The method list (excluding `make') is forwarded to PLUS+."
  (let* ((doc       (when (stringp (car rest)) (pop rest)))
         (slots     (pop rest))
         (methods   rest)
         (extra     (find :opts methods :key #'car))
         (methods   (remove :opts methods :key #'car))
         (make-spec (find 'make methods :key #'car))
         (methods   (remove 'make methods :key #'car))
         (priv      (intern (format nil "%MAKE-~A" name)))
         (pub       (intern (format nil  "MAKE-~A" name)))
         (make-defun
           (cond
             ((null make-spec)
              `(defun ,pub (&rest args) (apply #',priv args)))
             ((null (cadr make-spec))          ; (make () body...)
              `(defun ,pub (&rest args)
                 (let ((i (apply #',priv args)))
                   ,@(cddr make-spec) i)))
             (t                                ; (make (args...) body...)
              `(defun ,pub ,(cadr make-spec)
                 ,@(cddr make-spec) i))))
         (opts (cons `(:constructor ,priv)
                     (and extra (cadr extra)))))
    `(progn
       (defstruct (,name ,@opts)
         ,@(when doc (list doc))
         ,@slots)
       ,make-defun
       (plus+ ,name ,@methods)
       ',name)))

(defmacro for+ (expr &rest cs)
  "List comprehension. Nil results are skipped.

   (for+ EXPR for var in lst [if TEST] ...)

   E.g.  (for+ (* x x) for x in '(1 2 3 4 5) if (oddp x))
                 ==> (1 9 25)"
  (labels ((walk (cs)
             (cond ((null cs)
                    `(let ((v ,expr)) (if v (list v) nil)))
                   ((eq (car cs) 'for)
                    `(loop for ,(cadr cs) in ,(cadddr cs)
                           append ,(walk (cddddr cs))))
                   ((eq (car cs) 'if)
                    `(if ,(cadr cs) ,(walk (cddr cs)) nil)))))
    (walk cs)))

(defmacro let+ (((lhs &rest rhs) &rest rest) &body body)
  "Sequential bindings; entry shape picks form:
     (var val)         -> let
     ((sym...) val)    -> multiple-value-bind
     ((pat) val)       -> destructuring-bind  (pat has non-symbols)
     (name args body)  -> labels"
  (let ((tail (if rest `((let+ ,rest ,@body)) body)))
    (cond
      ((and (consp lhs) (every #'symbolp lhs))
       `(multiple-value-bind ,lhs ,(car rhs) ,@tail))
      ((consp lhs)
       `(destructuring-bind ,lhs ,(car rhs) ,@tail))
      ((cdr rhs)
       `(labels ((,lhs ,@rhs)) ,@tail))
      (t
       `(let ((,lhs ,(car rhs))) ,@tail)))))

;; =============================================
;; CLI framework
;; =============================================

(defmacro defeg (name doc &body body)
  "Define eg--NAME taking &optional file; bind rs+i (data).
   read-csv + make-data come from lib.lisp / the app."
  `(defun ,name (&optional (file @file))
     ,doc
     (let+ ((rs (read-csv file)) (i (make-data rs)))
       (declare (ignorable rs i))
       ,@body)))

(defun eg--all (&optional (arg @file))
  (do-symbols (s *package*)
    (let ((n (symbol-name s)))
      (when (and (fboundp s) (not (eq s 'eg--all))
                 (> (length n) 4) (string= n "EG--" :end1 4))
        (run s arg)))))

(defun eg-s (&optional (seed @seed))
  "Set seed."
  (setf *seed* seed  @seed  seed))

(defun run (it &optional arg)
  "Dispatch --flag to EG-FLAG function."
  (let+ ((f (if (symbolp it) it
                (intern (format nil
                                "EG~:@(~a~)" it))))
         (n (symbol-name f)))
    (when (and (fboundp f)
               (> (length n) 3)
               (string= n "EG-" :end1 3))
      (setf *seed* @seed)
      (if arg (! f arg) (! f))
      t)))

(defun args ()
  "Argv as list of strings (SBCL/CLISP portable)."
  #+sbcl (cdr sb-ext:*posix-argv*)
  #+clisp ext:*args*)

(defun cli (lsts)
  "Walk argv (flag arg) pairs: dispatch or update.
   `thing` comes from lib.lisp."
  (loop for (flag arg) on (args) by #'cddr do
    (unless (run flag (thing arg))
      (if+ (find flag lsts
                 :key #'third :test #'equalp)
           (setf (second it) (thing arg))))))
