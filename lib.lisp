; vim: set ft=lisp ts=2 sw=2 et :

; lib.lisp -- general "battery" utilities for the plus dialect:
;             stats, reproducible random, list/char/string
;             helpers, CSV reader.
; (c) 2026 Tim Menzies, timm@ieee.org, MIT license.
;
; Load AFTER plus.lisp: this file uses plus's @ reader macro
; (dist) and let+/f+ macros (%extremum-by, %stride), and shares
; its *seed* (random) and *the* (@p) specials.
;
; UTILITIES
;   stats:   adds sub dist sortby %extremum-by %stride
;   random:  rand rint shuffle
;   chars:   ch
;   strings: cells thing read-csv

;; =============================================
;; Utilities
;; =============================================

; ### Stats
(defun adds (lst &optional (summary (make-num)))
  "Fold LST into SUMMARY via `add`."
  (dolist (v lst summary) (add summary v)))

(defun sub (it v) (add it v -1))

(defun dist (lst f &aux (d 0))
  "Minkowski @p-norm of (! f v) for v in LST."
  (dolist (v lst (expt (/ d (length lst)) (/ 1 @p)))
    (incf d (expt (! f v) @p))))

(defun sortby (key lst) (sort (copy-list lst) #'< :key key))

(defun %extremum-by (lst key cmp)
  "Argmin/argmax of LST under KEY, ordered by CMP."
  (let+ ((best (car lst)) (m (! key best)))
    (dolist (x (cdr lst) best)
      (let ((k (! key x)))
        (when (! cmp k m) (setf best x m k))))))

(defun %stride (rows key &optional (n 30))
  (loop for x in (sort rows #'< :key key)
        by (f+ (nthcdr n _)) do (print x)))

; ### Random
(defun rand (&optional (n 1))
  "Reproducible float in [0,n). Advances *seed*."
  (setf *seed* (mod (* 16807.0d0 *seed*) 2147483647.0d0))
  (* n (- 1.0d0 (/ *seed* 2147483647.0d0))))

(defun rint (&optional (n 100) &aux (base 1E10))
  "Reproducible integer in [0,n)."
  (floor (* n (/ (rand base) base))))

; ### Lists
(defun shuffle (lst &aux (v (coerce lst 'vector)))
  "Fisher-Yates shuffle of LST. Seeded via *seed*."
  (loop for i from (1- (length v)) downto 1 do
    (rotatef (aref v i) (aref v (rint (1+ i)))))
  (coerce v 'list))

; ### Characters
(defun ch (s n c)
  "Is char N of S equal to C? S is a string or symbol;
   N<0 counts from the end. E.g. (ch 'mpg- -1 #\\-) => t."
  (let ((s (string s)))
    (char= c (char s (if (minusp n) (+ (length s) n) n)))))

; ### Strings / IO
(defun cells (s sep)
  "Split S on character SEP into substring list."
  (loop for start = 0 then (1+ end)
    for end = (position sep s :start start)
    collect (subseq s start end)
    while end))

(defun thing (str
              &aux (v (ignore-errors
                        (read-from-string str))))
  "Coerce STR to number; '? for \"?\"; else string."
  (cond ((numberp v) v)
        ((string= str "?") '?)
        (t str)))

(defun read-csv (file)
  "Read FILE as CSV; coerce cells via `thing`."
  (with-open-file (s file)
    (loop for line = (read-line s nil) while line
      collect (mapcar #'thing (cells line #\,)))))
