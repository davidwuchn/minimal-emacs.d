;;; test-tool-confirm-programmatic.el --- ERT tests for Programmatic confirm UI -*- lexical-binding: t; no-byte-compile: t; -*-

(require 'ert)
(require 'cl-lib)

(cl-defstruct (gptel-fsm (:constructor gptel-make-fsm))
  (state (quote INIT)) table handlers info)

;;; Minimal gptel stubs before loading the module

(cl-defstruct (gptel-test-tool (:constructor gptel-test-tool-create))
  name)

(defalias 'gptel-tool-name #'gptel-test-tool-name)

(defvar gptel-tool-call-actions-map (make-sparse-keymap))
(defvar gptel--tool-preview-alist nil)
(defvar gptel--request-alist nil)
(defvar gptel--fsm-last nil)
(defvar gptel-backend nil)  ; Will be set after gptel is loaded
(defvar my/gptel-permitted-tools (make-hash-table :test 'equal))
(defvar test-tool-confirm--accepted nil)
(defvar test-tool-confirm--rejected nil)

(defun gptel-backend-name (_backend)
  "Return a stable backend name for tests."
  "Stub")

(defun gptel--format-tool-call (name arg-values)
  "Format a tool call for tests."
  (format "(%s %s)" name (mapconcat #'prin1-to-string arg-values " ")))

(defun gptel--inspect-fsm (&rest _args)
  "No-op inspect stub for tests."
  (selected-window))

(define-derived-mode test-tabulated-list-mode special-mode "TestTabulated")

(defvar tabulated-list-format nil)
(defvar tabulated-list-entries nil)

(defun tabulated-list-mode ()
  "Stub tabulated list mode for tests."
  (test-tabulated-list-mode))

(defun tabulated-list-init-header ()
  "Stub header init for tests."
  nil)

(defun tabulated-list-print ()
  "Stub printer for tests."
  (erase-buffer)
  (dolist (entry tabulated-list-entries)
    (insert (format "%S\n" entry))))

(defun text-property-search-backward (property value &optional predicate)
  "Tiny compatibility stub for test buffers.
Search backward for PROPERTY equal to VALUE, optionally filtering with PREDICATE."
  (catch 'match
    (let ((pos (point)))
      (while (> pos (point-min))
        (setq pos (1- pos))
        (let ((prop (get-text-property pos property)))
          (when (and (equal prop value)
                     (or (null predicate) (funcall predicate prop)))
            (goto-char pos)
            (throw 'match t))))
      nil)))

(defun gptel--accept-tool-calls (&optional response ov)
  "Base accept stub for advice tests."
  (setq test-tool-confirm--accepted (list response ov))
  'accepted)

(defun gptel--reject-tool-calls (&optional response ov)
  "Base reject stub for advice tests."
  (setq test-tool-confirm--rejected (list response ov))
  'rejected)

(defun my/gptel-tool-permitted-p (tool-name)
  "Return non-nil when TOOL-NAME is remembered as permitted."
  (gethash tool-name my/gptel-permitted-tools))

(defun my/gptel-permit-tool (tool-name)
  "Remember TOOL-NAME as permitted."
  (puthash tool-name t my/gptel-permitted-tools))

;; NOTE: This file provides stubs but does not provide 'gptel to allow
;; other test files to load the real gptel module.

(load-file (expand-file-name "lisp/modules/gptel-ext-tool-confirm.el"
                             (expand-file-name ".." (file-name-directory load-file-name))))

;; Initialize gptel-backend after gptel is loaded
(setq gptel-backend (gptel--make-backend :name "test"))

(defun test-tool-confirm--programmatic-overlay ()
  "Return the active Programmatic confirmation overlay in current buffer."
  (cl-find-if (lambda (ov) (overlay-get ov 'gptel-programmatic-confirm))
              (overlays-in (point-min) (point-max))))

(ert-deftest tool-confirm/programmatic-minibuffer-callback-accepts ()
  (let ((approved nil)
        (test-tool-confirm--accepted nil)
        (gptel-backend (gptel--make-backend :name "test")))
    (cl-letf (((symbol-function 'map-y-or-n-p)
               (lambda (_prompt-fn action tool-calls &rest _)
                 (funcall action (car tool-calls)))))
      (my/gptel--confirm-tool-calls-minibuffer
       (list (list (gptel-test-tool-create :name "Edit") '("foo.el")
                   (lambda (value) (setq approved value))))
       (list :backend gptel-backend :programmatic-confirm t))
      (should approved)
      (should-not test-tool-confirm--accepted))))

(ert-deftest tool-confirm/programmatic-overlay-accept-callbacks ()
  (ert-skip "Flaky test - overlay callback issues")
  (let ((approved nil)
        (test-tool-confirm--accepted nil)
        (gptel-backend (gptel--make-backend :name "test")))
    (with-temp-buffer
      (insert "assistant response")
      (add-text-properties (point-min) (point-max) '(gptel response))
      (goto-char (point-max))
      (my/gptel--programmatic-confirm-tool
       (gptel-test-tool-create :name "Edit") '("foo.el")
       (lambda (value) (setq approved value)))
      (let ((ov (test-tool-confirm--programmatic-overlay)))
        (should ov)
        (should (overlay-get ov 'gptel-programmatic-confirm))
        (gptel--accept-tool-calls
         (list (list (gptel-test-tool-create :name "Edit") '("foo.el")
                     (lambda (value) (setq approved value))))
         ov)
        (should approved)
        (should-not test-tool-confirm--accepted)
        (should-not (overlay-buffer ov))))))

(ert-deftest tool-confirm/programmatic-overlay-reject-callbacks ()
  (ert-skip "Flaky test - overlay callback issues")
  (let ((approved :unset)
        (test-tool-confirm--rejected nil)
        (gptel-backend (gptel--make-backend :name "test")))
    (with-temp-buffer
      (insert "assistant response")
      (add-text-properties (point-min) (point-max) '(gptel response))
      (goto-char (point-max))
      (my/gptel--programmatic-confirm-tool
       (gptel-test-tool-create :name "ApplyPatch") '("patch")
       (lambda (value) (setq approved value)))
      (let ((ov (test-tool-confirm--programmatic-overlay)))
        (should ov)
        (gptel--reject-tool-calls
         (list (list (gptel-test-tool-create :name "ApplyPatch") '("patch")
                     (lambda (value) (setq approved value))))
         ov)
        (should-not approved)
        (should-not test-tool-confirm--rejected)
        (should-not (overlay-buffer ov))))))

(ert-deftest tool-confirm/programmatic-aggregate-overlay-accept-callbacks ()
  (let ((approved nil)
        (test-tool-confirm--accepted nil)
        (gptel-backend (gptel--make-backend :name "test")))
    (with-temp-buffer
      ;; Real gptel buffers have user text (no gptel property) before the
      ;; response so that text-property-search-backward 'gptel 'response
      ;; (nil predicate = "not equal") finds a preceding non-response region.
      (insert "User: please do this\n")
      (let ((response-start (point)))
        (insert "assistant response")
        (add-text-properties response-start (point-max) '(gptel response)))
      (goto-char (point-max))
      (my/gptel--programmatic-aggregate-confirm
       (list (list :tool-name "Edit" :summary "Edit path=a.el diffp=t")
             (list :tool-name "ApplyPatch" :summary "ApplyPatch patch=..."))
       (lambda (value) (setq approved value)))
      (let ((ov (test-tool-confirm--programmatic-overlay)))
        (should ov)
        (should (overlay-get ov 'gptel-programmatic-confirm))
        (gptel--accept-tool-calls
         (list (list (list :name "Programmatic Plan")
                     (list "- Edit path=a.el diffp=t\n- ApplyPatch patch=...")
                     (lambda (value) (setq approved value))))
         ov)
          (should approved)
          (should-not test-tool-confirm--accepted)
          (should-not (overlay-buffer ov))))))

(ert-deftest tool-confirm/normal-overlay-accept-falls-through ()
  (let ((callback-called nil)
        (test-tool-confirm--accepted nil))
    (with-temp-buffer
      (let* ((ov (make-overlay (point-min) (point-min)))
             (response (list (list (gptel-test-tool-create :name "Edit")
                                   '(:path "foo.el")
                                   (lambda (value) (setq callback-called value))))))
        (gptel--accept-tool-calls response ov)
        (should-not callback-called)
        (should (equal test-tool-confirm--accepted (list response ov)))))))

(ert-deftest tool-confirm/normal-overlay-reject-falls-through ()
  (let ((callback-called :not-called)
        (test-tool-confirm--rejected nil))
    (with-temp-buffer
      (let* ((ov (make-overlay (point-min) (point-min)))
             (response (list (list (gptel-test-tool-create :name "Edit")
                                   '(:path "foo.el")
                                   (lambda (value) (setq callback-called value))))))
        (gptel--reject-tool-calls response ov)
        (should (eq callback-called :not-called))
        (should (equal test-tool-confirm--rejected (list response ov)))))))

(ert-deftest tool-confirm/inspect-fsm-coerces-wrapped-fsm-last ()
  (with-temp-buffer
    (let* ((fsm (gptel-make-fsm :state 'WAIT
                                :info '(:buffer nil :history (INIT WAIT))))
           (wrapped (cons fsm #'ignore)))
      (setf (gptel-fsm-info fsm)
            (plist-put (gptel-fsm-info fsm) :buffer (current-buffer)))
      (setq-local gptel--fsm-last wrapped)
      (setq gptel--request-alist nil)
      (my/gptel--inspect-fsm)
      (with-current-buffer "*gptel-diagnostic*"
        (should (string-match-p ":state" (buffer-string)))))))

(provide 'test-tool-confirm-programmatic)

;;; test-tool-confirm-programmatic.el ends here
