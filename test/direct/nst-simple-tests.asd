;;; File mnst.asd
;;;
;;; This file is part of the NST unit/regression testing system.
;;;
;;; Copyright (c) 2006-2009 Smart Information Flow Technologies.
;;; Derived from RRT, Copyright (c) 2005 Robert Goldman.
;;;
;;; NST is free software: you can redistribute it and/or modify it
;;; under the terms of the GNU Lisp Lesser General Public License,
;;; which consists of the preamble published by Franz Incorporated,
;;; plus the LGPL published by the Free Software Foundation, either
;;; version 3 of the License, or (at your option) any later version.
;;;
;;; NST is distributed in the hope that it will be useful, but WITHOUT
;;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lisp Lesser
;;; General Public License for more details.
;;;
;;; You should have received a copy of the Preamble to the Gnu Lesser
;;; General Public License and the GNU Lesser General Public License
;;; along with NST.  If not, see respectively
;;; <http://opensource.franz.com/preamble.html> and
;;; <http://www.gnu.org/licenses/>.

(asdf:oos 'asdf:load-op :asdf-nst)
(defpackage :nst-simple-asd (:use :common-lisp :asdf))
(in-package :nst-simple-asd)

(defclass interpreted-file (cl-source-file) ())
(defmethod asdf:operation-done-p ((op compile-op) (fl interpreted-file)) t)
(defmethod asdf:input-files ((op load-op) (file interpreted-file))
  (list (component-pathname file)))
(defmethod perform ((o compile-op) (f interpreted-file)) (values))

(defsystem :nst-simple-tests
    :class nst-test-holder
    :description "M as in meta: NST- (or otherwise) testing NST."
    :serial t
    ;; :nst-systems (:masdfnst)
    :nst-packages (:nst-simple-tests :nst-simple-tests-interpreted)
    :depends-on (:nst :nst-selftest-utils)
    :components ((:file "package")

                 ;; A simple test suite
                 (:file "builtins")

                 ;; Same tests, but interpreted and not compiled
                 (:interpreted-file "interpreted")

;;;              ;; Checks with anonymous fixtures
;;;              (:file "anon-fixtures-mnst")

                 ))
