;;;; evol - transform.lisp
;;;; Copyright (C) 2011  Alexander Kahl <e-user@fsfe.org>
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

(defmacro mutagen (name args &body body)
  "mutagen name args &body body => lambda

MUTAGEN (latin: origin of change) is the DEFUN of ELAMBDA."
  `(setf (symbol-function ',name)
         (let ((out))
           (declare (ignorable out))
           (elambda ,args
             (env-bind-let* ,body
               out)))))

(defun transmap (in trans &rest args)
  (labels ((rec (in trans)
             (if trans
                 (mapcan #'(lambda (input)
                             (ensure-list (rec (funcall (car trans) input) (cdr trans))))
                         (ensure-list in))
                 in)))
    (rec in (cons trans args))))
 
(defmacro redirect (in trans)
  `(let ((in ,in))
     ,(if (eq 'lisp (car trans))
         (cadr trans)
         `(funcall #',(car trans) in ,@(cdr trans))))) ; write a test, bitch

(defmacro pipe (in trans &rest args)
  `(transmap ,in ,@(mapcar #'(lambda (form)
                               `(lambda (in)
                                  ,(if (eq 'lisp (car form))
                                       (cadr form)
                                       `(funcall #',(car form) in ,@(cdr form)))))
                           (cons trans args))))

(mutagen debug-pass (&optional (keyword "debug"))
  (out (prog1 in (format *error-output* "~a: (~a) ~s~%" keyword (type-of in) in))))

(mutagen %expand ()
  (out (if (evolvable-p in)
           (expand in)
           in)))

(mutagen bash (command)
  (out (nth-value 1 (run-bash command :fatal t))))

(mutagen evol (type in-arg &rest args)
  (out (apply #'make-instance type in-arg in
              :inputs (hash-table-plist *environment*)
              :deps (mapcar #'uri-of (remove-if-not #'evolvable-p (flatten (hash-table-values *environment*))))
              args)))

; ls ((in string) &optional (path string))
; : in | (bash "ls %{path}/%<") | (file)

(mutagen ls (&key (path "."))
  (out (pipe in (bash "ls %{path}/%<") (evol 'file :path))))

; change-suffix ((in string) (suffix string))
; : in | expand | (lisp (pathname-change-suffix suffix (expand in)))

(mutagen change-suffix (suffix)
  (out (pipe in (%expand) (lisp (pathname-change-suffix suffix in)))))

(mutagen collapse (&optional (token " "))
  (out (redirect (pipe in (%expand)) (lisp (format nil (concatenate 'string "~{~a~^" token "~}")
                                                   (ensure-list in))))))

; compile-c (in (suffix "o"))
; : [in | (bash "gcc ${CFLAGS} -c -o %@ %<")] > rules
; : in | (change-suffix suffix) | (definite :rules rules)

(mutagen compile-c (&key (suffix "o"))
  (rules (list (elambda () (pipe in (%expand) (bash "gcc ${CFLAGS} -c -o %@ %<")))))
  (source in)
  (out (pipe in (change-suffix suffix) (evol 'file :path :rules rules))))

; link-c (in name (path "."))
; : [in | (collapse) |> (bash "gcc ${CFLAGS -o %@ %<}")] > rules
; : in > source
; : name | (bash "echo %{path}/%<") > in
; : in | (evol 'definite :rules rules)

(mutagen link-c (name &key (path "."))
  (rules (list (elambda () (pipe (redirect in (collapse)) (bash "gcc ${CFLAGS} -o %@ %<")))))
  (source in)
  (in (pipe name (bash "echo %{path}/%<")))
  (out (pipe in (evol 'file :path :rules rules))))

; program-c (in name path) 
; : in | (ls :path path) | (compile-c) |> (link-c :name name :path path)

(mutagen program-c (name &optional (path "."))
  (out (redirect (pipe in (ls :path path) (compile-c)) (link-c name :path path))))

(mutagen junction (then else)
  (out (pipe in (lisp (if in then else)))))

(mutagen rm (&optional force)
  (force (pipe force (junction "-f" "")))
  (out (pipe (redirect in (collapse)) (bash "rm -v %{force} %<"))))

(mutagen which ()
  (out (pipe in (lisp (find-program in)))))

(mutagen call (predicate)
  (out (funcall predicate in)))

(mutagen filter (predicate)
  (dup in)
  (out (pipe (redirect in (call predicate)) (junction dup nil))))

;; (let ((breeder (jobs-breeder 4)))
;;   (reinitialize-instance breeder :job-capacity 4)
;;   (devolution "glob:///*.c" (:in "*.c" :path "/home/akahl/Projects/development/lisp/evol/showreel/simple-1") ()
;;               :type 'hive :of 'file :spawn #'(lambda ()
;;                                                (nth-value 1 (run-bash "ls %{path}/%<"))))
;;   (breed breeder (getenv "glob:///*.c" :expanded nil)))

;; (let ((breeder (jobs-breeder 1)))
;;   (breed breeder (getenv "/home/akahl/Projects/development/lisp/evol/showreel/simple-1/program.o" :env *evolvables* :expanded nil)))

;; (let ((breeder (jobs-breeder 4)))
;;   (reinitialize-instance breeder :job-capacity 4)
;;   (breed breeder (getenv "file:///home/akahl/Projects/development/lisp/evol/showreel/simple-1/main" :expanded nil)))
