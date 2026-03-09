;;; test-wrapped-fsm.el --- Regression tests for wrapped gptel FSM values -*- lexical-binding: t; no-byte-compile: t; -*-

(require 'ert)
(require 'cl-lib)

(cl-defstruct (gptel-fsm (:constructor gptel-make-fsm))
  state info)

(defvar gptel--request-alist nil)
(defvar gptel--fsm-last nil)
(defvar gptel-mode nil)
(defvar gptel-post-response-functions nil)
(defvar gptel-mode-map (make-sparse-keymap))
(defvar gptel-agent-request--handlers nil)

(defun gptel--fsm-transition (fsm &optional new-state)
  "Set FSM to NEW-STATE for tests."
  (when new-state
    (setf (gptel-fsm-state fsm) new-state))
  fsm)

(defun gptel--update-status (&rest _args)
  "No-op status updater for tests."
  nil)

(defun force-mode-line-update (&optional _all)
  "No-op mode line updater for tests."
  nil)

(defun gptel-mode (&optional arg)
  "Minimal toggle for tests."
  (setq-local gptel-mode (if (null arg) t (> (prefix-numeric-value arg) 0))))

(provide 'gptel)

(load-file (expand-file-name "lisp/modules/gptel-ext-fsm.el"
                             (expand-file-name ".." (file-name-directory load-file-name))))
(load-file (expand-file-name "lisp/modules/gptel-ext-abort.el"
                             (expand-file-name ".." (file-name-directory load-file-name))))
(load-file (expand-file-name "lisp/modules/gptel-tools-preview.el"
                             (expand-file-name ".." (file-name-directory load-file-name))))

(ert-deftest wrapped-fsm/recover-on-error-coerces-buffer-local-wrapper ()
  (with-temp-buffer
    (let* ((fsm (gptel-make-fsm :state 'WAIT
                                :info '(:error "boom" :stop-reason STOP)))
           (wrapped (cons fsm #'ignore)))
      (setq-local gptel--fsm-last wrapped)
      (my/gptel--recover-fsm-on-error nil nil)
      (should (eq (gptel-fsm-state fsm) 'DONE)))))

(ert-deftest wrapped-fsm/prompt-marker-coerces-buffer-local-wrapper ()
  (with-temp-buffer
    (gptel-mode 1)
    (insert "response")
    (let* ((fsm (gptel-make-fsm :state 'DONE
                                :info (list :buffer (current-buffer))))
           (wrapped (cons fsm #'ignore)))
      (setq-local gptel--fsm-last wrapped)
      (my/gptel-add-prompt-marker (point-min) (point-max))
      (should (string-match-p "### " (buffer-string))))))

(ert-deftest wrapped-fsm/preview-callback-restores-bare-fsm ()
  (let ((called nil))
    (with-temp-buffer
      (let* ((buf (current-buffer))
             (fsm (gptel-make-fsm :state 'WAIT :info (list :buffer buf)))
             (wrapped (cons fsm #'ignore))
             (callback nil))
        (setq-local gptel--fsm-last wrapped)
        (setq callback
              (my/gptel--make-preview-callback
               buf
               (lambda (_result)
                 (setq called t))))
        (funcall callback t)
        (should called)
        (should (eq (buffer-local-value 'gptel--fsm-last buf) fsm))))))

(provide 'test-wrapped-fsm)

;;; test-wrapped-fsm.el ends here
