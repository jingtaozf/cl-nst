;;; File junit.lisp
;;;
;;; This file is part of the NST unit/regression testing system.
;;;
;;; Copyright (c) 2009 Smart Information Flow Technologies.
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
;;; Generating status data within checks.
;;;

(defgeneric junit-xml-snippet (item &optional stream padding)
  (:documentation "Print XML items corresponding to a test result.  The padding
argument should be a string of just spaces."))

(defmethod junit-xml-snippet ((item multi-results)
			      &optional (s *standard-output*) (padding ""))
  (with-accessors ((elapsed-time result-stats-elapsed-time)
		   (tests result-stats-tests)
		   (errors result-stats-erring)
		   (failures result-stats-failing)
		   (system multi-results-system)
		   (group-reports multi-results-group-reports)) item
    (let ((new-padding (concatenate 'string "  " padding)))
      (loop for report in group-reports do
	(cond (report (junit-xml-snippet report s new-padding)))))))

(defmethod junit-xml-snippet ((item group-result)
			      &optional (s *standard-output*) (padding ""))
  (with-accessors ((elapsed-time result-stats-elapsed-time)
		   (tests result-stats-tests)
		   (errors result-stats-erring)
		   (failures result-stats-failing)
		   (system multi-results-system)
		   (group-name group-result-group-name)
		   (test-reports group-result-check-results)) item
    (format s
	"~a<testsuite errors=\"~d\" failures=\"~d\" name=~s ~
                      tests=\"~d\" time=\"~f\"~@[ hostname=~s~]>~%"
      padding errors failures (symbol-to-junit-name group-name) tests
      (/ elapsed-time internal-time-units-per-second)
      
      ;; The hostname.  This isn't Lisp-standard, so maybe we can't
      ;; have it.
      #+allegro (let ((outputs (excl.osi:command-output "hostname")))
		  (if (and outputs (stringp (car outputs)))
		      (car outputs)))
      #-allegro nil)
    (let ((new-padding (concatenate 'string "  " padding)))
      (loop for report being the hash-values of test-reports do
	(cond (report (junit-xml-snippet report s new-padding)))))
    (format s "~a  <system-out><![CDATA[" padding)
    (nst-dump :stream s)
    (format s "]]></system-out>~%")
    (format s "~a  <system-err><![CDATA[]]></system-err>~%" padding)
    (format s "~a</testsuite>~%" padding)))

(defmethod junit-xml-snippet ((item check-result)
			      &optional (s *standard-output*) (padding ""))
  (with-accessors ((group-name check-result-group-name)
		   (check-name check-result-check-name)
		   (warnings check-result-warnings)
		   (failures check-result-failures)
		   (errors check-result-errors)
		   (info check-result-info)
		   (elapsed-time check-result-elapsed-time)) item
    (format s "~a<testcase classname=~s name=\"~a\" time=\"~f\""
      padding
      (symbol-to-junit-name group-name) ; use the group for the classname
      check-name (/ elapsed-time internal-time-units-per-second))
    (cond
      (errors (format s
		  ">~%~a  <error message=\"~a raised an error: ~a\" type=~s/>~%"
		padding
		(symbol-to-junit-name check-name)
		(symbol-to-junit-name (type-of (car errors)))
		(symbol-to-junit-name (type-of (car errors))))
	      (format s "~a</testcase>~%" padding))
      (failures (format s ">~%~a  <failure type=\"FAILURE\"/>~%" padding)
		(format s "~a</testcase>~%" padding))
      (t (format s " />~%")))))

(defun nst-xml-dump (stream)
  (nst-junit-dump stream))

(defun symbol-to-junit-name (symbol)
  (format nil "lisp.~a.~a"
    (package-name (symbol-package symbol)) (symbol-name symbol)))

(defun junit-header (stream)
  (format stream "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>~%"))

(defgeneric nst-junit-dump (stream)
  (:documentation "Push the entire NST state to a JUnit XML file."))

(defmethod nst-junit-dump ((stream stream))
  (junit-header stream)
  (junit-xml-snippet (all-groups-report) stream))

(defmethod nst-junit-dump ((filename string))
  (with-open-file (stream filename :if-exists :supersede
			  :if-does-not-exist :create)
    (nst-junit-dump stream)))

(defgeneric junit-group-result ((group symbol) &rest args &key
				dir file verbose
				if-dir-does-not-exist if-file-exists))

(defmethod junit-group-result ((group symbol) &rest args &key
			       dir file verbose
			       if-dir-does-not-exist if-file-exists)
  (declare (ignorable dir file if-dir-does-not-exist if-file-exists))
  (apply #'junit-group-result (group-report group) args))

(defmethod junit-group-result ((group group-result) &rest args &key
			       verbose
			       (dir  nil dir-supp-p)
			       (file nil file-supp-p)
			       (stream nil stream-supp-p)
			       (if-dir-does-not-exist
				:create if-dir-does-not-exist-supp-p)
			       (if-file-exists :new-version
					       if-file-exists-supp-p))
  (declare (ignorable args))

  (when (and stream-supp-p (or dir-supp-p file-supp-p))
    (warn "Using :stream, ignoring :directory/:filename."))
  (when (and stream-supp-p (or if-dir-does-not-exist-supp-p
			       if-file-exists-supp-p))
    (warn "Options :if-dir-does-not-exist, :if-file-exists not used with :stream, ignoring"))
    
  (let ((the-stream
	 (cond
	  (stream-supp-p stream)
	     
	  ((or dir-supp-p file-supp-p)
  
	   ;; If there's no filename, build a default one.
	   (when (not file-supp-p)
	     (setf file (parse-namestring (concatenate 'string
					    "TEST-"
					    (symbol-to-junit-name
					     (group-result-group-name group))
					    ".xml"))))
  
	   ;; If there's no directory, use the current one.
	   (when (not dir-supp-p)
	     (setf dir (parse-filename "./")))
  
	   ;; If we just have a string for the filename, convert it to
	   ;; a Lisp pathname.
	   (when (and file-supp-p (stringp file))
	     (setf file (parse-namestring file)))
  
	   ;; If we just have a string for the directory, convert it
	   ;; to a Lisp pathname.
	   (when (and dir-supp-p (stringp dir))
	     (setf dir (parse-namestring dir)))

	   (let ((file-path (merge-pathnames file dir)))

	     (when (eq if-dir-does-not-exist :create)
	       (ensure-directories-exist file-path))
	     
	     (when verbose (format t "  Writing to ~w~%" file-path))
	     (open file-path :direction :output :element-type :default
		   :if-exists if-file-exists :if-does-not-exist :create)))
	  
	  (t (setf stream-supp-p t)
	     *standard-output*))))
    
    (junit-header the-stream)
    (junit-xml-snippet group the-stream)
    (unless stream-supp-p (close the-stream))))

(defun junit-results-by-group (&rest args &key verbose &allow-other-keys)
  (loop for report in (multi-results-group-reports (all-groups-report)) do
    (when verbose
      (format t "Making XML for group ~s~%" (group-result-group-name report)))
    (apply #'junit-group-result report args)))
