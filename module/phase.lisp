(defpackage :cp/phase
  (:use :cl)
  (:export #:phase<))
(in-package :cp/phase)

(declaim (inline phase<))
(defun phase< (p1 p2)
  "Returns true iff (< (phase p1) (phase p2))."
  (let ((x1 (realpart p1))
        (y1 (imagpart p1))
        (x2 (realpart p2))
        (y2 (imagpart p2)))
    (cond ((zerop y1)
           (and (>= x1 0)
                (or (> y2 0)
                    (and (zerop y2) (< x2 0)))))
          ((zerop y2)
           (or (< x2 0)
               (and (>= x2 0) (< y1 0))))
          ((and (> y2 0) (< y1 0)) t)
          ((and (< y2 0) (> y1 0)) nil)
          (t (> (* x1 y2) (* x2 y1))))))

