;;;; evol - path.lisp
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

(in-package :evol-test)

(in-suite all)
(defsuite path)
(in-suite path)

(deftest pathname-suffix-t ()
  (is (pathname-suffix-p "c" "foo.c"))
  (is (pathname-suffix-p "lisp" "bar.lisp")))

(deftest pathname-suffix-nil ()
  (is (not (pathname-suffix-p "vba" "foo.c")))
  (is (not (pathname-suffix-p "el" "bar.lisp"))))

(deftest pathname-change ()
  (is (string= "foo.d" (pathname-change-suffix "d" "foo")))
  (is (string= "foo.c" (pathname-change-suffix "c" "foo.bar")))
  (is (string= "foo.bar.bop" (pathname-change-suffix "bop" "foo.bar.baz"))))
