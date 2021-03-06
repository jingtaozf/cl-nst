;;; File runnable.lisp
;;;
;;; This file is part of the NST unit/regression testing system.
;;;
;;; Copyright (c) 2009-2010 Smart Information Flow Technologies.
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
(in-package :sift.asdf-nst)


(defclass nst-test-runner (system)
     ((nst-systems :initarg :nst-systems
                   :reader nst-systems
                   :initform nil
                   :documentation
                   "Other systems to which NST testing is delegated")

      (nst-init :initarg :nst-init
                :initform nil
                :reader nst-init
                :documentation
                "NST initialization steps.  Should a list of lists, each of
                 which gives arguments to run-nst-command/the REPL alias.")

      (nst-config :initarg :nst-config
                  :initform nil
                  :reader nst-config
                  :documentation
                  "An association list mapping NST configuration global
                   variables to settings to apply during a test run of this
                   system. Variables which may be set through this mechanism
                   are: *nst-verbosity*")

      (nst-debug-config :initarg :nst-debug-config
                        :initform '(symbol-value (intern (symbol-name '*default-debug-config*)
                                                  :nst))
                        :reader nst-debug-config
                        :documentation
                        "NST debugging customization for this system.  Should be
                         an expression which, when evaluated, returns a list of
                         keyword arguments; see *nst-default-debug-config*.")
      (nst-debug-protect :initarg :nst-debug-protect
                         :initform nil
                         :reader nst-debug-protect
                         :documentation
                         "Globals to be saved/restored in an NST debug run.
                          List of elements (package . symbol)")
      (nst-push-debug-config :initarg :nst-push-debug-config
                             :initform nil
                             :reader nst-push-debug-config
                             :documentation
                             "If non-null, then when this system is loaded
                              its :nst-debug and :nst-debug-protect settings
                              will be used as NST's defaults.")

      (error-when-nst :initarg :error-when-nst
                      :reader error-when-nst
                      :initform nil
                      :documentation
                      "Indicates whether NST should throw an error when tests fail.")
      (action-on-error :initarg :action-on-error
                       :reader action-on-error
                       :initform #+sbcl '(quit :unix-status 1)
                                 #+closure-common-lisp '(quit 1)
                                 #-(or sbcl closure-common-lisp)
                                 '(error 'requested-error-on-test-failure)
                       :documentation
                       "Describes the error action taken by NST on behalf of error-when-nst."))

  (:documentation "Class of ASDF systems that use NST for their test-op."))

(defgeneric get-test-specs (system)
  (:method (s) (declare (ignore s)) (values nil nil nil))
  (:method ((s symbol)) (get-test-specs (asdf:find-system s)))
  (:method ((s nst-test-runner))
    (with-accessors ((nst-systems nst-systems)) s
      (loop for sys in nst-systems
            for (ps gs ts) = (multiple-value-list (get-test-specs sys))
            append ps into packages
            append gs into groups
            append ts into tests
            finally
         (return-from get-test-specs
           (values packages groups tests))))))

(defgeneric all-nst-testers (system)
  (:documentation "Returns three values:
1.  A set of PACKAGES,
2.  A set of NST GROUP NAMES
3.  A set of NST TEST specifiers (pairs)
that should be tested while testing SYSTEM.")
  (:method ((sym symbol))
     (let ((system (asdf:find-system sym)))
       (cond
        (system (all-nst-testers system))
        (t (error "NST subsystem ~a not found" sym)))))

  (:method ((s nst-test-runner))
     (loop for subsystem in (nst-systems s)
           for (this-packages this-groups this-tests)
             = (multiple-value-list (all-nst-testers subsystem))
           append this-packages into packages
           append this-groups into groups
           append this-tests into tests
           finally (return-from all-nst-testers
                     (values packages groups tests)))))

(defmethod asdf::component-depends-on :around ((op test-op)
                                               (sys nst-test-runner))
  "To test this system, we\'ll need to have loaded NST, and we\'ll need to have
loaded and tested the systems actually holding our unit tests.  There may be
other contributors to the to-do list, so we include those tasks via
\(call-next-method\)."
  `((asdf:load-op ,sys)                 ;note that ASDF 2 will make this a
                                        ;standard dependency.  But it's not a
                                        ;big deal to have an
                                        ;extra... [2010/10/25:rpg]
    (asdf:load-op :nst)
    ,@(loop for sub in (nst-systems sys)
            append `((asdf:load-op ,sub)
                     (asdf:test-op ,sub)))
    ,@(call-next-method)))

(defmethod all-nst-tested ((nst-test-runner nst-test-runner)
                           &optional
                           (all-packages (make-hash-table :test 'eq))
                           (all-groups (make-hash-table :test 'eq))
                           (all-tests-by-group (make-hash-table :test 'eq)))
  "Recursively assemble the artifacts identified by the systems we use."

  (with-accessors ((systems nst-systems)
                   (packages nst-packages) (package nst-package)
                   (group nst-group) (groups nst-groups)
                   (test nst-test) (tests nst-tests)) nst-test-runner

    ;; Grab symbols from subsystems.
    (loop for system in systems do
      (all-nst-tested (find-system system)
          all-packages all-groups all-tests-by-group))

    (values all-packages all-groups all-tests-by-group)))

(defmethod operation-done-p ((o asdf:test-op) (c nst-test-runner))
  "Always re-run NST for the test-op."
  (values nil))

(defmethod perform :after ((o asdf:load-op) (c nst-test-runner))
  "Run the NST initialization options for this system."
  (let ((options (nst-init c)))
    (loop for opt in options do
      (apply (symbol-function (intern (symbol-name 'run-nst-command)
                                      :nst))
             opt)))

  ;; Check whether we should export our debug configuration as NST's
  ;; defaults.  This allows the :run-test, :run-package, etc. commands
  ;; to pick up a system's debug configuration.
  (when (nst-push-debug-config c)
    (setf (symbol-value (intern (symbol-name '*default-debug-config*) :nst))
          (eval (nst-debug-config c))
          (symbol-value (intern (symbol-name '*default-debug-protect*) :nst))
          (nst-debug-protect c))))

(defmethod perform ((o asdf:test-op) (c nst-test-runner))
  (macrolet ((nst-fn (fn &rest args)
               `(funcall (symbol-function (intern (symbol-name ',fn) :nst))
                         ,@args)))

    (cond
      ((and (boundp 'common-lisp-user::details-after-nst-testop)
            (symbol-value 'common-lisp-user::details-after-nst-testop))
       (funcall (symbol-function (intern (symbol-name '#:report-details)
                                         (find-package :nst)))
                nil nil nil nil)))

    ;; Check whether we're running this system on behalf of another
    ;; system.
    (unless *intermediate-system*
      ;; If not, report all the results from both this system, and
      ;; subordinated systems.
      (multiple-value-bind (package-set group-set test-set) (all-nst-tested c)
        (nst-fn report-multiple
                (loop for s being the hash-keys of package-set collect s)
                (loop for s being the hash-keys of group-set collect s)
                (loop for g being the hash-keys of test-set
                    using (hash-value hash)
                    append (loop for ts being the hash-keys of hash
                               collect (cons g ts)))
                :system c)))))

(defmacro collect-nst-values (runner &rest body)
  "This macro allows NST configuration variables to be shadowed during an NST test-op, without requiring the NST system to be loaded when the project system is loaded."
  (loop for var in '(*nst-verbosity*)
        for nst-sym = `(intern (symbol-name ',var) (find-package :nst))
        for nst-sym-name = (gensym (format nil "~a-sym-" (symbol-name var)))
        for nst-ref = `(symbol-value ,nst-sym-name)
        for local-ref = (gensym (format nil "~a-val-" (symbol-name var)))
        collect `(,nst-sym-name ,nst-sym) into symbol-names
        collect `(,local-ref ,nst-ref) into savers
        append `(,nst-ref (let ((spec (assoc ,nst-sym-name alist)))
                            (cond
                              ((or *intermediate-system* (not spec)) ,nst-ref)
                              (t (cdr spec))))) into shadowers
        append `(,nst-ref ,local-ref) into restorers
        finally (return-from collect-nst-values
                  `(let ((alist (loop for (name . value) in (nst-config ,runner)
                                      collect (cons (intern (symbol-name name)
                                                            (find-package :nst))
                                                    value))))
                     (let* (,@symbol-names ,@savers)
                       (unwind-protect (progn
                                         (setf ,@shadowers)
                                         ,@body)
                         (setf ,@restorers)))))))

(defmethod perform :around ((o asdf:test-op) (c nst-test-runner))
  (prog1 (collect-nst-values c (call-next-method))

    ;; Do we want to throw an error if tests pass?
    (macrolet ((nst-fn (fn &rest args)
                 `(funcall (symbol-function (intern (symbol-name ',fn) :nst))
                           ,@args)))
      (let ((requested-error (error-when-nst c))
            (error-action (action-on-error c)))
        (when requested-error
          (multiple-value-bind (package-specs group-specs test-specs)
              (get-test-specs c)
            (let ((results (nst-fn multiple-report
                                   package-specs group-specs test-specs)))
              (case requested-error
                ((t :fail)
                 (when (or (> (nst-fn result-stats-erring results) 0)
                           (> (nst-fn result-stats-failing results) 0))
                   (eval error-action)))
                ((:warn)
                 (when (or (> (nst-fn result-stats-erring results) 0)
                           (> (nst-fn result-stats-failing results) 0)
                           (> (nst-fn result-stats-warning results) 0))
                   (eval error-action)))
                ((:err)
                 (when (> (nst-fn result-stats-erring results) 0)
                   (eval error-action)))))))))))

(define-condition requested-error-on-test-failure (error) ())
