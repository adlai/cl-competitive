(defpackage :cp/range-tree
  (:use :cl)
  (:export #:make-range-tree #:rt-count #:rt-fold #:rt-update #:rt-set)
  (:documentation
   "Provides 2D range tree over an arbitrary commutative monoid.

build: O(nlog(n))
query: O(log^2(n))

Reference:
https://www.cse.wustl.edu/~taoju/cse546/lectures/Lecture21_rangequery_2d.pdf"))
(in-package :cp/range-tree)

;; TODO: map all the points in a given rectangle
;; TODO: k-dimensional range tree

(deftype index () '(mod #.(floor most-positive-fixnum 2)))

(declaim (inline op))
(defun op (a b)
  "Is a binary operator comprising a commutative monoid"
  (declare (fixnum a b))
  (+ a b))

(defconstant +op-identity+ 0
  "identity element w.r.t. OP")

(defstruct (xnode (:constructor make-xnode (xkey ykey ynode left right))
                  (:conc-name %xnode-)
                  (:copier nil))
  (xkey 0 :type fixnum)
  (ykey 0 :type fixnum)
  ynode
  left right)

(defstruct (ynode (:constructor make-ynode
                      (xkey ykey left right &key (count 1) value accumulator))
                  (:conc-name %ynode-)
                  (:copier nil))
  (xkey 0 :type fixnum)
  (ykey 0 :type fixnum)
  left
  right
  (count 1 :type index)
  (value +op-identity+ :type fixnum)
  (accumulator +op-identity+ :type fixnum))

(declaim (inline ynode-count))
(defun ynode-count (ynode)
  "Returns the number of the elements."
  (if (null ynode)
      0
      (%ynode-count ynode)))

(declaim (inline ynode-accumulator))
(defun ynode-accumulator (ynode)
  (if (null ynode)
      +op-identity+
      (%ynode-accumulator ynode)))

(declaim (inline ynode-update-count))
(defun ynode-update-count (ynode)
  (setf (%ynode-count ynode)
        (+ 1
           (ynode-count (%ynode-left ynode))
           (ynode-count (%ynode-right ynode)))))

(declaim (inline ynode-update-accumulator))
(defun ynode-update-accumulator (ynode)
  (setf (%ynode-accumulator ynode)
        (op (op (ynode-accumulator (%ynode-left ynode))
                (%ynode-value ynode))
            (ynode-accumulator (%ynode-right ynode)))))

(declaim (inline force-up))
(defun force-up (ynode)
  "Propagates the information up from children."
  (ynode-update-count ynode)
  (ynode-update-accumulator ynode))

;;
;; Merging w.r.t. Y-axis in O(n) time:
;; 1. transform two trees to two paths (with copying);
;; 2. merge the two paths into a path (destructively);
;; 3. transform the path to a tree (destructively);
;;

(declaim (inline %ynode-to-path))
(defun %ynode-to-path (ynode)
  "Returns a path that is equivalent to YNODE but in reverse order."
  (declare (inline make-ynode))
  (let ((res nil))
    (labels ((recur (node)
               (when node
                 (recur (%ynode-left node))
                 (setq res (make-ynode (%ynode-xkey node) (%ynode-ykey node) nil res
                                       :value (%ynode-value node)
                                       :accumulator (%ynode-value node)))
                 (recur (%ynode-right node)))))
      (recur ynode)
      res)))

(declaim (inline %ynode-merge-path!))
(defun %ynode-merge-path! (ypath1 ypath2)
  "Destructively merges two pathes in reverse order."
  (let ((res nil))
    (macrolet ((%push (y)
                 `(let ((rest (%ynode-right ,y)))
                    (setf (%ynode-right ,y) res
                          res ,y
                          ,y rest))))
      (loop (unless ypath1
              (loop while ypath2 do (%push ypath2))
              (return))
            (unless ypath2
              (loop while ypath1 do (%push ypath1))
              (return))
            ;; I use only #'< here for abstraction in the future
            (if (or (< (%ynode-ykey ypath1) (%ynode-ykey ypath2))
                    (and (not (< (%ynode-ykey ypath2) (%ynode-ykey ypath1)))
                         (< (%ynode-xkey ypath1) (%ynode-xkey ypath2))))
                (%push ypath2)
                (%push ypath1)))
      res)))

(declaim (inline %path-to-ynode!))
(defun %path-to-ynode! (ypath length)
  "Destructively transforms a path to a balanced binary tree."
  (declare (index length))
  (let* ((max-depth (- (integer-length length) 1)))
    (macrolet ((%pop ()
                 `(let ((rest (%ynode-right ypath))
                        (first ypath))
                    (setf (%ynode-right first) nil
                          ypath rest)
                    first)))
      (labels ((build (depth)
                 (declare (index depth))
                 (when ypath
                   (if (= depth max-depth)
                       (%pop)
                       (let ((left (build (+ 1 depth))))
                         (if (null ypath)
                             left
                             (let* ((node (%pop))
                                    (right (build (+ 1 depth))))
                               (setf (%ynode-left node) left)
                               (setf (%ynode-right node) right)
                               (force-up node)
                               node)))))))
        (build 0)))))

(defun %ynode-merge (ynode1 ynode2)
  "Merges two YNODEs non-destructively in O(n) time."
  (declare (optimize (speed 3) (safety 0)))
  (let* ((length (+ (ynode-count ynode1) (ynode-count ynode2))))
    (declare (fixnum length))
    (%path-to-ynode!
     (%ynode-merge-path! (%ynode-to-path ynode1)
                         (%ynode-to-path ynode2))
     length)))

(declaim (inline make-range-tree))
(defun make-range-tree (points &key (xkey #'car) (ykey #'cdr) value-key)
  "points := vector of points

Makes a range tree from the points. These points must be sorted
w.r.t. lexicographical order and must not contain duplicate points. (Duplicate
coordinates are allowed.) E.g. (-1, 3), (-1, 4), (-1, 7) (0, 1) (0, 3) (2,
-1) (2, 1)).

If VALUE-KEY is given, the i-th point is bounded to the value (FUNCALL VALUE-KEY
POINTS[i]), otherwise to the value +OP-IDENTITY+."
  (declare (vector points))
  ;; assert POINTS is sorted
  ;; TODO: do this only when safety > 0
  (dotimes (i (- (length points) 1))
    (let* ((point0 (aref points i))
           (point1 (aref points (+ i 1)))
           (x0 (funcall xkey point0))
           (y0 (funcall ykey point0))
           (x1 (funcall xkey point1))
           (y1 (funcall ykey point1)))
      (assert (or (< x0 x1)
                  (and (= x0 x1)
                       (< y0 y1))))))
  (when (zerop (length points))
    (return-from make-range-tree nil))
  (labels ((build (l r)
             (declare (index l r))
             (if (= (- r l) 1)
                 (let* ((point (aref points l))
                        (x (funcall xkey point))
                        (y (funcall ykey point))
                        (value (if value-key (funcall value-key point) +op-identity+)))
                   (make-xnode x y
                               (make-ynode x y nil nil
                                           :value value
                                           :accumulator value)
                               nil nil))
                 (let* ((mid (ash (+ l r) -1))
                        (left (build l mid))
                        (right (build mid r)))
                   (make-xnode (funcall xkey (aref points mid))
                               (funcall ykey (aref points mid))
                               (%ynode-merge (%xnode-ynode left)
                                             (%xnode-ynode right))
                               left right)))))
    (build 0 (length points))))

(defconstant +neg-inf+ most-negative-fixnum)
(defconstant +pos-inf+ most-positive-fixnum)

(declaim (inline xleaf-p))
(defun xleaf-p (xnode)
  (and (null (%xnode-left xnode)) (null (%xnode-right xnode))))

(defun rt-count (range-tree x1 y1 x2 y2)
  "Returns the number of the nodes within the rectangle [x1, x2)*[y1, y2). A
part or all of these coordinates can be NIL; then they are regarded as the
negative or positive infinity."
  (declare (optimize (speed 3))
           ((or null fixnum) x1 y1 x2 y2))
  (setq x1 (or x1 +neg-inf+)
        x2 (or x2 +pos-inf+)
        y1 (or y1 +neg-inf+)
        y2 (or y2 +pos-inf+))
  (labels ((xrecur (xnode x1 x2)
             (declare ((or null xnode) xnode)
                      (fixnum x1 x2)
                      ;; KLUDGE: declaring ftype is not sufficient for the
                      ;; optimization on SBCL 1.1.14.
                      #+sbcl (values index &optional))
             (cond ((null xnode) 0)
                   ((and (= x1 +neg-inf+) (= x2 +pos-inf+))
                    (yrecur (%xnode-ynode xnode) y1 y2))
                   (t
                    (let ((xkey (%xnode-xkey xnode)))
                      (if (<= x1 xkey)
                          (if (< xkey x2)
                              ;; XKEY is in [X1, X2)
                              (if (xleaf-p xnode)
                                  (yrecur (%xnode-ynode xnode) y1 y2)
                                  (+ (xrecur (%xnode-left xnode) x1 +pos-inf+)
                                     (xrecur (%xnode-right xnode) +neg-inf+ x2)))
                              ;; XKEY is in [X2, +inf)
                              (xrecur (%xnode-left xnode) x1 x2))
                          ;; XKEY is in (-inf, X1)
                          (xrecur (%xnode-right xnode) x1 x2))))))
           (yrecur (ynode y1 y2)
             (declare ((or null ynode) ynode)
                      (fixnum y1 y2)
                      #+sbcl (values index &optional))
             (cond ((null ynode) 0)
                   ((and (= y1 +neg-inf+) (= y2 +pos-inf+))
                    (%ynode-count ynode))
                   (t
                    (let ((key (%ynode-ykey ynode)))
                      (if (<= y1 key)
                          (if (< key y2)
                              (+ 1
                                 (yrecur (%ynode-left ynode) y1 +pos-inf+)
                                 (yrecur (%ynode-right ynode) +neg-inf+ y2))
                              (yrecur (%ynode-left ynode) y1 y2))
                          (yrecur (%ynode-right ynode) y1 y2)))))))
    ;; (declare (ftype (function * (values index &optional)) xrecur yrecur))
    (xrecur range-tree x1 x2)))

;; Below is almost the same as RT-COUNT. Is it better to integrate them?
(defun rt-fold (range-tree x1 y1 x2 y2)
  "Queries the `sum' of the nodes in the rectangle [x1, y1)*[x2, y2). A part or
all of these coordinates can be NIL; then they are regarded as the negative or
positive infinity."
  (declare (optimize (speed 3))
           ((or null fixnum) x1 y1 x2 y2))
  (setq x1 (or x1 +neg-inf+)
        x2 (or x2 +pos-inf+)
        y1 (or y1 +neg-inf+)
        y2 (or y2 +pos-inf+))
  (labels ((xrecur (xnode x1 x2)
             (declare ((or null xnode) xnode)
                      (fixnum x1 x2)
                      ;; KLUDGE: declaring ftype is not sufficient for the
                      ;; optimization on SBCL 1.1.14.
                      #+sbcl (values fixnum &optional))
             (cond ((null xnode) +op-identity+)
                   ((and (= x1 +neg-inf+) (= x2 +pos-inf+))
                    (yrecur (%xnode-ynode xnode) y1 y2))
                   (t
                    (let ((xkey (%xnode-xkey xnode)))
                      (if (<= x1 xkey)
                          (if (< xkey x2)
                              ;; XKEY is in [X1, X2)
                              (if (xleaf-p xnode)
                                  (yrecur (%xnode-ynode xnode) y1 y2)
                                  (op (xrecur (%xnode-left xnode) x1 +pos-inf+)
                                      (xrecur (%xnode-right xnode) +neg-inf+ x2)))
                              ;; XKEY is in [X2, +inf)
                              (xrecur (%xnode-left xnode) x1 x2))
                          ;; XKEY is in (-inf, X1)
                          (xrecur (%xnode-right xnode) x1 x2))))))
           (yrecur (ynode y1 y2)
             (declare ((or null ynode) ynode)
                      (fixnum y1 y2)
                      #+sbcl (values fixnum &optional))
             (cond ((null ynode) +op-identity+)
                   ((and (= y1 +neg-inf+) (= y2 +pos-inf+))
                    (%ynode-accumulator ynode))
                   (t
                    (let ((key (%ynode-ykey ynode)))
                      (if (<= y1 key)
                          (if (< key y2)
                              (op (op (yrecur (%ynode-left ynode) y1 +pos-inf+)
                                      (%ynode-value ynode))
                                  (yrecur (%ynode-right ynode) +neg-inf+ y2))
                              (yrecur (%ynode-left ynode) y1 y2))
                          (yrecur (%ynode-right ynode) y1 y2)))))))
    ;; (declare (ftype (function * (values index &optional)) xrecur yrecur))
    (xrecur range-tree x1 x2)))

(defun rt-update (range-tree x y delta)
  "Increments the point (X, Y) by DELTA. (X, Y) must be contained in RANGE-TREE."
  (declare (optimize (speed 3))
           (fixnum x y delta))
  (labels ((xrecur (xnode)
             (declare ((or null xnode) xnode))
             (when xnode
               (yrecur (%xnode-ynode xnode))
               (let ((xkey (%xnode-xkey xnode))
                     (ykey (%xnode-ykey xnode)))
                 (if (or (> x xkey)
                         (and (= x xkey) (>= y ykey)))
                     (xrecur (%xnode-right xnode))
                     (xrecur (%xnode-left xnode))))))
           (yrecur (ynode)
             (declare ((or null ynode) ynode))
             (when ynode
               (let ((xkey (%ynode-xkey ynode))
                     (ykey (%ynode-ykey ynode)))
                 (cond ((and (= x xkey) (= y ykey))
                        (incf (%ynode-value ynode) delta))
                       ((or (> y ykey)
                            (and (= y ykey) (>= x xkey)))
                        (yrecur (%ynode-right ynode)))
                       (t (yrecur (%ynode-left ynode)))))
               (ynode-update-accumulator ynode))))
    (xrecur range-tree)))

(defun rt-set (range-tree x y value)
  (declare (optimize (speed 3))
           (fixnum x y value))
  (labels ((xrecur (xnode)
             (declare ((or null xnode) xnode))
             (when xnode
               (yrecur (%xnode-ynode xnode))
               (let ((xkey (%xnode-xkey xnode))
                     (ykey (%xnode-ykey xnode)))
                 (if (or (> x xkey)
                         (and (= x xkey) (>= y ykey)))
                     (xrecur (%xnode-right xnode))
                     (xrecur (%xnode-left xnode))))))
           (yrecur (ynode)
             (declare ((or null ynode) ynode))
             (when ynode
               (let ((xkey (%ynode-xkey ynode))
                     (ykey (%ynode-ykey ynode)))
                 (cond ((and (= x xkey) (= y ykey))
                        (setf (%ynode-value ynode) value))
                       ((or (> y ykey)
                            (and (= y ykey) (>= x xkey)))
                        (yrecur (%ynode-right ynode)))
                       (t (yrecur (%ynode-left ynode)))))
               (ynode-update-accumulator ynode))))
    (xrecur range-tree)))
