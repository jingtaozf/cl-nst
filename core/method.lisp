;;; File method.lisp
;;;
;;; This file is part of the NST unit/regression testing system.
;;;
;;; Copyright (c) 2010, 2011 Smart Information Flow Technologies.
;;; Copyright (c) 2015-2016 John Maraist
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
(in-package :nst)

(defun check-result-union (&rest reports)
  (let ((result (cond
                  ((null reports) (make-and-calibrate-check-result))
                  (t (pop reports)))))
    (when reports
      (with-slots ((result-warnings warnings)
                   (result-failures failures)
                   (result-errors errors)
                   (result-info info)) result
        (loop for report in reports do
              (with-slots ((this-warnings warnings)
                           (this-failures failures)
                           (this-errors errors)
                           (this-info info)) report
                (setf result-warnings (nconc result-warnings this-warnings)
                      result-failures (nconc result-failures this-failures)
                      result-errors (nconc result-errors this-errors)
                      result-info (nconc result-info this-info)))))
      (calibrate-check-result result))
    result))

(define-method-combination nst-results :operator check-result-union
  :documentation "NST defines a method combination =nst-results= as the default
method combination for functions defined by =def-test-generic=.  This
combination runs /all/ applicable methods, and combines all of their results
into a single NST result record.

This default can be overridden by specifying =t= as the method combination in
the intial declaration.
#+begin_example
\(nst:def-test-generic overridden (:method-combination t))
\(nst:def-test-method-criterion overridden mid-cls
  \(:slots (mc1 (:eql 0))
          \(mc2 (:eql 2))))
\(nst:def-test-method-criterion overridden bot-cls
  \(:slots (sc1 (:eql 1))
          \(sc2 (:eql 1))))")

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defvar *test-methods* (make-hash-table :test 'eq)
    "Global variable for programmer-defined NST test methods."))

(defmacro def-test-generic (function-name &body forms)
  "The =def-test-generic= declares a generic test function.
#+begin_example
\(def-test-generic FUNCTION-NAME)
#+end_example
For example,
#+begin_example
\(nst:def-test-generic for-clses)
#+end_example"
  (multiple-value-bind (documentation method-combination)
      (decode-def-test-generic-body forms)
    (let ((arg (gensym))
          (use-combination (cond
                            (method-combination method-combination)
                            (t 'nst-results))))
      `(progn
         (defgeneric ,function-name (,arg)
           ,@(when documentation `((:documentation ,documentation)))
           ,@(unless (eq use-combination t)
               `((:method-combination ,use-combination))))
         (eval-when (:compile-toplevel :load-toplevel :execute)
           (setf (gethash ',function-name *test-methods*) ',use-combination))
         ',function-name))))

(defun decode-def-test-generic-body (forms)
  (let ((documentation)
        (doc-supp-p nil)
        (method-combination)
        (method-combination-supp-p nil))
    (loop for form in forms do
      (unless (consp form)
        (error "Expected cons, got ~s" form))
      (let ((form-head (car form)))
        (cond
          ((eq form-head :documentation)
           (when doc-supp-p
             (error "Multiple documentation strings in def-test-generic"))
           (setf documentation (cadr form) doc-supp-p t))
          ((eq form-head :method-combination)
           (when method-combination-supp-p
             (error "Multiple method combinations in def-test-generic"))
           (setf method-combination (cadr form) method-combination-supp-p t))
          (t
           (error "~s not expected in def-test-generic" form-head)))))
    (values documentation method-combination)))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

#-clisp
(defclass method-context-layer (context-layer)
     ((method-name :initarg :method-name :accessor method-name)
      (class-name :initarg :class-name :accessor class-name)
      (object :initarg :object :accessor object))
  (:documentation "A record of method-based test invocation."))

#-clisp
(set-pprint-dispatch 'method-context-layer
  (named-function pprint-method-context-layer
    (lambda (s cl)
      (with-accessors ((method-name method-name)
                       (class-name class-name)
                       (object object)) cl
        (cond
          ((> *nst-verbosity* 2)
           (format s "calling test method ~a on class ~a on ~s"
             method-name class-name object))
          (t
           (format s "calling test method ~a on class ~a"
             method-name class-name)))))))

#-clisp
(defmacro with-method-context-layer ((method-name class-name object) &body body)
  `(with-context-layer (make-instance 'method-context-layer
                         :method-name ',method-name
                         :class-name ',class-name
                         :object ,object)
     ,@body))

#-clisp
(defmethod show-context-layer ((layer method-context-layer))
  (declare (special -context-display-state-))
  (setf (gethash 'criterion -context-display-state-) t)
  t)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defmacro def-test-method (function-name (arg class) &body body)
  "The =def-test-method= defines a general method for a generic test function.
#+begin_example
\(def-test-method FUNCTION-NAME (TEST-VALUE CLASS-NAME)
  FORM
  ...
  FORM)
#+end_example
- function-name :: The name of the test function for which we are defining a
                   method.
- test-value :: Formal parameter to which the value under test will be bound.
- class-name :: The class for which we are defining a method.
The method body should return a test result report, constructed with
=make-success-result=, etc.
For example:
#+begin_example
\(nst:def-test-method for-clses (o mid-cls)
  \(with-slots (mc1 mc2) o
    \(cond
      \((< mc1 mc2) (make-success-report))
      \(t (make-failure-report :format \"~d not < ~d\" :args (list mc1 mc2))))))
\(nst:def-test-method for-clses (o side-cls)
  \(with-slots (sc1 sc2) o
    \(cond
      \((eql sc1 sc2) (make-success-report))
      \(t (make-failure-report :format \"~d not eql ~d\" :args (list sc1 sc2))))))
#+end_example"
  (let ((documentation (when (and body (stringp (car body)))
                         (pop body)))
        (combination (gethash function-name *test-methods*)))
    `(progn
       (defmethod ,function-name ,@(unless (eq combination t)
                                     `(,combination)) ((,arg ,class))
         ,@(when documentation `(,documentation))
         (let ((result (#-clisp with-method-context-layer
                                #-clisp (,function-name ,class ,arg)
                        #+clisp with-context-layer
                                #+clisp
                                (format nil
                                        "calling test method ~a on class ~a on ~s"
                                        ',function-name ',class ',arg)
                         ,@body)))
           (push ,(format nil "Checked test method ~s for ~s"
                    function-name class)
                 (check-result-info result))
           result))
       ',function-name)))

(defmacro def-test-method-criterion (function-name class documentation
                                                   &optional
                                                   (criterion nil crit-supp-p))
  "The =def-test-method-criterion= macro provides a simple facility for defining a generic test function method in terms of an NST criterion.
#+begin_example
\(def-test-method-criterion FUNCTION-NAME CLASS-NAME [ CRITERION ] )
#+end_example
- function-name :: The name of the test function for which we are defining a
                   method.
- class-name :: The class for which we are defining a method.
- criterion :: The criterion to be applied to members of the class.
For example:
#+begin_example
\(nst:def-test-method-criterion for-clses top-cls
  \(:predicate (lambda (tc) (< (tc1 tc) (tc2 tc)))))
#+end_example"
  (unless crit-supp-p
    (setf criterion documentation
          documentation nil))
  (let ((arg (gensym)))
    `(def-test-method ,function-name (,arg ,class)
       ,@(when documentation `(,documentation))
       (check-criterion-on-form ',criterion `(list ,,arg)))))

(defun collect-test-generics (obj)
  (loop for method-name being the hash-keys of *test-methods*
        for method-fn = (symbol-function method-name)
        for actual-method
             = (when method-fn
                 (#-clozure-common-lisp closer-mop:compute-applicable-methods-using-classes
                  #+clozure-common-lisp compute-applicable-methods-using-classes
                    method-fn (list (find-class (type-of obj)))))
        if actual-method collect method-fn))
(defun invoke-test-methods (obj)
  (apply #'check-result-union
         (loop for method-fn in (collect-test-generics obj)
               collect (funcall method-fn obj))))

(def-criterion (:methods () (object))
  (invoke-test-methods object))
(setf (documentation* :methods 'criterion)
      "The =:methods= criterion runs the test functions applicable to the value
under test.

For example:
#+begin_example
\(def-test-group method-tests ()
  \(def-test t-p :methods (make-instance 'top-cls :tc1 0 :tc2 2))
  \(def-test m-p :methods (make-instance 'mid-cls :tc1 0 :tc2 2 :mc1 0 :mc2 2))
  \(def-test s-p :methods (make-instance 'side-cls :sc1 1 :sc2 1))
  \(def-test b-p :methods (make-instance 'bot-cls
                           :tc1 0 :tc2 2 :mc1 0 :mc2 2 :sc1 1 :sc2 1))
  \(def-test t-f :methods (make-instance 'top-cls :tc1 4 :tc2 2))
  \(def-test m-f-t  :methods (make-instance 'mid-cls
                              :tc1 4 :tc2 2 :mc1 0 :mc2 2))
  \(def-test m-f-m  :methods (make-instance 'mid-cls
                              :tc1 0 :tc2 2 :mc1 4 :mc2 2))
  \(def-test m-f-mt :methods (make-instance 'mid-cls
                              :tc1 4 :tc2 2 :mc1 4 :mc2 2))
  \(def-test s-f :methods (make-instance 'side-cls :sc1 1 :sc2 3))
  \(def-test b-f-t :methods (make-instance 'bot-cls
                             :tc1 4 :tc2 2 :mc1 0 :mc2 2 :sc1 1 :sc2 1))
  \(def-test b-f-m :methods (make-instance 'bot-cls
                             :tc1 0 :tc2 2 :mc1 4 :mc2 2 :sc1 1 :sc2 1))
  \(def-test b-f-s :methods (make-instance 'bot-cls
                             :tc1 0 :tc2 2 :mc1 0 :mc2 2 :sc1 1 :sc2 3))
  \(def-test b-f-mt :methods (make-instance 'bot-cls
                              :tc1 4 :tc2 2 :mc1 4 :mc2 2 :sc1 1 :sc2 1))
  \(def-test b-f-ms :methods (make-instance 'bot-cls
                              :tc1 0 :tc2 2 :mc1 4 :mc2 2 :sc1 1 :sc2 3))
  \(def-test b-f-ts :methods (make-instance 'bot-cls
                              :tc1 4 :tc2 2 :mc1 0 :mc2 2 :sc1 1 :sc2 3))
  \(def-test b-f-mts :methods (make-instance 'bot-cls
                               :tc1 4 :tc2 2 :mc1 4 :mc2 2 :sc1 1 :sc2 3)))
#+end_example")