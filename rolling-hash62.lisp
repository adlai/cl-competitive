;;;
;;; Rolling hash (62-bit)
;;;

;; Reference:
;; https://www.mii.lt/olympiads_in_informatics/pdf/INFOL119.pdf
;; https://ei1333.github.io/luzhiled/snippets/string/rolling-hash.html

(defstruct (rhash (:constructor %make-rhash (cumul1 powers1 cumul2 powers2)))
  ;; lower 31-bit value
  (cumul1 nil :type (simple-array (unsigned-byte 31) (*)))
  (powers1 nil :type (simple-array (unsigned-byte 31) (*)))
  ;; upper 31-bit value
  (cumul2 nil :type (simple-array (unsigned-byte 31) (*)))
  (powers2 nil :type (simple-array (unsigned-byte 31) (*))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  ;; This table consists of pairs of primes less than 2^31 and the random
  ;; primitive roots modulo them and larger than 10^9. We randomly choose a pair
  ;; and adopt the prime as modulus, and the primitive root as base.
  (declaim ((simple-array (unsigned-byte 31) (100)) *moduli-table* *base-table*))
  (defparameter *moduli-table*
    (make-array 100 :element-type '(unsigned-byte 31)
                    :initial-contents '(2147483647 2147483629 2147483587 2147483579 2147483563 2147483549 2147483543
 2147483497 2147483489 2147483477 2147483423 2147483399 2147483353 2147483323
 2147483269 2147483249 2147483237 2147483179 2147483171 2147483137 2147483123
 2147483077 2147483069 2147483059 2147483053 2147483033 2147483029 2147482951
 2147482949 2147482943 2147482937 2147482921 2147482877 2147482873 2147482867
 2147482859 2147482819 2147482817 2147482811 2147482801 2147482763 2147482739
 2147482697 2147482693 2147482681 2147482663 2147482661 2147482621 2147482591
 2147482583 2147482577 2147482507 2147482501 2147482481 2147482417 2147482409
 2147482367 2147482361 2147482349 2147482343 2147482327 2147482291 2147482273
 2147482237 2147482231 2147482223 2147482121 2147482093 2147482091 2147482081
 2147482063 2147482021 2147481997 2147481967 2147481949 2147481937 2147481907
 2147481901 2147481899 2147481893 2147481883 2147481863 2147481827 2147481811
 2147481797 2147481793 2147481673 2147481629 2147481571 2147481563 2147481529
 2147481509 2147481499 2147481491 2147481487 2147481373 2147481367 2147481359
 2147481353 2147481337)))
  (defparameter *base-table*
    (make-array 100 :element-type '(unsigned-byte 31)
                    :initial-contents '(1059428526 2090066834 1772913519 1695158082 1516083910 1622025757 1248368302
 1894391153 2094976878 1193495823 1783230399 1520742486 1748395380 1703688443
 2138630366 1942049269 2066548889 1890950855 1480056952 1792721876 1092797280
 1204851872 1035383130 1002272185 1319736653 1980774767 1748793187 1866963602
 1200445534 1732959733 1214706585 1957228822 1479411729 1323155655 1052714514
 1989821027 1163834549 1095622874 2087901566 1670886084 1191975321 2091468260
 1429690292 1116037844 1420457779 1937649612 1552519679 1328604092 2090326292
 1397132095 1316705322 1664351025 1391513321 1851038917 1556301575 1928956735
 1764506480 1449537491 2119470570 1793768237 1831208371 1723755364 1643456516
 1993819805 1419297891 1755252963 1775153034 1388979165 2144586633 1501222238
 1872274033 1143076711 1229125474 1483974015 1997206147 1593231852 1632083893
 1601537043 2012194627 1299923971 1566635240 1814404069 1619988648 2072686565
 2014361572 1213868607 1166967329 1009325840 1306167671 1915239658 1223190075
 1821151471 2037700892 1646950698 1517859810 1099233635 1004913731 1653443892
 1782112665 1018916580)))

  (defun %choose-moduli (&optional mod1 mod2 base1 base2)
    "Chooses two appropriate pairs of moduli and bases."
    (declare ((or null (unsigned-byte 31)) mod1 mod2 base1 base2))
    (let* ((rand1 (random (length *moduli-table*)))
           (rand2 (loop (let ((tmp (random (length *moduli-table*))))
                          (unless (= tmp rand1)
                            (return tmp))))))
      (if mod1
          (progn
            #+sbcl (assert (sb-int:positive-primep mod1))
            (setq base1 (or base1 (+ 1 (random (- mod1 1))))))
          (progn
            (setq mod1 (or mod1 (aref *moduli-table* rand1)))
            (if base1
                (assert (<= 1 base1 (- mod1 1)))
                (setq base1 (aref *base-table* rand1)))))
      (if mod2
          (progn
            #+sbcl (assert (sb-int:positive-primep mod2))
            (setq base2 (or base2 (+ 1 (random (- mod2 1))))))
          (progn
            (setq mod2 (or mod2 (aref *moduli-table* rand2)))
            (if base2
                (assert (<= 1 base2 (- mod2 1)))
                (setq base2 (aref *base-table* rand2))))))
    (values mod1 mod2 base1 base2))

  (unless (and (boundp '+rhash-mod1+)
               (boundp '+rhash-mod2+)
               (boundp '+rhash-base1+)
               (boundp '+rhash-base2+))
    (multiple-value-bind (mod1 mod2 base1 base2) (%choose-moduli)
      (defconstant +rhash-mod1+ mod1)
      (defconstant +rhash-mod2+ mod2)
      (defconstant +rhash-base1+ base1)
      (defconstant +rhash-base2+ base2))))

;; KLUDGE: Type derivation of MOD fails in some cases on SBCL. See
;; https://bugs.launchpad.net/sbcl/+bug/1843108
(declaim (inline %mod))
(defun %mod (number divisor)
  (nth-value 1 (floor number divisor)))

(defun make-rhash (vector &key (key #'char-code))
  "Returns the table of rolling-hash of VECTOR modulo +RHASH-MOD1+ and
+RHASH-MOD2+. KEY is applied to each element of VECTOR prior to computing the
hash value.

KEY := FUNCTION returning FIXNUM"
  (declare (optimize (speed 3))
           (vector vector)
           (function key))
  (let* ((size (length vector))
         (cumul1 (make-array (+ 1 size) :element-type '(unsigned-byte 31)))
         (powers1 (make-array (+ 1 size) :element-type '(unsigned-byte 31)))
         (cumul2 (make-array (+ 1 size) :element-type '(unsigned-byte 31)))
         (powers2 (make-array (+ 1 size) :element-type '(unsigned-byte 31))))
    (setf (aref powers1 0) 1
          (aref powers2 0) 1)
    (dotimes (i size)
      (setf (aref powers1 (+ i 1))
            (%mod (* (aref powers1 i) +rhash-base1+) +rhash-mod1+)
            (aref powers2 (+ i 1))
            (%mod (* (aref powers2 i) +rhash-base2+) +rhash-mod2+))
      (let ((sum1 (+ (%mod (* +rhash-base1+ (aref cumul1 i)) +rhash-mod1+)
                     (%mod (the fixnum (funcall key (aref vector i))) +rhash-mod1+)))
            (sum2 (+ (%mod (* +rhash-base2+ (aref cumul2 i)) +rhash-mod2+)
                     (%mod (the fixnum (funcall key (aref vector i))) +rhash-mod2+))))
        (setf (aref cumul1 (+ i 1)) (if (>= sum1 +rhash-mod1+)
                                        (- sum1 +rhash-mod1+)
                                        sum1)
              (aref cumul2 (+ i 1)) (if (>= sum2 +rhash-mod2+)
                                        (- sum2 +rhash-mod2+)
                                        sum2))))
    (%make-rhash cumul1 powers1 cumul2 powers2)))

(declaim (ftype (function * (values (unsigned-byte 62) &optional)) rhash-vector-hash)
         (inline rhash-vector-hash))
(defun rhash-vector-hash (vector &key (key #'char-code))
  "Returns the hash code of VECTOR."
  (declare (optimize (speed 3))
           (vector vector)
           (function key))
  (let* ((size (length vector))
         (lower 0)
         (upper 0))
    (declare ((unsigned-byte 31) lower upper))
    (dotimes (i size)
      (setf lower (%mod (+ (* +rhash-base1+ lower)
                          (%mod (the fixnum (funcall key (aref vector i))) +rhash-mod1+))
                       +rhash-mod1+))
      (setf upper (%mod (+ (* +rhash-base2+ upper)
                          (%mod (the fixnum (funcall key (aref vector i))) +rhash-mod2+))
                       +rhash-mod2+)))
    (dpb upper (byte 31 31) lower)))

(declaim (inline rhash-query)
         (ftype (function * (values (unsigned-byte 62) &optional)) rhash-query))
(defun rhash-query (rhash l r)
  "Returns the hash value of the interval [L, R)."
  (declare ((integer 0 #.most-positive-fixnum) l r))
  (assert (<= l r))
  (let ((cumul1 (rhash-cumul1 rhash))
        (powers1 (rhash-powers1 rhash))
        (cumul2 (rhash-cumul2 rhash))
        (powers2 (rhash-powers2 rhash)))
    (let ((lower (+ (aref cumul1 r)
                    (- +rhash-mod1+ (%mod (* (aref cumul1 l) (aref powers1 (- r l))) +rhash-mod1+))))
          (upper (+ (aref cumul2 r)
                    (- +rhash-mod2+ (%mod (* (aref cumul2 l) (aref powers2 (- r l))) +rhash-mod2+)))))
      (let ((lower (if (>= lower +rhash-mod1+) (- lower +rhash-mod1+) lower))
            (upper (if (>= upper +rhash-mod2+) (- upper +rhash-mod2+) upper)))
        (declare ((unsigned-byte 31) lower upper))
        (dpb upper (byte 31 31) lower)))))

(declaim (inline rhash-concat))
(defun rhash-concat (rhash hash-value1 hash-value2 length2)
  "Returns the hash value of the concatenated sequence.

HASH-VALUE1 := hash value of the first sequence
HASH-VALUE2 := hash value of the second sequence
LENGTH2 := length of the second sequence."
  (declare ((unsigned-byte 62) hash-value1 hash-value2)
           ((integer 0 #.most-positive-fixnum) length2))
  (let* ((hash1-lower (ldb (byte 31 0) hash-value1))
         (hash1-upper (ldb (byte 31 31) hash-value1))
         (hash2-lower (ldb (byte 31 0) hash-value2))
         (hash2-upper (ldb (byte 31 31) hash-value2))
         (res-lower (%mod (+ hash2-lower
                            (* hash1-lower
                               (aref (rhash-powers1 rhash) length2)))
                         +rhash-mod1+))
         (res-upper (%mod (+ hash2-upper
                            (* hash1-upper
                               (aref (rhash-powers2 rhash) length2)))
                         +rhash-mod2+)))
    (declare ((unsigned-byte 31) res-lower res-upper))
    (dpb res-upper (byte 31 31) res-lower)))

(declaim (ftype (function * (values (integer 0 #.most-positive-fixnum) &optional)) rhash-get-lcp))
(defun rhash-get-lcp (rhash1 start1 rhash2 start2)
  "Returns the length of the longest common prefix of two suffixes which begin
at START1 and START2."
  (declare (optimize (speed 3))
           ((mod #.most-positive-fixnum) start1 start2))
  (assert (and (< start1 (length (rhash-cumul1 rhash1)))
               (< start2 (length (rhash-cumul1 rhash2)))))
  (let ((max-length (min (- (length (rhash-cumul1 rhash1)) start1 1)
                         (- (length (rhash-cumul1 rhash2)) start2 1))))
    (declare (optimize (safety 0)))
    (labels ((bisect (ok ng)
               (declare ((integer 0 #.most-positive-fixnum) ok ng))
               (if (<= (- ng ok) 1)
                   ok
                   (let ((mid (ash (+ ng ok) -1)))
                     (if (= (rhash-query rhash1 start1 (+ start1 mid))
                            (rhash-query rhash2 start2 (+ start2 mid)))
                         (bisect mid ng)
                         (bisect ok mid))))))
      (bisect 0 (+ 1 max-length)))))

(defun map-prefix-hash (vector function &key (start 0) end)
  "Applies FUNCTION to the hash value of each prefix of VECTOR (in ascending
order, including null prefix)."
  (declare (vector vector)
           (function function)
           ((integer 0 #.most-positive-fixnum) start)
           ((or null (integer 0 #.most-positive-fixnum)) end))
  (let* ((end (or end (length vector)))
         (lower 0)
         (upper 0))
    (loop for i from start below end
          do (funcall function (dpb upper (byte 31 31) lower))
             (setq lower (%mod (* lower +rhash-base1+) +rhash-mod1+)
                   upper (%mod (* upper +rhash-base2+) +rhash-mod2+)))))
