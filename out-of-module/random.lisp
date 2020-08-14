;; Just for an experiment. Please use RANDOM.

(defconstant +divisor+ (expt 2 31))

(let ((x (load-time-value (random +divisor+))))
  (declare ((integer 0 (#.(expt 2 31))) x))
  (defun seed-lcg (initial-number)
    (setq x initial-number))
  (defun random-lcg ()
    (declare (optimize (speed 3) (safety 0)))
    (setq x (logand (+ (* 1103515245 x) 12345) #.(- (expt 2 31) 1)))))

(defconstant +mask32+ #xffffffff)
(let ((x 2463534242))
  (declare ((unsigned-byte 32) x))
  (defun seed-xor32 (initial-number)
    (setq x initial-number))
  (defun random-xor32 ()
    (declare (optimize (speed 3) (safety 0)))
    (setq x (logxor x (logand +mask32+ (ash x 13))))
    (setq x (logxor x (ash x -17)))
    (setq x (logxor x (logand +mask32+ (ash x 5))))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (ql:quickload :galante))

(defun bench (num)
  (declare (optimize (speed 3) (safety 0)))
  (check-type num (integer 1 #.most-positive-fixnum))
  (galante:time-median 10 (dotimes (i (the fixnum num)) (random +mask32+))))
