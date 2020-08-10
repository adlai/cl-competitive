;;;
;;; Generate random trees
;;;

;; TODO: maybe better to use Prüfer sequence?

;; NOT TESTED
(defun make-random-tree (size)
  "Returns an undirected random tree of the given size."
  (declare ((integer 0 #.most-positive-fixnum) size))
  (let ((graph (make-array size :element-type 'list :initial-element nil))
        (dset (make-array size :element-type 'fixnum :initial-element -1))
        (count 0))
    (declare ((integer 0 #.most-positive-fixnum) count))
    ;; Union-Find
    (labels ((ds-root (x)
               (if (< (aref dset x) 0)
                   x
                   (setf (aref dset x)
                         (ds-root (aref dset x)))))
             (ds-unite (x1 x2)
               (let ((root1 (ds-root x1))
                     (root2 (ds-root x2)))
                 (unless (= root1 root2)
                   (when (> (aref dset root1) (aref dset root2))
                     (rotatef root1 root2))
                   (incf (aref dset root1) (aref dset root2))
                   (setf (aref dset root2) root1)))))
      (loop until (= count (- size 1))
            for u = (random size)
            for v = (random size)
            unless (= (ds-root u) (ds-root v))
            do (ds-unite u v)
               (push u (aref graph v))
               (push v (aref graph u))
               (incf count)))
    graph))
