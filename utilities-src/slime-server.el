
(setq-default indent-tabs-mode nil)

(defvar ss-init-path)

(defvar ss-repl-buffer nil)

(defvar ss-output-marker (make-marker))

(defun ss-get-repl-buffer ()
  (or ss-repl-buffer
      (setf ss-repl-buffer
	    (let (result)
	      (mapcar (lambda (x)
			(when (string-prefix-p "*slime-repl " (buffer-name x))
			  (setf result x)))
		      (buffer-list))
	      result))))

(defun ss-output-text ()
  (with-current-buffer (ss-get-repl-buffer)
    (prog1
      (if (marker-buffer ss-output-marker)
        (buffer-substring-no-properties ss-output-marker slime-output-end)
        (buffer-substring-no-properties 1 slime-output-end))
      (set-marker ss-output-marker slime-output-end))))

(defun ss-prompt ()
  (with-current-buffer (ss-get-repl-buffer)
    (buffer-substring-no-properties slime-repl-prompt-start-mark
				    slime-repl-input-start-mark)))

(defun ss-input ()
  (with-current-buffer (ss-get-repl-buffer)
    (buffer-substring-no-properties slime-repl-input-start-mark
				    (point-max))))

(defun ss-input-and-return (txt offset)
  (with-current-buffer (ss-get-repl-buffer)
    (ss-set-input txt)
    (goto-char slime-repl-input-start-mark)
    (forward-char offset)
    (slime-repl-return)))

(defun ss-set-input (x)
  (with-current-buffer (ss-get-repl-buffer)
    (delete-region slime-repl-input-start-mark (point-max))
    (goto-char slime-repl-input-start-mark)
    (insert x)))

(defun ss-db-hook ()
  ;(sldb-print-condition)
  (slime-repl-eval-string "(swank:sdlb-print-condition)")
  (sldb-quit))

(defun ss-finish-setup ()
  (setf slime-load-failed-fasl 'never)
  (setf sldb-hook 'ss-db-hook)
  (slime-eval
   `(cl:ignore-errors
     (cl:let ((cl:*package* (cl:find-package "CL-USER")))
       (cl:eval
         (cl:load ,ss-init-path))))))

(defun ss-setup-buffer ()
  (erase-buffer)
  (command-execute 'lisp-mode))

(defun ss-indent-lisp-string (str)
  (let ((x (get-buffer-create " myscratch.lisp")))
    (with-current-buffer x
      (ss-setup-buffer)
      (set (make-local-variable 'lisp-indent-function)
	   'common-lisp-indent-function)
      (set (make-local-variable 'indent-line-function)
	   'lisp-indent-line)
      (insert str)
      (goto-char (point-max))
      (lisp-indent-line)
      (buffer-string))))

(defun ss-complete-lisp-symbol (str)
  (let ((x (get-buffer-create " myscratch.lisp")))
    (with-current-buffer x
      (ss-setup-buffer)
      (set (make-local-variable 'lisp-indent-function)
	   'common-lisp-indent-function)
      (set (make-local-variable 'indent-line-function)
	   'lisp-indent-line)
      (insert str)
      (goto-char (point-max))
      (let* ((end (move-marker (make-marker) (slime-symbol-end-pos)))
	     (beg (move-marker (make-marker) (slime-symbol-start-pos)))
	     (completions (slime-contextual-completions beg end)))
	`(,(- (point-max) (marker-position beg))
	   ,(cl-second completions)
	   ,@(cl-first completions))))))


;;returns either ((&rest results) nil) or (nil error)
(defun ss-eval-expr (str)
  (let ((x (get-buffer-create " myscratch.lisp")))
    (with-current-buffer x
      (ss-setup-buffer)
      (slime-eval `(geany-helper::simple-eval ,str)))))

(defun ss-find-definitions (name package)
  (let* ((slime-buffer-package package)
        (dfns (slime-find-definitions name))
        (result nil))
    (apply 'concat
           (mapcar (lambda (x) (format "%S\n" x))
                   (when dfns
                     (dolist (elt dfns (reverse result))
                       (let ((location (cdr (assoc :location (cdr elt)))))
                         (push (car elt) result)
                         (push (cadr (assoc :file location)) result)
                         (push (cadr (assoc :position location)) result))))))))

;; This is more involved in slime's internals than I would like
(defun ss-async-wait (fn args callback)
  (let* ((tag (cl-gensym "ss-async-wait")))
    (apply
      callback
      (catch
        tag
        (apply fn `(,@args ,(lambda (&rest args) (throw tag args))))
        (let ((inhibit-quit nil)
              (conn (slime-connection)))
          (while t
                 (unless (eq (process-status conn) 'open)
                   (error "Lisp connection closed unexpectedly"))
                 (accept-process-output nil 0.01)))))))

;(defun ss-uses-xrefs (symbol)

(defun ss-start-server (slime-source lisp-exec init-file)
  (load (expand-file-name slime-source))
  (setq ss-init-path init-file)
  (cl-destructuring-bind
    (program &rest program-args)
    (split-string-and-unquote lisp-exec)
  (slime-start :program program
               :program-args program-args
               :init-function 'ss-finish-setup)))

(defun ss-compile-load (source)
  (let* ((sldb-hook (lambda () (sldb-abort)))
	 (results nil)
	 buf
	 (done nil)
	 (slime-compilation-finished-hook (lambda (&rest r) (setf done t))))
    (print source t)
    (find-file source)
    (setq buf (get-file-buffer source))
    (print (buffer-name buf) t)
    (unwind-protect
	(progn
	  (goto-char (point-min))
	  (slime-compile-and-load-file)
	  (while (not done)
	    (unless (eq (process-status (slime-connection)) 'open)
	      (error \"Lisp connection closed unexpectedly\"))
	    (accept-process-output nil 0.01))
	  (set-buffer buf)
	  (while (slime-find-next-note)
	    (push (list (line-number-at-pos) (get-char-property (point) 'help-echo)) results))
          (format "%s\n%s" (third slime-last-compilation-result)
                  (apply 'concat (mapcar (lambda (x) (format "%s\t%s\t%s\n" source (car x) (cadr x))) (reverse results)))))
      (kill-buffer buf))))
