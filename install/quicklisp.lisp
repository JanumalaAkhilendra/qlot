(defpackage #:qlot/install/quicklisp
  (:use #:cl)
  (:import-from #:qlot/logger
                #:message)
  (:import-from #:qlot/proxy
                #:*proxy*)
  (:import-from #:qlot/utils
                #:generate-random-string)
  (:import-from #:qlot/utils/shell
                #:run-lisp)
  (:import-from #:qlot/utils/tmp
                #:with-tmp-directory)
  (:import-from #:qlot/utils/http
                #:http-fetch)
  (:export #:install-quicklisp))
(in-package #:qlot/install/quicklisp)

(defun fetch-installer (to)
  (let ((quicklisp-file (if (uiop:directory-pathname-p to)
                            (merge-pathnames (format nil "quicklisp-~A.lisp"
                                                     (generate-random-string))
                                             to)
                            to)))
    (http-fetch "http://beta.quicklisp.org/quicklisp.lisp"
                quicklisp-file)
    quicklisp-file))

(defun install-quicklisp (path)
  (message "Installing Quicklisp to ~A ..." path)
  (with-tmp-directory (tmp-dir)
    (let ((quicklisp-file (fetch-installer tmp-dir)))
      (run-lisp (list
                  `(let ((*standard-output* (make-broadcast-stream)))
                     (load ,quicklisp-file))
                  "(setf quicklisp-quickstart:*after-initial-setup-message* \"\")"
                  (format nil "(let ((*standard-output* (make-broadcast-stream)) (*trace-output* (make-broadcast-stream))) (quicklisp-quickstart:install :path #P\"~A\"~@[ :proxy \"~A\"~]))"
                          path
                          *proxy*))
                :without-quicklisp t)
      t)))
