;;; test-workflow-status-require.el --- Test that workflow status works without manually loading experiment-loop -*- lexical-binding: t; -*-

;; Capture repo root at load time (see memory:
;; mementum/memories/ert-load-file-name-repo-root.md).  In batch mode,
;; user-emacs-directory may be redirected to var/ by pre-early-init.el,
;; so we cannot rely on it inside the test body.
(defvar test-workflow-status-require--repo-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name default-directory)))))

(ert-deftest test-workflow-status-without-manual-load ()
  "Test that workflow status works without manually loading experiment-loop."
  ;; Load only the main module
  (load-file (expand-file-name "lisp/modules/gptel-tools-agent-main.el"
                               test-workflow-status-require--repo-root))
  ;; This should work without manually loading experiment-loop
  (should (fboundp 'gptel-auto-workflow-status))
  ;; The status function should be callable
  (should (listp (gptel-auto-workflow-status))))
