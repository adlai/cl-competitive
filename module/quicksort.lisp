(defpackage :cp/quicksort
  (:use :cl)
  (:export #:quicksort! #:quicksort-by2!)
  (:documentation "Provides quicksort (deterministic median-of-three
partitioning)"))
(in-package :cp/quicksort)

(declaim (inline %median3))
(defun %median3 (x y z order)
  ;; symbol-macrolet copilot STOP
  (if (funcall order x y)
      (if (funcall order y z)
          y
          (if (funcall order z x)
              x
              z))
      (if (funcall order z y)
          y
          (if (funcall order x z)
              x
              z))))

(declaim (inline quicksort!))
(defun quicksort! (vector order &key (start 0) end)
  "Destructively sorts VECTOR w.r.t. ORDER. You can rely on the side effect.

NOTE: This quicksort is NOT randomized. You need to shuffle an input to avoid
getting hacked. CP/SHUFFLE:SHUFFLE! is available for example.

Reference:
Hannu Erkio, The worst case permutation for median-of-three quicksort"
  (declare (vector vector)
           ((mod #.array-dimension-limit) start)
           ((or null (mod #.array-dimension-limit)) end))
  (unless end
    (setq end (length vector)))
  (assert (<= 0 start end))
  (labels
      ((recur (left right)
         (when (< left right)
           (let* ((l left)
                  (r right)
                  (pivot (%median3 (aref vector l)
                                   (aref vector (ash (+ l r) -1))
                                   (aref vector r)
                                   order)))
             (declare ((mod #.array-dimension-limit) l r))
             (loop (loop while (funcall order (aref vector l) pivot)
                         do (incf l))
                   (loop while (funcall order pivot (aref vector r))
                         do (decf r))
                   (when (>= l r)
                     (return))
                   (rotatef (aref vector l) (aref vector r))
                   (incf l 1)
                   (decf r 1))
             (recur left (- l 1))
             (recur (+ r 1) right)))))
    (recur start (- end 1))
    vector))

;; TODO: move to another module
(declaim (inline quicksort-by2!))
(defun quicksort-by2! (vector order)
  "Destructively sorts VECTOR by two elements. You can rely on the side
effect. This function regards each (VECTOR[i], VECTOR[i+1]) for even i as an
element, and compares only the first elements (i.e. VECTOR[i] for even i).

This sort was written to efficiently sort certain types of data."
  (declare (vector vector))
  (labels
      ((recur (left right)
         (when (< left right)
           (let* ((l left)
                  (r right)
                  (pivot (%median3 (aref vector l)
                                   (aref vector (ash (ash (+ l r) -2) 1))
                                   (aref vector r)
                                   order)))
             (declare ((mod #.array-dimension-limit) l r))
             (loop (loop while (funcall order (aref vector l) pivot)
                         do (incf l 2))
                   (loop while (funcall order pivot (aref vector r))
                         do (decf r 2))
                   (when (>= l r)
                     (return))
                   (rotatef (aref vector l) (aref vector r))
                   (rotatef (aref vector (+ l 1)) (aref vector (+ r 1)))
                   (incf l 2)
                   (decf r 2))
             (recur left (- l 2))
             (recur (+ r 2) right)))))
    (recur 0 (- (length vector) 2))
    vector))
