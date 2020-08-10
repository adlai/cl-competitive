;; OBSOLETE

(defmacro dorange ((var begin end &optional step) &body body)
  "is a variant of DOTIMES for a given range."
  (check-type step (or null (and integer (not (integer 0 0)))))
  (check-type var symbol)
  (let ((step (or step 1))
        (e (gensym)))
    `(do ((,var ,begin (+ ,var ,step))
          (,e (the integer ,end)))
         ((,(if (> step 0) '>= '<=) ,var ,e))
       (declare (type integer ,var))
       ,@body)))
