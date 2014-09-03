;;; File group.lisp
;;;
;;; This file is part of the NST unit/regression testing system.
;;;
;;; Copyright (c) 2006-2011 Smart Information Flow Technologies.
;;; Written by John Maraist.
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
        (docstring nil) (docstring-supp-p nil)
        (aspirational nil) (aspirational-supp-p nil)
        (include-groups nil))
    (loop for form in forms do
      (case (car form)
        (:setup (setf setup (cdr form) setup-supp-p t))
        (:cleanup (setf cleanup (cdr form) cleanup-supp-p t))
        (:fixtures-setup
         (warn 'nst-soft-keyarg-deprecation :old-name :fixtures-setup
               :replacement ':replacement)
         (setf startup (cdr form) startup-supp-p t))
        (:fixtures-cleanup
         (warn 'nst-soft-keyarg-deprecation :old-name :fixtures-cleanup
               :replacement ':finish)
         (setf finish (cdr form)  finish-supp-p t))
        (:startup (setf startup (cdr form) startup-supp-p t))
        (:finish  (setf finish (cdr form)  finish-supp-p t))
        (:include-groups (setf include-groups (cdr form)))
        (:each-setup   (setf each-setup (cdr form)   each-setup-supp-p t))
        (:each-cleanup (setf each-cleanup (cdr form) each-cleanup-supp-p t))
        (:documentation (setf docstring (cadr form) docstring-supp-p t))
        (:aspirational (setf aspirational (cadr form) aspirational-supp-p t))
        (otherwise (push form checks))))
    (values (nreverse checks)
            setup setup-supp-p      cleanup cleanup-supp-p
            startup startup-supp-p  finish finish-supp-p
            each-setup each-setup-supp-p each-cleanup each-cleanup-supp-p
            docstring docstring-supp-p
            aspirational aspirational-supp-p
            include-groups)))

(defgeneric anon-fixture-forms (group-record)
  (:method ((s symbol)) (anon-fixture-forms (make-instance s))))
(defgeneric group-include-groups (group-record)
  (:method ((s symbol)) (group-include-groups (make-instance s))))

(defclass nst-group-record ()
  ((%group-name :reader group-name :initarg :group-name)
   (anon-fixture-forms :reader anon-fixture-forms)
   ;; (test-list :accessor test-list)
   ;; (test-name-lookup :reader test-name-lookup)
   (%aspirational :reader group-aspirational-flag)
   (%given-fixtures :reader group-given-fixtures)
   (%fixture-classes :reader group-fixture-class-names)
   (%fixtures-setup-thunk :reader group-fixtures-setup-thunk)
   (%fixtures-cleanup-thunk :reader group-fixtures-cleanup-thunk)
   (%withfixtures-setup-thunk :reader group-withfixtures-setup-thunk)
   (%withfixtures-cleanup-thunk :reader group-withfixtures-cleanup-thunk)
   (%eachtest-setup-thunk :reader group-eachtest-setup-thunk)
   (%eachtest-cleanup-thunk :reader group-eachtest-cleanup-thunk)
   (%include-groups :reader group-include-groups))
  (:documentation "Superclass of NST group definitions."))

(defmethod test-names ((group nst-group-record))
  (loop for tt in (test-list group)
      collect (test-name-lookup (make-instance tt))))

(defmethod group-record-p ((obj nst-group-record)) t)

(defmethod trace-group ((g nst-group-record))
  (format t "Group ~s:~%" (group-name g))
  (flet ((format-list (title list)
           (format t " - ~a: " title)
           (pprint-logical-block (t list)
             (loop for item = (pprint-pop) while item do
               (format t "~s " item)
               (pprint-exit-if-list-exhausted)
               (format t " ")
               (pprint-newline :fill t)))
           (format t "~%")))
    (format-list "Fixtures" (group-given-fixtures g))
    (format-list "Defines tests" (test-names g))))

(defun no-effect () nil)

;;; -----------------------------------------------------------------

(defvar +groupname-testname-to-classname+ (make-hash-table :test 'eq))
(defvar +groupname-testlist+ (make-hash-table :test 'eq))

(defun group-name-redef (group-name)
  (setf (gethash group-name +groupname-testlist+) nil)
  (let ((h (gethash group-name +groupname-testname-to-classname+)))
    (when h
      (clrhash h))))

(defmethod test-list ((group nst-group-record))
  (gethash (group-name group) +groupname-testlist+))
(defun group-add-testclassname (group-name testclass-name)
  (setf (gethash group-name +groupname-testlist+)
        (nconc (gethash group-name +groupname-testlist+)
               (list testclass-name))))
(defun remove-group-testclassname (group-name testclass-name)
  (setf (gethash group-name +groupname-testlist+)
        (delete testclass-name (gethash group-name +groupname-testlist+))))

(defmethod test-name-lookup ((group nst-group-record))
  (gethash (group-name group) +groupname-testname-to-classname+))
(defun add-group-test-name-and-class (group-name test-name test-class-name)
  (let ((name-to-class (gethash group-name +groupname-testname-to-classname+)))
    (unless name-to-class
      (setf name-to-class (make-hash-table :test 'eq)
            (gethash group-name +groupname-testname-to-classname+) name-to-class))
    (setf (gethash test-name name-to-class) test-class-name)))

;;; -----------------------------------------------------------------

(defmacro def-test-group (group-name given-fixtures &body forms)
  "The =def-test-group= form defines a group of the
given name, providing one instantiation of the bindings of the given fixtures
to each test.  Groups can be associated with fixture sets, stateful
initiatization, and stateful cleanup.
#+begin_example
\(def-test-group NAME (FIXTURE FIXTURE ...)
  (:aspirational FLAG)
  (:setup FORM FORM ... FORM)
  (:cleanup FORM FORM ... FORM)
  (:startup FORM FORM ... FORM)
  (:finish FORM FORM ... FORM)
  (:each-setup FORM FORM ... FORM)
  (:each-cleanup FORM FORM ... FORM)
  (:include-groups GROUP GROUP ... GROUP)
  (:documentation STRING)
  TEST
  ...
  TEST)
#+end_example
Arguments:
 - group-name :: Name of the test group being defined
 - given-fixtures :: List of the names of fixtures and anonymous fixtures to be used with the tests in this group.
 - aspirational :: An aspirational test is one which verifies some part of an API or code contract which may not yet be implemented.  Failures and errors of tests in aspirational groups may be treated differently than for other groups. When a group is marked aspirational, all tests within the group are taken to be aspirational as well.
 - forms :: Zero or more test forms, given by =def-check=.
 - setup :: These forms are run once, before any of the individual tests, but after the fixture names are bound.
 - cleanup :: These forms are run once, after all of the individual tests, but while the fixture names are still bound.
 - startup :: These forms are run once, before any of the individual tests and before the fixture names are bound.
 - finish :: These forms are run once, after all of the individual tests, and after the scope of the bindings to fixture names.
 - each-setup :: These forms are run before each individual test.
 - each-cleanup :: These forms are run after each individual test.
 - include-group :: The test groups named in this form will be run (respectively reported) anytime this group is run (reported).
 - documentation :: Docstring for the class."

  (handler-bind (#+sbcl (style-warning
                         (named-function def-test-group-style-warning-muffler
                           (lambda (c)
                             (muffle-warning c)))))

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
                                      docstring docstring-supp-p
                                      aspirational aspirational-supp-p
                                      include-groups)
        (separate-group-subforms forms)
      (declare (ignore aspirational-supp-p))

      ;; Get the package where the public group name symbol lives.
      (let ((group-orig-pkg (symbol-package group-name)))

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

                 (group-name-redef ',group-name)
                 (defclass ,group-name (,@fixture-class-names nst-group-record)
                      ()
                   ,@(when docstring-supp-p `((:documentation ,docstring))))
                 #-sbcl
                 ,@(when docstring-supp-p
                     `((setf (documentation ',group-name :nst-group) ,docstring)
                       (setf (documentation ',group-name :nst-test-group)
                             ,docstring)))

                 (set-pprint-dispatch ',group-name
                   (named-function ,(intern (format nil "pprint-test-group-~a"
                                              group-name))
                     (lambda (stream object)
                       (declare (ignorable object))
                       (format stream ,(format nil "Group ~s" group-name)))))

                 (defmethod initialize-instance :after ((g ,group-name)
                                                        &key &allow-other-keys)
                   (flet ((set-slot (slot value)
                            (setf (slot-value g slot)
                              value)))
                     (set-slot '%group-name ',group-name)
                     (set-slot 'anon-fixture-forms ',anon-fixture-forms)
                     (set-slot '%aspirational ',aspirational)
                     (set-slot '%given-fixtures ',given-fixtures)
                     (set-slot '%fixture-classes ',fixture-class-names)
                     (set-slot '%fixtures-setup-thunk
                               ,(cond
                                  (fixtures-setup-supp-p
                                   `(named-function
                                        ,(format nil
                                             "~a-fixtures-setup-thunk"
                                           group-name)
                                      (lambda () ,@fixtures-setup)))
                                  (t `#'no-effect)))
                     (set-slot '%fixtures-cleanup-thunk
                               ,(cond
                                  (fixtures-cleanup-supp-p
                                   `(named-function
                                        ,(format nil
                                             "~a-fixtures-cleanup-thunk"
                                           group-name)
                                      (lambda () ,@fixtures-cleanup)))
                                  (t `#'no-effect)))
                     (set-slot '%withfixtures-setup-thunk
                               ,(cond
                                  (setup-supp-p
                                   `(named-function
                                        ,(format nil
                                             "~a-withfixtures-setup-thunk"
                                           group-name)
                                      (lambda ()
                                        (declare (special ,@fixture-names))
                                        ,@setup)))
                                  (t `#'no-effect)))
                     (set-slot '%withfixtures-cleanup-thunk
                               ,(cond
                                  (cleanup-supp-p
                                   `(named-function
                                        ,(format nil
                                             "~a-withfixtures-cleanup-thunk"
                                           group-name)
                                      (lambda ()
                                        (declare (special ,@fixture-names))
                                        ,@cleanup)))
                                  (t `#'no-effect)))
                     (set-slot '%eachtest-setup-thunk
                               ,(cond
                                  (each-setup-supp-p
                                   `(named-function
                                        ,(format nil
                                             "~a-eachtest-setup-thunk"
                                           group-name)
                                      (lambda ()
                                        (declare (special ,@fixture-names))
                                        ,@each-setup)))
                                  (t `#'no-effect)))
                     (set-slot '%eachtest-cleanup-thunk
                               ,(cond
                                  (each-cleanup-supp-p
                                   `(named-function
                                        ,(format nil
                                             "~a-eachtest-cleanup-thunk"
                                           group-name)
                                      (lambda ()
                                        (declare (special ,@fixture-names))
                                        ,@each-cleanup)))
                                  (t `#'no-effect)))
                     (set-slot '%include-groups ',include-groups)))
                 ;; end of defmethod initialize-instance

                 ;; Record name usage.
                 (record-name-use :group ',group-name ',group-name)

                 ;; Fixture processing.
                 ,@anon-fixture-forms

                 ;; Clear the list of tests when redefining the group.
                 (let ((test-name-hash
                        (gethash ',group-name +groupname-testname-to-classname+)))
                   (when test-name-hash (clrhash test-name-hash)))

                 ;; Expansion of test macros.
                 ,@expanded-check-forms)

               ',group-name))))))))

(def-documentation (macro def-test-group)
  (:tags primary)
  (:properties (nst-manual groups) (api-summary primary))
  (:intro (:latex "The \\texttt{def-test-group}
form\\index{group}\\index{test group|see{group}} defines a group of the
given name, providing one instantiation of the bindings of the given fixtures
to each test.  Groups can be associated with fixture sets, stateful initiatization, and stateful cleanup.\\index{def-test-group@\\texttt{def-test-group}}"))
  (:callspec (NAME ((:seq FIXTURE)) &body
                   (:key-head :aspirational FLAG)
                   (:key-head :setup (:seq FORM))
                   (:key-head :cleanup (:seq FORM))
                   (:key-head :startup (:seq FORM))
                   (:key-head :finish (:seq FORM))
                   (:key-head :each-setup (:seq FORM))
                   (:key-head :each-cleanup (:seq FORM))
                   (:key-head :include-groups (:seq GROUP))
                   (:key-head :documentation STRING)
                   (:seq TEST)))
  (:params (group-name "Name of the test group being defined")
           (given-fixtures "List of the names of fixtures and anonymous fixtures to be used with the tests in this group.")
           (aspirational "An aspirational test is one which verifies some part of an API or code contract which may not yet be implemented.  Failures and errors of tests in aspirational groups may be treated differently than for other groups. When a group is marked aspirational, all tests within the group are taken to be aspirational as well.")
           (forms "Zero or more test forms, given by def-check.")
           (setup (:latex "These forms are run once, before any of the individual tests, but after the fixture names are bound.\\index{setup@\\texttt{:setup}}"))
           (cleanup (:latex "These forms are run once, after all of the individual tests, but while the fixture names are still bound.\\index{cleanup@\\texttt{:cleanup}}"))
           (startup (:latex "These forms are run once, before any of the individual tests and before the fixture names are bound.\\index{setup@\\texttt{:setup}}"))
           (finish (:latex "These forms are run once, after all of the individual tests, and after the scope of the bindings to fixture names.\\index{cleanup@\\texttt{:cleanup}}"))
           (each-setup (:latex "These forms are run before each individual test.\\index{setup@\\texttt{:setup}}"))
           (each-cleanup (:latex "These forms are run after each individual test.\\index{cleanup@\\texttt{:cleanup}}"))
           (include-group (:latex "The test groups named in this form will be run (respectively reported) anytime this group is run (reported)."))
           (documentation "Docstring for the class.")))

