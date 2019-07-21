(eval-when (:compile-toplevel :load-toplevel :execute)
  (load "test-util")
  (load "../bisect.lisp"))

(use-package :test-util)

(with-test (:name bisect-left)
  (assert (= 0 (bisect-left #(1 8) -3)))
  (assert (= 0 (bisect-left #(1 8) 1)))
  (assert (= 1 (bisect-left #(1 8) 4)))
  (assert (= 1 (bisect-left #(1 8) 8)))
  (assert (= 2 (bisect-left #(1 8) 9)))
  (assert (= 3 (bisect-left #(1 4 5 7 7 7 7 7 7 8) 7)))
  (assert (= 3 (bisect-left #(1 4 4 7 7 7 7 7 8) 6)))
  (assert (= 1 (bisect-left #(#\a #\c #\c #\d) #\b :order #'char<)))
  (assert (= 1 (bisect-left #(#\a #\c #\c #\d) (char-code #\b)
                            :order #'< :key #'char-code)))
  (assert (= 4 (bisect-left #(nil 1 4 4 7 7 nil nil) 6 :start 1 :end 4))))

(with-test (:name bisect-right)
  (assert (= 0 (bisect-right #(1) 0)))
  (assert (= 1 (bisect-right #(1) 1)))
  (assert (= 1 (bisect-right #(1) 2)))
  (assert (= 0 (bisect-right #(1 8) 0)))
  (assert (= 2 (bisect-right #(1 8) 8)))
  (assert (= 1 (bisect-right #(1 8) 4)))
  (assert (= 1 (bisect-right #(1 8) 1)))
  (assert (= 2 (bisect-right #(1 8) 9)))
  (assert (= 7 (bisect-right #(1 4 5 7 7 7 7 8) 7)))
  (assert (= 3 (bisect-right #(1 4 4 7 7 7 7 7 8) 6)))
  (assert (= 3 (bisect-right #(10 9 9 7 7 7 7 7 4) 9 :order #'>)))
  (assert (= 3 (bisect-right #(#\a #\c #\c #\d) #\c :order #'char<)))
  (assert (= 4 (bisect-right #(nil 1 4 4 4 4 7 7 nil nil) 4 :start 1 :end 4))))
