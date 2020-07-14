;;;
;;; Fast Number Theoretic Transform
;;; Reference: https://github.com/ei1333/library/blob/master/math/fft/number-theoretic-transform-friendly-mod-int.cpp
;;;

(defconstant +ntt-mod+ 998244353)
(defconstant +ntt-root+ 3)
(deftype ntt-int () '(unsigned-byte 31))
(deftype ntt-vector () '(simple-array ntt-int (*)))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (assert (typep +ntt-mod+ 'ntt-int)))

(declaim (inline %tzcount))
(defun %tzcount (x)
  (- (integer-length (logand x (- x))) 1))

(declaim (inline %mod-power))
(defun %mod-power (base exp)
  (declare (ntt-int base)
           ((integer 0 #.most-positive-fixnum) exp))
  (let ((res 1))
    (declare (ntt-int res))
    (loop while (> exp 0)
          when (oddp exp)
          do (setq res (mod (* res base) +ntt-mod+))
          do (setq base (mod (* base base) +ntt-mod+)
                   exp (ash exp -1)))
    res))

(defun check-ntt-vector (vector)
  (declare (optimize (speed 3))
           (vector vector))
  (let ((len (length vector)))
    (assert (zerop (logand len (- len 1)))) ;; power of two
    (check-type len ntt-int)))

(defun make-ntt-base ()
  (labels ((mod-inverse (x) (%mod-power x (- +ntt-mod+ 2))))
    (let* ((base-size (%tzcount (- +ntt-mod+ 1)))
           (base (make-array base-size :element-type 'ntt-int))
           (inv-base (make-array base-size :element-type 'ntt-int)))
      (dotimes (i base-size)
        (setf (aref base i)
              (mod (- (%mod-power +ntt-root+ (ash (- +ntt-mod+ 1) (- (+ i 2)))))
                   +ntt-mod+)
              (aref inv-base i)
              (mod-inverse (aref base i))))
      (values base inv-base))))

(multiple-value-bind (base inv-base) (make-ntt-base)
  (defparameter *ntt-base* base)
  (defparameter *ntt-inv-base* inv-base))

;; FIXME: Here I resort to SBCL's behaviour. Actually ADJUST-ARRAY isn't
;; guaranteed to preserve the given VECTOR.
(declaim (ftype (function * (values ntt-vector &optional)) %adjust-array))
(defun %adjust-array (vector length)
  (declare (vector vector))
  (let ((vector (coerce vector 'ntt-vector)))
    (if (= (length vector) length)
        (copy-seq vector)
        (adjust-array vector length :initial-element 0))))

(declaim (ftype (function * (values ntt-vector &optional)) ntt!))
(defun ntt! (vector)
  (declare (optimize (speed 3))
           (vector vector))
  (check-ntt-vector vector)
  (labels ((mod* (x y) (mod (* x y) +ntt-mod+))
           (mod+ (x y)
             (let ((res (+ x y)))
               (if (>= res +ntt-mod+)
                   (- res +ntt-mod+)
                   res)))
           (mod- (x y) (mod+ x (- +ntt-mod+ y))))
    (declare (inline mod* mod+ mod-))
    (let* ((vector (coerce vector 'ntt-vector))
           (len (length vector))
           (base *ntt-base*))
      (declare ((simple-array ntt-int (*)) vector base)
               (ntt-int len))
      (when (<= len 1)
        (return-from ntt! vector))
      (loop for m of-type ntt-int = (ash len -1) then (ash m -1)
            while (> m 0)
            for w of-type ntt-int = 1
            for k of-type ntt-int = 0
            do (loop for s of-type ntt-int from 0 below len by (* 2 m)
                     do (loop for i from s below (+ s m)
                              for j from (+ s m)
                              for x = (aref vector i)
                              for y = (mod* (aref vector j) w)
                              do (setf (aref vector i) (mod+ x y)
                                       (aref vector j) (mod- x y)))
                        (incf k)
                        (setq w (mod* w (aref base (%tzcount k))))))
      vector)))

(defun inverse-ntt! (vector)
  (declare (optimize (speed 3))
           (vector vector))
  (check-ntt-vector vector)
  (labels ((mod* (x y)
             (declare (ntt-int x y))
             (mod (* x y) +ntt-mod+))
           (mod+ (x y)
             (declare (ntt-int x y))
             (let ((res (+ x y)))
               (if (>= res +ntt-mod+)
                   (- res +ntt-mod+)
                   res)))
           (mod- (x y)
             (declare (ntt-int x y))
             (mod+ x (- +ntt-mod+ y))))
    (declare (inline mod* mod+ mod-))
    (let* ((vector (coerce vector 'ntt-vector))
           (len (length vector))
           (base *ntt-inv-base*))
      (declare ((simple-array ntt-int (*)) vector base)
               (ntt-int len))
      (when (<= len 1)
        (return-from inverse-ntt! vector))
      (loop for m of-type ntt-int = 1 then (ash m 1)
            while (< m len)
            for w of-type ntt-int = 1
            for k of-type ntt-int = 0
            do (loop for s of-type ntt-int from 0 below len by (* 2 m)
                     do (loop for i from s below (+ s m)
                              for j from (+ s m)
                              for x = (aref vector i)
                              for y = (aref vector j)
                              do (setf (aref vector i) (mod+ x y)
                                       (aref vector j) (mod* (mod- x y) w)))
                        (incf k)
                        (setq w (mod* w (aref base (%tzcount k))))))
      (let ((inv-len (%mod-power len (- +ntt-mod+ 2))))
        (dotimes (i len)
          (setf (aref vector i) (mod* inv-len (aref vector i)))))
      vector)))

(declaim (ftype (function * (values (simple-array ntt-int (*)) &optional)) ntt-convolute!))
(defun ntt-convolute! (vector1 vector2)
  (declare #.OPT
           ((simple-array ntt-int (*)) vector1 vector2))
  (let* ((len1 (length vector1))
         (len2 (length vector2))
         (mul-len (- (+ len1 len2) 1))
         (required-len (sb-int:power-of-two-ceiling mul-len))
         (vector1 (ntt! (adjust-array vector1 required-len)))
         (vector2 (ntt! (adjust-array vector2 required-len))))
    (dotimes (i required-len)
      (setf (aref vector1 i)
            (mod (* (aref vector1 i) (aref vector2 i)) +ntt-mod+)))
    (inverse-ntt! vector1 t)))

;; NOTE: buggy
(declaim (ftype (function * (values ntt-vector &optional)) ntt-convolute))
(defun ntt-convolute (vector1 vector2 &optional fixed)
  (declare (optimize (speed 3))
           (vector vector1 vector2))
  (let ((len1 (length vector1))
        (len2 (length vector1)))
    (when fixed
      (assert (= len1 len2)))
    (let* ((mul-len (max 0 (- (+ len1 len2) 1)))
           ;; power of two ceiling
           (required-len (if fixed
                             len1
                             (ash 1 (integer-length (max 0 (- mul-len 1))))))
           (vector1 (ntt! (%adjust-array vector1 required-len)))
           (vector2 (ntt! (%adjust-array vector2 required-len))))
      
      (dotimes (i required-len)
        (setf (aref vector1 i)
              (mod (* (aref vector1 i) (aref vector2 i)) +ntt-mod+)))
      (inverse-ntt! vector1))))
