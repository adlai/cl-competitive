(declaim (ftype (function * (values simple-bit-vector &optional)) make-prime-table))
(defun make-prime-table (sup)
  "Returns a simple-bit-vector of length SUP, whose (0-based) i-th bit is 1 if i
is prime and 0 otherwise.

Example: (make-prime-table 10) => #*0011010100"
  (declare (optimize (speed 3) (safety 0)))
  (check-type sup (integer 2 (#.array-total-size-limit)))
  (let ((table (make-array sup :element-type 'bit :initial-element 1)))
    (multiple-value-bind (sup/64 sup%64) (floor sup 64)
      ;; special treatment for p = 2
      (dotimes (i sup/64)
        (setf (sb-kernel:%vector-raw-bits table i) #xAAAAAAAAAAAAAAAA))
      (unless (zerop sup%64)
        (setf (sb-kernel:%vector-raw-bits table sup/64)
              (ldb (byte sup%64 0) #xAAAAAAAAAAAAAAAA)))
      (setf (sbit table 1) 0
            (sbit table 2) 1)
      ;; p >= 3
      (loop for p from 3 to (+ 1 (isqrt (- sup 1))) by 2
            when (= 1 (sbit table p))
            do (loop for composite from (* p p) below sup by p
                     do (setf (sbit table composite) 0)))
      table)))

;; FIXME: Currently the element type of the resultant vector is (UNSIGNED-BYTE 62).
(defun make-prime-sequence (sup)
  "Returns the ascending sequence of primes smaller than SUP."
  (declare (optimize (speed 3) (safety 0)))
  (check-type sup (integer 2 (#.array-total-size-limit)))
  (let ((table (make-prime-table sup)))
    (let* ((length (count 1 table))
           (result (make-array length :element-type '(integer 0 #.most-positive-fixnum)))
           (index 0))
      (declare ((integer 0 #.most-positive-fixnum) length))
      (loop for x below sup
            when (= 1 (sbit table x))
            do (setf (aref result index) x)
               (incf index))
      result)))

(declaim (ftype (function * (values list &optional)) factorize-with-table))
(defun factorize-with-table (x prime-table)
  "Returns the associative list of prime factors of X, which is composed
of (<prime> . <exponent>). E.g. (factorize 100 <prime-table>) => '((2 . 2) (5
. 5)).

PRIME-TABLE := simple-bit-vector (PRIME-TABLE[k] = 1 iff k is prime)

Note that the returned list is NOT guaranteed to be in ascending order."
  (declare (integer x)
           (simple-bit-vector prime-table))
  (assert (>= (length prime-table) 3))
  (setq x (abs x))
  (if (zerop x)
      nil
      (append
       (loop for exponent of-type (integer 0 #.most-positive-fixnum) from 0
             while (evenp x)
             do (setq x (ash x -1))
             finally (return
                       (when (> exponent 0)
                         (list (cons 2 exponent)))))
       (loop for prime from 3 to (min x (- (length prime-table) 1)) by 2
             for factor-cons =
                (when (= 1 (sbit prime-table prime))
                  (loop for exponent of-type (integer 0 #.most-positive-fixnum) from 0
                        do (multiple-value-bind (quot rem) (floor x prime)
                             (if (zerop rem)
                                 (setf x quot)
                                 (return
                                   (when (> exponent 0)
                                     (cons prime exponent)))))))
             when factor-cons
             collect factor-cons into res
             finally (return
                       (if (= x 1)
                           res
                           (cons (cons x 1) res)))))))

;; TODO: enable to take a list as PRIME-SEQ
(declaim (inline factorize)
         (ftype (function * (values list &optional)) factorize))
(defun factorize (x prime-seq)
  "Returns the associative list of prime factors of X, which is composed
of (<prime> . <exponent>). E.g. (factorize 100 <prime-table>) => '((2 . 2) (5
. 5)).

PRIME-SEQ := vector (composed only of not duplicated primes)
Note that the returned list is NOT guaranteed to be in ascending order."
  (declare (integer x)
           (vector prime-seq))
  (setq x (abs x))
  (if (zerop x)
      nil
      (let (result)
        (loop for prime of-type unsigned-byte across prime-seq
              do (when (= x 1)
                   (return-from factorize result))
                 (loop for exponent of-type (integer 0 #.most-positive-fixnum) from 0
                       do (multiple-value-bind (quot rem) (floor x prime)
                            (if (zerop rem)
                                (setf x quot)
                                (progn
                                  (when (> exponent 0)
                                    (push (cons prime exponent) result))
                                  (loop-finish))))))
        (if (= x 1)
            result
            (cons (cons x 1) result)))))
