;;; test-string-literal-syntax.el --- Test string literal syntax in key modules -*- lexical-binding: t -*-

;;; Commentary:
;; Tests to ensure string literals are properly formatted and don't span
;; multiple lines, which would cause syntax errors.

;;; Code:

(require 'ert)

(ert-deftest test-production-el-string-literals ()
  "Verify gptel-auto-workflow-production.el has valid string literals."
  (let ((file (expand-file-name "lisp/modules/gptel-auto-workflow-production.el"
                                (or (and (boundp 'user-emacs-directory)
                                         (file-name-as-directory user-emacs-directory))
                                    (expand-file-name "~/.emacs.d/")))))
    (should (file-exists-p file))
    ;; Try to load the file - should not signal syntax errors
    (let ((load-success nil)
          (error-msg nil))
      (condition-case err
          (progn
            (load file nil t)
            (setq load-success t))
        (error (setq error-msg (error-message-string err))))
      (should load-success)
      (should-not error-msg))))

(ert-deftest test-statechart-el-string-literals ()
  "Verify gptel-auto-workflow-pipeline-statechart.el has valid string literals."
  (let ((file (expand-file-name "lisp/modules/gptel-auto-workflow-pipeline-statechart.el"
                                (or (and (boundp 'user-emacs-directory)
                                         (file-name-as-directory user-emacs-directory))
                                    (expand-file-name "~/.emacs.d/")))))
    (should (file-exists-p file))
    ;; Try to load the file - should not signal syntax errors
    (let ((load-success nil)
          (error-msg nil))
      (condition-case err
          (progn
            (load file nil t)
            (setq load-success t))
        (error (setq error-msg (error-message-string err))))
      (should load-success)
      (should-not error-msg))))

(ert-deftest test-no-corrupted-string-literals ()
  "Verify no string literals start with multiple newlines (corruption pattern)."
  (dolist (filename '("lisp/modules/gptel-auto-workflow-production.el"
                      "lisp/modules/gptel-auto-workflow-pipeline-statechart.el"))
    (let ((file (expand-file-name filename
                                  (or (and (boundp 'user-emacs-directory)
                                           (file-name-as-directory user-emacs-directory))
                                      (expand-file-name "~/.emacs.d/")))))
      (when (file-exists-p file)
        (with-temp-buffer
          (insert-file-contents file)
          (emacs-lisp-mode)
          ;; Check for corruption pattern: strings starting with multiple newlines
          (goto-char (point-min))
          (let ((corruption-found nil))
            (while (re-search-forward "\"\n\n\n" nil t)
              (setq corruption-found t))
            (should-not corruption-found)))))))

(provide 'test-string-literal-syntax)
;;; test-string-literal-syntax.el ends here
