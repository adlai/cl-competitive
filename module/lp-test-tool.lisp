(defpackage :cp/lp-test-tool
  (:use :cl :cp/gaussian)
  (:export #:make-random-instance #:copy #:dual-std))
(in-package :cp/lp-test-tool)

(defun make-random-instance (sigma non-negative-b &optional round (size 5))
  (declare (optimize (speed 3))
           (double-float sigma))
  (let* ((m (round (* size (exp (* #.(log 10d0) (random 1d0))))))
         (n (round (* size (exp (* #.(log 10d0) (random 1d0))))))
         (as (make-array (list m n) :element-type 'double-float :initial-element 0d0))
         (bs (make-array m :element-type 'double-float :initial-element 0d0))
         (cs (make-array n :element-type 'double-float :initial-element 0d0)))
    (labels ((%rand ()
               (let ((val (* sigma (gaussian))))
                 (if round (fround val) val))))
      (dotimes (i m)
        (dotimes (j n)
          (setf (aref as i j) (%rand))))
      (dotimes (i m)
        (setf (aref bs i) (%rand)))
      (when non-negative-b
        (dotimes (i m)
          (setf (aref bs i) (abs (aref bs i)))))
      (dotimes (j n)
        (setf (aref cs j) (%rand)))
      (values as bs cs))))

(defun copy (a)
  (let ((res (make-array (array-dimensions a) :element-type 'double-float)))
    (replace (sb-ext:array-storage-vector res) (sb-ext:array-storage-vector a))
    res))

(declaim (ftype (function * (values (simple-array double-float (* *))
                                    (simple-array double-float (*))
                                    (simple-array double-float (*))
                                    &optional))
                dual-std))
(defun dual-std (a b c)
  (destructuring-bind (m n) (array-dimensions a)
    (let ((a* (make-array (list n m) :element-type 'double-float :initial-element 0d0))
          (b* (map '(simple-array double-float (*)) #'- c))
          (c* (map '(simple-array double-float (*)) #'- b)))
      (dotimes (i m)
        (dotimes (j n)
          (setf (aref a* j i) (- (aref a i j)))))
      (values a* b* c*))))
