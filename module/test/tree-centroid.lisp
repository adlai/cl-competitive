(defpackage :cp/test/tree-centroid
  (:use :cl :fiveam :cp/tree-centroid)
  (:import-from :cp/test/base #:base-suite))
(in-package :cp/test/tree-centroid)
(in-suite base-suite)

(test tree-centroid
  (let ((tc (make-tree-centroid (coerce #((1) (0 2) (1 3) (2))
                                        '(simple-array list (*))))))
    (dotimes (root 4)
      (multiple-value-bind (c1 children1 c2 children2) (tc-find-centroid tc root)
        (declare (ignore children1 children2))
        (is (or (and (= c1 1) (= c2 2))
                (and (= c1 2) (= c2 1))))))
    (tc-disable-vertex tc 1)
    (signals tree-centroid-disabled-vertex-error (tc-find-centroid tc 1))
    (multiple-value-bind (c1 children1 c2 children2) (tc-find-centroid tc 0)
      (declare (ignore children1 children2))
      (is (and (= c1 0) (null c2))))
    (multiple-value-bind (c1 children1 c2 children2) (tc-find-centroid tc 2)
      (declare (ignore children1 children2))
      (is (or (and (= c1 2) (= c2 3))
              (and (= c1 3) (= c2 2)))))))
