;;; test-workflow-status-require.el --- Test workflow status module loading -*- lexical-binding: t -*-

;;; Commentary:
;; Test that gptel-auto-workflow-status works without manually loading modules

;;; Code:

(require 'ert)

(ert-deftest test-workflow-status-without-manual-load ()
  "Test that workflow status works without manually loading experiment-loop."
  ;; Load only the main module
  (load-file (expand-file-name "lisp/modules/gptel-tools-agent-main.el"
                               (or (and (boundp 'user-emacs-directory)
                                        (file-name-as-directory user-emacs-directory))
                                   (expand-file-name "~/.emacs.d/"))))
  ;; This should work without manually loading experiment-loop
  (should (fboundp 'gptel-auto-workflow-status))
  ;; The status function should be callable
  (should (listp (gptel-auto-workflow-status))))

(provide 'test-workflow-status-require)
;;; test-workflow-status-require.el ends here
