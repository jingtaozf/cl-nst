(in-package :defdoc)


(defvar +defdocs+ (make-hash-table :test 'eq)
  "Master global hashtable of all documentation specifiers.")
(defvar +doctype-lispinstallers+ (make-hash-table :test 'eq)
  "Master global hashtable of all documentation specifiers.")

;;; -----------------------------------------------------------------

(defun get-doctype-lisp-installer (type)
  (let ((result (gethash type +doctype-lispinstallers+)))
    (unless result
      (error "No expander defined for documentation type ~s" type))
    result))

(define-setf-expander get-doctype-lisp-installer (type)
  (let ((store (gensym)))
    (values nil
            nil
            `(,store)
            `(setf (gethash ,type +doctype-lispinstallers+) ,store)
            `(get-doctype-lisp-installer ',type))))

(defmacro def-doctype (name (&key) &body forms)
  (multiple-value-bind (lisp-installer lisp-installer-supp-p)
      (decode-doctype-forms forms)
    `(progn
       (setf (get-doctype-lisp-installer ',name)
         #',(cond
             (lisp-installer-supp-p lisp-installer)
             (t '(lambda (x y) (declare (ignore x y))))))
       (unless (gethash ',name +defdocs+)
         (setf (gethash ',name +defdocs+) (make-hash-table :test 'eq))))))

(defun decode-doctype-forms (forms)
  (let ((lisp-installer nil)
        (lisp-installer-supp-p nil))
    (loop for form in forms do
      (case (car form)
        ((:docstring-installer)
         (destructuring-bind ((name spec) &rest body) (cdr form)
           (setf lisp-installer-supp-p t
                 lisp-installer `(lambda (,name ,spec) ,@body))))))
    (values lisp-installer lisp-installer-supp-p)))

;;; -----------------------------------------------------------------

(defun get-doc-spec-type-hash (type)
  (let ((type-hash (gethash type +defdocs+)))
    (unless type-hash
      (error "No such documentation type ~s" type))
    type-hash))

(defun get-doc-spec (name type)
  (let ((type-hash (get-doc-spec-type-hash type)))
    (gethash name type-hash)))

(define-setf-expander get-doc-spec (name type)
  (let ((store (gensym))
        (type-hash (gensym)))
    (values nil
            nil
            `(,store)
            `(let ((,type-hash (get-doc-spec-type-hash ,type)))
               (setf (gethash ,name ,type-hash) ,store))
            `(get-doc-spec ,name ,type))))

(defmacro def-spec-format (name-or-name-and-options formals &rest body)
  (declare (ignore name-or-name-and-options formals body))
  nil)

(defun guess-spec-type (name)
  (cond
    ((fboundp name) 'function)
    ((boundp name) 'variable)
    (t (error "Cannot determine name use for documentation of ~s" name))))

;;; -----------------------------------------------------------------
