;; This is a decimal reader specialized for the inputs that can be handled
;; within the range of FIXNUM. The implementation is based on
;; SB-IMPL::MAKE-FLOAT.

;; TODO: test
(declaim (ftype (function * (values rational &optional)) read-decimal))
(defun read-decimal (&optional (in *standard-input*))
  "Reads a fixed-point decimal and returns it as a rational.

Example:
CL-USER> (read-decimal)
-3.5
-> -7/2

Note: Two numbers before and after the decimal point must be within (INTEGER 0
#.MOST-POSITIVE-FIXNUM)."
  (declare (optimize (speed 3)))
  (macrolet ((%read-byte ()
               `(the (unsigned-byte 8)
                     #+swank (char-code (read-char in nil #\Nul))
                     #-swank (sb-impl::ansi-stream-read-byte in nil #.(char-code #\Nul) nil))))
    (let* ((byte 0)
           (minus nil)
           (number (loop
                     (setq byte (%read-byte))
                     (cond ((<= 48 byte 57)
                            (return (- byte 48)))
                           ((zerop byte) ; #\Nul
                            (error "Read EOF or #\Nul."))
                           ((= byte #.(char-code #\-))
                            (setq minus t)))))
           (divisor 1))
      (declare ((integer 0 #.most-positive-fixnum) number))
      (loop
        (setq byte (%read-byte))
        (if (<= 48 byte 57)
            (setq number
                  (+ (- byte 48)
                     (* 10 (the (integer 0 #.(floor most-positive-fixnum 10)) number))))
            (return)))
      (when (= byte #.(char-code #\.))
        (loop
          (setq byte (%read-byte))
          (if (<= 48 byte 57)
              (setq number
                    (+ (- byte 48)
                       (* 10 (the (integer 0 #.(floor most-positive-fixnum 10)) number)))
                    divisor
                    (* 10 (the (integer 0 #.(floor most-positive-fixnum 10)) divisor)))
              (return))))
      (if minus
          (- (/ number divisor))
          (/ number divisor)))))

(declaim (inline read-float)
         (ftype (function * (values float &optional)) read-float))
(defun read-float (&optional (in *standard-input*))
  "Reads a fixed-point decimal in the format of *READ-DEFAULT-FLOAT-FORMAT*.

NOTE: Two numbers before and after the decimal point must be within (INTEGER 0
#.MOST-POSITIVE-FIXNUM)."
  (coerce (read-decimal in) *read-default-float-format*))
