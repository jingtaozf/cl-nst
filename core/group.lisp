;;; File group.lisp
;;;
;;; This file is part of the NST unit/regression testing system.
;;;
;;; Copyright (c) 2006-2010 Smart Information Flow Technologies.
;;; Written by John Maraist.
;;; Derived from RRT, Copyright (c) 2005 Robert Goldman.
;;;
;;; NST is free software: you can redistribute it and/or modify it
;;; under the terms of the GNU Lesser General Public License as
;;; published by the Free Software Foundation, either version 3 of the
;;; License, or (at your option) any later version.
;;;
;;; NST is distributed in the hope that it will be useful, but WITHOUT
;;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General
;;; Public License for more details.
;;;
;;; You should have received a copy of the GNU Lesser General Public
;;; License along with NST.  If not, see
;;; <http://www.gnu.org/licenses/>.
(in-package :sift.nst)

;;;
;;; Helper functions for the macros.
;;;
(defun pull-test-name-list (form)
  (unless (listp form) (return-from pull-test-name-list nil))
  (case (car form)
    ((def-check def-test) (list (symbol-or-car (cadr form))))
    (otherwise nil)))

(defun separate-group-subforms (forms)
  (let ((checks nil)
        (setup nil) (setup-supp-p nil)
        (cleanup nil) (cleanup-supp-p nil)
        (startup nil) (startup-supp-p nil)
        (finish nil) (finish-supp-p nil)
        (each-setup nil) (each-setup-supp-p nil)
        (each-cleanup nil) (each-cleanup-supp-p nil)
        (docstring nil) (docstring-supp-p nil))
    (loop for form in forms do
      (case (car form)
        (:setup (setf setup (cdr form) setup-supp-p t))
        (:cleanup (setf cleanup (cdr form) cleanup-supp-p t))
        (:fixtures-setup
         (warn 'style-warning
          "The :fixtures-setup argument name is deprecated; use :startup instead.")
         (setf startup (cdr form) startup-supp-p t))
        (:fixtures-cleanup
         (warn 'style-warning
          "The :fixtures-cleanup argument name is deprecated; use :finish instead.")
         (setf finish (cdr form)  finish-supp-p t))
        (:startup (setf startup (cdr form) startup-supp-p t))
        (:finish  (setf finish (cdr form)  finish-supp-p t))
        (:each-setup   (setf each-setup (cdr form)   each-setup-supp-p t))
        (:each-cleanup (setf each-cleanup (cdr form) each-cleanup-supp-p t))
        (:documentation (setf docstring (cadr form) docstring-supp-p t))
        (otherwise (push form checks))))
    (values (nreverse checks)
            setup setup-supp-p      cleanup cleanup-supp-p
            startup startup-supp-p  finish finish-supp-p
            each-setup each-setup-supp-p each-cleanup each-cleanup-supp-p
            docstring docstring-supp-p)))

(defclass nst-group-record ()
  ((%group-name :reader group-name :initarg :group-name)
   (anon-fixture-forms :reader anon-fixture-forms)
   (test-list :accessor test-list)
   (test-name-lookup :reader test-name-lookup)
   (%given-fixtures :reader group-given-fixtures)
   (%fixture-classes :reader group-fixture-class-names)
   (%fixtures-setup-thunk :reader group-fixtures-setup-thunk)
   (%fixtures-cleanup-thunk :reader group-fixtures-cleanup-thunk)
   (%withfixtures-setup-thunk :reader group-withfixtures-setup-thunk)
   (%withfixtures-cleanup-thunk :reader group-withfixtures-cleanup-thunk)
   (%eachtest-setup-thunk :reader group-eachtest-setup-thunk)
   (%eachtest-cleanup-thunk :reader group-eachtest-cleanup-thunk))
  (:documentation "Superclass of NST group definitions."))

(defmethod test-names ((group nst-group-record))
  (loop for tt in (test-list group)
      collect (test-name-lookup (make-instance tt))))

(defmethod group-record-p ((obj nst-group-record)) t)

(defmethod trace-group ((g nst-group-record))
  (format t "Group ~s:~%" (group-name g))
  (format t " - Fixtures: ~@<~{~s~^ ~:_~}~:>~%" (group-given-fixtures g))
  (format t " - Defines tests: ~@<~{~s~^ ~:_~}~:>~%" (test-names g)))

(defun no-effect () nil)

#+allegro (excl::define-simple-parser def-test-group second :nst-group)
(defmacro def-test-group (group-name given-fixtures &body forms)
  "Define a group of tests associated with certain fixtures,
initialization and cleanup.

group-name - name of the test group being defined

given-fixtures - list of the names of fixtures and anonymous fixtures to be
used with the tests in this group.

forms - zero or more test forms, given by def-check."

  (handler-bind (#+sbcl (style-warning
                         #'(lambda (c)
                             (muffle-warning c))))

  ;; Establish a binding of the group name to a special variable for
  ;; use in the expansion of the test-defining forms.
  (let ((*the-group* group-name)
        ;; (package-finder (intern (symbol-name group-name)
        ;;                        (find-package :nst-name-use-in-packages)))
        )
    (declare (special *the-group*))

    ;; Separate the test-defining forms from the group and test setup
    ;; definitions.
    (multiple-value-bind (check-forms setup setup-supp-p
                                      cleanup cleanup-supp-p
                                      fixtures-setup fixtures-setup-supp-p
                                      fixtures-cleanup fixtures-cleanup-supp-p
                                      each-setup each-setup-supp-p
                                      each-cleanup each-cleanup-supp-p
                                      docstring docstring-supp-p)
        (separate-group-subforms forms)

      ;; Get the package where the public group name symbol lives.
      (let ((group-orig-pkg (symbol-package group-name))
            (*group-object-variable* (gensym "group-object")))
        (declare (special *group-object-variable*))

        ;; Go through the fixtures, extracting names, and preparing
        ;; anonymous fixture set instances.
        (multiple-value-bind
            (fixture-class-names anon-fixture-forms fixture-names)
            (process-fixture-list given-fixtures)

          ;; Expand the test forms in this environment which include
          ;; a binding to *the-group*.
          (let ((expanded-check-forms
                 (let ((*group-class-name* group-name)
                       (*group-fixture-classes* fixture-class-names))
                   (declare (special *group-class-name*
                                     *group-fixture-classes*))
                   (mapcar #'macroexpand check-forms))))

            ;; As with the other NST forms, all execution is at load
            ;; time (or less usually, when typed into the REPL
            ;; manually).
            `(eval-when (:compile-toplevel :load-toplevel :execute)
               #+allegro
               (excl:record-source-file ',(if (listp group-name)
                                              (first group-name)
                                              group-name)
                                        :type :nst-test-group)
               (let ((*group-class-name* ',group-name)
                     (*group-fixture-classes* ',fixture-class-names))
                 (declare (special *group-class-name* *group-fixture-classes*))

                 (eval-when (:load-toplevel :execute)
                   (let* ((package-hash (gethash ,group-orig-pkg
                                                 +package-groups+)))
                     (unless package-hash
                       (setf package-hash (make-hash-table :test 'eq)
                             (gethash ,group-orig-pkg
                                      +package-groups+) package-hash))
                     (setf (gethash ',group-name package-hash) t)))

                 (defclass ,group-name (,@fixture-class-names nst-group-record)
                      ()
                   (:metaclass singleton-class)
                   ,@(when docstring-supp-p `((:documentation ,docstring))))
                 #-sbcl
                 ,@(when docstring-supp-p
                     `((setf (documentation ',group-name :nst-group) ,docstring)
                       (setf (documentation ',group-name :nst-test-group)
                             ,docstring)))

                 ;; Complete the group class setup
                 (finalize-inheritance (find-class ',group-name))
                 (set-pprint-dispatch ',group-name
                   #'(lambda (stream object)
                       (declare (ignorable object))
                       (format stream ,(format nil "Group ~s" group-name))))

                 ;; Copnfiguration of the actual group object
                 ;; instance.
                 (let ((,*group-object-variable* (make-instance ',group-name)))

                   ;; Fill in the object's slot values for the given
                   ;; group definition.
                   (flet ((set-slot (slot value)
                            (setf (slot-value ,*group-object-variable* slot)
                                  value)))
                     (set-slot '%group-name ',group-name)
                     (set-slot 'anon-fixture-forms ',anon-fixture-forms)
                     (set-slot 'test-list nil)
                     (set-slot 'test-name-lookup (make-hash-table :test 'eq))
                     (set-slot '%given-fixtures ',given-fixtures)
                     (set-slot '%fixture-classes ',fixture-class-names)
                     (set-slot '%fixtures-setup-thunk
                               ,(cond
                                  (fixtures-setup-supp-p
                                   `#'(lambda () ,@fixtures-setup))
                                  (t `#'no-effect)))
                     (set-slot '%fixtures-cleanup-thunk
                               ,(cond
                                  (fixtures-cleanup-supp-p
                                   `#'(lambda () ,@fixtures-cleanup))
                                  (t `#'no-effect)))
                     (set-slot '%withfixtures-setup-thunk
                               ,(cond
                                  (setup-supp-p
                                   `#'(lambda ()
                                        (declare (special ,@fixture-names))
                                        ,@setup))
                                  (t `#'no-effect)))
                     (set-slot '%withfixtures-cleanup-thunk
                               ,(cond
                                  (cleanup-supp-p
                                   `#'(lambda ()
                                        (declare (special ,@fixture-names))
                                        ,@cleanup))
                                  (t `#'no-effect)))
                     (set-slot '%eachtest-setup-thunk
                               ,(cond
                                  (each-setup-supp-p
                                   `#'(lambda ()
                                        (declare (special ,@fixture-names))
                                        ,@each-setup))
                                  (t `#'no-effect)))
                     (set-slot '%eachtest-cleanup-thunk
                               ,(cond
                                  (each-cleanup-supp-p
                                   `#'(lambda ()
                                        (declare (special ,@fixture-names))
                                        ,@each-cleanup))
                                  (t `#'no-effect))))

                   ;; Record name usage.
                   (record-name-use :group ',group-name
                                    ,*group-object-variable*)

                   ;; Fixture processing.
                   ,@anon-fixture-forms

                   ;; Clear the list of tests when redefining the group.
                   (clrhash (test-name-lookup ,*group-object-variable*))

                   ,@expanded-check-forms

                   ;; Store the new artifact against the uses of its
                   ;; name in NST.
                   (note-executable ',group-name ,*group-object-variable*)))

               ',group-name))))))))
