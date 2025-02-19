(defpackage :cp/ext-gcd
  (:use :cl)
  (:import-from :sb-c #:defoptimizer #:defknown #:movable #:foldable #:flushable
                #:derive-type #:lvar-type #:integer-type-numeric-bounds #:make-numeric-type
                #:make-values-type)
  (:export #:ext-gcd)
  (:documentation "Provides extended euclidean algorithm (aka Blankinship algorithm).

Reference:
https://topcoder-g-hatena-ne-jp.jag-icpc.org/spaghetti_source/20130126/"))
(in-package :cp/ext-gcd)

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (defknown %ext-gcd (integer integer) (values integer integer)
      (movable foldable flushable)
    :overwrite-fndb-silently t)
  (defoptimizer (%ext-gcd derive-type) ((a b))
    (multiple-value-bind (lo1 hi1) (integer-type-numeric-bounds (lvar-type a))
      (multiple-value-bind (lo2 hi2) (integer-type-numeric-bounds (lvar-type b))
        (let ((type
                (if (every #'integerp (list lo1 hi1 lo2 hi2))
                    (let ((max (max (abs lo1) (abs hi1) (abs lo2) (abs hi2))))
                      (make-numeric-type :class 'integer :low `(,(- max)) :high `(,max)))
                    (make-numeric-type :class 'integer))))
          (make-values-type :required (list type type)))))))

(defun %ext-gcd (a b)
  (declare (optimize (speed 3) (safety 0))
           (integer a b)
           #+sbcl (sb-ext:muffle-conditions sb-ext:compiler-note))
  (macrolet ((frob (type)
               `(let ((y 1)
                      (x 0)
                      (u 1)
                      (v 0))
                  (declare (,type y x u v a b))
                  (loop (when (zerop a)
                          (return (values x y)))
                        (let ((q (floor b a)))
                          (decf x (the ,type (* q u)))
                          (rotatef x u)
                          (decf y (the ,type (* q v)))
                          (rotatef y v)
                          (decf b (the ,type (* q a)))
                          (rotatef b a))))))
    (if (and (typep a 'fixnum) (typep b 'fixnum))
        (frob fixnum)
        (frob integer))))

(declaim (inline ext-gcd))
(defun ext-gcd (a b)
  "Returns two integers X and Y which satisfy AX + BY = gcd(A, B)."
  (declare (integer a b))
  (if (>= a 0)
      (if (>= b 0)
          (%ext-gcd a b)
          (multiple-value-bind (x y) (%ext-gcd a (- b))
            (values x (- y))))
      (if (>= b 0)
          (multiple-value-bind (x y) (%ext-gcd (- a) b)
            (values (- x) y))
          (multiple-value-bind (x y) (%ext-gcd (- a) (- b))
            (values (- x) (- y))))))
