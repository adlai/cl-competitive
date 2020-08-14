#-compiled
(eval-when (:execute)
  (defun self-compile ()
    (let ((*compile-print* nil)
          (*compile-verbose* nil))
      (assert *load-pathname*)
      (pushnew :compiled *features*)
      (compile-file *load-pathname*)
      (with-open-file (out-lisp *load-pathname* :direction :output :if-exists :supersede :element-type '(unsigned-byte 8))
        (with-open-file (in-fasl (make-pathname :type "fasl" :defaults *load-pathname*) :direction :input :element-type '(unsigned-byte 8))
          (loop for byte = (read-byte in-fasl nil -1)
                while (>= byte 0)
                do (write-byte byte out-lisp)))))
    (quit
     :unix-status
     (process-exit-code
      (run-program *runtime-pathname*
                   `("--control-stack-size" "128MB"
                     "--noinform" "--disable-ldb" "--lose-on-corruption" "--end-runtime-options"
                     "--script" ,(namestring *load-pathname*))
                   :output t :error t :input t))))
  (self-compile))

