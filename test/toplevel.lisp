;;;; evol - toplevel.lisp
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

(shadowing-import
 '(breeder swarm jobs-breeder)
 (find-package :evol-test))

(in-package :evol-test)

(in-suite all)
(defsuite toplevel)
(in-suite toplevel)

(deftest breeder-type ()
  (is (typep (jobs-breeder 1) 'breeder))
  (is (typep (jobs-breeder 2) 'swarm))
  (is (typep (jobs-breeder 3) 'swarm)))