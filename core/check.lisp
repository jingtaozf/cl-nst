;;; File check.lisp
;;;
;;; This file is part of the NST unit/regression testing system.
;;;
;;; Copyright (c) 2006-2009 Smart Information Flow Technologies.
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

(defun decode-defcheck-name-and-args (name-or-name-and-args)
  "This function unpacks the information inside the first form of a def-check
block, which can be either a single symbol naming the test, or a list whose
first element is that symbol and whose remaining elements are options."

  (cond
   ((symbolp name-or-name-and-args)
    (return-from decode-defcheck-name-and-args
      (values name-or-name-and-args nil nil nil nil nil nil)))
   ((listp name-or-name-and-args)
    (destructuring-bind (name &key (setup nil setup-supp-p)
                                   (cleanup nil cleanup-supp-p)
                                   (fixtures nil fixtures-supp-p))
        name-or-name-and-args
      (return-from decode-defcheck-name-and-args
        (values name
                setup setup-supp-p
                cleanup cleanup-supp-p
                fixtures fixtures-supp-p))))
   (t
    (error "~@<Expected symbol or list for def-check argument~_ ~s~:>"
           name-or-name-and-args))))

(defgeneric build-check-form (criterion args formals)
  (:documentation
   "Assemble a Lisp expression corresponding to the logic of a single test.")
  (:method (unknown-criterion args formals)
     (declare (ignorable args formals))
     (error "Undefined criterion ~s" unknown-criterion)))

(defvar *error-checking* nil
  "Criteria such as :check-err set this variable to t (and declare it special)
to suppress error-handling in continue-check, and thus become able to handle
all further errors themselves.")

(defmacro within-context ((name args values) &body forms)
  `(let ((*nst-context* (cons (make-context-layer
                               :criterion ',name
                               :criterion-args ',args
                               :given-stack ,(cond
                                              (*nst-context-evaluable*
                                               values)
                                              (t `',values)))
                              *nst-context*)))
     (declare (special *nst-context*))
     ,@forms))

(defun continue-check (criterion forms)
  "This function is available from within the check-defining forms to process
subsequences of a current check definition.
 - criterion is an expression denoting a check to be made.
 - forms is an expression which at runtime will evaluate to the stack of values
   to be tested."

  (declare (special *nst-context-evaluable*))
  (let (criterion-name criterion-args)
    (cond ((symbolp criterion)
           (setf criterion-name criterion criterion-args nil))
          ((listp criterion)
           (setf criterion-name (car criterion)
                 criterion-args (cdr criterion)))
          (t
           (error "Malformed criterion in def-check: ~s" criterion)))
    (let ((body (build-check-form criterion-name criterion-args forms))
          (checker-block (gensym "block.")))
      (cond
       (*error-checking*
        body)
       (t
        `(let ((*nst-context* (cons (make-context-layer
                                     :criterion ',criterion-name
                                     :criterion-args ',criterion-args
                                     :given-stack ,(cond
                                                    (*nst-context-evaluable*
                                                     forms)
                                                    (t `',forms)))
                                    *nst-context*)))
           (declare (special *nst-context*))
           (block ,checker-block
             (handler-bind
                 ((error #'(lambda (e)
                             (unless *debug-on-error*
                               (return-from ,checker-block (emit-error e))))))
               ,body))))))))

#+allegro (excl::define-simple-parser def-value-check caadr :nst-criterion)
(defmacro def-value-check ((name criterion-args check-args &key
                                 (declare nil declare-supp-p)
                                 (blurb-format nil blurb-format-supp-p)
                                 (full-format nil full-format-supp-p)
                                 (stack-transformer nil))
                           &body expansion)
  "Mechanism for defining a new check criterion.
Arguments:
NAME - Name of check.
CRITERION-ARGS - arguments that can be passed to the criterion itself.
     For example in the definition of :equalp criterion, the criterion-args
     are \"\(eql-form\)\" the form to which the return value is expected to be
     equalp.
CHECK-ARGS - Arguments that are bound by the results of evaluating the check
    form in a def-check whose criterion is NAME.  Mostly of interest in
    forms that return multiple values.
    [The above is quite possibly incorrect. [2009/03/27:rpg]]
DECLARE - Sometimes one will want to make declarations about the CHECK-ARGS
    \(e.g., when some are to be ignored\).  Declarations go here.  The expected
    form is a LIST of declarations, so, e.g., \(\(ignore args\)\) rather than
    \(ignore args\).
BLURB-FORMAT - Something
FULL-FORMAT - Something else
STACK-TRANSFORMER - Something else again
EXPANSION - An s-expression of code \(must be quoted or, more typically, backquoted\).
    This will typically mention the criterion args, which will have to be evaluated,
    and mention the check args, which will have to  not be evaluated.
Example:
\(def-value-check \(:eql \(eql-form\) \(check-form\)\)
  \`\(if \(eql ,eql-form check-form\)
     \(check-result\)
     \(emit-failure :format \"Not eql to ~s\" :args \'\(,eql-form\)\)\)\)"

  (let* ((stream (gensym "stream")) (id (gensym "id"))
         (args (gensym "args")) (forms (gensym "forms"))
         (criterion-formals (lambda-list-names criterion-args nil))
         (check-formals (lambda-list-names check-args nil)))
    (unless blurb-format-supp-p
      (setf blurb-format
        `("~s ~@<~{~s~^ ~:_~}~:>" ',name (list ,@criterion-formals))))
    (unless full-format-supp-p
      (setf full-format
        (if stack-transformer
          (list "~@<~?~_~@<~:~{@_  ~s~}~:>~:>"
                (car blurb-format) (cdr blurb-format) forms)
          blurb-format)))
    `(eval-when (:compile-toplevel :load-toplevel)
       #+allegro (eval-when (:load-toplevel)
                   (excl:record-source-file ',name :type :nst-criterion))
       (defmethod blurb-context-line (,stream (,id (eql ',name)) ,args ,forms)
         (destructuring-bind ,criterion-args ,args
           (declare (ignorable ,@criterion-formals))
           (destructuring-bind ,check-args ,forms
             (declare (ignorable ,@check-formals))
             (format ,stream ,@blurb-format))))
       (defmethod detail-context-line (,stream (,id (eql ',name)) ,args ,forms)
         (destructuring-bind ,criterion-args ,args
           (declare (ignorable ,@criterion-formals))
           (destructuring-bind ,check-args ,forms
             (declare (ignorable ,@check-formals))
             (format ,stream ,@full-format))))
       (defmethod stack-transformer ((,id (eql ',name)))
         ,stack-transformer)
       (defmethod build-check-form ((,id (eql ',name)) ,args ,forms)
         (destructuring-bind ,criterion-args ,args
           (list 'destructuring-bind ',check-args ,forms
                 ,@(when declare-supp-p `('(declare ,@declare)))
                 ,@expansion))))))

#+allegro (excl::define-simple-parser def-control-check caadr :nst-criterion)
(defmacro def-control-check ((name criterion-args forms-formal
                              &key (stack-transformer t)
                                   (blurb-format nil blurb-format-supp-p)
                                   (full-format nil full-format-supp-p))
                             &body check-forms)
  "Mechanism for defining a new check criterion."

  (let ((criterion-formals
         (lambda-list-names criterion-args nil))
        (stream (gensym "stream")) (id (gensym "id"))
        (args (gensym "args")))
    (unless (symbolp forms-formal)
      (error "Expected a symbol but got ~s" forms-formal))
    (unless blurb-format-supp-p
      (setf blurb-format
        `("~s ~@<~{~s~^ ~:_~}~:>" ',name (list ,@criterion-formals))))
    (unless full-format-supp-p
      (setf full-format
        (if stack-transformer
          (list "~@<~?~_~@<~:{~_  ~s~}~:>~:>"
                (car blurb-format) (cons 'list (cdr blurb-format))
                forms-formal)
          blurb-format)))
    `(eval-when (:compile-toplevel :load-toplevel :execute)
       #+allegro (excl:record-source-file ',name :type :nst-criterion)
       (defmethod blurb-context-line (,stream (,id (eql ',name))
                                      ,args ,forms-formal)
         (declare (ignorable ,forms-formal))
         (destructuring-bind ,criterion-args ,args
           (declare (ignorable ,@criterion-formals))
           (format ,stream ,@blurb-format)))
       (defmethod detail-context-line (,stream (,id (eql ',name))
                                       ,args ,forms-formal)
         (declare (ignorable ,forms-formal))
         (destructuring-bind ,criterion-args ,args
           (declare (ignorable ,@criterion-formals))
           (format ,stream ,@full-format)))
       (defmethod stack-transformer ((,id (eql ',name)))
         ,stack-transformer)
       (defmethod build-check-form ((,id (eql ',name))
                                    ,args ,forms-formal)
         (destructuring-bind ,criterion-args ,args
           ,@check-forms)))))

#+allegro (excl::define-simple-parser def-check-alias caadr :nst-criterion)
(defmacro def-check-alias ((name &rest args)
                           &body forms
                           &aux
                           (documentation nil)
                           (documentation-supp-p nil)
                           (declaration-form nil)
                           (declaration-form-supp-p nil)
                           (expansion nil))
  "Defines how a criterion should be rewritten as another criterion
or criteria.
     The name is the name of the alias, and the args are the arguments
that appear with it.
     The FORMS argument needs quotation, since the body provides forms
that will be substituted for the \(name &rest args\) where they appear
in a def-check.  Typically the ARGS will be substituted into the forms
when def-check-alias is macroexpanded."
  (when (stringp (car forms))
    (setf documentation (pop forms)
          documentation-supp-p t))
  (when (eq (caar forms) 'declare)
    (setf declaration-form (pop forms)
          declaration-form-supp-p t))
  (cond
   ((eql (length forms) 1)
    (setf expansion (pop forms)))
   (t
    (error "Ill-formed (d~@<ef-check-alias (~s~{ ~s~}) ~
                            ~:[~*~;~:@_~s~]~
                            ~:[~*~;~:@_~s~]~
                            ~{~:@_~s~}~:>)"
           name args
           documentation-supp-p documentation
           declaration-form-supp-p declaration-form
           forms)))

  (let* ((forms (gensym "forms")) (stream (gensym "stream"))
         (id (gensym "id")) (exp (gensym "exp"))
         (given-args (gensym "given-args")))
    `(eval-when (:compile-toplevel :load-toplevel :execute)
       #+allegro (excl:record-source-file ',name :type :nst-criterion)
       (defmethod blurb-context-line (,stream (,id (eql ',name))
                                      ,given-args ,forms)
         (destructuring-bind ,args ,given-args
           ,@(when declaration-form-supp-p `(,declaration-form))
           (let ((,exp ,expansion))
             (blurb-context-line ,stream
                                 (car ,exp) (cdr ,exp) ,forms))))
       (defmethod detail-context-line (,stream (,id (eql ',name))
                                       ,given-args ,forms)
         (destructuring-bind ,args ,given-args
           ,@(when declaration-form-supp-p `(,declaration-form))
           (let ((,exp ,expansion))
             (detail-context-line ,stream
                                  (car ,exp) (cdr ,exp) ,forms))))
       (defmethod stack-transformer ((,id (eql ',name))) nil)
       (defmethod build-check-form ((,id (eql ',name))
                                    ,given-args ,forms)
         ,@(when documentation-supp-p
             (when (stringp documentation) `(,documentation)))
         (destructuring-bind ,args ,given-args
           ,@(when declaration-form-supp-p `(,declaration-form))
           (let ((,exp ,expansion))
             (build-check-form (car ,exp) (cdr ,exp) ,forms)))))))

(defvar +storage-name-to-test-package+
    (make-hash-table :test 'eq))

(defmethod canonical-storage-name ((s symbol))
  (canonical-storage-name (make-instance s)))

(defmacro def-check (name-or-name-and-args criterion &rest forms)
  "Define a single unit test.

\(def-check NAME-OR-NAME-AND-OPTIONS
     CRITERION
   FORM ... FORM)

NAME-OR-NAME-AND-OPTIONS ::= name | NAME-AND-OPTIONS

NAME-AND-OPTIONS ::= \( name [ :fixtures FORM ]
                            [ :setup FORM ] [ :cleanup FORM ] )"

  (declare (special *the-group* *group-class-name* *group-fixture-classes*
                    *test-in-group-class* *standalone-test-in-group-class*))
                                        ; The def-group we're within.

  ;; Decode the name-or-name-and-args, pulling out the individual
  ;; components, and indicating which are given in this test.
  (multiple-value-bind (name setup setup-supp-p cleanup cleanup-supp-p
                             fixtures fixtures-supp-p)
      (decode-defcheck-name-and-args name-or-name-and-args)
    (declare (ignorable fixtures-supp-p))

    (let* ((*nst-context* nil)
           (base-rename (concatenate 'string
                          (package-name (symbol-package name)) "///"
                          (symbol-name *the-group*) "///"
                          (symbol-name name)))

           (test-config-class-name (intern base-rename
                                           :nst-test-config-class-names))
           (suite-class-name (intern base-rename :nst-suite-class-names))
           (test-in-group-class-name (intern base-rename
                                             :nst-test-in-group-class-names))
           (standalone-class-name (intern base-rename
                                          :nst-standalone-class-names))

           (core-run-body
            (cond
             ((eql 1 (length forms))
              (continue-check criterion
                              `(common-lisp:multiple-value-list ,(car forms))))
             (t
              (continue-check criterion (cons 'list forms))))))
      (declare (special *nst-context*))
      (multiple-value-bind (z check-fixture-classes anon-fixture-forms)
          (process-fixture-list fixtures)
        (declare (ignorable z))

        `(block ,name
           (macrolet ((eval-dbg (form) `(progn (format t "~%~s~%" ,form)
                                               (eval ,form)
                                               (format t "OK~%"))))
             (loop for form in ,anon-fixture-forms do (eval form))

             (defclass ,test-config-class-name ()
                  ((suite-class-name-by-class :reader suite-class-name-by-class
                                              :allocation :class)
                   (standalone-class-name-by-class
                    :reader standalone-class-name-by-class
                    :allocation :class)
                   (test-config-class-name-by-class
                    :reader test-config-class-name-by-class
                    :allocation :class)
                   (fixtures-from-group-by-class
                    :reader fixtures-from-group-by-class
                    :allocation :class)
                   (test-in-group-class-name-by-class
                    :allocation :class
                    :reader test-in-group-class-name-by-class)))

             (defclass ,suite-class-name (,*group-class-name*
                                          ,*test-in-group-class*
                                          ,@check-fixture-classes)
                  ((suite-class-name-by-class :reader suite-class-name-by-class
                                              :allocation :class)
                   (standalone-class-name-by-class
                    :reader standalone-class-name-by-class
                    :allocation :class)
                   (test-config-class-name-by-class
                    :reader test-config-class-name-by-class
                    :allocation :class)
                   (fixtures-from-group-by-class
                    :reader fixtures-from-group-by-class
                    :allocation :class)
                   (test-in-group-class-name-by-class
                    :allocation :class
                    :reader test-in-group-class-name-by-class)))

             (defclass ,standalone-class-name
                  (,*group-class-name* ,@*group-fixture-classes*
                                       ,@check-fixture-classes
                                       ,*standalone-test-in-group-class*)
                  ((suite-class-name-by-class :reader suite-class-name-by-class
                                              :allocation :class)
                   (standalone-class-name-by-class
                    :reader standalone-class-name-by-class
                    :allocation :class)
                   (test-config-class-name-by-class
                    :reader test-config-class-name-by-class
                    :allocation :class)
                   (fixtures-from-group-by-class
                    :reader fixtures-from-group-by-class
                    :allocation :class)
                   (test-in-group-class-name-by-class
                    :allocation :class
                    :reader test-in-group-class-name-by-class)))

             (loop for class-name in '(,test-config-class-name
                                       ,suite-class-name
                                       ,standalone-class-name)
                   for the-class = (find-class class-name)
                   do
                (finalize-inheritance the-class)
                (let ((proto (class-prototype the-class)))
                  (setf (slot-value proto 'suite-class-name-by-class)
                        ',suite-class-name

                        (slot-value proto 'test-config-class-name-by-class)
                        ',test-config-class-name

                        (slot-value proto 'test-in-group-class-name-by-class)
                        ',test-in-group-class-name

                        (slot-value proto 'standalone-class-name-by-class)
                        ',standalone-class-name)))

             (let ((gproto (class-prototype (find-class ',*the-group*))))
               (setf (gethash ',name (suite-test-classes gproto))
                     ',suite-class-name

                     (gethash ',name (standalone-test-classes gproto))
                     ',standalone-class-name

                     (gethash ',name (config-test-classes gproto))
                     ',test-config-class-name))

             (defmethod check-name ((obj ,suite-class-name))
               ',name)

             (defmethod check-name ((obj ,standalone-class-name))
               ',name)

             (defmethod core-run ((obj ,standalone-class-name))
               (core-run-test obj))

             (defmethod core-run-test ((obj ,suite-class-name))
               (declare (special ,@(loop for fx in check-fixture-classes
                                         append (bound-names fx))
                                 ,@(loop for fx in *group-fixture-classes*
                                         append (bound-names fx))))
               ,core-run-body)
             (defmethod core-run-test ((obj ,standalone-class-name))
               (declare (special ,@(loop for fx in check-fixture-classes
                                         append (bound-names fx))
                                 ,@(loop for fx in *group-fixture-classes*
                                         append (bound-names fx))))
               ,core-run-body)

             ,@(when setup-supp-p
                 `((defmethod core-run-test
                       :before ((obj ,test-config-class-name))
                     ,setup)))

             ,@(when cleanup-supp-p
                 `((defmethod core-run-test
                       :after ((obj ,test-config-class-name))
                     ,cleanup)))

             ;; Test results are stored under a canonical name.
             (defmethod canonical-storage-name ((inst ,suite-class-name))
               ',suite-class-name)
             (defmethod canonical-storage-name ((inst ,standalone-class-name))
               ',suite-class-name)
             (setf (gethash ',standalone-class-name
                            +storage-name-to-test-package+)
               ',(intern (package-name (symbol-package name))
                         (find-package :keyword)))

             ;; Clear any previous stored results, since we've just
             ;; (re-)defined this check.
             (when (boundp '+results-record+)
               (remhash ',suite-class-name (symbol-value '+results-record+)))

             ;; Provide debugging information about this test.
             (defmethod trace-test ((gr (eql ',*the-group*))
                                    (ts (eql ',name)))
               (format t "Test ~s (group ~s)~%" gr ts)
               (format t " - Given name and args: ~s~%"
                 ',name-or-name-and-args)
               (format t " - Given criterion: ~s~%" ',criterion)
               (format t " - Given forms: ~@<~{~s~^ ~:_~}~:>~%" ',forms)

               (format t " - In-suite class name: ~s~%"
                 (suite-class-name ',*the-group* ',name))
               (format t "              expected: ~s~%" ',suite-class-name)
               (format t "   Superclasses: ~@<~{~s~^ ~:_~}~:>~%"
                 (loop for super
                     in (class-direct-superclasses
                         (find-class (suite-class-name ',*the-group* ',name)))
                     collect (class-name super)))
               (when *nst-info-shows-expected*
                 (format t "       expected: ~s~%"
                   ',test-in-group-class-name))

               (format t " - Standalone class name: ~s~%"
                 (standalone-class-name ',*the-group* ',name))
               (when *nst-info-shows-expected*
                 (format t "                expected: ~s~%"
                   ',standalone-class-name))
               (format t "   Superclasses: ~@<~{~s~^ ~:_~}~:>~%"
                 (loop for super
                     in (class-direct-superclasses
                         (find-class (standalone-class-name ',*the-group*
                                                            ',name)))
                     collect (class-name super)))
               (when *nst-info-shows-expected*
                 (format t
                     "       expected: ~@<~s ~:_~@<~{~s~^ ~:_~}~:>~:>~%"
                   ',*standalone-test-in-group-class*
                   ',*group-fixture-classes*)))))))))

(defmacro debug-check (defcheck)
  "Debugging aid for def-check forms.  Provides all-caps dummy values for
dynamic variables normally provided by def-test-group."
  `(let ((*the-group* '<<THE-GROUP>>)
         (*group-fixture-classes* '(<<GROUP-FIXTURE-CLASSES>>))
         (*group-class-name* '<<GROUP-CLASS-NAME>>)
         (*test-in-group-class* '<<TEST-IN-GROUP-CLASS>>)
         (*standalone-test-in-group-class* '<<STANDALONE-TEST-IN-GROUP-CLASS>>))
     (declare (special *the-group* *group-class-name* *group-fixture-classes*
                       *test-in-group-class* *standalone-test-in-group-class*))
     (pprint (macroexpand ',defcheck))))