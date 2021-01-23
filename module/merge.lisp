(defpackage :cp/merge
  (:use :cl)
  (:export #:intersected-merge #:unique-merge))
(in-package :cp/merge)

;; unfinished && not tested
(declaim (inline intersect-merge))
(defun intersect-merge (element-type vec1 vec2 predicate)
  (let ((result (make-array 0 :element-type element-type :fill-pointer 0))
        (i1 0)
        (i2 0)
        (pos 0))
    (declare ((integer 0 #.most-positive-fixnum) i1 i2 pos))
    (loop
      (when (or (= i1 (length vec1))
                (= i2 (length vec2)))
        (return result))
      (cond ((funcall predicate (aref vec1 i1) (aref vec2 i2))
             (incf i1))
            ((funcall predicate (aref vec2 i2) (aref vec1 i1))
             (incf i2))
            (t
             (when (or (zerop pos)
                       (funcall predicate (aref result (- pos 1)) (aref vec1 i1)))
               (vector-push-extend (aref vec1 i1) result)
               (incf pos))
             (incf i1)
             (incf i2))))))


(declaim (inline unique-merge))
(defun unique-merge (element-type vec1 vec2 predicate)
  (let ((result (make-array 0 :element-type element-type :fill-pointer 0))
        (i1 1)
        (i2 0)
        (pos -1))
    (declare ((integer -1 #.most-positive-fixnum) i1 i2 pos))
    (loop
      (when (= i1 (length vec1))
        (loop (when (= i2 (length vec2))
                (return-from unique-merge result))
              (when (or (= -1 pos)
                        (funcall predicate (aref result pos) (aref vec2 i2)))
                (vector-push-extend (aref vec2 i2) result)
                (incf pos))
              (incf i2)))
      (when (= i2 (length vec2))
        (loop (when (= i1 (length vec1))
                (return-from unique-merge result))
              (when (or (= -1 pos)
                        (funcall predicate (aref result pos) (aref vec1 i1)))
                (vector-push-extend (aref vec1 i1) result)
                (incf pos))
              (incf i1)))
      (if (funcall predicate (aref vec1 i1) (aref vec2 i2))
          (progn
            (when (or (= -1 pos)
                      (funcall predicate (aref result pos) (aref vec1 i1)))
              (vector-push-extend (aref vec1 i1) result)
              (incf pos))
            (incf i1))
          (progn
            (when (or (= -1 pos)
                      (funcall predicate (aref result pos) (aref vec2 i2)))
              (vector-push-extend (aref vec2 i2) result)
              (incf pos))
            (incf i2))))))
