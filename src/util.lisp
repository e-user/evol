;;;; evol - util.lisp
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

(set-dispatch-macro-character #\# #\> 'cl-heredoc:read-heredoc)

(defun posix-argv ()
  "posix-argv => list

Return command line argument list. Implementation dependent."
  #+sbcl sb-ext:*posix-argv*
  #+ccl *command-line-argument-list*
  #+clisp ext:*args*
  #-(or sbcl ccl clisp) nil)

(defun posix-quit (&optional code)
  "posix-quit => bye bye

Quit the current running CL instance returning error CODE."
  #+ccl (ccl:quit code)
  #+clisp (#+lisp=cl ext:quit #-lisp=cl lisp:quit code)
  #+gcl (lisp:bye code)
  #+sbcl (sb-ext:quit :unix-status (typecase code
                                     ((signed-byte 32) code)
                                     (null 0)
                                     (t 1)))
  #-(or ccl clisp gcl sbcl)
    (error 'not-implemented :proc (list 'quit code)))

(defun mapthread (function list &rest more-lists)
  "mapthread function list &rest more-lists => list

Apply FUNCTION against each set of elements from LIST and MORE-LISTS just like
MAPCAR but use a new thread for each call. Returns result list from joining all
threads created that way."
  (mapcar #'bt:join-thread
          (apply #'mapcar #'(lambda (&rest args)
                              (bt:make-thread #'(lambda ()
                                                  (apply function
                                                         (car args)
                                                         (cdr args)))
                                              :name (gensym)))
                 list more-lists)))

(defmacro with-outputs-to-strings ((&rest vars) &body forms-decls)
  "with-outputs-to-strings (&rest vars) &body forms-decls => (result string1 .. stringN)

The multi-version of WITH-OUTPUT-TO-STRING preserving original return values.
Evaluate FORMS-DECLS with each element in VARS bound to a fresh open stream.
Return multiple VALUES of FORMS-DECLS evaluation result and one string per VARS
in given argument order."
  `(let (,@(mapcar #'(lambda (var)
                       (list var '(make-string-output-stream :element-type 'character)))
                   vars))
     (apply #'values
      (unwind-protect (progn ,@forms-decls)
        (mapc #'close (list ,@vars)))
      (mapcar #'get-output-stream-string (list ,@vars)))))

(defun stringify (object)
  "stringify object => string

If OBJECT is a STRING, return it - else cast WRITE-TO-STRING."
  (if (stringp object)
      object
    (write-to-string object)))

(defmacro env-let (bindings &body body)
  "env let bindings &body body => context

Evaluate BODY in scope of overridden *ENVIRONMENT* that is extended by
LET-style key/value BINDINGS list."
  (let ((%bindings (gensym)))
    `(let ((,%bindings ,bindings)
           (*environment* (copy-hash-table *environment*)))
       (mapc #'(lambda (binding)
                 (destructuring-bind (name value)
                     binding
                   (setf (getenv name) value)))
             ,%bindings)
       ,@body)))

(defmacro with-slot-enhanced-environment ((slots object) &body body)
  "with-slot-enhanced-environment (slots object) body => context

Create lexical context overriding *ENVIRONMENT* with a fresh copy enhanced by
all slot names/values as key/values from symbol list SLOTS in OBJECT."
  (let ((%object (gensym))
        (%slots (gensym)))
    `(let ((,%object ,object)
           (,%slots ,slots))
       (env-let (mapcar #'(lambda (slot)
                            (list slot (slot-value ,%object slot)))
                        ,%slots)
         ,@body))))

(defun replace-with-region (replacefn &rest args)
  "replace-with-region replacefn &rest args => closure

Create closure that is suitable for use with CL-PPCRE replacement forms. Created
closure invokes REPLACEFN against the matched subsequence in the string to be
searched additionally passing ARGS."
  #'(lambda (target-string start end match-start match-end reg-starts reg-ends)
      (declare (ignore start end match-start match-end))
      (apply replacefn (subseq target-string
                               (svref reg-starts 0) (svref reg-ends 0))
             args)))
