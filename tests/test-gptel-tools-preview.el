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

(provide 'test-gptel-tools-preview)

;;; test-gptel-tools-preview.el ends here
