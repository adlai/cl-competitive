(defpackage :cp/test/convolution-ntt
  (:use :cl :fiveam :cp/convolution-ntt)
  (:import-from :cp/test/base #:base-suite)
  (:import-from :cp/convolution-ntt #:inv-gcd))
(in-package :cp/test/convolution-ntt)
(in-suite base-suite)

;; from https://github.com/atcoder/ac-library/blob/master/test/unittest/internal_math_test.cpp
(test inv-gcd
  (let ((*test-dribble* nil)
        (list (list 998244353 -998244353 100000007 -100000007 100000009 -100000009)))
    (loop for i to 10
          do (push i list)
             (push (- i) list)
             (push (+ most-negative-fixnum i) list)
             (push (- most-positive-fixnum i) list)
             (push (+ (floor most-negative-fixnum 2) i) list)
             (push (- (floor most-negative-fixnum 2) i) list)
             (push (- (floor most-positive-fixnum 2) i) list)
             (push (+ (floor most-positive-fixnum 2) i) list)
             (push (+ (floor most-negative-fixnum 3) i) list)
             (push (- (floor most-negative-fixnum 3) i) list)
             (push (- (floor most-positive-fixnum 3) i) list)
             (push (+ (floor most-positive-fixnum 3) i) list))
    (dolist (a list)
      (dolist (b list)
        (when (> b 0)
          (let* ((a2 (mod a b))
                 (g (gcd a2 b)))
            (multiple-value-bind (eg ex) (inv-gcd a b)
              (is (= g eg))
              (is (>= ex 0))
              (is (<= ex (truncate b eg)))
              (is (= (mod g b) (mod (* ex a2) b))))))))))

(defun convolve-naive (vector1 vector2)
  (let ((n (length vector1))
        (m (length vector2)))
    (when (or (zerop n) (zerop m))
      (return-from convolve-naive
        (make-array 0 :element-type 'convolution-int)))
    (let* ((result (make-array (+ n m -1) :element-type 'convolution-int)))
      (dotimes (i (+ n m -1))
        (setf (aref result i)
              (loop for x from (max 0 (+ 1 (- i m))) to (min i (- n 1))
                    sum (* (aref vector1 x) (aref vector2 (- i x))))))
      result)))

(test convolution/random
  (let ((*test-dribble* nil)
        (*random-state* (sb-ext:seed-random-state 0)))
    (dotimes (_ 2000)
      (let ((vector1 (make-array (random 30) :element-type 'fixnum))
            (vector2 (make-array (random 30) :element-type 'fixnum)))
        (dotimes (i (length vector1))
          (setf (aref vector1 i) (- (random 1000) 500)))
        (dotimes (i (length vector2))
          (setf (aref vector2 i) (- (random 1000) 500)))
        (is (equalp (convolve vector1 vector2)
                    (convolve-naive vector1 vector2)))))))
