;;;; evol - evolvable.lisp
;;;; Copyright (C) 2009 2010 2011  Alexander Kahl <e-user@fsfe.org>
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

;;; conditions
(define-condition hive-burst (error)
  ((spawn :initarg :spawn
          :reader  spawn-burst-of))
  (:documentation "Condition that signals a HIVE has hatched and child
evolvables have been created and need to be taken into account during evolution processes."))


;;; classes
;;; evolvable, base target class
(defclass evolvable ()
  ((name :reader   name
         :initarg  :name
         :initform (required-argument :name)
         :documentation "The name of the evolvable, also available in evol's environment")
   (inputs :accessor inputs
           :initarg :inputs
           :initform nil)
   (outputs :accessor outputs
            :initarg :outputs
            :initform nil)
   (dependencies :accessor dependencies
                 :initarg  :deps
                 :initform nil
                 :documentation "List of supplementary evolvables this one depends on")
   (env-slots :accessor env-slots
              :initarg  :env-slots
              :initform nil
              :documentation "List of slots to lexically bind to the environment during evolution")
   (mutex     :reader   mutex
              :initform (bt:make-lock)
              :documentation "Mutex for the wait queue")
   (waitqueue :reader   waitqueue
              :initform (bt:make-condition-variable)
              :documentation "Wait queue used for multithreaded breeding")
   (hatched   :accessor hatched-p
              :initform nil
              :documentation "Whether evolution is finished"))
  (:documentation "Base class for all evolvables."))

(defmethod initialize-instance :after ((evol evolvable) &rest initargs)
  "initialize-instance :after evol &rest initargs => evol

Also register EVOLVABLE in the evol *ENVIRONMENT*."
  (declare (ignore initargs))
  (setf (getenv (name evol)) evol))

(defmethod print-object ((evol evolvable) stream)
  "print-object evolvable stream => nil

Printing evolvable-derived objects must simply return their names."
  (princ (name evol) stream))

(defmethod expand ((evol evolvable))
  "expand evol => string

Expand EVOL to its name."
  (name evol))

(defgeneric evolve (evolvable &rest args &key &allow-other-keys)
  (:documentation "Evolve this, whatever that may be")
  (:method :after ((evol evolvable) &rest args &key &allow-other-keys)
    "evolve :after evol &rest args &key &allow-other-keys => t

Mark evolvable EVOL hatched."
    (declare (ignore args))
    (setf (hatched-p evol) t))
  (:method :around ((evol evolvable) &rest args &key &allow-other-keys)
    "evolve :around evol &rest args &key &allow-other-keys => context

Call the next method in scope of a copy of *ENVIRONMENT* enhanced by all slots
in EVOL specified by ENV-SLOTS."
    (declare (ignore args))
    (with-slot-enhanced-environment (env-slots evol)
        evol
      (call-next-method))))

(defgeneric reset (evolvable)
  (:documentation "reset evolvable => result

Reset evolution of EVOLVABLE.")
  (:method ((evol evolvable))
    "reset evolvable => nil

Set slot HATCHED back to nil. Useful for development (only?)."
    (setf (hatched-p evol) nil)))

(defun evolvable-p (object)
  "evolvable-p object => boolean

Tell whether OBJECT is an EVOLVABLE."
  (typep object 'evolvable))

(defun reset-evolvables (&optional (env *environment*))
  "reset-evolvables env => evolvables-list

RESET all evolvables in hashtable ENV. Useful for development."
  (mapc #'(lambda (object)
            (reset object))
          (remove-if-not #'evolvable-p
                         (hash-table-values env))))


;;; virtual class
(defclass virtual (evolvable) ()
  (:documentation "Virtual evolvables exist for the sole purpose of
beautification through grouping and/or naming by having its dependencies
evolve."))

(defmethod evolve ((virt virtual) &rest args &key &allow-other-keys) t)


;;; hive class
(defclass hive (virtual)
  ((of    :reader   :of
          :initarg  :of
          :initform (required-argument :of)
          :documentation "The subtype of evolvable to harbor")
   (spawn :reader   :spawn
          :initarg  :spawn
          :initform (required-argument :spawn)
          :documentation "Source of spawn evolvables; can be a function or a list")
   (trigger :accessor hive-trigger
            :initform nil
            :documentation "Thunk created during INITIALIZE-INSTANCE :AFTER that
gets evaluated upon evolution.")
   (burst :accessor burst-p
          :initform nil
          :documentation "Hatch pre-state: Tells whether evolution has already
been triggered once so the spawn has been created and a second attempt will
finally finish evolution (hatching)."))
  (:documentation "Hives enable mass spawning of evolvables during evolution;
that way, indeterminate builds can be accomplished."))

(defmethod initialize-instance :after ((hive hive) &rest initargs &key &allow-other-keys)
  "initialize-instance :after hive &rest initargs &key &allow-other-keys => void

Bind a thunk to HIVE's TRIGGER that creates an EVOLVABLE :OF type for each
:SPAWN with all key arguments proxied but :NAME, :OF:, :SPAWN and have the HIVE
itself auto-depend on them."
  (let ((of (getf initargs :of))
        (spawn (getf initargs :spawn))
        (spawnargs (remove-from-plist initargs :name :of :spawn)))
    (with-accessors ((deps dependencies)
                     (trigger hive-trigger))
        hive
      (setq trigger #'(lambda ()
                        (setq deps
                              (mapcar #'(lambda (name)
                                          (apply #'make-instance of :name name spawnargs))
                                      (if (functionp spawn)
                                          (funcall spawn)
                                          spawn))))))))

(defmethod evolve ((hive hive) &rest args &key &allow-other-keys)
    "evolve hive &rest args &key &allow-other-keys => condition

Call HIVE's TRIGGER thunk. Signals HIVE-BURST condition."
    (declare (ignore args))
    (with-accessors ((burst burst-p))
        hive
      (or burst
          (progn
            (setq burst t)
            (signal 'hive-burst :spawn (funcall (hive-trigger hive)))))))

(defmethod expand ((hive hive))
  "expand hive => list

Hives expand to a list of their dependencies' names."
  (dependencies hive))


;;; definite class
(defclass definite (evolvable)
  ((rules :accessor rules
          :initarg :rules
          :documentation "The rules used to evolve the definite"))
  (:documentation "Definite evolvables define transformation rules."))

(defmethod evolve ((definite definite) &rest args &key &allow-other-keys)
  (declare (ignore args))
  (mapcar #'funcall
          (rules definite)))


;;; checkable class
(defclass checkable (evolvable) ()
   (:documentation "Evolvables derived from checkable provide a means to pre- and
post-validate their evolution."))

(defgeneric evolved-p (checkable)
  (:documentation "Check that given evolution has been evolved properly"))

(defmethod evolve :around ((evol checkable) &rest args &key &allow-other-keys)
  (or (evolved-p evol)
      (call-next-method)))


;;; file class
(defclass file (checkable) ()
  (:documentation "Files are targets that usually lead to evolution
of... files. Their existence can easily be checked through their distinct
pathnames."))

(defmethod evolved-p ((file file))
  (file-exists-p (osicat:pathname-as-file (name file))))


;;; executable
(defclass executable (file) ()
  (:documentation "Executables are files that can be run on a machine's stack by
either containing machince code themselves or referring to an interpreter for
source code contained within. This class ensures its file is executable after
creation."))

(defmethod evolve :after ((exe executable) &rest args &key &allow-other-keys)
  (run-command (interpolate-commandline "chmod +x %@" :target (name exe))))


;; ;;;; Generic
;; ;;; generic-transformator class
;; (defclass generic-transformator (definite)
;;   ((rule :accessor rule
;;          :initarg :rule
;;          :initform (required-argument :rule)))
;;   (:documentation "Objects of this kind evolve through running an external
;; program through interpolating the rule and source function contained within
;; honoring common quoting rules in line with Bourne shell syntax."))

;; (defmethod evolve ((trans generic-transformator) &rest args &key &allow-other-keys)
;;   (run-command (interpolate-commandline (rule trans) *environment*)))


;; ;;; generic class
;; (defclass generic (generic-transformator file) ()
;;   (:documentation "TODO"))


;; ;;; program class
;; (defclass program (generic-transformator executable) ()
;;   (:documentation "TODO"))
