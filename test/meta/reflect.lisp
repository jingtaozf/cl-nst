;;; File reflect.lisp
;;;
;;; This file is part of the NST unit/regression testing system.
;;;
;;; Copyright (c) 2006-2011 Smart Information Flow Technologies.
;;; Copyright (c) 2015-2016 John Maraist
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

(in-package :mnst)

(defvar *debug-within-metatested* nil)

(def-criterion-alias (---aspirational)
  `(:predicate nst::test-is-aspirational))

(def-criterion (--with-group (group-name &rest subcriteria) ())
  (let ((group (make-instance group-name)))
    (check-criterion-on-value `(:all ,@subcriteria) group)))

(def-criterion (--with-test (group-name test-name &rest subcriteria) ())
  (let* ((test-obj (nst::test-record group-name test-name)))
    (check-criterion-on-value `(:all ,@subcriteria) test-obj)))

(def-criterion (--nst-group-has-test (group-name test-name) ())
    (let* ((group-record (nst::group-record group-name))
           (test-record (nst::test-record group-name test-name))
           (results-key (nst::test-record-results test-record)))
      (cond
        ((and (gethash test-name (nst::group-record-tests group-record))
              (gethash results-key nst::+results-record+))
         (make-success-report))
        (t (make-failure-report :format "Expected NST group ~s to have test ~s"
                                :args (list group-name test-name))))))

(def-criterion (--nst-run (args &rest subcriteria) ())
  (let ((results))
    (destructuring-bind (&key packages groups tests) args
      (let ((nst::+results-record+ (make-hash-table :test 'eq))
            (nst::*debug-on-error*
             (cond
              (*debug-within-metatested* nst::*debug-on-error*)
              (t nil)))
            (nst::*debug-on-fail*
             (cond
              (*debug-within-metatested* nst::*debug-on-fail*)
              (t nil))))
        (declare (special nst::+results-record+))
        (let ((nst::*nst-verbosity* (cond
                                      ((< nst::*nst-verbosity* 2)
                                       -1)
                                      (t nst::*nst-verbosity*))))
          (loop for package in packages do (run-package package))
          (loop for group in groups do (run-group group))
          (loop for (group test) in tests do (run-test group test)))
        (setf results nst::+results-record+))
      ;; (format t "***** Running subcriteria~%")
      (check-criterion-on-value `(:all ,@subcriteria) results))))

(def-criterion-alias (--nst-package group-name &rest subcriteria)
  `(--nst-run (:packages (,group-name)) ,@subcriteria))
(def-criterion-alias (--nst-group group-name &rest subcriteria)
  (cond
    ((listp group-name)
     `(--nst-run (:groups ,group-name) ,@subcriteria))
    ((symbolp group-name)
     `(--nst-run (:groups (,group-name)) ,@subcriteria))
    (t (error "Expected a symbol or list; got ~s" group-name))))
(def-criterion-alias (--nst-test group-name test-name &rest subcriteria)
  `(--nst-run (:tests ((,group-name ,test-name))) ,@subcriteria))

(def-criterion-alias (--nst-no-test-in-group group-name test-name)
    `(:true-form (not (gethash ',test-name
                               (nst::group-record-tests
                                (nst::group-record ',group-name))))))

(def-criterion (---on-test (group-name test-name &rest subcriteria)
                               (results-hash))
  "Subcriteria get a results report of type nst:check-result"
  (let* ((inst (nst::test-record group-name test-name))
         (result (gethash (nst::test-record-results inst) results-hash)))
    (cond
      (result
       (check-criterion-on-value `(:all ,@subcriteria) result))
      (t (make-failure-report :format "No record of test ~s (group ~s)"
                              :args (list test-name group-name))))))

(def-criterion-alias (---test-passes group-name test-name)
  `(---on-test ,group-name ,test-name
               (:predicate (lambda (r)
                             (and (null (nst::check-result-failures r))
                                  (null (nst::check-result-errors r)))))))
(def-criterion-alias (---test-fails group-name test-name)
  `(---on-test ,group-name ,test-name
               (:all
                (:predicate (lambda (r) (null (nst::check-result-errors r))))
                (:predicate (lambda (r) (nst::check-result-failures r))))))

(def-criterion-alias (---test-errs group-name test-name)
  `(---on-test ,group-name ,test-name
               (:all
                (:predicate (lambda (r) (null (nst::check-result-failures r))))
                (:predicate (lambda (r) (nst::check-result-errors r))))))

(def-criterion-alias (---error-records subcriterion)
  `(:apply (lambda (x) (nst::check-result-errors x)) ,subcriterion))
(def-criterion-alias (---fail-records subcriterion)
  `(:apply (lambda (x) (nst::check-result-failures x)) ,subcriterion))
(def-criterion-alias (---warning-records subcriterion)
  `(:apply (lambda (x) (nst::check-result-warnings x)) ,subcriterion))
(def-criterion-alias (---info-records subcriterion)
  `(:apply (lambda (x) (nst::check-result-info x)) ,subcriterion))

(def-criterion (---form-true (bool) (result))
  (declare (ignore result))
  (let ((result (eval bool)))
    (if result
      (make-success-report)
      (make-failure-report
       :format "Expected form evaluating to non-nil, got: ~s"
       :args (list bool)))))
