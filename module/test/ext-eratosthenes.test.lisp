(eval-when (:compile-toplevel :load-toplevel :execute)
  (load "test-util")
  (load "../ext-eratosthenes.lisp"))

(use-package :test-util)

(with-test (:name make-minfactor-table)
  (signals type-error (make-minfactor-table 0))
  (signals type-error (make-minfactor-table 1))
  (assert (equalp #(0 1) (make-minfactor-table 2)))
  (assert (equalp #(0 1 2) (make-minfactor-table 3)))
  (assert (equalp #(0 1 2 3 2 5 2 7 2 3) (make-minfactor-table 10)))
  (assert (equalp #(0 1 2 3 2 5 2 7 2 3 2 11 2 13 2 3 2 17 2 19 2 3 2 23 2 5 2 3 2 29)
                  (make-minfactor-table 30)))
  (let ((table (make-minfactor-table 200)))
    (loop for i from 2 below 200
          when (= (aref table i) i)
          do (assert (sb-int:positive-primep i)))))


(defun set-equal (list1 list2)
  (let ((table1 (make-hash-table :test #'equalp))
        (table2 (make-hash-table :test #'equalp)))
    (dolist (x list1)
      (setf (gethash x table1) t))
    (dolist (x list2)
      (setf (gethash x table2) t))
    (and (loop for x in list1 always (gethash x table2))
         (loop for x in list2 always (gethash x table1)))))

(with-test (:name factorize-osak)
  (assert (equal '((2 . 2) (3 . 2) (7 . 1))
                 (factorize -252 (make-minfactor-table 253))))
  (assert (null (factorize 1 (make-minfactor-table 10))))
  (assert (null (factorize 0 (make-minfactor-table 10))))
  (signals simple-error (factorize 252 (make-minfactor-table 252))))
 
