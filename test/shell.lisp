;;;; evol - shell.lisp
;;;; Copyright (C) 2009  Alexander Kahl <e-user@fsfe.org>
;;;; This file is part of evol.
;;;; evol is free software; you can redistribute it and/or modify
;;;; it under the terms of the GNU General Public License as published by
;;;; the Free Software Foundation; either version 3 of the License, or
;;;; (at your option) any later version.
;;;;
;;;; evol is distributed in the hope that it will be useful,
;;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;;;; GNU General Public License for more details.
;;;;
;;;; You should have received a copy of the GNU General Public License
;;;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

(in-package :evol)

(shadowing-import
 '(flatten deflate-string expand-%-match trim-{} interpolate-commandline)
 (find-package :evol-test))

(in-package :evol-test)

(in-suite all)
(defsuite shell)
(in-suite shell)

(deftest flattening (expected list)
  (is (equal expected (flatten list)))
  (unless (atom list)
    (is (not (eql list (flatten list))))))

(deftest flatten-lists ()
  (mapc #'flattening
        (list '(A B C D E F G)
              '("foo" "bar" "baz")
              nil)
        (list '(A (B C (D E) F) G)
              '("foo" "bar" ("baz"))
              nil)))

(deftest deflating ()
  (mapc #'(lambda (expected list separator)
            (is (equal expected
                       (deflate-string list separator))))
        (list "foo bar baz"
              "1,-,3,-,5"
              "abcdef")
        (list '("foo" "bar" "baz")
              '(1 3 5)
              '("a" "b" "c" "d" "e" "f"))
        (list " "
              ",-,"
              nil)))

(defparameter *environment* nil)

(deftest trimming-{} ()
  (mapcar #'(lambda (string)
              (is (string= "foo" (trim-{} string))))
          (list "{foo}" "{{foo}" "{foo}}")))

(defixture shell-environment-fixture
  (:setup (setq *environment* (make-hash-table))
          (defenv test1 "42 23")
          (defenv cc "gcc")
          (defenv file1 "foo.c")
          (defenv file2 "bar.c")))

(deftest expanding-%-matches ()
  (with-fixture shell-environment-fixture
    (is (string= "%"
                 (expand-%-match "%" "" #'default-sourcefn *environment*)))
    (is (string= "Layer 8"
                 (expand-%-match "@" "Layer 8" #'default-sourcefn *environment*)))
    (is (string= "right"
                 (expand-%-match "<" "foo"
                                 #'(lambda (input1 input2)
                                     (declare (ignore input2))
                                     (if (string= "foo" input1) "right" "wrong"))
                                 *environment*)))
    (is (string= "right"
                 (expand-%-match "<--|WIN|" "foo"
                                 #'(lambda (input1 input2)
                                     (declare (ignore input1))
                                     (if (string= "--|WIN|" input2) "right" "wrong"))
                                 *environment*)))
    (is (string= "WIN AWESOME lol."
                 (expand-%-match "<" ""
                                 #'(lambda (input1 input2) (list "WIN" "AWESOME" "lol."))
                               *environment*)))
    (is (string= "42 23"
                 (expand-%-match "test1" "" #'default-sourcefn *environment*)))))

(deftest test-complex-commandlines ()
  (with-fixture shell-environment-fixture
    (is (equal '("gcc" "foo.c" "bar.c")
               (interpolate-commandline "%cc %file1 %file2")))))
