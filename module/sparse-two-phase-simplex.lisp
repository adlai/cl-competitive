(defpackage :cp/sparse-two-phase-simplex
  (:use :cl :cp/csc :cp/lud)
  (:import-from :cp/csc #:+zero+ #:+one+ #:csc-float)
  (:import-from :cp/lud #:vector-set* #:extend-vectorf)
  (:export #:make-sparse-lp #:sparse-primal! #:sparse-dual!
           #:sparse-dual-primal! #:sparse-lp-restore)
  (:documentation "Provides two-phase (dual-then-primal) simplex method for
sparse LP, using Dantzig's pivot rule.

Usage procedure:
1. MAKE-SPARSE-LP
2. SPARSE-DUAL-PRIMAL!
3. SRARSE-LP-RESTORE

Reference:
Robert J. Vanderbei. Linear Programming: Foundations and Extensions. 5th edition."))
(in-package :cp/sparse-two-phase-simplex)

(defconstant +eps1+ (coerce 1d-8 'csc-float))
(defconstant +eps2+ (coerce 1d-12 'csc-float))
(defconstant +inf+ most-positive-double-float)

(defun add-slack! (a c)
  (declare (optimize (speed 3))
           (csc a)
           ((simple-array csc-float (*)) c))
  (symbol-macrolet ((m (csc-m a))
                    (n (csc-n a))
                    (colstarts (csc-colstarts a))
                    (rows (csc-rows a))
                    (values (csc-values a))
                    (nz (csc-nz a)))
    (setq c (adjust-array c (the (mod #.array-dimension-limit) (+ n m))))
    ;; Add slack variable
    (loop for row below m
          for col from n
          for k from (aref colstarts n)
          do (setf (aref c col) +zero+)
             (vector-set* values k +one+)
             (vector-set* rows k row)
             (vector-set* colstarts (+ col 1) (+ k 1))
             (incf nz)
          finally (setf n (+ n m)))
    (values a c)))

(defstruct (sparse-lp (:constructor %make-sparse-lp))
  (m nil :type (mod #.array-dimension-limit))
  (n nil :type (mod #.array-dimension-limit))
  (mat nil :type csc)
  (tmat nil :type csc)
  (b nil :type (simple-array csc-float (*)))
  (c nil :type (simple-array csc-float (*)))
  (x-basic nil :type (simple-array csc-float (*)))
  (y-nonbasic nil :type (simple-array csc-float (*)))
  (basics nil :type (simple-array fixnum (*)))
  (nonbasics nil :type (simple-array fixnum (*)))
  (basic-flag nil :type (simple-array fixnum (*)))
  (lude nil :type lud-eta))

(defun correct-x-basic! (lude x-basic)
  (assert (zerop (lud-eta-count lude)))
  (dense-solve! (lud-eta-lud lude) x-basic))

(defun correct-y-nonbasic! (sparse-lp)
  (declare (optimize (speed 3)))
  (let* ((lude (sparse-lp-lude sparse-lp))
         (m (sparse-lp-m sparse-lp))
         (n (sparse-lp-n sparse-lp))
         (tmat (sparse-lp-tmat sparse-lp))
         (c (sparse-lp-c sparse-lp))
         (tmp (make-sparse-vector m))
         (basics (sparse-lp-basics sparse-lp))
         (nonbasics (sparse-lp-nonbasics sparse-lp))
         (basic-flag (sparse-lp-basic-flag sparse-lp))
         (y-nonbasic (sparse-lp-y-nonbasic sparse-lp))
         (tmp-values (sparse-vector-values tmp))
         (tmp-indices (sparse-vector-indices tmp)))
    (symbol-macrolet ((tmp-nz (sparse-vector-nz tmp)))
      (dotimes (i m)
        (let ((coef (aref c (aref basics i))))
          (when (> (abs coef) +eps1+)
            (setf (aref tmp-values tmp-nz) coef
                  (aref tmp-indices tmp-nz) i)
            (incf tmp-nz))))
      (sparse-solve-transposed! lude tmp)
      (let* ((tmp (tmat-times-vec! tmat tmp basic-flag))
             (tmp-values (sparse-vector-values tmp))
             (tmp-indices (sparse-vector-indices tmp)))
        (dotimes (j n)
          (setf (aref y-nonbasic j) (- (aref c (aref nonbasics j)))))
        (dotimes (k (sparse-vector-nz tmp))
          (incf (aref y-nonbasic (aref tmp-indices k)) (aref tmp-values k)))))
    sparse-lp))

(defun make-sparse-lp (a b c &key (add-slack t))
  "Creates SPARSE-LP from a sparse matrix, which has the standard form: maximize
c'x subject to Ax <= b, x >= 0.

This function translates a given LP to an equality form Ax + w = b by adding
slack variables and changes A to (A E). If you want to give an equality form
directly, just disable ADD-SLACK."
  (declare (optimize (speed 3))
           (csc a)
           ((simple-array csc-float (*)) b c))
  (let ((m (csc-m a))
        (n (if add-slack (csc-n a) (- (csc-n a) (csc-m a)))))
    (when add-slack
      (setf (values a c) (add-slack! a c)))
    (let ((x-basic (make-array m :element-type 'csc-float))
          (y-nonbasic (make-array n :element-type 'csc-float))
          (nonbasics (make-array n :element-type 'fixnum))
          (basics (make-array m :element-type 'fixnum))
          (basic-flag (make-array (+ n m) :element-type 'fixnum))
          (a-transposed (csc-transpose a)))
      (dotimes (j n)
        (setf (aref nonbasics j) j
              (aref basic-flag j) (lognot j)
              (aref y-nonbasic j) (- (aref c j))))
      (dotimes (i m)
        (setf (aref basics i) (+ n i)
              (aref basic-flag (+ n i)) i
              (aref x-basic i) (aref b i)))
      (let* ((lude (refactor a basics)))
        ;; (correct-x-basic! lude x-basic)
        (%make-sparse-lp :m m :n n
                         :mat a :tmat a-transposed
                         :b b :c c
                         :x-basic x-basic
                         :y-nonbasic y-nonbasic
                         :basics basics
                         :nonbasics nonbasics
                         :basic-flag basic-flag
                         :lude lude)))))

(declaim (ftype (function * (values csc-float &optional)) dot*))
(defun dot* (coefs x-basic basics)
  (declare (optimize (speed 3))
           ((simple-array csc-float (*)) coefs x-basic)
           ((simple-array fixnum (*)) basics))
  (let ((res +zero+))
    (declare (csc-float res))
    (dotimes (i (length x-basic))
      (incf res (* (aref coefs (aref basics i)) (aref x-basic i))))
    res))

(defun pick-negative (vector)
  (declare (optimize (speed 3))
           ((simple-array csc-float (*)) vector))
  (let ((min (- +eps2+))
        res)
    (dotimes (i (length vector))
      (when (< (aref vector i) min)
        (setq min (aref vector i)
              res i)))
    res))

(defun ratio-test (x dx)
  (declare (optimize (speed 3))
           ((simple-array csc-float (*)) x)
           (sparse-vector dx))
  (let ((min +inf+)
        (dx-indices (sparse-vector-indices dx))
        (dx-values (sparse-vector-values dx))
        res)
    (dotimes (k (sparse-vector-nz dx))
      (when (> (aref dx-values k) +eps1+)
        (let* ((index (aref dx-indices k))
               (rate (/ (aref x index) (aref dx-values k))))
          (when (< rate min)
            (setq min rate
                  res index)))))
    res))

(defconstant +initial-size+ 16)

(declaim ((simple-array csc-float (*)) *tmp-values*)
         ((simple-array fixnum (*)) *tmp-tags* *tmp-rows*)
         ((integer 0 #.most-positive-fixnum) *tmp-tag*))
(defparameter *tmp-values*
  (make-array +initial-size+ :element-type 'csc-float))
(defparameter *tmp-tags*
  (make-array +initial-size+ :element-type 'fixnum :initial-element 0))
(defparameter *tmp-tag* 1)
(defparameter *tmp-rows* (make-array +initial-size+ :element-type 'fixnum))

(defun tmat-times-vec! (tmat vec basic-flag &optional res)
  (declare (optimize (speed 3))
           (csc tmat)
           (sparse-vector vec)
           ((or null sparse-vector) res)
           ((simple-array fixnum (*)) basic-flag))
  (let ((m (csc-m tmat)))
    (extend-vectorf *tmp-values* m)
    (extend-vectorf *tmp-tags* m)
    (extend-vectorf *tmp-rows* m))
  (let ((tmp-values *tmp-values*)
        (tmp-tags *tmp-tags*)
        (tag *tmp-tag*)
        (tmp-rows *tmp-rows*)
        (vector-indices (sparse-vector-indices vec))
        (vector-values (sparse-vector-values vec))
        (tmat-values (csc-values tmat))
        (tmat-colstarts (csc-colstarts tmat))
        (tmat-rows (csc-rows tmat))
        (end 0))
    (declare ((mod #.array-dimension-limit)))
    (dotimes (k1 (sparse-vector-nz vec))
      (let ((col (aref vector-indices k1)))
        (loop for k2 from (aref tmat-colstarts col) below (aref tmat-colstarts (+ col 1))
              for row = (aref tmat-rows k2)
              when (< (aref basic-flag row) 0)
              do (unless (eql tag (aref tmp-tags row))
                   (setf (aref tmp-values row) +zero+
                         (aref tmp-tags row) tag
                         (aref tmp-rows end) row
                         end (+ end 1)))
                 (incf (aref tmp-values row)
                       (* (aref vector-values k1) (aref tmat-values k2))))))
    (let* ((res (or res (make-sparse-vector end)))
           (res-values (sparse-vector-values res))
           (res-indices (sparse-vector-indices res))
           (nz 0))
      (declare ((simple-array csc-float (*)) res-values)
               ((simple-array fixnum (*)) res-indices)
               ((mod #.array-dimension-limit) nz))
      (extend-vectorf res-values end)
      (extend-vectorf res-indices end)
      (dotimes (k end)
        (let ((row (aref tmp-rows k)))
          (when (> (abs (aref tmp-values row)) +eps1+)
            (setf (aref res-values nz) (aref tmp-values row)
                  (aref res-indices nz) (lognot (aref basic-flag row))
                  nz (+ nz 1)))))
      (setf (sparse-vector-values res) res-values
            (sparse-vector-indices res) res-indices
            (sparse-vector-nz res) nz)
      (incf *tmp-tag*)
      res)))

(defun sparse-lp-restore (sparse-lp)
  "Restores the current solution of LP and returns five values: objective value,
primal solution, dual solution, values of primal slack variables, and values of
dual slack variables. (Note that they are not necessarily feasible solutions if
the current dictionary is not optimal.)"
  (declare (optimize (speed 3)))
  (let* ((m (sparse-lp-m sparse-lp))
         (n (sparse-lp-n sparse-lp))
         (c (sparse-lp-c sparse-lp))
         (x-basic (sparse-lp-x-basic sparse-lp))
         (y-nonbasic (sparse-lp-y-nonbasic sparse-lp))
         (basics (sparse-lp-basics sparse-lp))
         (nonbasics (sparse-lp-nonbasics sparse-lp))
         (x (make-array (+ n m) :element-type 'csc-float :initial-element +zero+))
         (y (make-array (+ n m) :element-type 'csc-float :initial-element +zero+)))
    (dotimes (i m)
      (setf (aref x (aref basics i)) (aref x-basic i)))
    (dotimes (i n)
      (setf (aref y (aref nonbasics i)) (aref y-nonbasic i)))
    (values (dot* c x-basic basics)
            (subseq x 0 n)
            (subseq y n)
            (subseq x n)
            (subseq y 0 n))))

(defun sparse-primal! (sparse-lp)
  "Applies primal simplex method to SPARSE-LP and returns the terminal state:
:optimal or :unbounded."
  (declare (optimize (speed 3)))
  (let* ((m (sparse-lp-m sparse-lp))
         (n (sparse-lp-n sparse-lp))
         (x-basic (sparse-lp-x-basic sparse-lp))
         (y-nonbasic (sparse-lp-y-nonbasic sparse-lp))
         (basics (sparse-lp-basics sparse-lp))
         (nonbasics (sparse-lp-nonbasics sparse-lp))
         (basic-flag (sparse-lp-basic-flag sparse-lp))
         (mat (sparse-lp-mat sparse-lp))
         (tmat (sparse-lp-tmat sparse-lp))
         (dx (make-sparse-vector m))
         (dy (make-sparse-vector n))
         (tmp (make-sparse-vector m)))
    (symbol-macrolet ((lude (sparse-lp-lude sparse-lp))
                      (dx-values (sparse-vector-values dx))
                      (dx-indices (sparse-vector-indices dx))
                      (dx-nz (sparse-vector-nz dx))
                      (dy-values (sparse-vector-values dy))
                      (dy-indices (sparse-vector-indices dy))
                      (dy-nz (sparse-vector-nz dy))
                      (tmp-values (sparse-vector-values tmp))
                      (tmp-indices (sparse-vector-indices tmp))
                      (tmp-nz (sparse-vector-nz tmp)))
      (loop
        ;; find entering column
        (let* ((col-in (pick-negative y-nonbasic)))
          (unless col-in
            (return :optimal))
          ;; dx_B := B^(-1)Ne_j (j = col-in)
          (let ((acolstarts (csc-colstarts mat))
                (arows (csc-rows mat))
                (avalues (csc-values mat))
                (j (aref nonbasics col-in)))
            (loop for i from 0
                  for k from (aref acolstarts j) below (aref acolstarts (+ j 1))
                  do (setf (aref dx-values i) (aref avalues k)
                           (aref dx-indices i) (aref arows k))
                  finally (setq dx-nz i)))
          (sparse-solve! lude dx)
          ;; find leaving column
          (let ((col-out (ratio-test x-basic dx)))
            (unless col-out
              (return :unbounded))
            ;; dy_N := -(B^(-1)N)^Te_i (i = col-out)
            (setf (aref tmp-values 0) (- +one+)
                  (aref tmp-indices 0) col-out
                  tmp-nz 1)
            (sparse-solve-transposed! lude tmp)
            (tmat-times-vec! tmat tmp basic-flag dy)
            ;; t := x_i/dx_i
            ;; s := y_j/dy_j
            (let ((rate-t (loop for k below dx-nz
                                when (= (aref dx-indices k) col-out)
                                do (return (/ (aref x-basic col-out)
                                              (aref dx-values k)))
                                finally (error "Huh?")))
                  (rate-s (loop for k below dy-nz
                                when (= (aref dy-indices k) col-in)
                                do (return (/ (aref y-nonbasic col-in)
                                              (aref dy-values k)))
                                finally (error "Huh?"))))
              ;; y_N := y_N - s dy_N
              ;; y_i := s
              ;; x_B := x_B - t dx_B
              ;; x_j := t
              (dotimes (k dy-nz)
                (let ((j (aref dy-indices k)))
                  (decf (aref y-nonbasic j) (* rate-s (aref dy-values k)))))
              (setf (aref y-nonbasic col-in) rate-s)
              (dotimes (k dx-nz)
                (let ((i (aref dx-indices k)))
                  (decf (aref x-basic i) (* rate-t (aref dx-values k)))))
              (setf (aref x-basic col-out) rate-t)
              ;; Update basis
              (let ((i (aref basics col-out))
                    (j (aref nonbasics col-in)))
                (setf (aref basics col-out) j
                      (aref nonbasics col-in) i
                      (aref basic-flag i) (lognot col-in)
                      (aref basic-flag j) col-out))
              (add-eta! lude col-out dx)
              (when (refactor-p lude col-out)
                (setq lude (refactor mat basics))))))))))

(defun sparse-dual! (sparse-lp)
  "Applies dual simplex method to SPARSE-LP and returns the terminal state:
:optimal or :infeasible."
  (declare (optimize (speed 3)))
  (let* ((m (sparse-lp-m sparse-lp))
         (n (sparse-lp-n sparse-lp))
         (x-basic (sparse-lp-x-basic sparse-lp))
         (y-nonbasic (sparse-lp-y-nonbasic sparse-lp))
         (basics (sparse-lp-basics sparse-lp))
         (nonbasics (sparse-lp-nonbasics sparse-lp))
         (basic-flag (sparse-lp-basic-flag sparse-lp))
         (mat (sparse-lp-mat sparse-lp))
         (tmat (sparse-lp-tmat sparse-lp))
         (dx (make-sparse-vector m))
         (dy (make-sparse-vector n))
         (tmp (make-sparse-vector m)))
    (symbol-macrolet ((lude (sparse-lp-lude sparse-lp))
                      (dx-values (sparse-vector-values dx))
                      (dx-indices (sparse-vector-indices dx))
                      (dx-nz (sparse-vector-nz dx))
                      (dy-values (sparse-vector-values dy))
                      (dy-indices (sparse-vector-indices dy))
                      (dy-nz (sparse-vector-nz dy))
                      (tmp-values (sparse-vector-values tmp))
                      (tmp-indices (sparse-vector-indices tmp))
                      (tmp-nz (sparse-vector-nz tmp)))
      (loop
        ;; find leaving column
        (let ((col-out (pick-negative x-basic)))
          (unless col-out
            (return :optimal))
          ;; dy_N := -(B^(-1)N)^Te_i (i = col-out)
          (setf (aref tmp-values 0) (- +one+)
                (aref tmp-indices 0) col-out
                tmp-nz 1)
          (sparse-solve-transposed! lude tmp)
          (tmat-times-vec! tmat tmp basic-flag dy)
          ;; find entering column
          (let ((col-in (ratio-test y-nonbasic dy)))
            (unless col-in
              (return :infeasible))
            ;; dx_B := B^(-1)Ne_j (j = col-in)
            (let ((acolstarts (csc-colstarts mat))
                  (arows (csc-rows mat))
                  (avalues (csc-values mat))
                  (j (aref nonbasics col-in)))
              (loop for i from 0
                    for k from (aref acolstarts j) below (aref acolstarts (+ j 1))
                    do (setf (aref dx-values i) (aref avalues k)
                             (aref dx-indices i) (aref arows k))
                    finally (setq dx-nz i)))
            (sparse-solve! lude dx)
            ;; t := x_i/dx_i
            ;; s := y_j/dy_j
            (let ((rate-t (loop for k below dx-nz
                                when (= (aref dx-indices k) col-out)
                                do (return (/ (aref x-basic col-out)
                                              (aref dx-values k)))
                                finally (error "Huh?")))
                  (rate-s (loop for k below dy-nz
                                when (= (aref dy-indices k) col-in)
                                do (return (/ (aref y-nonbasic col-in)
                                              (aref dy-values k)))
                                finally (error "Huh?"))))
              ;; y_N := y_N - s dy_N
              ;; y_i := s
              ;; x_B := x_B - t dx_B
              ;; x_j := t
              (dotimes (k dy-nz)
                (let ((j (aref dy-indices k)))
                  (decf (aref y-nonbasic j) (* rate-s (aref dy-values k)))))
              (setf (aref y-nonbasic col-in) rate-s)
              (dotimes (k dx-nz)
                (let ((i (aref dx-indices k)))
                  (decf (aref x-basic i) (* rate-t (aref dx-values k)))))
              (setf (aref x-basic col-out) rate-t)
              ;; Update basis
              (let ((i (aref basics col-out))
                    (j (aref nonbasics col-in)))
                (setf (aref basics col-out) j
                      (aref nonbasics col-in) i
                      (aref basic-flag i) (lognot col-in)
                      (aref basic-flag j) col-out))
              (add-eta! lude col-out dx)
              (when (refactor-p lude col-out)
                (setq lude (refactor mat basics))))))))))

(defun sparse-dual-primal! (sparse-lp)
  "Applies two-phase simplex method to SPARSE-LP and returns the terminal state:
:optimal, :unbounded, or :infeasible. "
  (declare (optimize (speed 3)))
  (let ((n (sparse-lp-n sparse-lp))
        (nonbasics (sparse-lp-nonbasics sparse-lp))
        (y-nonbasic (sparse-lp-y-nonbasic sparse-lp))
        (c (sparse-lp-c sparse-lp)))
    ;; Set all the coefficiets of objective to negative values.
    (dotimes (j n)
      (setf (aref y-nonbasic j)
            (+ (max (aref c (aref nonbasics j)) +one+)
               (random +one+))))
    (let ((state-dual (sparse-dual! sparse-lp)))
      (unless (eql state-dual :optimal)
        (return-from sparse-dual-primal! state-dual))
      (correct-y-nonbasic! sparse-lp)
      (sparse-primal! sparse-lp))))
