;;;
;;; Fast Walsh-Hadamard Transform
;;;

(declaim (inline power2-p))
(defun power2-p (x)
  "Checks if X is a power of 2."
  (zerop (logand x (- x 1))))

(declaim (inline fwht!))
(defun fwht! (vector &optional inverse)
  "Does (if specified, inverse) fast Walsh-Hadamard
Transformation. Destructively modifies VECTOR. The length of VECTOR must be a
power of 2."
  (declare (vector vector))
  (let ((n (length vector)))
    (assert (power2-p n))
    (do ((len 1 (ash len 1)))
        ((> len (ash n -1)))
      (declare ((integer 0 #.most-positive-fixnum) len))
      (do ((i 0 (+ i (ash len 1))))
          ((>= i n))
        (dotimes (j len)
          (let* ((i+j (+ i j))
                 (u (aref vector i+j))
                 (v (aref vector (+ i+j len))))
            (declare ((integer 0 #.most-positive-fixnum) i+j))
            (setf (aref vector i+j) (+ u v)
                  (aref vector (+ i+j len)) (- u v))))))
    (when inverse
      (let ((shift (- (integer-length (- n 1)))))
        (dotimes (i n)
          (setf (aref vector i)
                (ash (aref vector i) shift)))))
    vector))
