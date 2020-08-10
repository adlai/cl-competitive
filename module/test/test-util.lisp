;;;
;;; This test utility is based on SBCL's test-util.lisp
;;;

(defpackage :test-util
  (:use :cl :sb-ext)
  (:export #:with-test #:report-test-status #:*failures*
           #:really-invoke-debugger
           #:*break-on-failure* #:*break-on-expected-failure*
           #:*elapsed-times*

           ;; type tools
           #:random-type
           #:type-evidently-=
           #:ctype=
           #:assert-tri-eq
           #:random-type

           ;; thread tools
           #:make-kill-thread #:make-join-thread
           #:wait-for-threads
           #:process-all-interrupts
           #:test-interrupt
           ;; cause tests to run in multiple threads
           #:enable-test-parallelism

           ;; MAP-OPTIMIZATION-*
           #:map-optimization-quality-combinations
           #:map-optimize-declarations

           #:assemble
           #:scratch-file-name
           #:with-scratch-file
           #:opaque-identity
           #:runtime #:split-string #:integer-sequence #:shuffle

           #:signals #:quit-with-test-result))

(in-package :test-util)

(defvar *test-count* 0)
(defvar *test-file* nil)
(defvar *failures* nil)
(defvar *break-on-failure* nil)
(defvar *break-on-expected-failure* nil)

(defvar *threads-to-kill*)
(defvar *threads-to-join*)

(defun setenv (name value)
  #-win32
  (let ((r (sb-alien:alien-funcall
            (sb-alien:extern-alien
             "setenv" (function sb-alien:int (sb-alien:c-string :not-null t)
                                (sb-alien:c-string :not-null t) sb-alien:int))
                          name value 1)))
    (if (minusp r)
        (error "setenv: ~a" (sb-int:strerror))
        r))
  #+win32
  (let ((r (sb-alien:alien-funcall
            (sb-alien:extern-alien "_putenv" (function sb-alien:int (sb-alien:c-string :not-null t)))
                          (format nil "~A=~A" name value))))
    (if (minusp r)
        (error "putenv: ~a" (sb-int:strerror))
        r)))

(setenv "SBCL_MACHINE_TYPE" (machine-type))
(setenv "SBCL_SOFTWARE_TYPE" (software-type))


;;; Type tools

(defun random-type (n)
  `(integer ,(random n) ,(+ n (random n))))

(defun type-evidently-= (x y)
  (and (subtypep x y) (subtypep y x)))

(defun ctype= (left right)
  (let ((a (sb-kernel:specifier-type left)))
    ;; SPECIFIER-TYPE is a memoized function, and TYPE= is a trivial
    ;; operation if A and B are EQ.
    ;; To actually exercise the type operation, remove the memoized parse.
    (sb-int:drop-all-hash-caches)
    (let ((b (sb-kernel:specifier-type right)))
      (assert (not (eq a b)))
      (sb-kernel:type= a b))))

(defmacro assert-tri-eq (expected-result expected-certainp form)
  (sb-int:with-unique-names (result certainp)
    `(multiple-value-bind (,result ,certainp) ,form
       (assert (eq ,expected-result ,result))
       (assert (eq ,expected-certainp ,certainp)))))


;;; Thread tools

(defun make-kill-thread (&rest args)
  #-sb-thread (error "can't make-kill-thread ~s" args)
  #+sb-thread
  (let ((thread (apply #'sb-thread:make-thread args)))
    #-win32 ;; poor thread interruption on safepoints
    (when (boundp '*threads-to-kill*)
      (push thread *threads-to-kill*))
    thread))

#+sb-thread
(defun make-join-thread (&rest args)
  (let ((thread (apply #'sb-thread:make-thread args)))
    (when (boundp '*threads-to-join*)
      (push thread *threads-to-join*))
    thread))

(defun wait-for-threads (threads)
  (mapc (lambda (thread) (sb-thread:join-thread thread :default nil)) threads)
  (assert (not (some #'sb-thread:thread-alive-p threads))))

(defun process-all-interrupts (&optional (thread sb-thread:*current-thread*))
  (sb-ext:wait-for (null (sb-thread::thread-interruptions thread))))

(defun test-interrupt (function-to-interrupt &optional quit-p)
  (let ((child  (make-kill-thread function-to-interrupt)))
    (format t "interrupting child ~A~%" child)
    (sb-thread:interrupt-thread child
     (lambda ()
       (format t "child pid ~A~%" sb-thread:*current-thread*)
       (when quit-p (sb-thread:abort-thread))))
    (process-all-interrupts child)
    child))

(defun log-msg (stream &rest args)
  (prog1 (apply #'format stream "~&::: ~@?~%" args)
    (force-output stream)))

(defun log-msg/non-pretty (stream &rest args)
  (let ((*print-pretty* nil))
    (apply #'log-msg stream args)))

(defvar *elapsed-times* nil)
(defun record-test-elapsed-time (test-name start-time)
  (let ((et (- (get-internal-real-time) start-time)))
    (push (cons et test-name) *elapsed-times*)))

(defun run-test (test-function name fails-on
                 &aux (start-time (get-internal-real-time)))
  (start-test)
  (let (#+sb-thread (threads (sb-thread:list-all-threads))
        (*threads-to-join* nil)
        (*threads-to-kill* nil))
    (handler-bind ((error (lambda (error)
                            (if (expected-failure-p fails-on)
                                (fail-test :expected-failure name error)
                                (fail-test :unexpected-failure name error))
                            (return-from run-test))))
      ;; Non-pretty is for cases like (with-test (:name (let ...)) ...
      (log-msg/non-pretty *trace-output* "Running ~S" name)
      (funcall test-function)
      #+sb-thread
      (let ((any-leftover nil))
        (dolist (thread *threads-to-join*)
          (ignore-errors (sb-thread:join-thread thread)))
        (dolist (thread *threads-to-kill*)
          (ignore-errors (sb-thread:terminate-thread thread)))
        (setf threads (union (union *threads-to-kill*
                                    *threads-to-join*)
                             threads))
        #+(and sb-safepoint-strictly (not win32))
        (dolist (thread (sb-thread:list-all-threads))
          (when (typep thread 'sb-thread:signal-handling-thread)
            (ignore-errors (sb-thread:join-thread thread))))
        (dolist (thread (sb-thread:list-all-threads))
          (unless (or (not (sb-thread:thread-alive-p thread))
                      (eql (the sb-thread:thread thread)
                           sb-thread:*current-thread*)
                      (member thread threads)
                      (sb-thread:thread-ephemeral-p thread))
            (setf any-leftover thread)
            #-win32
            (ignore-errors (sb-thread:terminate-thread thread))))
        (when any-leftover
          (fail-test :leftover-thread name any-leftover)
          (return-from run-test)))
      (if (expected-failure-p fails-on)
          (fail-test :unexpected-success name nil)
          ;; Non-pretty is for cases like (with-test (:name (let ...)) ...
          (log-msg/non-pretty *trace-output* "Success ~S" name))))
  (record-test-elapsed-time name start-time))

;;; Like RUN-TEST but do not perform any of the automated thread management.
;;; Since multiple threads are executing tests, there is no reason to kill
;;; unrecognized threads.
(sb-ext:define-load-time-global *output-mutex* (sb-thread:make-mutex))
(defun run-test-concurrently (test-spec)
  (destructuring-bind (test-body . name) test-spec
    (sb-thread:with-mutex (*output-mutex*)
      (log-msg/non-pretty *trace-output* "Running ~S" name))
    (let ((stream (make-string-output-stream)))
      (let ((*standard-output* stream)
            (*error-output* stream))
        (let ((f (compile nil `(lambda () ,@test-body))))
          (funcall f))
        (let ((string (get-output-stream-string stream)))
          (sb-thread:with-mutex (*output-mutex*)
            (when (plusp (length string))
              (log-msg/non-pretty *trace-output* "Output from ~S" name)
              (write-string string *trace-output*))
            (log-msg/non-pretty *trace-output* "Success ~S" name)))))))

(defvar *deferred-test-forms*)
(defun enable-test-parallelism ()
  (let ((n (sb-ext:posix-getenv "SBCL_TEST_PARALLEL")))
    (when n
      (setq *deferred-test-forms* (vector (parse-integer n) nil nil)))))

;;; Tests which are not broken in any way and do not mandate sequential
;;; execution are pushed on a worklist to execute in multiple threads.
;;; The purpose of running tests in parallel is to exercise the compiler
;;; to show that it works without acquiring the world lock,
;;; but the nice side effect is that the tests finish quicker.
(defmacro with-test ((&key fails-on broken-on skipped-on name serial slow)
                     &body body)
  (flet ((name-ok (x y)
           (declare (ignore y))
           (typecase x
             (symbol (let ((package (symbol-package x)))
                       (or (null package)
                           (eql package (find-package "CL-USER"))
                           (eql package (find-package "CL"))
                           (eql package (find-package "KEYWORD")))))
             (integer t))))
    (unless (tree-equal name name :test #'name-ok)
      (error "test name must be all-keywords: ~S" name)))
  (cond
    ((broken-p broken-on)
     `(progn
        (start-test)
        (fail-test :skipped-broken ',name "Test broken on this platform")))
    ((skipped-p skipped-on)
     `(progn
        (start-test)
        (fail-test :skipped-disabled ',name "Test disabled for this combination of platform and features")))
    ((and (boundp '*deferred-test-forms*)
          (not serial)
          (or (not fails-on)
              (not (expected-failure-p fails-on))))
     ;; To effectively parallelize calls to COMPILE, we must defer compilation
     ;; until a worker thread has picked off the test from shared worklist.
     ;; Thus we push only the form to be compiled, not a lambda.
     `(push (cons ',body ',name)
            (elt *deferred-test-forms* ,(if slow 1 2))))
    (t
     `(run-test (lambda () ,@body)
                ',name
                ',fails-on))))

(defun report-test-status ()
  (with-standard-io-syntax
      (with-open-file (stream "test-status.lisp-expr"
                              :direction :output
                              :if-exists :supersede)
        (format stream "~s~%" *failures*))))

(defun start-test ()
  (unless (eq *test-file* *load-pathname*)
    (setf *test-file* *load-pathname*)
    (setf *test-count* 0))
  (incf *test-count*))

(defun really-invoke-debugger (condition)
  (with-simple-restart (continue "Continue")
    (let ((*invoke-debugger-hook* *invoke-debugger-hook*))
      (enable-debugger)
      (invoke-debugger condition))))

(defun fail-test (type test-name condition)
  (if (stringp condition)
      (log-msg *trace-output* "~@<~A ~S ~:_~A~:>"
               type test-name condition)
      (log-msg *trace-output* "~@<~A ~S ~:_due to ~S: ~4I~:_\"~A\"~:>"
               type test-name (type-of condition) condition))
  (push (list type *test-file* (or test-name *test-count*))
        *failures*)
  (unless (stringp condition)
    (when (or (and *break-on-failure*
                   (not (eq type :expected-failure)))
              *break-on-expected-failure*)
      (really-invoke-debugger condition))))

(defun expected-failure-p (fails-on)
  (sb-impl::featurep fails-on))

(defun broken-p (broken-on)
  (sb-impl::featurep broken-on))

(defun skipped-p (skipped-on)
  (sb-impl::featurep skipped-on))

;;;; MAP-{OPTIMIZATION-QUALITY-COMBINATIONS,OPTIMIZE-DECLARATIONS}

(sb-int:defconstant-eqx +optimization-quality-names+
    '(speed safety debug compilation-speed space) #'equal)

(sb-int:defconstant-eqx +optimization-quality-keywords+
    '(:speed :safety :debug :compilation-speed :space) #'equal)

(deftype optimization-quality-range-designator ()
  '(or (eql nil)                                ; skip quality
       (integer 0 3)                            ; one value
       (cons (or (eql nil) (integer 0 3)) list) ; list of values, nil means skip
       (eql t)))                                ; all values

;;; Call FUNCTION with the specified combinations of optimization
;;; quality values.
;;;
;;; MAP-OPTIMIZATION-QUALITY-COMBINATIONS calls FUNCTION with keyword
;;; argument thus expecting a lambda list of the form
;;;
;;;   (&key speed safety debug compilation-speed space)
;;;
;;; or any subset compatible with the generated combinations.
;;;
;;; MAP-OPTIMIZE-DECLARATIONS calls FUNCTION with a list intended to
;;; be spliced into a DECLARE form like this:
;;;
;;;   (lambda (quality-values)
;;;     `(declare (optimize ,@quality-values)))
;;;
;;; The set of combinations is controlled via keyword arguments
;;;
;;;   :FILTER FILTER-FUNCTION
;;;     A function that should be called with optimization quality
;;;     keyword arguments and whose return value controls whether
;;;     FUNCTION should be called for the given combination.
;;;
;;;   (:SPEED | :SAFETY | :DEBUG | :COMPILATION-SPEED | :SPACE) SPEC
;;;     Specify value range for the given optimization quality. SPEC
;;;     can be
;;;
;;;       NIL
;;;         Omit the quality.
;;;
;;;       (INTEGER 0 3)
;;;
;;;         Use the specified value for the quality.
;;;
;;;       (NIL | (INTEGER 0 3))*
;;;         Generate the specified values. A "value" of NIL omits the
;;;         quality from the combination.
;;;
;;;       T
;;;         Generate all values (0, 1, 2, 3) for the quality.
(declaim (ftype (function #.`(function
                              &key
                              ,@(mapcar #'list +optimization-quality-keywords+
                                        '#1=(optimization-quality-range-designator . #1#))
                              (:filter function)))
                map-optimization-quality-combinations
                map-optimize-declarations))
(defun map-optimization-quality-combinations
    (function &key (speed t) (safety t) (debug t) (compilation-speed t) (space t)
                   filter)
  (labels ((map-quantity-values (values thunk)
             (typecase values
               ((eql t)
                (dotimes (i 4) (funcall thunk i)))
               (cons
                (map nil thunk values))
               ((integer 0 3)
                (funcall thunk values))))
           (one-quality (qualities specs values)
             (let ((quality (first qualities))
                   (spec    (first specs)))
               (cond
                 ((not quality)
                  (when (or (not filter) (apply filter values))
                    (apply function values)))
                 ((not spec)
                  (one-quality (rest qualities) (rest specs) values))
                 (t
                  (map-quantity-values
                   spec
                   (lambda (value)
                     (one-quality (rest qualities) (rest specs)
                                  (if value
                                      (list* quality value values)
                                      values)))))))))
    (one-quality +optimization-quality-keywords+
                 (list speed safety debug compilation-speed space)
                 '())))

(defun map-optimize-declarations
    (function &rest args
              &key speed safety debug compilation-speed space filter)
  (declare (ignore speed safety debug compilation-speed space filter))
  (apply #'map-optimization-quality-combinations
         (lambda (&rest args &key &allow-other-keys)
           (funcall function (loop for name in +optimization-quality-names+
                                for keyword in +optimization-quality-keywords+
                                for value = (getf args keyword)
                                when value collect (list name value))))
         args))

(defun expand-optimize-specifier (specifier)
  (etypecase specifier
    (cons
     specifier)
    ((eql nil)
     '(:speed nil :safety nil :debug nil :compilation-speed nil :space nil))
    ((eql :default)
     '(:speed 1 :safety 1 :debug 1 :compilation-speed 1 :space 1))
    ((eql :maximally-safe)
     (list :filter (lambda (&key safety &allow-other-keys)
                     (= safety 3))))
    ((eql :safe)
     (list :filter (lambda (&key speed safety &allow-other-keys)
                     (and (> safety 0) (>= safety speed)))))
    ((eql :quick)
     '(:compilation-speed 1 :space 1))
    ((eql :quick/incomplete)
     '(:compilation-speed nil :space nil))
    ((eql :all)
     '())))

(defun map-optimization-quality-combinations* (function specifier)
  (apply #'map-optimization-quality-combinations
         function (expand-optimize-specifier specifier)))

(defun map-optimize-declarations* (function specifier)
  (apply #'map-optimize-declarations
         function (expand-optimize-specifier specifier)))


;;; Repeat calling THUNK until its cumulated runtime, measured using
;;; GET-INTERNAL-RUN-TIME, is larger than PRECISION. Repeat this
;;; REPETITIONS many times and return the time one call to THUNK took
;;; in seconds as a float, according to the minimum of the cumulated
;;; runtimes over the repetitions.
;;; This allows to easily measure the runtime of expressions that take
;;; much less time than one internal time unit. Also, the results are
;;; unaffected, modulo quantization effects, by changes to
;;; INTERNAL-TIME-UNITS-PER-SECOND.
;;; Taking the minimum is intended to reduce the error introduced by
;;; garbage collections occurring at unpredictable times. The inner
;;; loop doubles the number of calls to THUNK each time before again
;;; measuring the time spent, so that the time measurement overhead
;;; doesn't distort the result if calling THUNK takes very little time.
(defun runtime* (thunk repetitions precision)
  (loop repeat repetitions
        minimize
        (loop with start = (get-internal-run-time)
              with duration = 0
              for n = 1 then (* n 2)
              for total-runs = n then (+ total-runs n)
              for gc-start = *gc-run-time*
              do (dotimes (i n)
                   (funcall thunk))
                 (setf duration (- (get-internal-run-time) start
                                   (- *gc-run-time* gc-start)))
              when (> duration precision)
              return (/ (float duration)
                        (float total-runs)))
        into min-internal-time-units-per-call
        finally (return (/ min-internal-time-units-per-call
                           (float internal-time-units-per-second)))))

(defmacro runtime (form &key (repetitions 5) (precision 30))
  `(runtime* (lambda () ,form) ,repetitions ,precision))

(declaim (notinline opaque-identity))
(defun opaque-identity (x) x)
(compile 'opaque-identity) ; in case this file was loaded as interpreted code

(defun split-string (string delimiter)
  (loop for begin = 0 then (1+ end)
        for end = (position delimiter string) then (position delimiter string :start begin)
        collect (subseq string begin end)
        while end))

(defun integer-sequence (n)
  (loop for i below n collect i))

(defun shuffle (sequence)
  (typecase sequence
    (list
     (coerce (shuffle (coerce sequence 'vector)) 'list))
    (vector ; destructive
     (let ((vector sequence))
       (loop for lim from (1- (length vector)) downto 0
             for chosen = (random (1+ lim))
             unless (= chosen lim)
             do (rotatef (aref vector chosen) (aref vector lim)))
       vector))))

;;; Return a random file name to avoid writing into the source tree.
;;; We can't use any of the interfaces provided in libc because those are inadequate
;;; for purposes of COMPILE-FILE. This is not trying to be robust against attacks.
(defun scratch-file-name (&optional extension)
  (let ((a (make-array 10 :element-type 'character)))
    (dotimes (i 10)
      (setf (aref a i) (code-char (+ (char-code #\a) (random 26)))))
    ;; not sure where to write files on win32. this is no worse than what it was
    #+win32 (format nil "~a~@[.~a~]" a extension)
    #-win32 (let ((dir (posix-getenv "TMPDIR"))
                  (file (format nil "sbcl~d~a~@[.~a~]"
                                (sb-unix:unix-getpid) a extension)))
              (if dir
                  (namestring
                   (merge-pathnames
                    file (parse-native-namestring dir nil *default-pathname-defaults*
                                                  :as-directory t)))
                  (concatenate 'string "/tmp/" file)))))

(defmacro with-scratch-file ((var &optional extension) &body forms)
  (sb-int:with-unique-names (tempname)
    `(let ((,tempname (scratch-file-name ,extension)))
       (unwind-protect
            (let ((,var ,tempname)) ,@forms) ; rebind, as test might asssign into VAR
         (ignore-errors (delete-file ,tempname))))))

;; from UIOP
(defmacro signals (condition sexp &aux (x (gensym)))
  `(block ,x
     (let ((,x (handler-bind ((,condition (lambda (c) (return-from ,x))))
                 ,sexp)))
       (error "Expression ~S fails to raise condition ~S, instead returning ~S"
              ',sexp ',condition ,x))))

(push (lambda ()
        (when *failures*
          (sb-ext:exit :code 1)))
      sb-ext:*exit-hooks*)
