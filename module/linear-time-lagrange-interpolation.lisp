(defpackage :cp/linear-time-lagrange-interpolation
  (:use :cl :cp/binom-mod-prime :cp/mod-power :cp/mod-inverse)
  (:export #:lagrange-interpolation #:lagrange-interpolation0)
  (:documentation "Provides linear-time Lagrange interpolation over a finite
field. Input values must comprise an arithmetic progression.

Please note that here CP/BINOM-MOD-PRIME:+BINOM-MOD+ is used for a modulus."))
(in-package :cp/linear-time-lagrange-interpolation)

;; (lagrange-interpolation #(-5 -1 3 7 11) #(10 7 0 -8 13) (+ 7 (expt 10 9)))
;; #(254394539 466796877 678710942 287109377 820800787)
;; -> value at 1: 507812508

;; TODO: add docs
;; TODO: add test
(declaim (inline lagrange-interpolation))
(defun lagrange-interpolation (init difference values target)
  (declare (vector values)
           (integer init difference target))
  (let* ((init- (mod (- init) +binom-mod+))
         (difference (mod difference +binom-mod+))
         (difference- (mod (- difference) +binom-mod+))
         (target (mod target +binom-mod+))
         (n (length values)))
    (assert (not (zerop difference)))
    (when (zerop n)
      (return-from lagrange-interpolation
        (make-array 0 :element-type '(unsigned-byte 31))))
    (let ((/power (mod-power (mod-inverse difference +binom-mod+) (- n 1) +binom-mod+))
          (coefs (make-array n :element-type '(unsigned-byte 31) :initial-element 0)))
      (dotimes (i n)
        (let ((coef (mod (* (mod (* /power
                                    (mod (* (aref *fact-inv* i) (aref *fact-inv* (- n i 1)))
                                         +binom-mod+))
                                 +binom-mod+)
                            (the integer (aref values i)))
                         +binom-mod+)))
          (setf (aref coefs i)
                (if (evenp (- n i))
                    (- +binom-mod+ coef)
                    coef))))
      (let ((rprods (make-array (+ n 1) :element-type '(unsigned-byte 31)))
            (lprods (make-array (+ n 1) :element-type '(unsigned-byte 31)))
            (res 0))
        (declare ((unsigned-byte 31) res))
        (setf (aref lprods 0) (mod 1 +binom-mod+)
              (aref rprods n) (mod 1 +binom-mod+))
        (loop for i below n
              for x = (mod (+ target init-) +binom-mod+)
              then (mod (+ x difference-) +binom-mod+)
              do (setf (aref lprods (+ i 1)) (mod (* x (aref lprods i)) +binom-mod+)
                       (aref rprods i) x))
        (loop for i from (- n 1) downto 0
              do (setf (aref rprods i)
                       (mod (* (aref rprods i) (aref rprods (+ i 1))) +binom-mod+)))
        (dotimes (i n)
          (setq res (mod (+ res
                            (* (aref coefs i)
                               (mod (* (aref lprods i) (aref rprods (+ i 1))) +binom-mod+)))
                         +binom-mod+)))
        res))))

(declaim (inline lagrange-interpolation0))
(defun lagrange-interpolation0 (values target)
  (declare (vector values)
           (integer  target))
  (let* ((difference- (- +binom-mod+ 1))
         (target (mod target +binom-mod+))
         (n (length values)))
    (when (zerop n)
      (return-from lagrange-interpolation0
        (make-array 0 :element-type '(unsigned-byte 31))))
    (let ((coefs (make-array n :element-type '(unsigned-byte 31) :initial-element 0)))
      (dotimes (i n)
        (let ((coef (mod (* (mod (* (aref *fact-inv* i) (aref *fact-inv* (- n i 1)))
                                 +binom-mod+)
                            (the integer (aref values i)))
                         +binom-mod+)))
          (setf (aref coefs i)
                (if (evenp (- n i))
                    (- +binom-mod+ coef)
                    coef))))
      (let ((rprods (make-array (+ n 1) :element-type '(unsigned-byte 31)))
            (lprods (make-array (+ n 1) :element-type '(unsigned-byte 31)))
            (res 0))
        (declare ((unsigned-byte 31) res))
        (setf (aref lprods 0) (mod 1 +binom-mod+)
              (aref rprods n) (mod 1 +binom-mod+))
        (loop for i below n
              for x = (mod target +binom-mod+)
              then (mod (+ x difference-) +binom-mod+)
              do (setf (aref lprods (+ i 1)) (mod (* x (aref lprods i)) +binom-mod+)
                       (aref rprods i) x))
        (loop for i from (- n 1) downto 0
              do (setf (aref rprods i)
                       (mod (* (aref rprods i) (aref rprods (+ i 1))) +binom-mod+)))
        (dotimes (i n)
          (setq res (mod (+ res
                            (* (aref coefs i)
                               (mod (* (aref lprods i) (aref rprods (+ i 1))) +binom-mod+)))
                         +binom-mod+)))
        res))))
