;;;; evol - m4-builtin.lisp
;;;; Copyright (C) 2010  Alexander Kahl <e-user@fsfe.org>
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

(defparameter *m4-lib* (make-hash-table :test #'equal))

(defmacro defm4macro (name args &body body)
  (let ((macro-args (gensym)))
    `(setf (gethash ,name *m4-lib*)
           #'(lambda (&rest ,macro-args)
               (when (> (length ,macro-args) (length ',args))
                 (warn (format nil "excess arguments to builtin `~a' ignored" ,name)))
               (destructuring-bind ,args ,macro-args
                 ,@body)))))

(defun m4-macro-exists (macro)
  (gethash macro *m4-lib*))
