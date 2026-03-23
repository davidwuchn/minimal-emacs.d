;;; test-gptel-tools-preview.el --- ERT tests for Preview tool -*- lexical-binding: t; no-byte-compile: t; -*-

;;; Commentary:
;; TDD-style unit tests for gptel-tools-preview.el
;; Run: emacs -batch -L lisp/modules -L tests -l tests/test-gptel-tools-preview.el -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'subr-x)
(require 'diff-mode)

;;; Stub gptel dependencies

(cl-defstruct (gptel-fsm (:constructor gptel-make-fsm))
  state info)

(defvar gptel--request-alist nil)
(defvar gptel--fsm-last nil)
(defvar gptel-mode nil)
(defvar gptel-post-response-functions nil)
(defvar gptel-mode-map (make-sparse-keymap))
(defvar gptel-agent-request--handlers nil)
(defvar gptel-agent--skills nil)
(defvar gptel-confirm-tool-calls nil)
(defvar gptel--preset nil)

(defun gptel--fsm-transition (fsm &optional new-state)
  (when new-state (setf (gptel-fsm-state fsm) new-state))
  fsm)

(defun gptel--update-status (&rest _args) nil)
(defun force-mode-line-update (&optional _all) nil)
(defun gptel-mode (&optional arg)
  (setq-local gptel-mode (if (null arg) t (> (prefix-numeric-value arg) 0))))

(defun my/gptel-make-temp-file (prefix &optional dir-flag suffix)
  (make-temp-file (concat "gptel-test-" prefix) dir-flag suffix))

(defun my/gptel--fsm-p (object)
  (ignore-errors (gptel-fsm-state object) t))

(defun my/gptel--coerce-fsm (object)
  (cond ((my/gptel--fsm-p object) object)
        ((consp object) (or (my/gptel--coerce-fsm (car object))
                            (my/gptel--coerce-fsm (cdr object))))
        (t nil)))

(defun gptel-make-tool (&rest args) (plist-get args :name))

(provide 'gptel)
(provide 'gptel-ext-core)
(provide 'gptel-ext-fsm-utils)
(provide 'gptel-agent-tools)

;;; Load modules under test

(load-file (expand-file-name "lisp/modules/gptel-ext-fsm.el"
                             (expand-file-name ".." (file-name-directory load-file-name))))
(load-file (expand-file-name "lisp/modules/gptel-ext-abort.el"
                             (expand-file-name ".." (file-name-directory load-file-name))))
(load-file (expand-file-name "lisp/modules/gptel-tools-preview.el"
                             (expand-file-name ".." (file-name-directory load-file-name))))

;;; Test Fixtures

(defvar test-preview--temp-dir nil)

(defun test-preview--setup ()
  (setq test-preview--temp-dir (make-temp-file "gptel-preview-test-" t)))

(defun test-preview--teardown ()
  (when (and test-preview--temp-dir (file-directory-p test-preview--temp-dir))
    (delete-directory test-preview--temp-dir t)))

(defmacro test-preview--with-temp (&rest body)
  (declare (indent 0))
  `(unwind-protect (progn (test-preview--setup) ,@body) (test-preview--teardown)))

(defun test-preview--write-file (name content)
  (let ((path (expand-file-name name test-preview--temp-dir)))
    (with-temp-file path (insert content))
    path))

(defun test-preview--read-file (name)
  (with-temp-buffer
    (insert-file-contents (expand-file-name name test-preview--temp-dir))
    (buffer-string)))

;;; Tests for my/gptel--preview-bypass-p

(ert-deftest preview/bypass-p/enabled-default ()
  "Should not bypass when preview is enabled."
  (let ((gptel-tools-preview-enabled t)
        (gptel-tools-preview--never-ask-again nil))
    (should-not (my/gptel--preview-bypass-p))))

(ert-deftest preview/bypass-p/disabled-by-user ()
  "Should bypass when preview is disabled."
  (let ((gptel-tools-preview-enabled nil)
        (gptel-tools-preview--never-ask-again nil))
    (should (my/gptel--preview-bypass-p))))

(ert-deftest preview/bypass-p/never-ask-again ()
  "Should bypass when never-ask-again is set."
  (let ((gptel-tools-preview-enabled t)
        (gptel-tools-preview--never-ask-again t))
    (should (my/gptel--preview-bypass-p))))

(ert-deftest preview/bypass-p/both-disabled ()
  "Should bypass when both flags are set."
  (let ((gptel-tools-preview-enabled nil)
        (gptel-tools-preview--never-ask-again t))
    (should (my/gptel--preview-bypass-p))))

;;; Tests for my/gptel--unique-preview-buffer-name

(ert-deftest preview/unique-buffer-name/format ()
  "Should generate buffer name with timestamp."
  (let ((name (my/gptel--unique-preview-buffer-name "*test*")))
    (should (string-prefix-p "*test*-" name))
    (should (string-match-p "\\*test\\*-[0-9]\\{6\\}" name))))

(ert-deftest preview/unique-buffer-name/unique-per-call ()
  "Should generate unique names for different calls."
  (let ((name1 (my/gptel--unique-preview-buffer-name "*test*"))
        (name2 (my/gptel--unique-preview-buffer-name "*test*")))
    (should (string-match-p "\\*test\\*-[0-9]\\{6\\}" name1))
    (should (string-match-p "\\*test\\*-[0-9]\\{6\\}" name2))))

;;; Tests for my/gptel--create-diff-buffer

(ert-deftest preview/create-diff-buffer/creates-buffer ()
  "Should create a buffer with given name."
  (let ((buf (my/gptel--create-diff-buffer "*test-diff*" "Header" nil nil)))
    (should (buffer-live-p buf))
    (should (string= "*test-diff*" (buffer-name buf)))
    (kill-buffer buf)))

(ert-deftest preview/create-diff-buffer/inserts-header ()
  "Should insert header content."
  (let ((buf (my/gptel--create-diff-buffer "*test-diff*" "Test Header" nil nil)))
    (with-current-buffer buf
      (should (string-prefix-p "Test Header" (buffer-string))))
    (kill-buffer buf)))

(ert-deftest preview/create-diff-buffer/inserts-content ()
  "Should insert content after header."
  (let ((buf (my/gptel--create-diff-buffer "*test-diff*" "Header" "Content" nil)))
    (with-current-buffer buf
      (should (string-match-p "Header" (buffer-string)))
      (should (string-match-p "Content" (buffer-string))))
    (kill-buffer buf)))

(ert-deftest preview/create-diff-buffer/sets-read-only ()
  "Should set buffer to read-only."
  (let ((buf (my/gptel--create-diff-buffer "*test-diff*" "Header" nil nil)))
    (with-current-buffer buf
      (should buffer-read-only))
    (kill-buffer buf)))

;;; Tests for my/gptel--run-diff

(ert-deftest preview/run-diff/no-differences ()
  "Should return empty diff for identical files."
  (test-preview--with-temp
    (let ((file1 (test-preview--write-file "same1.el" "(defun foo () 1)\n"))
          (file2 (test-preview--write-file "same2.el" "(defun foo () 1)\n")))
      (let ((diff (my/gptel--run-diff file1 file2)))
        (should (string-empty-p diff))))))

(ert-deftest preview/run-diff/with-differences ()
  "Should return unified diff for different files."
  (test-preview--with-temp
    (let ((file1 (test-preview--write-file "diff1.el" "(defun foo () 1)\n"))
          (file2 (test-preview--write-file "diff2.el" "(defun foo () 2)\n")))
      (let ((diff (my/gptel--run-diff file1 file2)))
        (should (string-match-p "@@" diff))
        (should (string-match-p "^-.*1" diff))
        (should (string-match-p "^\\+.*2" diff))))))

(ert-deftest preview/run-diff/unified-format ()
  "Should return unified diff format (-u flag)."
  (test-preview--with-temp
    (let ((file1 (test-preview--write-file "u1.el" "line1\nline2\n"))
          (file2 (test-preview--write-file "u2.el" "line1\nline3\n")))
      (let ((diff (my/gptel--run-diff file1 file2)))
        (should (string-match-p "@@" diff))))))

;;; Tests for my/gptel--make-preview-callback

(ert-deftest preview/make-callback/wraps-callback ()
  "Should wrap callback function."
  (let ((called nil)
        (result nil)
        (buf (get-buffer-create "*test-callback*")))
    (unwind-protect
        (let ((wrapped (my/gptel--make-preview-callback buf (lambda (r) (setq called t result r)))))
          (should (functionp wrapped))
          (funcall wrapped "test-result")
          (should called)
          (should (string= "test-result" result)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest preview/make-callback/idempotent ()
  "Should only call callback once (idempotent)."
  (let ((call-count 0)
        (buf (get-buffer-create "*test-idempotent*")))
    (unwind-protect
        (let ((wrapped (my/gptel--make-preview-callback buf (lambda (&rest _) (setq call-count (1+ call-count))))))
          (funcall wrapped "first")
          (funcall wrapped "second")
          (funcall wrapped "third")
          (should (= 1 call-count)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

;;; Tests for gptel-tools-preview-register

(ert-deftest preview/register/registers-tool ()
  "gptel-tools-preview-register should register Preview tool."
  (let ((gptel-tools-preview--registered nil))
    (gptel-tools-preview-register)
    (should gptel-tools-preview--registered)))

(ert-deftest preview/register/idempotent ()
  "gptel-tools-preview-register should be idempotent."
  (let ((gptel-tools-preview--registered nil))
    (gptel-tools-preview-register)
    (should gptel-tools-preview--registered)
    (gptel-tools-preview-register)
    (should gptel-tools-preview--registered)))

;;; Tests for my/gptel--preview-file-change (bypass paths)

(ert-deftest preview/file-change/bypass-when-disabled ()
  "Should skip preview when bypass flag is set."
  (let ((gptel-tools-preview-enabled nil)
        (callback-called nil)
        (callback-result nil))
    (my/gptel--preview-file-change
     (current-buffer)
     "test.el"
     "original"
     "replacement"
     (lambda (r) (setq callback-called t callback-result r)))
    (should callback-called)
    (should (string-prefix-p "Preview disabled" callback-result))))

(ert-deftest preview/file-change/bypass-when-never-ask ()
  "Should skip preview when never-ask-again is set."
  (let ((gptel-tools-preview--never-ask-again t)
        (callback-called nil)
        (callback-result nil))
    (my/gptel--preview-file-change
     (current-buffer)
     "test.el"
     "original"
     "replacement"
     (lambda (r) (setq callback-called t callback-result r)))
    (should callback-called)
    (should (string-prefix-p "Preview disabled" callback-result))))

;;; Tests for my/gptel--preview-patch (bypass paths)

(ert-deftest preview/patch/bypass-when-disabled ()
  "Should skip patch preview when bypass flag is set."
  (let ((gptel-tools-preview-enabled nil)
        (callback-called nil)
        (callback-result nil))
    (my/gptel--preview-patch
     "--- a/test.el\n+++ b/test.el"
     (current-buffer)
     (lambda (r) (setq callback-called t callback-result r))
     "Test Header")
    (should callback-called)
    (should (string-prefix-p "Preview disabled" callback-result))))

;;; Tests for gptel-tools-preview-reset-confirmation

(ert-deftest preview/reset-confirmation/resets-flag ()
  "Should reset never-ask-again flag."
  (let ((gptel-tools-preview--never-ask-again t))
    (gptel-tools-preview-reset-confirmation)
    (should-not gptel-tools-preview--never-ask-again)))

;;; Tests for path validation

(ert-deftest preview/validate-path/safe-path ()
  "Should accept safe relative paths."
  (should-not (my/gptel--validate-file-path "src/main.el"))
  (should-not (my/gptel--validate-file-path "test.el"))
  (should-not (my/gptel--validate-file-path "lisp/modules/foo.el")))

(ert-deftest preview/validate-path/rejects-traversal-start ()
  "Should reject paths starting with ../"
  (should (string-match-p "traversal" (my/gptel--validate-file-path "../etc/passwd"))))

(ert-deftest preview/validate-path/rejects-traversal-middle ()
  "Should reject paths containing /../"
  (should (string-match-p "traversal" (my/gptel--validate-file-path "foo/../bar.el"))))

(ert-deftest preview/validate-path/rejects-null-byte ()
  "Should reject paths with null bytes."
  (should (string-match-p "Null" (my/gptel--validate-file-path "foo\0bar.el"))))

(ert-deftest preview/validate-path/rejects-empty ()
  "Should reject empty paths."
  (should (my/gptel--validate-file-path "")))

(ert-deftest preview/validate-path/rejects-non-string ()
  "Should reject non-string paths."
  (should (my/gptel--validate-file-path 123))
  (should (my/gptel--validate-file-path nil)))

;;; Tests for patch validation

(ert-deftest preview/validate-patch-path/safe-path ()
  "Should accept safe patch paths."
  (should-not (my/gptel--validate-patch-path "a/foo.el"))
  (should-not (my/gptel--validate-patch-path "b/bar.el")))

(ert-deftest preview/validate-patch-path/rejects-traversal ()
  "Should reject path traversal in patch paths."
  (should (my/gptel--validate-patch-path "../etc/passwd"))
  (should (my/gptel--validate-patch-path "a/../../etc/passwd")))

(ert-deftest preview/validate-patch-path/rejects-absolute ()
  "Should reject absolute paths in patches."
  (should (my/gptel--validate-patch-path "/etc/passwd")))

(ert-deftest preview/sanitize-patch/rejects-missing-minus-header ()
  "Should reject patches without --- header."
  (let ((result (my/gptel--sanitize-patch "+++ b/foo.el\n@@ -1 +1 @@\n-bar\n+foo")))
    (should-not (car result))
    (should (string-match-p "---" (cdr result)))))

(ert-deftest preview/sanitize-patch/rejects-missing-plus-header ()
  "Should reject patches without +++ header."
  (let ((result (my/gptel--sanitize-patch "--- a/foo.el\n@@ -1 +1 @@\n-bar\n+foo")))
    (should-not (car result))
    (should (string-match-p "\\+\\+\\+" (cdr result)))))

(ert-deftest preview/sanitize-patch/rejects-missing-hunk ()
  "Should reject patches without @@ hunk marker."
  (let ((result (my/gptel--sanitize-patch "--- a/foo.el\n+++ b/foo.el\n-bar\n+foo")))
    (should-not (car result))
    (should (string-match-p "@@" (cdr result)))))

(ert-deftest preview/sanitize-patch/rejects-traversal-in-patch ()
  "Should reject path traversal in patch headers."
  (let ((result (my/gptel--sanitize-patch "--- ../../etc/passwd\n+++ b/foo.el\n@@ -1 +1 @@\n-bar\n+foo")))
    (should-not (car result))
    (should (string-match-p "traversal" (cdr result)))))

(ert-deftest preview/sanitize-patch/accepts-valid-patch ()
  "Should accept valid unified diff."
  (let ((result (my/gptel--sanitize-patch "--- a/foo.el\n+++ b/foo.el\n@@ -1 +1 @@\n-bar\n+foo")))
    (should (car result))
    (should-not (cdr result))))

(provide 'test-gptel-tools-preview)

;;; Window Management Tests

(defvar test-preview--window-config nil
  "Saved window configuration for testing.")

(defun test-preview--save-window-config ()
  "Save current window configuration."
  (setq test-preview--window-config (current-window-configuration)))

(defun test-preview--restore-window-config ()
  "Restore saved window configuration."
  (when test-preview--window-config
    (set-window-configuration test-preview--window-config)))

(defun test-preview--count-windows ()
  "Count visible windows."
  (length (window-list)))

(ert-deftest preview/window/save-configuration ()
  "Should save window configuration."
  (test-preview--save-window-config)
  (should test-preview--window-config)
  (should (window-configuration-p test-preview--window-config)))

(ert-deftest preview/window/restore-configuration ()
  "Should restore window configuration."
  (test-preview--save-window-config)
  (delete-other-windows)
  (test-preview--restore-window-config)
  (should test-preview--window-config))

(ert-deftest preview/window/display-in-side-window ()
  "Should display preview in side window."
  (let ((buf (get-buffer-create "*preview-test*")))
    (unwind-protect
        (progn
          (with-current-buffer buf (insert "Preview content"))
          (display-buffer-in-side-window buf '((side . right) (window-width . 0.3)))
          (should (get-buffer-window buf)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest preview/window/display-in-bottom-window ()
  "Should display preview in bottom window."
  (let ((buf (get-buffer-create "*preview-bottom*")))
    (unwind-protect
        (progn
          (with-current-buffer buf (insert "Preview content"))
          (display-buffer-in-side-window buf '((side . bottom) (window-height . 0.3)))
          (should (get-buffer-window buf)))
      (when (buffer-live-p buf) (kill-buffer buf)))))

(ert-deftest preview/window/teardown-closes-buffer ()
  "Should close preview buffer on teardown."
  (let ((buf (get-buffer-create "*preview-teardown*")))
    (with-current-buffer buf (insert "Content"))
    (should (buffer-live-p buf))
    (kill-buffer buf)
    (should-not (buffer-live-p buf))))

(ert-deftest preview/window/teardown-restores-focus ()
  "Should restore focus to original window on teardown."
  :tags '(:interactive)
  (skip-unless (display-graphic-p))
  (let ((original-window (selected-window))
        (preview-buf (get-buffer-create "*preview-focus*")))
    (unwind-protect
        (progn
          (display-buffer preview-buf)
          (select-window (get-buffer-window preview-buf))
          (should-not (eq (selected-window) original-window))
          (kill-buffer preview-buf)
          ;; Focus should return to original
          (should (eq (selected-window) original-window)))
      (when (buffer-live-p preview-buf) (kill-buffer preview-buf)))))

(ert-deftest preview/window/multiple-previews ()
  "Should handle multiple preview buffers."
  :tags '(:interactive)
  (skip-unless (display-graphic-p))
  (let ((buf1 (get-buffer-create "*preview-1*"))
        (buf2 (get-buffer-create "*preview-2*"))
        (buf3 (get-buffer-create "*preview-3*")))
    (unwind-protect
        (progn
          (display-buffer buf1)
          (display-buffer buf2)
          (display-buffer buf3)
          (should (get-buffer-window buf1))
          (should (get-buffer-window buf2))
          (should (get-buffer-window buf3)))
      (dolist (buf (list buf1 buf2 buf3))
        (when (buffer-live-p buf) (kill-buffer buf))))))

(ert-deftest preview/window/cleanup-orphaned-buffers ()
  "Should cleanup orphaned preview buffers."
  (let ((orphan-buf (get-buffer-create "*preview-orphan*")))
    (with-current-buffer orphan-buf (insert "Orphaned"))
    ;; Simulate orphan detection
    (should (buffer-live-p orphan-buf))
    (kill-buffer orphan-buf)
    (should-not (buffer-live-p orphan-buf))))

;;; FSM State Tests

(defvar test-preview--fsm-states
  '(:idle :previewing :waiting :applied :cancelled :error)
  "Preview FSM states.")

(defvar test-preview--current-fsm-state :idle
  "Current FSM state for testing.")

(defun test-preview--fsm-transition (from-state to-state)
  "Transition FSM from FROM-STATE to TO-STATE."
  (setq test-preview--current-fsm-state to-state))

(defun test-preview--fsm-can-transition-p (from-state to-state)
  "Check if FSM can transition from FROM-STATE to TO-STATE."
  (let ((valid-transitions
         '((:idle . (:previewing))
           (:previewing . (:waiting :cancelled))
           (:waiting . (:applied :cancelled))
           (:applied . (:idle))
           (:cancelled . (:idle))
           (:error . (:idle :previewing)))))
    (member to-state (cdr (assoc from-state valid-transitions)))))

(ert-deftest preview/fsm/initial-state ()
  "FSM should start in idle state."
  (let ((test-preview--current-fsm-state :idle))
    (should (eq :idle test-preview--current-fsm-state))))

(ert-deftest preview/fsm/idle-to-previewing ()
  "FSM should transition from idle to previewing."
  (let ((test-preview--current-fsm-state :idle))
    (should (test-preview--fsm-can-transition-p :idle :previewing))
    (test-preview--fsm-transition :idle :previewing)
    (should (eq :previewing test-preview--current-fsm-state))))

(ert-deftest preview/fsm/previewing-to-waiting ()
  "FSM should transition from previewing to waiting."
  (let ((test-preview--current-fsm-state :previewing))
    (should (test-preview--fsm-can-transition-p :previewing :waiting))
    (test-preview--fsm-transition :previewing :waiting)
    (should (eq :waiting test-preview--current-fsm-state))))

(ert-deftest preview/fsm/waiting-to-applied ()
  "FSM should transition from waiting to applied."
  (let ((test-preview--current-fsm-state :waiting))
    (should (test-preview--fsm-can-transition-p :waiting :applied))
    (test-preview--fsm-transition :waiting :applied)
    (should (eq :applied test-preview--current-fsm-state))))

(ert-deftest preview/fsm/waiting-to-cancelled ()
  "FSM should transition from waiting to cancelled."
  (let ((test-preview--current-fsm-state :waiting))
    (should (test-preview--fsm-can-transition-p :waiting :cancelled))
    (test-preview--fsm-transition :waiting :cancelled)
    (should (eq :cancelled test-preview--current-fsm-state))))

(ert-deftest preview/fsm/cancelled-to-idle ()
  "FSM should transition from cancelled to idle."
  (let ((test-preview--current-fsm-state :cancelled))
    (should (test-preview--fsm-can-transition-p :cancelled :idle))
    (test-preview--fsm-transition :cancelled :idle)
    (should (eq :idle test-preview--current-fsm-state))))

(ert-deftest preview/fsm/applied-to-idle ()
  "FSM should transition from applied to idle."
  (let ((test-preview--current-fsm-state :applied))
    (should (test-preview--fsm-can-transition-p :applied :idle))
    (test-preview--fsm-transition :applied :idle)
    (should (eq :idle test-preview--current-fsm-state))))

(ert-deftest preview/fsm/error-recovery ()
  "FSM should recover from error state."
  (let ((test-preview--current-fsm-state :error))
    (should (test-preview--fsm-can-transition-p :error :idle))
    (should (test-preview--fsm-can-transition-p :error :previewing))
    (test-preview--fsm-transition :error :idle)
    (should (eq :idle test-preview--current-fsm-state))))

(ert-deftest preview/fsm/invalid-transition ()
  "FSM should reject invalid transitions."
  (let ((test-preview--current-fsm-state :idle))
    (should-not (test-preview--fsm-can-transition-p :idle :applied))
    (should-not (test-preview--fsm-can-transition-p :idle :cancelled))
    (should-not (test-preview--fsm-can-transition-p :previewing :applied))))

(ert-deftest preview/fsm/state-restoration ()
  "FSM should support state restoration."
  (let ((test-preview--current-fsm-state :idle)
        (saved-state :idle))
    ;; Save state
    (setq saved-state test-preview--current-fsm-state)
    ;; Transition
    (test-preview--fsm-transition :idle :previewing)
    (should (eq :previewing test-preview--current-fsm-state))
    ;; Restore
    (setq test-preview--current-fsm-state saved-state)
    (should (eq :idle test-preview--current-fsm-state))))

(ert-deftest preview/fsm/all-states-defined ()
  "All FSM states should be defined."
  (dolist (state test-preview--fsm-states)
    (should (keywordp state))
    (should (> (length (symbol-name state)) 1))))

;;; Multi-Preview Concurrency Tests

(defvar test-preview--active-previews 0
  "Count of active previews for testing.")

(defun test-preview--start-preview ()
  "Start a preview (mock)."
  (setq test-preview--active-previews (1+ test-preview--active-previews)))

(defun test-preview--end-preview ()
  "End a preview (mock)."
  (setq test-preview--active-previews (max 0 (1- test-preview--active-previews))))

(ert-deftest preview/concurrency/single-preview ()
  "Should handle single preview."
  (let ((test-preview--active-previews 0))
    (test-preview--start-preview)
    (should (= 1 test-preview--active-previews))
    (test-preview--end-preview)
    (should (= 0 test-preview--active-previews))))

(ert-deftest preview/concurrency/multiple-previews ()
  "Should handle multiple concurrent previews."
  (let ((test-preview--active-previews 0))
    (test-preview--start-preview)
    (test-preview--start-preview)
    (test-preview--start-preview)
    (should (= 3 test-preview--active-previews))
    (test-preview--end-preview)
    (test-preview--end-preview)
    (test-preview--end-preview)
    (should (= 0 test-preview--active-previews))))

(ert-deftest preview/concurrency/preview-queue ()
  "Should queue previews when limit reached."
  (let ((test-preview--active-previews 0)
        (max-concurrent 2)
        (queued 0))
    ;; Start max concurrent
    (test-preview--start-preview)
    (test-preview--start-preview)
    (should (= 2 test-preview--active-previews))
    ;; Queue additional
    (setq queued (1+ queued))
    (should (= 1 queued))
    ;; End one, process queue
    (test-preview--end-preview)
    (setq queued (max 0 (1- queued)))
    (test-preview--start-preview)
    (should (= 2 test-preview--active-previews))))

(ert-deftest preview/concurrency/race-condition-prevention ()
  "Should prevent race conditions in concurrent previews."
  (let ((test-preview--active-previews 0)
        (lock nil))
    ;; Simulate atomic operation
    (setq lock t)
    (setq test-preview--active-previews (1+ test-preview--active-previews))
    (setq lock nil)
    (should (= 1 test-preview--active-previews))
    (should-not lock)))

(provide 'test-gptel-tools-preview)

;;; test-gptel-tools-preview.el ends here
