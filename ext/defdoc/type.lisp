(in-package :defdoc)

(defvar *docstring-style* 'standard-docstring-style)

(def-doctype function ()
  (:docstring-installer (name spec)
    (setf (documentation name 'function)
          (with-output-to-string (stream)
            (format-docspec stream *docstring-style* spec 'function)))))

(def-doctype compiler-macro ()
  (:docstring-installer (name spec)
    (setf (documentation name 'compiler-macro)
          (with-output-to-string (stream)
            (format-docspec stream *docstring-style* spec 'compiler-macro)))))

(def-doctype setf ()
  (:docstring-installer (name spec)
    (setf (documentation name 'setf)
          (with-output-to-string (stream)
            (format-docspec stream *docstring-style* spec 'setf)))))

(def-doctype type ()
  (:docstring-installer (name spec)
    (setf (documentation name 'type)
          (with-output-to-string (stream)
            (format-docspec stream *docstring-style* spec 'type)))))

(def-doctype structure ()
  (:docstring-installer (name spec)
    (setf (documentation name 'structure)
          (with-output-to-string (stream)
            (format-docspec stream *docstring-style* spec 'structure)))))

(def-doctype package ()
  (:docstring-installer (name spec)
    (setf (documentation (find-package name) t)
          (with-output-to-string (stream)
            (format-docspec stream *docstring-style* spec 'package)))))

(def-doctype method-combination ()
  (:docstring-installer (name spec)
    (setf (documentation name 'method-combination)
          (with-output-to-string (stream)
            (format-docspec stream *docstring-style* spec
                            'method-combination)))))

(def-doctype variable ()
  (:docstring-installer (name spec)
    (setf (documentation name 'variable)
          (with-output-to-string (stream)
            (format-docspec stream *docstring-style* spec 'variable)))))

(def-doctype method ())
