(defpackage #:qlot/utils/shell
  (:use #:cl)
  (:import-from #:qlot/logger
                #:debug-log)
  (:export #:safety-shell-command
           #:shell-command-error
           #:run-lisp
           #:*qlot-source-directory*))
(in-package #:qlot/utils/shell)

(defparameter *qlot-source-directory*
  (asdf:system-source-directory :qlot))

(define-condition shell-command-error (simple-error)
  ((command :type cons
            :initarg :command)
   (code :type integer
         :initarg :code)
   (stderr :type string
           :initarg :stderr))
  (:report
   (lambda (condition stream)
     (format stream "Error while executing a shell command: ~{~S~^ ~} (Code=~D)~2%  ~A"
             (slot-value condition 'command)
             (slot-value condition 'code)
             (slot-value condition 'stderr)))))

(defun safety-shell-command (program args)
  (setf args (mapcar #'princ-to-string args))
  (debug-log "Running shell command: ~A ~{~S~^ ~}" program args)
  (let ((process (uiop:launch-program (cons program args)
                                      :input :interactive
                                      :output :stream
                                      :error-output :stream
                                      :ignore-error-status t)))
    (unwind-protect
        (let ((code (uiop:wait-process process)))
          (unless (zerop code)
            (error 'shell-command-error
                   :command (cons program args)
                   :code code
                   :stderr (uiop:slurp-stream-string
                             (uiop:process-info-error-output process))))
          (uiop:slurp-stream-string
            (uiop:process-info-output process)))
      (uiop:terminate-process process))))

(defvar *current-lisp-path*
  (or #+ccl (car ccl:*command-line-argument-list*)
      #+sbcl (car sb-ext:*posix-argv*)
      #+allegro (car (system:command-line-arguments))
      #+clisp "clisp"
      #+cmu (car ext:*command-line-strings*)
      #+ecl (car (si:command-args))))

(defvar *eval-option*
  (or
    #+ros.init "-e"
    #+ccl "--eval"
    #+sbcl "--eval"
    #+allegro "-e"
    #+clisp "-x"
    #+cmu "-eval"
    #+ecl "-eval"))

(defun str (form)
  (let ((*package* (find-package :cl-user)))
    (if (stringp form)
        form
        (let ((*print-case* :downcase) (*print-pretty* nil))
          (prin1-to-string form)))))

(defun -e (form)
  (list *eval-option* (str form)))

(defvar *default-args*
  (append
    (-e "(require 'asdf)")
    (-e
      '(setf *debugger-hook*
             (lambda (cl-user::c cl-user::parent)
               (declare (ignore cl-user::parent))
               (format *error-output* "~&Error: ~A~2%" cl-user::c)
               (uiop:print-backtrace :condition cl-user::c)
               (uiop:quit -1))))))

(defun build-command-args (forms &key systems source-registry without-quicklisp)
  (let ((qlhome (if without-quicklisp
                    nil
                    (symbol-value (intern (string '#:*quicklisp-home*) '#:ql)))))
    (append
      *default-args*

      (when source-registry
        (-e `(push ,source-registry asdf:*central-registry*)))

      (-e '(setf asdf::*default-source-registries*
                 (quote (asdf::environment-source-registry
                          asdf::system-source-registry
                          asdf::system-source-registry-directory))))

      (when qlhome
        (-e `(load ,(merge-pathnames #P"setup.lisp" qlhome))))

      (loop for system in systems
            append (-e
                     (if qlhome
                         `(uiop:symbol-call :ql :quickload ,system :silent t)
                         `(let ((*standard-output* (make-broadcast-stream))
                                (*trace-output* (make-broadcast-stream)))
                            (asdf:load-system ,system)))))

      (loop for form in forms
            append (-e
                     (if (pathnamep form)
                         `(load ,form)
                         form))))))

#+ros.init
(defun run-roswell (forms &rest args &key systems source-registry without-quicklisp)
  (declare (ignore systems source-registry without-quicklisp))
  (let ((ros (or (ros:opt "wargv0")
                 (ros:opt "argv0"))))
    (safety-shell-command ros
                          (list* "+Q"
                                 "-L" "sbcl-bin"
                                 (apply #'build-command-args forms args)))))

(defun run-lisp (forms &rest args &key systems source-registry without-quicklisp)
  (declare (ignore systems source-registry without-quicklisp))
  #+ros.init
  (apply #'run-roswell forms args)
  #-ros.init
  (safety-shell-command *current-lisp-path*
                        (append
                          #+ccl '("--no-init" "--quiet" "--batch")
                          #+sbcl '("--noinform" "--no-sysinit" "--no-userinit" "--non-interactive")
                          #+allegro '("--qq")
                          #+clisp '("-norc" "--quiet" "--silent" "-on-error" "exit")
                          #+cmu '("-noinit")
                          #+ecl '("-norc")

                          (apply #'build-command-args forms args)

                          (-e
                            (quote
                              #+ccl (ccl:quit)
                              #+sbcl (sb-ext:exit)
                              #+allegro (excl:exit :quiet t)
                              #+clisp (ext:quit)
                              #+cmucl (unix:unix-exit)
                              #+ecl (ext:quit)
                              #-(or ccl sbcl allegro clisp cmucl ecl) (cl-user::quit))))))
